const res = await fetch('/data/atlas-matrix.json');
const m = await res.json();
const box = document.getElementById('tactics');
m.tactics.forEach((t, i) => {
  const a = document.createElement('a');
  a.className = 'tactic-chip';
  a.href = '/matriz.html#' + t.id;
  const n = document.createElement('small'); n.textContent = String(i + 1).padStart(2, '0');
  const name = document.createElement('strong'); name.textContent = t.name;
  const c = document.createElement('span'); c.textContent = t.techniques.length + ' técnicas';
  a.append(n, name, c);
  box.append(a);
});
