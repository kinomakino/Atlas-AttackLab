// Si quien navega tiene el rol admin, añade el acceso al panel en la cabecera.
try {
  const me = await fetch('/.auth/me').then((r) => r.json());
  if (me.clientPrincipal?.userRoles?.includes('admin')) {
    const a = Object.assign(document.createElement('a'), { href: '/admin/', className: 'btn btn-ghost btn-small', textContent: 'Admin' });
    document.querySelector('.nav-links')?.append(a);
  }
} catch {
  // Sin sesión o sin /.auth (en local): no se enseña nada.
}
