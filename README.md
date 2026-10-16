# Atlas-AttackLab

Lab local para aprender y practicar las técnicas de [MITRE ATLAS](https://atlas.mitre.org) atacando sistemas de IA vulnerables. Todo corre en tu equipo con Docker, con el modelo incluido.

Estado: en construcción. Decisiones en [docs/decisiones.md](docs/decisiones.md) y arquitectura en [docs/arquitectura.md](docs/arquitectura.md).

## Arrancar el lab

Solo necesitas Docker.

```bash
docker compose up -d --build
```

Abre http://127.0.0.1:8080. La primera vez la web te ofrece descargar el modelo (unos 2 GB).

- Todo escucha solo en `127.0.0.1`. Ollama no publica ningún puerto.
- Tu progreso se guarda en el volumen `progreso`; los modelos, en `modelos`.
- `ATTACKLAB_THREADS` fija los hilos de inferencia si quieres ajustarlos.

## Desarrollo

```bash
uv run pytest                   # tests del motor
uv run attacklab list           # retos instalados (carpeta retos/)
uv run attacklab import-atlas   # catálogo oficial de ATLAS en data/atlas.json
```

Cada reto es un módulo en `retos/<id>/`: `module.yaml` (manifiesto) y su contenido.

Catálogo de ATLAS © MITRE, licencia Apache 2.0.
