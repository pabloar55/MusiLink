const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const html = readFileSync(`${__dirname}/../web/index.html`, 'utf8');
const source = html.match(
  /<script>\s*(\/\/ Enlaces compartidos[\s\S]*?)<\/script>/,
)[1];

const android =
  'Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36';
const androidWebView =
  'Mozilla/5.0 (Linux; Android 16; Pixel 9 Build/AB1; wv) AppleWebKit/537.36 Version/4.0 Chrome/140.0 Mobile Safari/537.36';
const iphone =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Version/26.0 Mobile/15E148 Safari/604.1';
const playUrl = 'https://play.google.com/store/apps/details?id=app.musilink';
const profileIntent =
  'intent://musilink.app/u/pablo_1#Intent;scheme=https;package=app.musilink;' +
  `S.browser_fallback_url=${encodeURIComponent(playUrl)};end`;

function open(path, { userAgent = android, standalone = false, stored = [],
  storageBlocked = false } = {}) {
  const result = { state: null, replaced: null, href: null };
  const location = {
    pathname: path,
    replace: (url) => { result.replaced = url; },
  };
  Object.defineProperty(location, 'href', {
    set: (url) => { result.href = url; },
  });
  const window = {
    location,
    navigator: { userAgent },
    matchMedia: () => ({ matches: standalone }),
    history: { replaceState: (_, __, url) => { result.state = url; } },
  };
  Object.defineProperty(window, 'localStorage', {
    get() {
      if (storageBlocked) throw new Error('blocked');
      return { length: stored.length, key: (index) => stored[index] };
    },
  });
  runInNewContext(source, { window });
  return result;
}

test('fuera de Android el enlace continúa en la web', () => {
  assert.deepEqual(open('/u/Pablo_1', { userAgent: iphone }), {
    state: '/#/u/pablo_1', replaced: null, href: null,
  });
  assert.deepEqual(open('/invite/', { userAgent: iphone }), {
    state: '/', replaced: null, href: null,
  });
});

test('Android entrega el perfil a la app y deja Google Play como alternativa', () => {
  assert.deepEqual(open('/u/Pablo_1'), {
    state: '/#/u/pablo_1', replaced: null, href: profileIntent,
  });
});

test('Android sin perfil que abrir va a Google Play', () => {
  assert.deepEqual(open('/invite'), {
    state: null, replaced: playUrl, href: null,
  });
});

test('un WebView de Android no recibe un intent', () => {
  assert.deepEqual(open('/u/pablo_1', { userAgent: androidWebView }), {
    state: null, replaced: playUrl, href: null,
  });
});

test('quien ya usa la web en Android se queda en ella', () => {
  const expected = { state: '/#/u/pablo_1', replaced: null, href: null };
  assert.deepEqual(open('/u/pablo_1', { standalone: true }), expected);
  assert.deepEqual(
    open('/u/pablo_1', {
      stored: ['flutter.theme_mode', 'flutter.user_setup_state_v2_uid123'],
    }),
    expected,
  );
  assert.deepEqual(
    open('/invite', { stored: ['flutter.user_setup_state_v2_uid123'] }),
    { state: '/', replaced: null, href: null },
  );
});

test('otras claves o un almacenamiento bloqueado no cuentan como uso de la web', () => {
  assert.equal(
    open('/u/pablo_1', { stored: ['flutter.theme_mode'] }).href,
    profileIntent,
  );
  assert.equal(open('/u/pablo_1', { storageBlocked: true }).href, profileIntent);
});

test('las rutas que no son enlaces compartidos no se tocan', () => {
  for (const path of ['/', '/u/ab', '/u/a/b', '/u/', '/invitex']) {
    assert.deepEqual(open(path), { state: null, replaced: null, href: null });
  }
});

test('la clave buscada coincide con la de UserSetupCache', () => {
  const cache = readFileSync(
    `${__dirname}/../lib/utils/user_setup_cache.dart`,
    'utf8',
  );
  const prefix = cache.match(/_keyPrefix = '([^']+)'/)[1];
  assert.ok(source.includes(`'flutter.${prefix}'`));
});
