const assert = require('node:assert/strict');
const test = require('node:test');

const {
  normalizeArtistName,
  rankSpotifyArtists,
  scoreArtistMatch,
} = require('../../lib/spotify_artist_ranking.js');

function artist(id, name, { popularity, followers, image = true, genres } = {}) {
  return {
    id,
    name,
    ...(popularity === undefined ? {} : { popularity }),
    ...(followers === undefined ? {} : { followers: { total: followers } }),
    ...(image ? { images: [{ url: `https://img/${id}` }] } : {}),
    ...(genres === undefined ? {} : { genres }),
  };
}

function ids(items) {
  return items.map((item) => item.id);
}

test('normalizeArtistName folds accents, case, apostrophes, ampersands and symbols', () => {
  assert.equal(normalizeArtistName('Beyoncé'), 'beyonce');
  assert.equal(normalizeArtistName("Guns N' Roses"), 'guns n roses');
  assert.equal(normalizeArtistName('Simon & Garfunkel'), 'simon and garfunkel');
  assert.equal(normalizeArtistName('  AC/DC  '), 'ac dc');
  assert.equal(normalizeArtistName('!!!'), '');
});

test('normalizeArtistName applies compatibility decomposition (NFKD)', () => {
  assert.equal(normalizeArtistName('ﬁve'), 'five');
  assert.equal(normalizeArtistName('ＡＢＣ'), 'abc');
});

test('scoreArtistMatch keeps the current weights for each kind of name match', () => {
  const queryTokens = ['muse'];
  assert.equal(
    scoreArtistMatch(artist('a', 'Muse', { popularity: 50, followers: 999, genres: ['rock'] }), 'muse', queryTokens),
    350 + 450 + 135 + 30 + 20,
  );
  assert.equal(
    scoreArtistMatch(artist('b', 'Muse Band', { image: false }), 'muse', queryTokens),
    300 - 250 - 80,
  );
  assert.equal(
    scoreArtistMatch(artist('c', 'The Muse', { popularity: 10, followers: 9_999 }), 'muse', queryTokens),
    180 + 90 + 180 + 30,
  );
  assert.equal(
    scoreArtistMatch(artist('d', 'Coldplay', { popularity: 100 }), 'muse', queryTokens),
    -200 + 900 + 30,
  );
});

test('scoreArtistMatch rewards partial token overlap proportionally', () => {
  assert.equal(
    scoreArtistMatch(
      artist('a', 'Red Hot Peppers', { popularity: 20 }),
      'red hot chili peppers',
      ['red', 'hot', 'chili', 'peppers'],
    ),
    90 + 180 + 30,
  );
});

test('scoreArtistMatch clamps optional metrics and rejects names without letters or digits', () => {
  assert.equal(
    scoreArtistMatch(artist('a', 'Muse', { popularity: 150, followers: -5 }), 'muse', ['muse']),
    350 + 900 + 30,
  );
  assert.equal(scoreArtistMatch(artist('b', 'Muse', { image: false }), 'muse', ['muse']), 350 - 80);
  assert.equal(scoreArtistMatch(artist('c', '¿?'), 'muse', ['muse']), Number.NEGATIVE_INFINITY);
});

test('rankSpotifyArtists drops weak unrelated names when an exact match exists', () => {
  const items = [
    artist('coldplay', 'Coldplay', { popularity: 40 }),
    artist('amuse', 'Amuse', { popularity: 20 }),
    artist('tribute', 'Muse Tribute', { popularity: 30 }),
    artist('radiohead', 'Radiohead', { popularity: 80 }),
    artist('muse', 'Muse', { popularity: 80 }),
  ];

  assert.deepEqual(ids(rankSpotifyArtists(items, 'muse', 10)), [
    'muse',
    'tribute',
    'radiohead',
    'amuse',
  ]);
});

test('rankSpotifyArtists keeps positive unrelated names when there is no exact match', () => {
  const items = [
    artist('coldplay', 'Coldplay', { popularity: 40 }),
    artist('tribute', 'Muse Tribute', { popularity: 30 }),
  ];

  assert.deepEqual(ids(rankSpotifyArtists(items, 'muse', 10)), ['tribute', 'coldplay']);
});

test('rankSpotifyArtists matches regardless of accents and case', () => {
  const items = [
    artist('cover', 'Beyonce Covers', { popularity: 5 }),
    artist('other', 'Rihanna', { popularity: 40 }),
    artist('queen-b', 'Beyoncé', { popularity: 90 }),
  ];

  assert.deepEqual(ids(rankSpotifyArtists(items, 'BEYONCE', 10)), ['queen-b', 'cover']);
});

test('rankSpotifyArtists orders homonyms by popularity and followers', () => {
  const items = [
    artist('small', 'Nirvana', { popularity: 20, followers: 1_000 }),
    artist('big', 'Nirvana', { popularity: 85, followers: 20_000_000 }),
    artist('mid', 'Nirvana', { popularity: 20, followers: 50_000 }),
  ];

  assert.deepEqual(ids(rankSpotifyArtists(items, 'Nirvana', 10)), ['big', 'mid', 'small']);
});

test('rankSpotifyArtists keeps Spotify order for tied scores', () => {
  const items = [
    artist('first', 'Muse', { popularity: 50 }),
    artist('second', 'Muse', { popularity: 50 }),
    artist('third', 'Muse', { popularity: 50 }),
  ];

  assert.deepEqual(ids(rankSpotifyArtists(items, 'Muse', 10)), ['first', 'second', 'third']);
});

test('rankSpotifyArtists handles artists without optional data', () => {
  const bare = { id: 'bare', name: 'Muse' };
  const bareCover = { id: 'bare-cover', name: 'Muse Cover' };

  const ranked = rankSpotifyArtists([bareCover, bare], 'Muse', 10);

  assert.deepEqual(ids(ranked), ['bare']);
  assert.equal(ranked[0], bare);
});

test('rankSpotifyArtists applies the limit after sorting', () => {
  const items = [
    artist('low', 'Muse', { popularity: 10 }),
    artist('high', 'Muse', { popularity: 90 }),
    artist('mid', 'Muse', { popularity: 50 }),
  ];

  assert.deepEqual(ids(rankSpotifyArtists(items, 'Muse', 2)), ['high', 'mid']);
  assert.deepEqual(rankSpotifyArtists([], 'Muse', 5), []);
});
