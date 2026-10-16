// Inicio del lab local: la matriz ATLAS con los retos instalados y el progreso.
import { watchModels } from '/static/model.js';

const el = (tag, props = {}, ...children) => {
  const n = Object.assign(document.createElement(tag), props);
  n.append(...children);
  return n;
};

const [matrix, { retos }] = await Promise.all([
  fetch('/data/atlas-matrix.json').then((r) => r.json()),
  fetch('/api/retos').then((r) => r.json()),
]);

const solved = retos.filter((r) => r.progress.vulnerable).length;
document.getElementById('summary').textContent =
  `${retos.length} ${retos.length === 1 ? 'reto instalado' : 'retos instalados'} · has resuelto ${solved}. Tu progreso se guarda en tu equipo.`;

const byTechnique = new Map();
for (const r of retos) {
  for (const id of r.atlas) {
    for (const key of new Set([id, id.split('.').slice(0, 2).join('.')])) {
      if (!byTechnique.has(key)) byTechnique.set(key, []);
      byTechnique.get(key).push(r);
    }
  }
}

const box = document.getElementById('matrix');
matrix.tactics.forEach((t, i) => {
  const col = el('div', { className: 'col' }, el('div', { className: 'col-head' },
    el('small', { textContent: `${String(i + 1).padStart(2, '0')} · ${t.techniques.length} técnicas` }),
    el('strong', { textContent: t.name })));
  for (const tech of t.techniques) {
    const found = byTechnique.get(tech.id) || [];
    const id = el('span', { className: 'id' }, el('span', { textContent: tech.id }));
    const label = el('span', { textContent: tech.name });
    if (found.length) {
      const r = found[0];
      const mark = r.progress.protegido ? '✓✓' : r.progress.vulnerable ? '✓' : '';
      if (mark) id.append(el('span', { textContent: mark, title: 'Resuelto' }));
      col.append(el('a', { className: 'cell free', href: `/retos/${encodeURIComponent(r.id)}` }, id, label));
    } else {
      col.append(el('div', { className: 'cell' }, id, label));
    }
  }
  box.append(col);
});

watchModels(document.getElementById('model'));
