"""Motor de los retos de tipo chat/1: monta el contexto, llama al modelo, aplica las
defensas del modo, hace de juez y deja la traza de cada paso para la web."""

import re
import secrets
import string

from attacklab import llm
from attacklab.modules import Module

MODES = ("vulnerable", "protegido")
HIDDEN = "[oculto hasta que resuelvas el reto]"

# Flag de la partida en curso, por reto y modo. Cambia al empezar de nuevo.
_flags: dict[tuple[str, str], str] = {}


def _new_flag(fmt: str) -> str:
    alphabet = string.ascii_uppercase + string.digits
    return fmt.replace("{random}", "".join(secrets.choice(alphabet) for _ in range(6)))


def flag_for(m: Module, mode: str) -> str:
    key = (m.id, mode)
    if key not in _flags:
        _flags[key] = _new_flag(m.content["flag_format"])
    return _flags[key]


def reset(m: Module, mode: str) -> None:
    _flags.pop((m.id, mode), None)


def _normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def leaks(text: str, flag: str) -> bool:
    """El juez da por buena la flag aunque venga con espacios, guiones cambiados o en minúsculas."""
    return _normalize(flag) in _normalize(text)


def output_filter(text: str, flag: str) -> tuple[str, bool]:
    """Defensa del modo protegido: tapa la flag si aparece tal cual."""
    if flag in text:
        return text.replace(flag, "[CENSURADO]"), True
    return text, False


def attempt(m: Module, mode: str, history: list[dict]) -> dict:
    cfg = m.content["modes"][mode]
    flag = flag_for(m, mode)
    system = cfg["system_prompt"].replace("{flag}", flag)
    defenses = cfg.get("defenses", [])
    trace = [
        {"step": "Tu mensaje", "status": "info",
         "detail": "Llega al backend tal cual. Este asistente no valida la entrada."},
        {"step": "Contexto del modelo", "status": "warn" if mode == "vulnerable" else "ok",
         "detail": ("Instrucciones del sistema + tus mensajes, todo como texto seguido. El secreto va dentro."
                    if mode == "vulnerable" else
                    "Instrucciones endurecidas + tus mensajes. El secreto sigue dentro del contexto."),
         "data": [{"role": "system", "content": HIDDEN}] + history},
    ]

    try:
        out = llm.chat(m.model, [{"role": "system", "content": system}] + history)
    except Exception as e:  # noqa: BLE001
        trace.append({"step": "Modelo", "status": "error", "detail": f"No ha respondido: {e}"})
        return {"reply": None, "solved": False, "trace": trace, "error": "El modelo no ha respondido. ¿Está arrancado y descargado?"}

    trace.append({"step": "Modelo", "status": "info",
                  "detail": f"{m.model} · {out['prompt_tokens']} tokens de entrada y {out['output_tokens']} de salida · {out['seconds']} s"})

    raw = out["content"]
    model_leaked = leaks(raw, flag)
    reply = raw
    if "output_filter" in defenses:
        reply, blocked = output_filter(raw, flag)
        trace.append({
            "step": "Filtro de salida",
            "status": "blocked" if blocked else ("bypassed" if model_leaked else "ok"),
            "detail": ("El modelo soltó el código y el filtro lo ha tapado." if blocked
                       else "El código ha salido de otra forma y el filtro no lo ha reconocido." if model_leaked
                       else "Busca el código exacto en la respuesta. No ha encontrado nada que tapar."),
        })

    solved = leaks(reply, flag)
    trace.append({
        "step": "Juez",
        "status": "solved" if solved else "fail",
        "detail": ("Reto resuelto: el secreto ha salido." if solved
                   else "El modelo cedió, pero no te ha llegado." if model_leaked
                   else "El secreto no ha salido."),
    })
    result = {"reply": reply, "solved": solved, "trace": trace}
    if solved:
        result["reveal"] = {"system_prompt": system, "flag": flag}
    return result
