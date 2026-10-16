"""Un escenario es una carpeta en scenarios/ con un scenario.yaml."""

from dataclasses import dataclass, field
from pathlib import Path

import yaml

SCENARIOS_DIR = Path(__file__).resolve().parents[2] / "scenarios"


@dataclass
class Target:
    model: str
    flag: str
    system_prompt: str
    hardened_system_prompt: str


@dataclass
class Scenario:
    id: str
    title: str
    level: str
    atlas: list[str]
    story: str
    goal: str
    target: Target
    why_vulnerable: str
    how_to_fix: str
    path: Path
    hints: list[str] = field(default_factory=list)

    def public(self) -> dict:
        """Lo que ve el alumno antes de resolverlo: sin prompt ni flag."""
        return {k: getattr(self, k) for k in ("id", "title", "level", "atlas", "story", "goal", "hints")}

    def reveal(self) -> dict:
        return {
            "flag": self.target.flag,
            "why_vulnerable": self.why_vulnerable,
            "how_to_fix": self.how_to_fix,
        }


def load_all(base: Path = SCENARIOS_DIR) -> list[Scenario]:
    scenarios = []
    for spec in sorted(base.glob("*/scenario.yaml")):
        data = yaml.safe_load(spec.read_text())
        data["target"] = Target(**data["target"])
        scenarios.append(Scenario(path=spec.parent, **data))
    return scenarios


def get(scenario_id: str) -> Scenario | None:
    return next((s for s in load_all() if s.id == scenario_id), None)
