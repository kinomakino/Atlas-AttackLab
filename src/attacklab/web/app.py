"""Web y API del lab local. Sin cuentas ni login: todo corre en el equipo del alumno."""

from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from attacklab import engine, llm, modules, progress
from attacklab.atlas import load_catalog

STATIC = Path(__file__).parent / "static"
SITE = modules.REPO / "site"

app = FastAPI(title="Atlas-AttackLab", docs_url=None, redoc_url=None)
app.mount("/assets", StaticFiles(directory=SITE / "assets"), name="assets")
app.mount("/data", StaticFiles(directory=SITE / "data"), name="data")
app.mount("/static", StaticFiles(directory=STATIC), name="static")

ATLAS = load_catalog()


@app.middleware("http")
async def security_headers(request, call_next):
    resp = await call_next(request)
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'")
    resp.headers["X-Content-Type-Options"] = "nosniff"
    return resp


def _module(reto_id: str) -> modules.Module:
    m = modules.load_all().get(reto_id)
    if not m:
        raise HTTPException(404, "Ese reto no está instalado")
    return m


@app.get("/")
def index():
    return FileResponse(STATIC / "index.html")


@app.get("/retos/{reto_id}")
def reto_page(reto_id: str):
    return FileResponse(STATIC / "reto.html")


@app.get("/api/health")
def health():
    return {"ok": True}


@app.get("/api/status")
def status():
    if not llm.reachable():
        return {"ollama": False, "models": {}}
    have = llm.installed_models()
    needed = {m.model for m in modules.load_all().values()}
    return {"ollama": True, "models": {
        name: {"ready": name in have or f"{name}:latest" in have, "pull": llm.pulls.get(name)} for name in needed}}


class Pull(BaseModel):
    model: str = Field(max_length=100)


@app.post("/api/models/pull")
def pull(body: Pull):
    if body.model not in {m.model for m in modules.load_all().values()}:
        raise HTTPException(400, "Ese modelo no lo necesita ningún reto instalado")
    return llm.start_pull(body.model)


@app.get("/api/retos")
def retos():
    done = progress.load()
    return {"retos": [{**m.summary(), "progress": done.get(m.id, {})} for m in modules.load_all().values()]}


@app.get("/api/retos/{reto_id}")
def reto(reto_id: str):
    m = _module(reto_id)
    c = m.content
    tactics = {t["id"]: t["name"] for t in ATLAS["tactics"]}
    techniques = []
    for tid in m.atlas:
        t = ATLAS["techniques"].get(tid)
        if t:
            parent = ATLAS["techniques"].get(t["parent"]) if t["parent"] else None
            techniques.append({"id": tid, "name": f"{parent['name']}: {t['name']}" if parent else t["name"],
                               "tactics": [tactics[x] for x in t["tactics"]]})
    mitigations = [{"id": mid, "name": ATLAS["mitigations"][mid]["name"]}
                   for mid in c.get("mitigations", []) if mid in ATLAS["mitigations"]]
    return {**m.summary(), "story": c["story"], "goal": c["goal"], "technique": c["technique"],
            "hints": c.get("hints", []), "techniques": techniques, "mitigations": mitigations,
            "why_vulnerable": c["why_vulnerable"], "how_to_fix": c["how_to_fix"],
            "progress": progress.load().get(m.id, {})}


class Message(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(max_length=4000)


class Attempt(BaseModel):
    mode: Literal["vulnerable", "protegido"] = "vulnerable"
    messages: list[Message] = Field(min_length=1, max_length=40)
    hints_used: int = Field(0, ge=0, le=10)


@app.post("/api/retos/{reto_id}/attempt")
def attempt(reto_id: str, body: Attempt):
    m = _module(reto_id)
    if body.messages[-1].role != "user":
        raise HTTPException(400, "El último mensaje tiene que ser tuyo")
    result = engine.attempt(m, body.mode, [x.model_dump() for x in body.messages])
    if result["solved"]:
        result["progress"] = progress.record(m.id, body.mode, body.hints_used)
    return result


class Reset(BaseModel):
    mode: Literal["vulnerable", "protegido"]


@app.post("/api/retos/{reto_id}/reset")
def reset(reto_id: str, body: Reset):
    engine.reset(_module(reto_id), body.mode)
    return {"ok": True}
