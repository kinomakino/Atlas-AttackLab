// Catálogo de retos: validación y almacenamiento en Azure Table Storage.
import { TableClient } from '@azure/data-tables';

const PARTITION = 'reto';
const ID = /^[a-z0-9][a-z0-9-]{2,62}$/;
const ATLAS = /^AML\.T\d{4}(\.\d{3})?$/;
const VERSION = /^\d+\.\d+\.\d+$/;
const LEVELS = ['básico', 'intermedio', 'avanzado'];
const TIERS = ['free', 'paid'];
const STATUSES = ['draft', 'published'];

let client;
function table() {
  client ??= TableClient.fromConnectionString(process.env.CATALOG_CONNECTION, 'retos');
  return client;
}

const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

// Devuelve el reto limpio o lanza un Error con un mensaje para el usuario.
export function validate(id, body) {
  if (!ID.test(id)) throw new Error('Identificador no válido: minúsculas, números y guiones.');
  if (body.id && body.id !== id) throw new Error('El identificador no coincide con la URL.');
  const atlas = Array.isArray(body.atlas) ? [...new Set(body.atlas.map((a) => String(a).trim()))] : [];
  if (!atlas.length || atlas.length > 8 || !atlas.every((a) => ATLAS.test(a))) {
    throw new Error('Técnicas ATLAS no válidas. Formato: AML.T0051 o AML.T0051.000.');
  }
  const reto = {
    id,
    title: text(body.title, 120),
    atlas,
    level: body.level,
    tier: body.tier,
    status: body.status,
    version: text(body.version, 20),
    model: text(body.model, 80),
    image: text(body.image, 300),
    summary: text(body.summary, 600),
  };
  if (!reto.title) throw new Error('Falta el título.');
  if (!LEVELS.includes(reto.level)) throw new Error('Nivel no válido.');
  if (!TIERS.includes(reto.tier)) throw new Error('Tipo no válido.');
  if (!STATUSES.includes(reto.status)) throw new Error('Estado no válido.');
  if (!VERSION.test(reto.version)) throw new Error('Versión no válida. Formato: 0.1.0.');
  return reto;
}

const toEntity = (r) => ({ partitionKey: PARTITION, rowKey: r.id, ...r, atlas: JSON.stringify(r.atlas), updatedAt: new Date().toISOString() });

const fromEntity = (e) => ({
  id: e.rowKey,
  title: e.title,
  atlas: JSON.parse(e.atlas),
  level: e.level,
  tier: e.tier,
  status: e.status,
  version: e.version,
  model: e.model,
  image: e.image,
  summary: e.summary,
  updatedAt: e.updatedAt,
});

export async function list({ publishedOnly }) {
  const out = [];
  for await (const e of table().listEntities({ queryOptions: { filter: `PartitionKey eq '${PARTITION}'` } })) {
    const r = fromEntity(e);
    if (!publishedOnly || r.status === 'published') out.push(r);
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

export async function save(reto) {
  await table().upsertEntity(toEntity(reto), 'Replace');
  return reto;
}

export async function remove(id) {
  await table().deleteEntity(PARTITION, id);
}
