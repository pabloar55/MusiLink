const assert = require('node:assert/strict');
const test = require('node:test');

const {
  calculateRecommendation,
  normalizeArtistIdentityName,
  readMusicProfile,
  similarityScore,
} = require('../../lib/recommendations.js');

test('normalizeArtistIdentityName folds punctuation and supported diacritics', () => {
  assert.equal(normalizeArtistIdentityName('  Sigur Rós & Björk!  '), 'sigur ros and bjork');
  assert.equal(normalizeArtistIdentityName("Guns N’ Roses"), 'guns n roses');
});

test('readMusicProfile trims values and derives stable artist keys', () => {
  assert.deepEqual(readMusicProfile({
    topArtistNames: ['  Björk ', '', 12],
    topArtists: [{ name: 'Björk', spotifyId: 'abc123' }],
    topGenreNames: [' Art Pop ', null],
  }), {
    topArtistNames: ['Björk'],
    topArtistKeys: ['spotify:abc123'],
    topGenreNames: ['Art Pop'],
  });
});

test('calculateRecommendation combines artist and genre coverage', () => {
  const result = calculateRecommendation(
    {
      topArtistNames: ['Björk'],
      topArtistKeys: ['spotify:one'],
      topGenreNames: ['Art Pop'],
    },
    {
      uid: 'candidate',
      topArtistNames: ['Björk'],
      topArtistKeys: ['spotify:one'],
      topGenreNames: ['art pop'],
    },
  );
  assert.deepEqual(result, {
    uid: 'candidate',
    score: 100,
    sharedArtistNames: ['Björk'],
    sharedGenreNames: ['art pop'],
  });
});

test('calculateRecommendation does not merge different Spotify identities', () => {
  assert.equal(calculateRecommendation(
    {
      topArtistNames: ['Phoenix'],
      topArtistKeys: ['spotify:french-band'],
      topGenreNames: [],
    },
    {
      uid: 'candidate',
      topArtistNames: ['Phoenix'],
      topArtistKeys: ['spotify:different-artist'],
      topGenreNames: [],
    },
  ), null);
});

test('similarityScore caps evidence while preserving coverage', () => {
  assert.equal(similarityScore(0, 10, 10, 7, 70), 0);
  assert.equal(similarityScore(1, 1, 20, 7, 70), 70);
  assert.equal(similarityScore(7, 20, 20, 7, 70), 70);
});
