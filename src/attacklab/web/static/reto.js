// Pantalla de un reto: teoría y pistas, conversación con el objetivo y traza de cada intento.
import { watchModels } from '/static/model.js';

const id = decodeURIComponent(location.pathname.split('/').pop());
const $ = (s) => document.getElementById(s);
const el = (tag, props = {}, ...children) => {
  const n = Object.assign(document.createElement(tag), props);
  n.append(...children);
  return n;
};

const res = await fetch(`/api/retos/${encodeURIComponent(id)}`);
if (!res.ok) {
  $('title').textContent = 'Este reto no está instalado';
  throw new Error('reto no encontrado');
}
const reto = await res.json();
document.title = `${reto.title} · Atlas-AttackLab`;

let mode = 'vulnerable';
let messages = [];
let hintsUsed = 0;

// Columna de teoría
$('chips').append(
  ...reto.techniques.map((t) => el('span', { className: 'chip', textContent: t.id, title: t.name })),
  el('span', { className: 'chip plain', textContent: [...new Set(reto.techniques.flatMap((t) => t.tactics))].join(' · ') }));
$('title').textContent = reto.title;
$('story').textContent = reto.story;
$('goal').textContent = reto.goal;
$('technique').textContent = reto.technique;
reto.hints.forEach((text, i) => {
  const btn = el('button', { type: 'button', className: 'btn btn-ghost btn-small', textContent: `Ver pista ${i + 1}` });
  btn.addEventListener('click', () => {
    hintsUsed = Math.max(hintsUsed, i + 1);
    btn.replaceWith(el('div', { className: 'card', style: 'padding: 12px; font-size: 14px', textContent: text }));
  });
  $('hints').append(btn);
});

// Modo vulnerable / protegido
const modeButtons = document.querySelectorAll('[data-mode]');
function paintModes() {
  for (const b of modeButtons) {
    const on = b.dataset.mode === mode;
    b.className = `btn btn-small ${on ? 'btn-attack' : 'btn-ghost'}`;
    b.setAttribute('aria-pressed', String(on));
    const done = reto.progress[b.dataset.mode] ? ' ✓' : '';
    b.textContent = (b.dataset.mode === 'vulnerable' ? 'Vulnerable' : 'Protegido') + done;
  }
}
for (const b of modeButtons) {
  b.addEventListener('click', () => {
    if (b.dataset.mode === mode) return;
    mode = b.dataset.mode;
    restart();
  });
}

async function restart() {
  messages = [];
  $('chat').replaceChildren();
  $('solved').hidden = true;
  $('trace').replaceChildren(el('p', { className: 'muted', style: 'margin: 0; font-size: 14px', textContent: 'Partida nueva. El secreto ha cambiado.' }));
  paintModes();
  await fetch(`/api/retos/${encodeURIComponent(id)}/reset`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ mode }),
  });
  $('msg').focus();
}
$('restart').addEventListener('click', restart);

// Conversación
function bubble(role, text) {
  const mine = role === 'user';
  $('chat').append(el('div', {
    style: `max-width: 78%; padding: 12px 14px; white-space: pre-wrap; align-self: ${mine ? 'flex-end' : 'flex-start'}; ` +
      `border-radius: ${mine ? '12px 12px 4px 12px' : '12px 12px 12px 4px'}; ` +
      (mine ? 'background: var(--attack-bg); border: 1px solid var(--attack-line)' : 'background: var(--surface-2)'),
    textContent: text,
  }));
  $('chat').scrollTop = $('chat').scrollHeight;
}

const BADGE = {
  info: ['var(--muted)', 'var(--surface-2)'], ok: ['var(--defense)', '#0F2A36'], warn: ['var(--attack)', 'var(--attack-bg)'],
  blocked: ['var(--defense)', '#0F2A36'], bypassed: ['var(--attack)', 'var(--attack-bg)'],
  solved: ['var(--bg)', 'var(--attack)'], fail: ['var(--muted)', 'var(--surface-2)'], error: ['var(--attack)', 'var(--attack-bg)'],
};
const LABEL = { info: 'ok', ok: 'endurecido', warn: 'vulnerable', blocked: 'tapado', bypassed: 'esquivado', solved: 'resuelto', fail: 'no ha salido', error: 'error' };

function showTrace(trace) {
  $('trace').replaceChildren(...trace.map((s, i) => {
    const [color, bg] = BADGE[s.status] || BADGE.info;
    const box = el('div', { className: 'card', style: 'padding: 12px' },
      el('div', { style: 'display: flex; justify-content: space-between; gap: 8px; align-items: center' },
        el('strong', { style: 'font-size: 14px', textContent: `${i + 1} · ${s.step}` }),
        el('span', { style: `font-size: 11px; padding: 2px 8px; border-radius: 999px; color: ${color}; background: ${bg}`, textContent: LABEL[s.status] || s.status })),
      el('div', { className: 'muted', style: 'margin-top: 6px; font-size: 13px', textContent: s.detail }));
    if (s.data) {
      box.append(el('details', { style: 'margin-top: 8px; font-size: 12px' },
        el('summary', { style: 'cursor: pointer', textContent: 'Ver lo que recibe el modelo' }),
        el('pre', { className: 'code', style: 'margin-top: 8px; font-size: 12px', textContent: JSON.stringify(s.data, null, 1) })));
    }
    return box;
  }));
}

function showSolved(r) {
  reto.progress[mode] = r.progress?.[mode] || true;
  paintModes();
  $('solved-mode').textContent = `Modo ${mode}${hintsUsed ? ` · ${hintsUsed} pista${hintsUsed > 1 ? 's' : ''}` : ' · sin pistas'}`;
  $('reveal').textContent = r.reveal.system_prompt;
  $('why').textContent = reto.why_vulnerable;
  $('fix').textContent = reto.how_to_fix;
  $('mitigations').replaceChildren(...reto.mitigations.map((m) => el('span', { className: 'chip def', textContent: `${m.id} · ${m.name}` })));
  const next = [];
  if (mode === 'vulnerable') {
    const b = el('button', { type: 'button', className: 'btn btn-def', textContent: 'Probar la versión protegida' });
    b.addEventListener('click', () => { mode = 'protegido'; restart(); window.scrollTo({ top: 0 }); });
    next.push(b);
  }
  next.push(el('a', { className: 'btn btn-ghost', href: '/', textContent: 'Volver a la matriz' }));
  $('next').replaceChildren(...next);
  $('solved').hidden = false;
  $('solved').scrollIntoView({ behavior: 'smooth' });
}

$('form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const text = $('msg').value.trim();
  if (!text) return;
  $('msg').value = '';
  $('send').disabled = true;
  messages.push({ role: 'user', content: text });
  bubble('user', text);
  try {
    const r = await fetch(`/api/retos/${encodeURIComponent(id)}/attempt`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode, messages, hints_used: hintsUsed }),
    }).then((x) => x.json());
    showTrace(r.trace || []);
    if (r.reply == null) {
      messages.pop();
      bubble('assistant', r.error || r.detail || 'No ha habido respuesta.');
    } else {
      messages.push({ role: 'assistant', content: r.reply });
      bubble('assistant', r.reply);
      if (r.solved) showSolved(r);
    }
  } finally {
    $('send').disabled = false;
    $('msg').focus();
  }
});

paintModes();
watchModels($('model'));
