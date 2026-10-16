import typer

from attacklab.modules import load_all

app = typer.Typer(help="Atlas-AttackLab: practica las técnicas de MITRE ATLAS en tu equipo.")


@app.command("list")
def list_retos() -> None:
    """Lista los retos instalados."""
    for m in load_all().values():
        typer.echo(f"{m.id:36} {', '.join(m.atlas):28} {m.level:10} {m.title}")


@app.command()
def serve(host: str = "127.0.0.1", port: int = 8080, reload: bool = False) -> None:
    """Arranca la web del lab."""
    import uvicorn

    uvicorn.run("attacklab.web.app:app", host=host, port=port, reload=reload)


@app.command("import-atlas")
def import_atlas(version: str = "2026.09") -> None:
    """Descarga el catálogo oficial de ATLAS a data/atlas.json."""
    from attacklab.atlas import import_release

    c = import_release(version)
    typer.echo(f"ATLAS {c['version']}: {len(c['tactics'])} tácticas, "
               f"{len(c['techniques'])} técnicas, {len(c['mitigations'])} mitigaciones")
