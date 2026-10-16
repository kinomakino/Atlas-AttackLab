from pathlib import Path
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from attacklab import engine, scenario
from attacklab.atlas import load_catalog

STATIC = Path(__file__).parent / "static"
app = FastAPI(title="Atlas-AttackLab")
app.mount("/static", StaticFiles(directory=STATIC), name="static")


class Message(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class Attempt(BaseModel):
    mode: Literal["vulnerable", "protegido"] = "vulnerable"
    messages: list[Message]


@app.get("/")
def index():
    return FileResponse(STATIC / "index.html")


@app.get("/lab/{lab_id}")
def lab_page(lab_id: str):
    return FileResponse(STATIC / "lab.html")


@app.get("/api/catalog")
def catalog():
    c = load_catalog()
    covered: dict[str, list[str]] = {}
    for s in scenario.load_all():
        for tid in s.atlas:
            covered.setdefault(tid, []).append(s.id)
    techniques = [
        {"id": t["id"], "name": t["name"], "tactics": t["tactics"], "parent": t["parent"],
         "labs": covered.get(t["id"], [])}
        for t in c["techniques"].values()
    ]
    return {"version": c["version"], "source": c["source"],
            "tactics": [{"id": t["id"], "name": t["name"]} for t in c["tactics"]],
            "techniques": techniques}


@app.get("/api/labs/{lab_id}")
def lab(lab_id: str):
    s = scenario.get(lab_id)
    if not s:
        raise HTTPException(404, "No existe ese laboratorio")
    c = load_catalog()
    tactic_names = {t["id"]: t["name"] for t in c["tactics"]}
    techniques = []
    for tid in s.atlas:
        t = c["techniques"][tid]
        techniques.append({
            **t,
            "tactics": [tactic_names[x] for x in t["tactics"]],
            "parent_name": c["techniques"][t["parent"]]["name"] if t["parent"] else None,
            "mitigations": [c["mitigations"][m] for m in t["mitigations"]],
        })
    return {**s.public(), "techniques": techniques, "model": s.target.model}


@app.post("/api/labs/{lab_id}/attempt")
def attempt(lab_id: str, body: Attempt):
    s = scenario.get(lab_id)
    if not s:
        raise HTTPException(404, "No existe ese laboratorio")
    if not body.messages or body.messages[-1].role != "user":
        raise HTTPException(400, "El último mensaje tiene que ser tuyo")
    return engine.attempt(s, body.mode, [m.model_dump() for m in body.messages])


@app.get("/api/health")
def health():
    try:
        tags = httpx.get(f"{engine.OLLAMA_URL}/api/tags", timeout=3).json()
        return {"ollama": True, "url": engine.OLLAMA_URL, "models": [m["name"] for m in tags.get("models", [])]}
    except httpx.HTTPError:
        return {"ollama": False, "url": engine.OLLAMA_URL, "models": []}
