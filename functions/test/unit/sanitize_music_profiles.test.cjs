const assert = require('node:assert/strict');
const test = require('node:test');

const {
  cleanupFor,
} = require('../../scripts/sanitize_music_profiles.cjs');

test('cleanup marks malformed nested profile lists for deletion', () => {
  const patch = cleanupFor({
    topArtists: [1],
    topGenres: [{ name: 'rock', count: 'many', percentage: 100 }],
  });

  assert.deepEqual(Object.keys(patch).sort(), ['topArtists', 'topGenres']);
});

test('cleanup preserves valid rich data and filters malformed scalar lists', () => {
  const patch = cleanupFor({
    topArtists: [{ name: 'Radiohead', imageUrl: '', genres: ['rock'] }],
    topGenres: [{ name: 'rock', count: 1, percentage: 100 }],
    topArtistNames: [1, ' Radiohead '],
    topArtistKeys: [' name:radiohead '],
    topGenreNames: ['rock'],
  });

  assert.deepEqual(patch.topArtistNames, ['Radiohead']);
  assert.deepEqual(patch.topArtistKeys, ['name:radiohead']);
  assert.equal('topArtists' in patch, false);
  assert.equal('topGenres' in patch, false);
  assert.equal('topGenreNames' in patch, false);
});
