const assert = require('node:assert/strict');
const test = require('node:test');

const {
  catalogSearchMaxLimit,
  parseLastFmSearchRequest,
  parseSpotifyArtistSearchRequest,
  parseSpotifySearchRequest,
} = require('../../lib/catalog_request.js');

function assertInvalidArgument(callback) {
  assert.throws(callback, (error) => error?.code === 'invalid-argument');
}

test('Spotify search trims the query and defaults to the provider maximum', () => {
  assert.deepEqual(parseSpotifySearchRequest({ query: '  Radiohead  ' }), {
    value: 'Radiohead',
    limit: catalogSearchMaxLimit,
  });
});

test('catalog searches accept only integer limits from 1 to 10', () => {
  assert.deepEqual(parseSpotifySearchRequest({ query: 'Muse', limit: 1 }), {
    value: 'Muse',
    limit: 1,
  });
  assert.deepEqual(parseSpotifySearchRequest({ query: 'Muse', limit: 10 }), {
    value: 'Muse',
    limit: 10,
  });

  for (const limit of [0, -1, 1.5, 11, '10', null, Number.NaN]) {
    assertInvalidArgument(() => parseSpotifySearchRequest({ query: 'Muse', limit }));
  }
});

test('catalog searches reject malformed request bodies and query types', () => {
  for (const data of [null, [], 'Muse', 42]) {
    assertInvalidArgument(() => parseSpotifySearchRequest(data));
  }
  for (const query of [undefined, null, 42, [], {}]) {
    assertInvalidArgument(() => parseSpotifySearchRequest({ query }));
  }
});

test('catalog searches reject empty, oversized, and control-character queries', () => {
  assertInvalidArgument(() => parseSpotifySearchRequest({ query: '   ' }));
  assertInvalidArgument(() => parseSpotifySearchRequest({ query: 'a'.repeat(201) }));
  assertInvalidArgument(() => parseSpotifySearchRequest({ query: 'Björk\nLive' }));
  // The boundary is measured in UTF-8 bytes, not JavaScript code units.
  assertInvalidArgument(() => parseSpotifySearchRequest({ query: 'é'.repeat(101) }));
});

test('artist search validates and normalizes the optional Spotify market', () => {
  assert.deepEqual(parseSpotifyArtistSearchRequest({ query: 'Rosalía' }), {
    value: 'Rosalía',
    limit: 10,
    market: 'ES',
  });
  assert.deepEqual(parseSpotifyArtistSearchRequest({ query: 'Rosalía', market: ' us ' }), {
    value: 'Rosalía',
    limit: 10,
    market: 'US',
  });
  for (const market of ['', 'USA', 34, null]) {
    assertInvalidArgument(() => parseSpotifyArtistSearchRequest({ query: 'Rosalía', market }));
  }
});

test('Last.fm search validates artistName with the shared constraints', () => {
  assert.deepEqual(parseLastFmSearchRequest({ artistName: '  Portishead ', limit: 5 }), {
    value: 'Portishead',
    limit: 5,
  });
  assertInvalidArgument(() => parseLastFmSearchRequest({ artistName: 123 }));
  assertInvalidArgument(() => parseLastFmSearchRequest({ artistName: 'Portishead', limit: 50 }));
});
