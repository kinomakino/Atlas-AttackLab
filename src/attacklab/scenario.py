"""Un escenario es una carpeta en scenarios/ con un scenario.yaml."""

from dataclasses import dataclass, field
from pathlib import Path

import yaml

SCENARIOS_DIR = Path(__file__).resolve().parents[2] / "scenarios"


@dataclass
class Scenario:
    id: str
    title: str
    atlas: list[str]
    tactic: str
    level: str
    goal: str
    path: Path
    hints: list[str] = field(default_factory=list)


def load_all(base: Path = SCENARIOS_DIR) -> list[Scenario]:
    scenarios = []
    for spec in sorted(base.glob("*/scenario.yaml")):
        data = yaml.safe_load(spec.read_text())
        scenarios.append(Scenario(path=spec.parent, **data))
    return scenarios
