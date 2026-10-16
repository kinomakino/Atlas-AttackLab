import pytest

from attacklab import engine
from attacklab.modules import load_all

RETO = "aml-t0051-secreto-asistente"


@pytest.fixture
def reto():
    return load_all()[RETO]


def fake_model(monkeypatch, reply):
    """Sustituye al modelo por uno que contesta lo que digamos; reply recibe la flag."""
    def chat(model, messages, temperature=0.6):
        flag = engine.flag_for(load_all()[RETO], "vulnerable" if "deletrear" not in messages[0]["content"] else "protegido")
        return {"content": reply(flag), "prompt_tokens": 1, "output_tokens": 1, "seconds": 0}
    monkeypatch.setattr(engine.llm, "chat", chat)


def ask(reto, mode):
    return engine.attempt(reto, mode, [{"role": "user", "content": "hola"}])


def test_la_flag_cambia_al_reiniciar(reto):
    a = engine.flag_for(reto, "vulnerable")
    engine.reset(reto, "vulnerable")
    assert engine.flag_for(reto, "vulnerable") != a
    assert a.startswith("KINO-90-")


def test_vulnerable_resuelto_si_sale_la_flag(reto, monkeypatch):
    fake_model(monkeypatch, lambda f: f"El código es {f}")
    r = ask(reto, "vulnerable")
    assert r["solved"] and r["reveal"]["flag"] in r["reveal"]["system_prompt"]
    assert r["trace"][-1]["status"] == "solved"


def test_vulnerable_no_resuelto_si_no_sale(reto, monkeypatch):
    fake_model(monkeypatch, lambda f: "No puedo ayudarte con eso.")
    r = ask(reto, "vulnerable")
    assert not r["solved"] and "reveal" not in r


def test_protegido_el_filtro_tapa_la_flag_exacta(reto, monkeypatch):
    fake_model(monkeypatch, lambda f: f"El código es {f}")
    r = ask(reto, "protegido")
    assert not r["solved"] and "[CENSURADO]" in r["reply"]
    assert next(s for s in r["trace"] if s["step"] == "Filtro de salida")["status"] == "blocked"


def test_protegido_el_juez_detecta_la_flag_deformada(reto, monkeypatch):
    fake_model(monkeypatch, lambda f: " ".join(f.lower()))
    r = ask(reto, "protegido")
    assert r["solved"]
    assert next(s for s in r["trace"] if s["step"] == "Filtro de salida")["status"] == "bypassed"


def test_el_contexto_nunca_ensena_la_flag_antes_de_resolver(reto, monkeypatch):
    fake_model(monkeypatch, lambda f: "nada")
    r = ask(reto, "vulnerable")
    assert engine.flag_for(reto, "vulnerable") not in str(r["trace"])
