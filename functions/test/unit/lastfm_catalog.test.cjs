const assert = require('node:assert/strict');
const { test } = require('node:test');
const { LastFmCatalog } = require('../../lib/lastfm_catalog.js');

function cacheStore() {
  const documents = new Map();
  const firestore = {
    doc(path) {
      return {
        async get() { return { data: () => documents.get(path) }; },
        async set(data) { documents.set(path, data); },
      };
    },
  };
  return { documents, firestore, catalog: new LastFmCatalog(firestore) };
}

const parse = (data) => data.values;
const lookup = (catalog, artist = 'Muse', method = 'artist.getSimilar') => (
  catalog.getStrings(method, artist, 'test-secret', parse)
);

test('persistent cache is shared by instances and separates methods and artist identities', async (t) => {
  const { catalog, documents, firestore } = cacheStore();
  const fetchMock = t.mock.method(global, 'fetch', async () => Response.json({ values: ['Radiohead'] }));
  await lookup(catalog, '  Muse  ');
  assert.deepEqual(await lookup(new LastFmCatalog(firestore), 'muse'), ['Radiohead']);
  assert.equal(fetchMock.mock.callCount(), 1);
  await lookup(catalog, 'Muse', 'artist.getTopTags');
  await lookup(catalog, 'Another artist');
  assert.equal(fetchMock.mock.callCount(), 3);
  assert.equal(documents.size, 3);
  assert.equal(JSON.stringify([...documents]).includes('test-secret'), false);
});

test('concurrent misses for the same artist share a single upstream request', async (t) => {
  const { catalog } = cacheStore();
  let release;
  const ready = new Promise((resolve) => { release = resolve; });
  const fetchMock = t.mock.method(global, 'fetch', async () => {
    await ready;
    return Response.json({ values: ['Radiohead'] });
  });
  const calls = Array.from({ length: 8 }, () => lookup(catalog));
  release();
  assert.deepEqual(await Promise.all(calls), Array.from({ length: 8 }, () => ['Radiohead']));
  assert.equal(fetchMock.mock.callCount(), 1);
});

test('positive and truly empty entries expire after 24 hours and five minutes', async (t) => {
  let now = 1_000;
  t.mock.method(Date, 'now', () => now);
  const { catalog } = cacheStore();
  const fetchMock = t.mock.method(global, 'fetch', async (input) => Response.json({
    values: new URL(input).searchParams.get('artist') === 'Empty' ? [] : ['Radiohead'],
  }));
  await lookup(catalog);
  await lookup(catalog, 'Empty');
  now += 5 * 60_000 - 1;
  await lookup(catalog);
  await lookup(catalog, 'Empty');
  assert.equal(fetchMock.mock.callCount(), 2);
  now++;
  await lookup(catalog, 'Empty');
  assert.equal(fetchMock.mock.callCount(), 3);
  now = 1_000 + 24 * 60 * 60_000;
  await lookup(catalog);
  assert.equal(fetchMock.mock.callCount(), 4);
});

test('provider cache headers shorten or disable storage', async (t) => {
  let now = 1_000;
  t.mock.method(Date, 'now', () => now);
  const { catalog, documents } = cacheStore();
  let headers = { 'Cache-Control': 'public, max-age=60', Age: '50' };
  const fetchMock = t.mock.method(global, 'fetch', async () => Response.json({ values: ['Radiohead'] }, { headers }));
  await lookup(catalog);
  assert.equal([...documents.values()][0].expiresAt.toMillis(), now + 10_000);
  now += 10_000;
  await lookup(catalog);
  assert.equal(fetchMock.mock.callCount(), 2);
  for (const control of ['no-store', 'no-cache', 'private', 'max-age=0']) {
    documents.clear();
    headers = { 'Cache-Control': control };
    await lookup(catalog);
    await lookup(catalog);
    assert.equal(documents.size, 0);
  }
  headers = { Date: new Date(now).toUTCString(), Expires: new Date(now + 30_000).toUTCString() };
  await lookup(catalog);
  assert.equal([...documents.values()][0].expiresAt.toMillis(), now + 30_000);
});

test('network, HTTP, API and JSON errors never populate the cache or leave pending failures', async (t) => {
  const { catalog, documents } = cacheStore();
  const cases = [
    [() => { throw new Error('offline'); }, 'unavailable'],
    [() => new Response('', { status: 503 }), 'unavailable'],
    [() => new Response('', { status: 429 }), 'resource-exhausted'],
    [() => Response.json({ error: 29 }), 'resource-exhausted'],
    [() => Response.json({ error: 11 }), 'unavailable'],
    [() => new Response('broken JSON'), 'unavailable'],
  ];
  for (const [response, code] of cases) {
    const mocked = t.mock.method(global, 'fetch', async () => response());
    await assert.rejects(lookup(catalog), { code });
    assert.equal(documents.size, 0);
    mocked.mock.restore();
  }
  t.mock.method(global, 'fetch', async () => Response.json({ values: ['Radiohead'] }));
  assert.deepEqual(await lookup(catalog), ['Radiohead']);
  assert.equal(documents.size, 1);
});
