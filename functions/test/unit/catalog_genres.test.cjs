const assert = require('node:assert/strict');
const test = require('node:test');

const { normalizeGenreName } = require('../../lib/genre_normalizer.js');
const {
  normalizeLastFmTags,
  normalizeSpotifyGenres,
} = require('../../lib/catalog_genres.js');

test('normalizeGenreName folds accents, compatibility characters and aliases', () => {
  assert.equal(normalizeGenreName('Corridos Bélicos'), 'corridos belicos');
  assert.equal(normalizeGenreName('Ｋ－Ｐｏｐ'), 'k pop');
  assert.equal(normalizeGenreName('R & B'), 'r&b');
  assert.equal(normalizeGenreName('Hip-Hop Music'), 'hip hop');
  assert.equal(normalizeGenreName('Drum & Bass'), 'drum and bass');
});

test('normalizeGenreName rejects non-genre tags', () => {
  for (const tag of ['seen live', 'Spanish', '80s', '1990s', 'my favorite', 'x', '!!!']) {
    assert.equal(normalizeGenreName(tag), undefined, tag);
  }
});

test('normalizeSpotifyGenres deduplicates, filters and caps at five genres', () => {
  assert.deepEqual(
    normalizeSpotifyGenres(['Rap', 'hip hop', 'usa', 7, 'trap', 'edm', 'electro', 'pop', 'rock', 'soul']),
    ['hip hop', 'trap', 'electronic', 'pop', 'rock'],
  );
  assert.deepEqual(normalizeSpotifyGenres(undefined), []);
});

test('normalizeLastFmTags keeps frequent genre-like tags and caps at two', () => {
  assert.deepEqual(
    normalizeLastFmTags([
      { name: 'seen live', count: 100 },
      { name: 'Beyoncé', count: 90 },
      { name: 'Indie Rock', count: '80' },
      { name: 'jazz', count: 9 },
      { name: 'Synth-Pop', count: 50 },
      { name: 'punk', count: 40 },
    ]),
    ['indie rock', 'synthpop'],
  );
});

test('catalog genres are stable when the profile write normalizes them again', () => {
  const genres = [
    ...normalizeSpotifyGenres(['Ｊ－Ｒｏｃｋ', 'Música Electrónica', 'R&B']),
    ...normalizeLastFmTags([{ name: 'Ｒｅｇｇａｅｔｏｎ', count: 50 }]),
  ];
  for (const genre of genres) {
    assert.equal(normalizeGenreName(genre), genre);
  }
});
