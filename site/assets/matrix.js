// Pinta la matriz ATLAS y marca las técnicas que tienen reto según el catálogo.
const LOCAL_LAB = 'http://127.0.0.1:8080';

const el = (tag, props = {}, ...children) => {
  const n = Object.assign(document.createElement(tag), props);
  n.append(...children);
  return n;
};

async function loadCatalog() {
  try {
    const res = await fetch('/api/catalog');
    if (!res.ok) return [];
    return (await res.json()).retos || [];
  } catch {
    return [];
  }
}

const [matrix, retos] = await Promise.all([
  fetch('/data/atlas-matrix.json').then((r) => r.json()),
  loadCatalog(),
]);

// Un reto sobre una subtécnica (AML.T0051.000) también marca su técnica (AML.T0051).
const byTechnique = new Map();
for (const r of retos) {
  for (const id of r.atlas) {
    const parent = id.split('.').slice(0, 2).join('.');
    for (const key of new Set([id, parent])) {
      if (!byTechnique.has(key)) byTechnique.set(key, []);
      byTechnique.get(key).push(r);
    }
  }
}

document.getElementById('version').textContent = `MITRE ATLAS ${matrix.version}`;
const free = retos.filter((r) => r.tier === 'free').length;
document.getElementById('count').textContent = retos.length
  ? `${retos.length} ${retos.length === 1 ? 'reto disponible' : 'retos disponibles'} · ${free} gratis`
  : 'Todavía no hay retos publicados.';

const box = document.getElementById('matrix');
matrix.tactics.forEach((t, i) => {
  const col = el('div', { className: 'col', id: t.id });
  col.append(el('div', { className: 'col-head' },
    el('small', { textContent: `${String(i + 1).padStart(2, '0')} · ${t.techniques.length} técnicas` }),
    el('strong', { textContent: t.name })));
  for (const tech of t.techniques) {
    const found = byTechnique.get(tech.id) || [];
    const tier = found.some((r) => r.tier === 'free') ? 'free' : found.length ? 'paid' : '';
    const id = el('span', { className: 'id' }, el('span', { textContent: tech.id }));
    if (found.length > 1) id.append(el('span', { textContent: `${found.length} retos` }));
    const label = el('span', { textContent: tech.name });
    if (tier) {
      const cell = el('button', { type: 'button', className: `cell ${tier}` }, id, label);
      cell.addEventListener('click', () => openReto(found[0], cell));
      col.append(cell);
    } else {
      col.append(el('div', { className: 'cell' }, id, label));
    }
  }
  box.append(col);
});

if (location.hash) document.getElementById(location.hash.slice(1))?.scrollIntoView({ inline: 'start' });

// Panel lateral con el detalle del reto.
const drawer = document.getElementById('drawer');
let opener = null;

function openReto(r, from) {
  opener = from;
  const chips = document.getElementById('d-chips');
  chips.replaceChildren(...r.atlas.map((a) => el('span', { className: 'chip', textContent: a })),
    el('span', { className: `chip ${r.tier === 'free' ? '' : 'def'}`, textContent: r.tier === 'free' ? 'Gratis' : 'Suscripción' }),
    el('span', { className: 'chip plain', textContent: `Nivel ${r.level}` }));
  document.getElementById('d-title').textContent = r.title;
  document.getElementById('d-summary').textContent = r.summary || '';
  document.getElementById('d-meta').textContent = `Versión ${r.version}${r.model ? ` · modelo ${r.model}` : ''}`;
  const play = document.getElementById('d-play');
  if (r.tier === 'free') {
    play.replaceChildren(
      el('a', { className: 'btn btn-attack', href: `${LOCAL_LAB}/retos/${encodeURIComponent(r.id)}`, textContent: 'Abrir en mi lab' }),
      el('p', { className: 'muted', style: 'font-size: 14px; margin: 12px 0 0' },
        'Necesitas el lab arrancado en tu equipo. ¿Aún no lo tienes? ',
        el('a', { href: '/descargar.html', textContent: 'Descárgalo' })));
  } else {
    play.replaceChildren(el('div', { className: 'note' },
      el('span', { textContent: 'Este reto será parte de la suscripción. Muy pronto.' })));
  }
  drawer.hidden = false;
  document.getElementById('d-close').focus();
}

function closeDrawer() {
  drawer.hidden = true;
  opener?.focus();
}
document.getElementById('d-close').addEventListener('click', closeDrawer);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !drawer.hidden) closeDrawer(); });
