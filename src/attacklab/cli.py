import typer

from attacklab.scenario import load_all

app = typer.Typer(help="Atlas-AttackLab: practica y evalúa TTP de MITRE ATLAS.")


@app.command("list")
def list_scenarios() -> None:
    """Lista los escenarios y las técnicas ATLAS que cubren."""
    for s in load_all():
        typer.echo(f"{s.id:40} {', '.join(s.atlas):22} {s.level:8} {s.title}")


@app.command()
def show(scenario_id: str) -> None:
    """Muestra el objetivo de un escenario."""
    match = [s for s in load_all() if s.id == scenario_id]
    if not match:
        raise typer.BadParameter(f"No existe el escenario {scenario_id}")
    s = match[0]
    typer.echo(f"{s.title}\nATLAS: {', '.join(s.atlas)} · Táctica: {s.tactic} · Nivel: {s.level}\n\n{s.goal}")
