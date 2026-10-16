// Comprueba que Ollama responde y que los modelos de los retos están descargados.
// Si falta alguno, ofrece descargarlo y enseña el progreso en el elemento indicado.
export async function watchModels(box) {
  const tick = async () => {
    let st;
    try {
      st = await fetch('/api/status').then((r) => r.json());
    } catch {
      return show('No se puede hablar con el lab. ¿Sigue arrancado?');
    }
    if (!st.ollama) return show('El modelo todavía está arrancando. Espera unos segundos…', true);
    const missing = Object.entries(st.models).filter(([, m]) => !m.ready);
    if (!missing.length) {
      box.hidden = true;
      return;
    }
    const [name, m] = missing[0];
    const pull = m.pull;
    if (pull && !pull.error && !pull.done) {
      show(`Descargando el modelo ${name}: ${pull.percent ?? 0} %. Solo pasa la primera vez.`, true);
    } else {
      const btn = Object.assign(document.createElement('button'), {
        type: 'button', className: 'btn btn-attack btn-small', textContent: `Descargar ${name}`,
      });
      btn.addEventListener('click', async () => {
        btn.disabled = true;
        await fetch('/api/models/pull', {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: name }),
        });
        setTimeout(tick, 1000);
      });
      const text = pull?.error ? `La descarga de ${name} ha fallado: ${pull.error}. ` : `Los retos necesitan el modelo ${name} (unos 2 GB). `;
      box.replaceChildren(Object.assign(document.createElement('span'), { textContent: text }), btn);
      box.hidden = false;
    }
  };
  const show = (text, again) => {
    box.textContent = text;
    box.hidden = false;
    if (again) setTimeout(tick, 2000);
  };
  await tick();
}
