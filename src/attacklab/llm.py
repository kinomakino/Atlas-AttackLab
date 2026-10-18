"""Cliente mínimo de Ollama: conversar, saber si un modelo está y descargarlo."""

import json
import os
import threading
import time

import httpx

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
# Con todos los núcleos, los de eficiencia y el resto de contenedores frenan la inferencia
# (medido en un M2 Max: 12 hilos < 1 token/s, 8 hilos ~67 tokens/s). Usamos dos tercios.
THREADS = int(os.environ.get("ATTACKLAB_THREADS") or max(1, (os.cpu_count() or 3) * 2 // 3))

# Estado de las descargas en curso, por modelo. Lo consulta la web para enseñar el progreso.
pulls: dict[str, dict] = {}
_lock = threading.Lock()


def reachable() -> bool:
    try:
        httpx.get(f"{OLLAMA_URL}/api/version", timeout=3).raise_for_status()
        return True
    except httpx.HTTPError:
        return False


def installed_models() -> set[str]:
    tags = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=5).json()
    return {m["name"] for m in tags.get("models", [])}


def has_model(model: str) -> bool:
    names = installed_models()
    return model in names or f"{model}:latest" in names


def _pull(model: str) -> None:
    # Ollama baja el modelo por capas (la grande y luego varias pequeñas), y cada una informa
    # de su propio avance. El porcentaje es del total y nunca baja: si no, al pasar a las capas
    # pequeñas volvía a 0 % y parecía que la descarga empezaba de nuevo.
    state = pulls[model]
    layers: dict[str, tuple[int, int]] = {}
    try:
        with httpx.stream("POST", f"{OLLAMA_URL}/api/pull", json={"model": model}, timeout=None) as resp:
            resp.raise_for_status()
            for line in resp.iter_lines():
                if not line:
                    continue
                ev = json.loads(line)
                if "error" in ev:
                    raise RuntimeError(ev["error"])
                state["status"] = ev.get("status", "")
                if ev.get("total"):
                    layers[ev.get("digest", "")] = (ev.get("completed", 0), ev["total"])
                    done = sum(c for c, _ in layers.values())
                    total = sum(t for _, t in layers.values())
                    state["percent"] = max(state["percent"], min(99, 100 * done // total))
        state.update(done=True, percent=100)
    except Exception as e:  # noqa: BLE001 — se enseña al usuario tal cual
        state.update(error=str(e))


def start_pull(model: str) -> dict:
    with _lock:
        state = pulls.get(model)
        if state and not state.get("error") and not state.get("done"):
            return state
        pulls[model] = {"status": "empezando", "percent": 0, "done": False, "error": None}
        threading.Thread(target=_pull, args=(model,), daemon=True).start()
        return pulls[model]


def chat(model: str, messages: list[dict], temperature: float = 0.6) -> dict:
    started = time.monotonic()
    resp = httpx.post(
        f"{OLLAMA_URL}/api/chat",
        json={"model": model, "messages": messages, "stream": False,
              "options": {"temperature": temperature, "num_predict": 400, "num_thread": THREADS}},
        timeout=300,
    )
    resp.raise_for_status()
    data = resp.json()
    return {
        "content": data["message"]["content"],
        "prompt_tokens": data.get("prompt_eval_count"),
        "output_tokens": data.get("eval_count"),
        "seconds": round(time.monotonic() - started, 1),
    }
