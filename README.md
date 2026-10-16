# Atlas-AttackLab

Lab local para aprender y practicar las técnicas de [MITRE ATLAS](https://atlas.mitre.org) atacando sistemas de IA vulnerables. Todo corre en tu equipo con Docker, con el modelo incluido.

Estado: en construcción. Decisiones en [docs/decisiones.md](docs/decisiones.md) y arquitectura en [docs/arquitectura.md](docs/arquitectura.md).

## Lo que ya funciona

```bash
uv run attacklab import-atlas   # catálogo oficial de ATLAS en data/atlas.json
uv run attacklab list           # labs definidos
```

Catálogo de ATLAS © MITRE, licencia Apache 2.0.
