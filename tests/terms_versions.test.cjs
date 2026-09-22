const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');

const root = resolve(__dirname, '..');
const siteRoot = process.env.MUSILINK_SITE_DIR
  ? resolve(process.env.MUSILINK_SITE_DIR)
  : resolve(root, '..', 'musilink-site');

function readVersion(relativePath, declaration) {
  const source = readFileSync(resolve(root, relativePath), 'utf8');
  const matches = [...source.matchAll(declaration)];
  assert.equal(matches.length, 1,
    `${relativePath}: se esperaba una única declaración de versión de términos`);
  return matches[0][2];
}

function readSiteVersion() {
  const path = resolve(siteRoot, 'terms-and-conditions', 'index.html');
  let html;
  try {
    html = readFileSync(path, 'utf8');
  } catch (error) {
    assert.fail(`No se pudo leer ${path}. Clona musilink-site junto a MusiLink ` +
      `o configura MUSILINK_SITE_DIR con la ruta del repositorio. ${error.message}`);
  }

  const versions = [];
  for (const [tag] of html.matchAll(/<meta\b[^>]*>/gi)) {
    const attributes = Object.fromEntries(
      [...tag.matchAll(/([\w-]+)\s*=\s*(["'])(.*?)\2/g)]
        .map(([, name, , value]) => [name.toLowerCase(), value]),
    );
    if (attributes.name === 'terms-version') versions.push(attributes.content);
  }
  assert.equal(versions.length, 1,
    `${path}: se esperaba una única etiqueta meta name="terms-version"`);
  assert.ok(versions[0]?.trim(), `${path}: terms-version no puede estar vacía`);
  return versions[0];
}

test('la app, la callable y musilink-site exigen la misma versión de términos', () => {
  const app = readVersion('lib/utils/terms_and_conditions.dart',
    /^\s*static\s+const\s+version\s*=\s*(['"])([^'"]+)\1\s*;/gm);
  const callable = readVersion('functions/src/terms_acceptance.ts',
    /^\s*export\s+const\s+currentTermsVersion\s*=\s*(['"])([^'"]+)\1\s*;/gm);
  const site = readSiteVersion();

  assert.ok(app === callable && app === site,
    `Versiones de términos desincronizadas: app=${app}, callable=${callable}, ` +
    `musilink-site=${site}. Actualiza las tres versiones conjuntamente.`);
});
