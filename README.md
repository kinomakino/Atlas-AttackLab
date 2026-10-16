# Atlas-AttackLab

Plataforma para aprender y practicar las técnicas de [MITRE ATLAS](https://atlas.mitre.org) atacando sistemas de IA vulnerables.

- **Plataforma online** (Azure): retos que puntúan, ranking y perfil.
- **Lab local** (Docker): todos los labs para practicar a fondo en tu equipo. No puntúa.

Estado: fase de diseño. Las decisiones están en [docs/decisiones.md](docs/decisiones.md).

## Lo que ya funciona

```bash
uv run attacklab import-atlas   # catálogo oficial de ATLAS en data/atlas.json
uv run attacklab list           # labs definidos
```

Catálogo de ATLAS © MITRE, licencia Apache 2.0.
