// Gestión del catálogo. El acceso lo controla Static Web Apps (rol "admin") y la API lo vuelve a comprobar.
const rows = document.getElementById('rows');
const form = document.getElementById('form');
const msg = document.getElementById('msg');
let retos = [];

const el = (tag, props = {}, ...children) => {
  const n = Object.assign(document.createElement(tag), props);
  n.append(...children);
  return n;
};

async function api(path, options = {}) {
  const res = await fetch(`/api/admin/retos${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || res.statusText);
  }
  return res.status === 204 ? null : res.json();
}

async function load() {
  const me = await fetch('/.auth/me').then((r) => r.json()).catch(() => ({}));
  document.getElementById('who').textContent = me.clientPrincipal?.userDetails || '';
  retos = (await api('')).retos;
  render();
}

function render() {
  if (!retos.length) {
    rows.replaceChildren(el('tr', {}, el('td', { colSpan: 7, className: 'muted', textContent: 'No hay retos. Crea el primero.' })));
    return;
  }
  rows.replaceChildren(...retos.map((r) => {
    const edit = el('button', { type: 'button', className: 'btn btn-ghost btn-small', textContent: 'Editar' });
    edit.addEventListener('click', () => openForm(r));
    const del = el('button', { type: 'button', className: 'btn btn-ghost btn-small', textContent: 'Borrar' });
    del.addEventListener('click', () => remove(r));
    return el('tr', {},
      el('td', {}, el('strong', { textContent: r.title }), el('div', { className: 'mono muted', style: 'font-size: 12px', textContent: r.id })),
      el('td', { className: 'mono', style: 'font-size: 13px', textContent: r.atlas.join(', ') }),
      el('td', { textContent: r.level }),
      el('td', { textContent: r.tier === 'free' ? 'Gratis' : 'Suscripción' }),
      el('td', { className: 'mono', textContent: r.version }),
      el('td', {}, el('span', { className: `status ${r.status}`, textContent: r.status === 'published' ? 'Publicado' : 'Borrador' })),
      el('td', { style: 'white-space: nowrap' }, edit, ' ', del));
  }));
}

function openForm(r) {
  form.reset();
  msg.textContent = '';
  document.getElementById('form-title').textContent = r ? `Editar: ${r.title}` : 'Nuevo reto';
  form.elements.id.readOnly = !!r;
  if (r) {
    for (const [k, v] of Object.entries(r)) {
      if (form.elements[k]) form.elements[k].value = Array.isArray(v) ? v.join(', ') : v ?? '';
    }
  }
  form.hidden = false;
  form.elements[r ? 'title' : 'id'].focus();
}

async function remove(r) {
  if (!confirm(`¿Borrar "${r.title}" del catálogo? Dejará de aparecer en la matriz.`)) return;
  await api(`/${encodeURIComponent(r.id)}`, { method: 'DELETE' });
  await load();
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const data = Object.fromEntries(new FormData(form));
  data.atlas = data.atlas.split(',').map((s) => s.trim()).filter(Boolean);
  msg.textContent = 'Guardando…';
  try {
    await api(`/${encodeURIComponent(data.id)}`, { method: 'PUT', body: JSON.stringify(data) });
    form.hidden = true;
    await load();
  } catch (err) {
    msg.textContent = `No se ha guardado: ${err.message}`;
  }
});

document.getElementById('new').addEventListener('click', () => openForm(null));
document.getElementById('cancel').addEventListener('click', () => { form.hidden = true; });

load().catch((err) => {
  rows.replaceChildren(el('tr', {}, el('td', { colSpan: 7, className: 'muted', textContent: `Error al cargar: ${err.message}` })));
});
