"""Ejecuta un intento contra un escenario y deja la traza de cada paso.

La traza es lo que el portal enseña en el panel "Qué pasa por dentro": por dónde
pasa el mensaje del alumno, qué defensas actúan y por qué el juez da el reto por
resuelto o no.
"""

import os
import re
import time

import httpx

from attacklab.scenario import Scenario

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
HIDDEN = "[oculto hasta que resuelvas el reto]"


def _normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def _leaks(text: str, flag: str) -> bool:
    """El flag cuenta aunque venga con espacios, guiones cambiados o en minúsculas."""
    return _normalize(flag) in _normalize(text)


def _output_filter(text: str, flag: str) -> tuple[str, bool]:
    """Defensa del modo protegido: tapa el flag si aparece tal cual."""
    if flag in text:
        return text.replace(flag, "[CENSURADO]"), True
    return text, False


def chat(model: str, messages: list[dict]) -> dict:
    model = os.environ.get("ATTACKLAB_MODEL", model)
    started = time.monotonic()
    resp = httpx.post(
        f"{OLLAMA_URL}/api/chat",
        json={"model": model, "messages": messages, "stream": False, "options": {"temperature": 0.7}},
        timeout=120,
    )
    resp.raise_for_status()
    data = resp.json()
    return {
        "model": model,
        "content": data["message"]["content"],
        "prompt_tokens": data.get("prompt_eval_count"),
        "output_tokens": data.get("eval_count"),
        "seconds": round(time.monotonic() - started, 2),
    }


def attempt(s: Scenario, mode: str, history: list[dict]) -> dict:
    protected = mode == "protegido"
    system = s.target.hardened_system_prompt if protected else s.target.system_prompt
    flag = s.target.flag
    trace = []

    trace.append({
        "step": "Tu mensaje",
        "detail": "Llega al backend tal cual. No hay validación de entrada.",
        "data": history[-1]["content"],
    })
    trace.append({
        "step": "Contexto que recibe el modelo",
        "detail": (
            "El backend junta sus instrucciones (system prompt) con la conversación. "
            "El modelo lo ve todo como texto seguido."
            + (" En modo protegido el system prompt está endurecido." if protected else "")
        ),
        "data": [{"role": "system", "content": HIDDEN}] + history,
    })

    try:
        out = chat(s.target.model, [{"role": "system", "content": system}] + history)
    except httpx.HTTPError as e:
        trace.append({"step": "Llamada a Ollama", "detail": f"Ha fallado: {e}", "status": "error"})
        return {"reply": None, "solved": False, "trace": trace, "error": str(e)}

    trace.append({
        "step": "Llamada a Ollama",
        "detail": f"Modelo {out['model']} · {out['prompt_tokens']} tokens de entrada, "
                  f"{out['output_tokens']} de salida · {out['seconds']} s",
    })

    raw = out["content"]
    model_leaked = _leaks(raw, flag)
    reply = raw

    if protected:
        reply, blocked = _output_filter(raw, flag)
        trace.append({
            "step": "Filtro de salida",
            "detail": "Busca el código exacto en la respuesta y lo tapa.",
            "status": "blocked" if blocked else ("bypassed" if model_leaked else "ok"),
            "data": (
                "El modelo sí soltó el código, pero el filtro lo ha tapado." if blocked
                else "El código ha salido de otra forma y el filtro no lo ha reconocido." if model_leaked
                else "No ha encontrado nada que tapar."
            ),
        })

    solved = _leaks(reply, flag)
    trace.append({
        "step": "Juez",
        "detail": "Comprueba si el código aparece en lo que te llega, aunque venga deformado.",
        "status": "solved" if solved else "fail",
        "data": "Reto resuelto: el secreto ha salido." if solved
                else "El modelo ha cedido, pero no te ha llegado." if model_leaked
                else "El secreto no ha salido.",
    })

    result = {"reply": reply, "solved": solved, "trace": trace}
    if solved:
        result["reveal"] = s.reveal()
        result["reveal"]["system_prompt"] = system
    return result
