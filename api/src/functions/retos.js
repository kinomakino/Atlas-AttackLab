import { app } from '@azure/functions';
import { list, remove, save, validate } from '../catalog.js';

const json = (status, body) => ({ status, jsonBody: body, headers: { 'Cache-Control': 'no-store' } });

// Static Web Apps ya exige el rol "admin" en /api/admin/*; lo volvemos a comprobar aquí.
function isAdmin(request) {
  const header = request.headers.get('x-ms-client-principal');
  if (!header) return false;
  try {
    const principal = JSON.parse(Buffer.from(header, 'base64').toString('utf8'));
    return Array.isArray(principal.userRoles) && principal.userRoles.includes('admin');
  } catch {
    return false;
  }
}

// Público: lo que ve la matriz y leerá la herramienta local.
app.http('catalog', {
  route: 'catalog',
  methods: ['GET'],
  authLevel: 'anonymous',
  handler: async (_request, context) => {
    try {
      const retos = (await list({ publishedOnly: true })).map(({ status, updatedAt, ...r }) => r);
      return { status: 200, jsonBody: { version: 1, retos }, headers: { 'Cache-Control': 'public, max-age=60' } };
    } catch (err) {
      context.error(err);
      return json(500, { error: 'No se ha podido leer el catálogo.' });
    }
  },
});

app.http('adminRetos', {
  route: 'admin/retos/{id?}',
  methods: ['GET', 'PUT', 'DELETE'],
  authLevel: 'anonymous',
  handler: async (request, context) => {
    if (!isAdmin(request)) return json(403, { error: 'Sin permiso.' });
    const id = request.params.id;
    try {
      if (request.method === 'GET') return json(200, { retos: await list({ publishedOnly: false }) });
      if (!id) return json(400, { error: 'Falta el identificador.' });
      if (request.method === 'DELETE') {
        await remove(id);
        return { status: 204 };
      }
      let reto;
      try {
        reto = validate(id, await request.json());
      } catch (err) {
        return json(400, { error: err.message });
      }
      return json(200, await save(reto));
    } catch (err) {
      context.error(err);
      return json(500, { error: 'Error interno.' });
    }
  },
});
