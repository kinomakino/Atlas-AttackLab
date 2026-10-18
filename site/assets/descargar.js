// Enseña primero los comandos del sistema de quien visita y pliega los del otro.
// Sin JavaScript se ven los dos bloques, como siempre.
const win = /Windows/i.test(navigator.userAgent);
const mine = document.querySelector(win ? '[data-os="windows"]' : '[data-os="unix"]');
const other = document.querySelector(win ? '[data-os="unix"]' : '[data-os="windows"]');
if (mine && other) {
  other.before(mine);
  mine.querySelector('.os-badge').hidden = false;
  const d = document.createElement('details');
  const s = Object.assign(document.createElement('summary'), {
    textContent: win ? '¿No usas Windows? Comandos para macOS y Linux' : '¿Usas Windows? Comandos para PowerShell',
  });
  s.style.cssText = 'cursor: pointer; font-weight: 600; font-size: 15px';
  other.replaceWith(d);
  other.style.marginTop = '12px';
  d.append(s, other);
}
