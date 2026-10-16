"""Catálogo oficial de MITRE ATLAS (github.com/mitre-atlas/atlas-data, Apache 2.0).

`attacklab import-atlas` descarga la release y la reduce a data/atlas.json, que es
lo que usa el portal: tácticas en el orden de la matriz, técnicas y mitigaciones.
"""

import json
from pathlib import Path

import httpx
import yaml

DATA_DIR = Path(__file__).resolve().parents[2] / "data"
CATALOG = DATA_DIR / "atlas.json"
RELEASE_URL = "https://github.com/mitre-atlas/atlas-data/releases/download/v{v}/ATLAS-{v}.yaml"


def build_catalog(raw: dict) -> dict:
    rels = raw["relationships"]

    def targets(source: str, kind: str) -> list[str]:
        return [r["target"] for r in rels.get(source, {}).get(kind, [])]

    order = sorted(rels["ATLAS-matrix"]["sequences"], key=lambda r: r["position"])
    tactics = [
        {"id": r["target"], "name": raw["tactics"][r["target"]]["name"],
         "description": raw["tactics"][r["target"]]["description"]}
        for r in order
    ]

    mitigated_by: dict[str, list[str]] = {}
    for mid in raw["mitigations"]:
        for tid in targets(mid, "mitigates"):
            mitigated_by.setdefault(tid, []).append(mid)

    techniques = {}
    for tid, t in raw["techniques"].items():
        parent = targets(tid, "specializes")
        techniques[tid] = {
            "id": tid,
            "name": t["name"],
            "description": t["description"],
            "maturity": t.get("maturity"),
            "tactics": targets(tid, "achieves"),
            "parent": parent[0] if parent else None,
            "mitigations": mitigated_by.get(tid, []),
        }

    mitigations = {
        mid: {"id": mid, "name": m["name"], "description": m["description"]}
        for mid, m in raw["mitigations"].items()
    }

    return {
        "version": raw["collection"]["version"],
        "source": "MITRE ATLAS, https://atlas.mitre.org (Apache 2.0)",
        "tactics": tactics,
        "techniques": techniques,
        "mitigations": mitigations,
    }


def import_release(version: str) -> dict:
    resp = httpx.get(RELEASE_URL.format(v=version), follow_redirects=True, timeout=60)
    resp.raise_for_status()
    catalog = build_catalog(yaml.safe_load(resp.text))
    DATA_DIR.mkdir(exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=1))
    return catalog


def load_catalog() -> dict:
    return json.loads(CATALOG.read_text())
