"""Progreso del alumno, guardado en su equipo. No puntúa en ningún ranking."""

import json
import os
import threading
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = Path(os.environ.get("ATTACKLAB_DATA", Path.home() / ".attacklab"))
_FILE = DATA_DIR / "progress.json"
_lock = threading.Lock()


def load() -> dict:
    try:
        return json.loads(_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def record(reto_id: str, mode: str, hints_used: int) -> dict:
    with _lock:
        data = load()
        entry = data.setdefault(reto_id, {})
        if mode not in entry:
            entry[mode] = {"solved_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                           "hints_used": hints_used}
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            tmp = _FILE.with_suffix(".tmp")
            tmp.write_text(json.dumps(data, indent=1))
            tmp.replace(_FILE)
        return entry
