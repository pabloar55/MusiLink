const assert = require('node:assert/strict');
const { test } = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');
const { db } = require('../../lib/firebase.js');
const {
  catalogSearchWindowMs,
  maxCatalogSearchesPerWindow,
  consumeCatalogSearchQuota,
} = require('../../lib/rate_limits.js');
const { searchSpotifyArtists, searchSpotifyTracks } = require('../../lib/spotify.js');
const { getSimilarArtists } = require('../../lib/lastfm.js');

const endpoints = [
  [searchSpotifyArtists, { query: 'Muse' }],
  [searchSpotifyTracks, { query: 'Muse' }],
  [getSimilarArtists, { artistName: 'Muse' }],
];

function setTestSecrets(t) {
  for (const key of ['SPOTIFY_CLIENT_ID', 'SPOTIFY_CLIENT_SECRET', 'LASTFM_API_KEY']) {
    const original = process.env[key];
    process.env[key] = 'test-catalog-secret';
    t.after(() => {
      if (original === undefined) delete process.env[key];
      else process.env[key] = original;
    });
  }
}

function quotaStore(t, initial = {}) {
  const documents = new Map(Object.entries(initial));
  const transaction = t.mock.method(db, 'runTransaction', async (callback) => callback({
    async get(ref) {
      return { data: () => documents.get(ref.path) };
    },
    set(ref, fields, options) {
      assert.deepEqual(options, { merge: true });
      documents.set(ref.path, { ...documents.get(ref.path), ...fields });
    },
  }));
  return { documents, transaction };
}

test('catalog quota creates a window, isolates users and preserves other counters', async (t) => {
  const { documents } = quotaStore(t, { 'rate_limits/alice': { messageCount: 7 } });
  const now = Timestamp.fromMillis(1_000);
  await consumeCatalogSearchQuota(db, 'alice', now);
  await consumeCatalogSearchQuota(db, 'alice', Timestamp.fromMillis(2_000));
  await consumeCatalogSearchQuota(db, 'bob', now);
  assert.deepEqual(documents.get('rate_limits/alice'), {
    messageCount: 7,
    catalogSearchWindowStart: now,
    catalogSearchCount: 2,
  });
  assert.equal(documents.get('rate_limits/bob').catalogSearchCount, 1);
});

test('catalog quota rejects over the limit and resets only after the window expires', async (t) => {
  const start = Timestamp.fromMillis(1_000);
  const { documents } = quotaStore(t, {
    'rate_limits/alice': {
      catalogSearchWindowStart: start,
      catalogSearchCount: maxCatalogSearchesPerWindow - 1,
    },
  });
  const boundary = Timestamp.fromMillis(start.toMillis() + catalogSearchWindowMs);
  await consumeCatalogSearchQuota(db, 'alice', boundary);
  await assert.rejects(consumeCatalogSearchQuota(db, 'alice', boundary), {
    code: 'resource-exhausted',
  });
  assert.equal(documents.get('rate_limits/alice').catalogSearchCount, maxCatalogSearchesPerWindow);
  const expired = Timestamp.fromMillis(boundary.toMillis() + 1);
  await consumeCatalogSearchQuota(db, 'alice', expired);
  assert.deepEqual(documents.get('rate_limits/alice'), {
    catalogSearchWindowStart: expired,
    catalogSearchCount: 1,
  });
});

test('all catalog callables authenticate and validate before accessing quota or providers', async (t) => {
  const { transaction } = quotaStore(t);
  const fetchMock = t.mock.method(global, 'fetch', async () => assert.fail('Unexpected external request'));
  for (const [endpoint, data] of endpoints) {
    await assert.rejects(endpoint.run({ data }), { code: 'unauthenticated' });
    await assert.rejects(endpoint.run({ auth: { uid: 'alice' }, data: {} }), {
      code: 'invalid-argument',
    });
  }
  assert.equal(transaction.mock.callCount(), 0);
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('exhausted catalog quota blocks all providers, including Spotify token requests', async (t) => {
  const { documents } = quotaStore(t, {
    'rate_limits/alice': {
      catalogSearchWindowStart: Timestamp.now(),
      catalogSearchCount: maxCatalogSearchesPerWindow,
    },
  });
  const fetchMock = t.mock.method(global, 'fetch', async () => assert.fail('Unexpected external request'));
  for (const [endpoint, data] of endpoints) {
    // Client-supplied identities and counters must not affect admission.
    await assert.rejects(endpoint.run({
      auth: { uid: 'alice' },
      data: { ...data, uid: 'bob', catalogSearchCount: 0 },
    }), { code: 'resource-exhausted' });
  }
  assert.equal(documents.size, 1);
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('catalog callables fail closed when the quota transaction fails', async (t) => {
  t.mock.method(db, 'runTransaction', async () => { throw new Error('Firestore unavailable'); });
  const fetchMock = t.mock.method(global, 'fetch', async () => assert.fail('Unexpected external request'));
  for (const [endpoint, data] of endpoints) {
    await assert.rejects(endpoint.run({ auth: { uid: 'alice' }, data }));
  }
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('successful searches share quota and reserve it before token, search and genre requests', async (t) => {
  const { documents } = quotaStore(t, {
    'rate_limits/alice': {
      catalogSearchWindowStart: Timestamp.now(),
      catalogSearchCount: maxCatalogSearchesPerWindow - 3,
    },
  });
  setTestSecrets(t);
  let expectedCount = maxCatalogSearchesPerWindow - 3;
  const fetchMock = t.mock.method(global, 'fetch', async (input) => {
    assert.equal(documents.get('rate_limits/alice').catalogSearchCount, expectedCount);
    const url = new URL(input);
    if (url.pathname === '/api/token') {
      return Response.json({ access_token: 'test-token', expires_in: 3600 });
    }
    if (url.searchParams.get('type') === 'artist') {
      return Response.json({ artists: { items: [{ id: 'muse-id', name: 'Muse', genres: [] }] } });
    }
    if (url.searchParams.get('type') === 'track') {
      return Response.json({ tracks: { items: [] } });
    }
    if (url.searchParams.get('method') === 'artist.getTopTags') {
      return Response.json({ toptags: { tag: [] } });
    }
    assert.equal(url.searchParams.get('method'), 'artist.getSimilar');
    return Response.json({ similarartists: { artist: [{ name: 'Radiohead' }] } });
  });
  const results = [];
  for (const [endpoint, data] of endpoints) {
    expectedCount++;
    results.push(await endpoint.run({ auth: { uid: 'alice' }, data }));
  }
  assert.deepEqual(results, [
    [{ name: 'Muse', imageUrl: '', genres: [], spotifyId: 'muse-id' }],
    [],
    ['Radiohead'],
  ]);
  assert.equal(fetchMock.mock.callCount(), 5);
  for (const [endpoint, data] of endpoints) {
    await assert.rejects(endpoint.run({ auth: { uid: 'alice' }, data }), {
      code: 'resource-exhausted',
    });
  }
  assert.equal(fetchMock.mock.callCount(), 5);
});

test('failed upstream requests still consume catalog quota', async (t) => {
  setTestSecrets(t);
  const { documents } = quotaStore(t);
  const fetchMock = t.mock.method(global, 'fetch', async () => new Response('', { status: 503 }));
  for (const [endpoint, data] of endpoints) {
    await assert.rejects(endpoint.run({ auth: { uid: 'alice' }, data }));
  }
  assert.equal(documents.get('rate_limits/alice').catalogSearchCount, 3);
  assert.equal(fetchMock.mock.callCount(), 3);
});
