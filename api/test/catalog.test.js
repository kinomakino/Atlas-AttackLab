import assert from 'node:assert/strict';
import { test } from 'node:test';
import { validate } from '../src/catalog.js';

const ok = {
  title: 'Saca el secreto del asistente',
  atlas: ['AML.T0051.000', 'AML.T0056'],
  level: 'básico',
  tier: 'free',
  status: 'published',
  version: '0.1.0',
};

test('acepta un reto válido y limpia los campos', () => {
  const r = validate('aml-t0051-secreto', { ...ok, title: '  Saca el secreto  ', extra: 'x' });
  assert.equal(r.title, 'Saca el secreto');
  assert.equal(r.extra, undefined);
  assert.deepEqual(r.atlas, ['AML.T0051.000', 'AML.T0056']);
});

test('rechaza identificadores, técnicas y enumerados no válidos', () => {
  assert.throws(() => validate('../etc', ok), /Identificador/);
  assert.throws(() => validate('reto-1', { ...ok, id: 'otro' }), /no coincide/);
  assert.throws(() => validate('reto-1', { ...ok, atlas: ['T0051'] }), /ATLAS/);
  assert.throws(() => validate('reto-1', { ...ok, atlas: [] }), /ATLAS/);
  assert.throws(() => validate('reto-1', { ...ok, tier: 'vip' }), /Tipo/);
  assert.throws(() => validate('reto-1', { ...ok, version: '1' }), /Versión/);
  assert.throws(() => validate('reto-1', { ...ok, title: ' ' }), /título/);
});
