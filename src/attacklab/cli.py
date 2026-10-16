import typer

from attacklab.scenario import load_all

app = typer.Typer(help="Atlas-AttackLab: practica y evalúa TTP de MITRE ATLAS.")


@app.command("list")
def list_scenarios() -> None:
    """Lista los escenarios y las técnicas ATLAS que cubren."""
    for s in load_all():
        typer.echo(f"{s.id:40} {', '.join(s.atlas):28} {s.level:8} {s.title}")


@app.command()
def serve(host: str = "127.0.0.1", port: int = 8000, reload: bool = False) -> None:
    """Arranca el portal web."""
    import uvicorn

    uvicorn.run("attacklab.web.app:app", host=host, port=port, reload=reload)


@app.command("import-atlas")
def import_atlas(version: str = "2026.09") -> None:
    """Descarga el catálogo oficial de ATLAS a data/atlas.json."""
    from attacklab.atlas import import_release

    c = import_release(version)
    typer.echo(f"ATLAS {c['version']}: {len(c['tactics'])} tácticas, "
               f"{len(c['techniques'])} técnicas, {len(c['mitigations'])} mitigaciones")
