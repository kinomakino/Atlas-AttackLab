"""Retos instalados como módulos: una carpeta con module.yaml y su contenido."""

import os
import re
from dataclasses import dataclass
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
RETOS_DIR = Path(os.environ.get("ATTACKLAB_RETOS", REPO / "retos"))
ENGINES = {"chat/1"}
_ID = re.compile(r"^[a-z0-9][a-z0-9-]{2,62}$")


@dataclass
class Module:
    id: str
    version: str
    title: str
    atlas: list[str]
    level: str
    tier: str
    engine: str
    model: str
    content: dict
    path: Path

    def summary(self) -> dict:
        return {k: getattr(self, k) for k in ("id", "version", "title", "atlas", "level", "tier", "model")}


def load(path: Path) -> Module:
    meta = yaml.safe_load((path / "module.yaml").read_text())
    if not _ID.fullmatch(meta.get("id", "")) or meta["id"] != path.name:
        raise ValueError(f"{path}: el id del módulo no es válido o no coincide con la carpeta")
    if meta.get("engine") not in ENGINES:
        raise ValueError(f"{path}: motor no soportado: {meta.get('engine')}")
    if meta.get("encryption", "none") != "none":
        raise ValueError(f"{path}: los módulos cifrados todavía no están soportados")
    content = yaml.safe_load((path / meta["content"]).read_text())
    return Module(
        id=meta["id"], version=meta["version"], title=meta["title"], atlas=meta["atlas"],
        level=meta["level"], tier=meta["tier"], engine=meta["engine"], model=meta["model"],
        content=content, path=path,
    )


def load_all(base: Path = RETOS_DIR) -> dict[str, Module]:
    return {m.id: m for m in (load(p.parent) for p in sorted(base.glob("*/module.yaml")))}
