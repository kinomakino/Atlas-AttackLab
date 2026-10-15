# Atlas-AttackLab

Framework para evaluar y practicar las TTP de [MITRE ATLAS](https://atlas.mitre.org) contra sistemas de IA.

- **Escenarios** (`scenarios/`): cada uno es un objetivo vulnerable en Docker (LLM, RAG, agente con MCP, modelo ML) mapeado a técnicas ATLAS.
- **Evaluador** (`src/attacklab/`): lanza las TTP contra un escenario o un sistema real y puntúa si el ataque tuvo éxito.

## Uso

```bash
uv run attacklab list
uv run attacklab show aml-t0051-prompt-injection-directa
```

## Formato de un escenario

`scenarios/<id>/scenario.yaml` con `id`, `title`, `atlas` (IDs de técnica), `tactic`, `level`, `goal` y `hints`. El objetivo vulnerable va en la misma carpeta con su `Dockerfile`.
