// Guards against drift between the website's utility list and the app's catalog
// (Sources/MacPeekCore/Registry/UtilityCatalog.swift): same ids, names, categories and availability.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const swift = readFileSync(new URL('../../Sources/MacPeekCore/Registry/UtilityCatalog.swift', import.meta.url), 'utf8');
const ts = readFileSync(new URL('../src/data/utilities.ts', import.meta.url), 'utf8');

function swiftCatalog() {
  const out = [];
  for (const m of swift.matchAll(/UtilityInfo\(\s*id: "([a-z]+)", name: "(\w+)"[\s\S]*?category: \.(\w+), availability: \.(\w+)/g)) {
    out.push({ id: m[1], name: m[2], category: m[3] === 'everyday' ? 'everyday' : 'developer', status: m[4] === 'available' ? 'available' : 'coming-soon' });
  }
  return out;
}
function siteCatalog() {
  const out = [];
  for (const m of ts.matchAll(/id: '([a-z]+)', name: '(\w+)', category: '(\w+)', status: '([\w-]+)'/g)) {
    out.push({ id: m[1], name: m[2], category: m[3], status: m[4] });
  }
  return out;
}

test('website utilities match the Swift catalog (ids, names, categories, availability, order)', () => {
  const a = swiftCatalog(), b = siteCatalog();
  assert.ok(a.length >= 11, `parsed ${a.length} utilities from Swift`);
  assert.deepEqual(b, a);
});

test('AudioPeek is not listed anywhere yet', () => {
  assert.doesNotMatch(swift + ts, /audiopeek/i);
});
