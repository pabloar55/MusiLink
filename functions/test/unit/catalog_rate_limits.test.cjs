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
  [searchSpotifyArtists, { query: 'Muse' }, 'spotifySearch'],
  [searchSpotifyTracks, { query: 'Muse' }, 'spotifySearch'],
  [getSimilarArtists, { artistName: 'Muse' }, 'lastFmSimilar'],
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
  t.mock.method(db, 'doc', (path) => ({
    path,
    async get() { return { data: () => documents.get(path) }; },
    async set(data) { documents.set(path, data); },
  }));
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
  await consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', now);
  await consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', Timestamp.fromMillis(2_000));
  await consumeCatalogSearchQuota(db, 'bob', 'spotifySearch', now);
  assert.deepEqual(documents.get('rate_limits/alice'), {
    messageCount: 7,
    spotifySearchWindowStart: now,
    spotifySearchCount: 2,
  });
  assert.equal(documents.get('rate_limits/bob').spotifySearchCount, 1);
});

test('catalog quota rejects over the limit and resets only after the window expires', async (t) => {
  const start = Timestamp.fromMillis(1_000);
  const { documents } = quotaStore(t, {
    'rate_limits/alice': {
      spotifySearchWindowStart: start,
      spotifySearchCount: maxCatalogSearchesPerWindow - 1,
    },
  });
  const boundary = Timestamp.fromMillis(start.toMillis() + catalogSearchWindowMs);
  await consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', boundary);
  await assert.rejects(consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', boundary), {
    code: 'resource-exhausted',
  });
  assert.equal(documents.get('rate_limits/alice').spotifySearchCount, maxCatalogSearchesPerWindow);
  const expired = Timestamp.fromMillis(boundary.toMillis() + 1);
  await consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', expired);
  assert.deepEqual(documents.get('rate_limits/alice'), {
    spotifySearchWindowStart: expired,
    spotifySearchCount: 1,
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
      spotifySearchWindowStart: Timestamp.now(),
      spotifySearchCount: maxCatalogSearchesPerWindow,
      lastFmSimilarWindowStart: Timestamp.now(),
      lastFmSimilarCount: maxCatalogSearchesPerWindow,
    },
  });
  const fetchMock = t.mock.method(global, 'fetch', async () => assert.fail('Unexpected external request'));
  for (const [endpoint, data] of endpoints) {
    // Client-supplied identities and counters must not affect admission.
    await assert.rejects(endpoint.run({
      auth: { uid: 'alice' },
      data: { ...data, uid: 'bob', spotifySearchCount: 0 },
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

test('Spotify calls share quota while similar artists use a separate reservation', async (t) => {
  const { documents } = quotaStore(t, {
    'rate_limits/alice': {
      spotifySearchWindowStart: Timestamp.now(),
      spotifySearchCount: maxCatalogSearchesPerWindow - 2,
      lastFmSimilarWindowStart: Timestamp.now(),
      lastFmSimilarCount: maxCatalogSearchesPerWindow - 1,
    },
  });
  setTestSecrets(t);
  let expectedCount = maxCatalogSearchesPerWindow - 2;
  let expectedField = 'spotifySearchCount';
  const fetchMock = t.mock.method(global, 'fetch', async (input) => {
    assert.equal(documents.get('rate_limits/alice')[expectedField], expectedCount);
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
  for (const [endpoint, data, quota] of endpoints) {
    expectedField = `${quota}Count`;
    expectedCount = documents.get('rate_limits/alice')[expectedField] + 1;
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
  assert.equal(documents.get('rate_limits/alice').spotifySearchCount, 2);
  assert.equal(documents.get('rate_limits/alice').lastFmSimilarCount, 1);
  assert.equal(fetchMock.mock.callCount(), 3);
});

test('30 artists with two Spotify searches each leave room for all 30 suggestions', async (t) => {
  const { documents } = quotaStore(t);
  const now = Timestamp.fromMillis(1_000);
  for (let artist = 0; artist < 30; artist++) {
    await consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', now);
    await consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', now);
    await consumeCatalogSearchQuota(db, 'alice', 'lastFmSimilar', now);
  }
  assert.equal(documents.get('rate_limits/alice').spotifySearchCount, 60);
  assert.equal(documents.get('rate_limits/alice').lastFmSimilarCount, 30);
  await assert.rejects(consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', now), {
    code: 'resource-exhausted',
  });
  await consumeCatalogSearchQuota(db, 'alice', 'lastFmSimilar', now);
});

test('similar artists reuse the full cached list across limits and users despite exhausted Spotify quota', async (t) => {
  setTestSecrets(t);
  const { documents } = quotaStore(t, {
    'rate_limits/alice': {
      spotifySearchWindowStart: Timestamp.now(),
      spotifySearchCount: maxCatalogSearchesPerWindow,
    },
  });
  const fetchMock = t.mock.method(global, 'fetch', async (input) => {
    assert.equal(new URL(input).searchParams.get('limit'), '10');
    return Response.json({ similarartists: { artist: [{ name: 'Muse' }, { name: 'Radiohead' }] } });
  });
  assert.deepEqual(await getSimilarArtists.run({
    auth: { uid: 'alice' }, data: { artistName: 'Portishead', limit: 1 },
  }), ['Muse']);
  assert.deepEqual(await getSimilarArtists.run({
    auth: { uid: 'bob' }, data: { artistName: ' portishead ', limit: 10 },
  }), ['Muse', 'Radiohead']);
  assert.equal(fetchMock.mock.callCount(), 1);
  assert.equal(documents.get('rate_limits/alice').lastFmSimilarCount, 1);
  assert.equal(documents.get('rate_limits/bob').lastFmSimilarCount, 1);
});

test('Last.fm JSON throttles and malformed responses propagate and are not cached', async (t) => {
  setTestSecrets(t);
  quotaStore(t);
  let response = { error: 29, message: 'Rate limit exceeded' };
  const fetchMock = t.mock.method(global, 'fetch', async () => Response.json(response));
  const request = { auth: { uid: 'alice' }, data: { artistName: 'Muse' } };
  await assert.rejects(getSimilarArtists.run(request), { code: 'resource-exhausted' });
  response = { similarartists: {} };
  await assert.rejects(getSimilarArtists.run(request), { code: 'unavailable' });
  response = { similarartists: { artist: [{ name: 123 }] } };
  await assert.rejects(getSimilarArtists.run(request), { code: 'unavailable' });
  response = { similarartists: { artist: [{ name: 'Radiohead' }] } };
  assert.deepEqual(await getSimilarArtists.run(request), ['Radiohead']);
  assert.equal(fetchMock.mock.callCount(), 4);
});

test('Spotify genre enrichment reuses cached Last.fm tags without consuming similar-artist quota', async (t) => {
  setTestSecrets(t);
  const { documents } = quotaStore(t, {
    'rate_limits/alice': {
      lastFmSimilarWindowStart: Timestamp.now(),
      lastFmSimilarCount: maxCatalogSearchesPerWindow,
    },
  });
  let tagRequests = 0;
  t.mock.method(global, 'fetch', async (input) => {
    const url = new URL(input);
    if (url.pathname === '/api/token') {
      return Response.json({ access_token: 'test-token', expires_in: 3600 });
    }
    if (url.searchParams.get('type') === 'artist') {
      return Response.json({ artists: { items: [{ id: 'muse-id', name: 'Muse', genres: [] }] } });
    }
    assert.equal(url.searchParams.get('method'), 'artist.getTopTags');
    tagRequests++;
    if (tagRequests === 1) return Response.json({ toptags: { tag: [{ name: 123 }] } });
    return Response.json({ toptags: { tag: [{ name: 'rock', count: 100 }] } });
  });
  const failedEnrichment = await searchSpotifyArtists.run({ auth: { uid: 'alice' }, data: { query: 'Muse' } });
  assert.deepEqual(failedEnrichment[0].genres, []);
  for (const query of ['muse', 'Muse']) {
    const result = await searchSpotifyArtists.run({ auth: { uid: 'alice' }, data: { query } });
    assert.deepEqual(result[0].genres, ['rock']);
  }
  assert.equal(tagRequests, 2);
  assert.equal(documents.get('rate_limits/alice').spotifySearchCount, 3);
  assert.equal(documents.get('rate_limits/alice').lastFmSimilarCount, maxCatalogSearchesPerWindow);
});
