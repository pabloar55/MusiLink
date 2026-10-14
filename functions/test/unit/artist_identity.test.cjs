const assert = require('node:assert/strict');
const test = require('node:test');

const {
  artistIdentityKey,
  normalizeArtistIdentityName,
} = require('../../lib/artist_identity.js');

test('normalizeArtistIdentityName folds punctuation and supported diacritics', () => {
  assert.equal(normalizeArtistIdentityName('  Sigur Rós & Björk!  '), 'sigur ros and bjork');
  assert.equal(normalizeArtistIdentityName("Guns N’ Roses"), 'guns n roses');
});

test('artistIdentityKey prefers the Spotify id over the normalized name', () => {
  assert.equal(artistIdentityKey('Björk', 'abc123'), 'spotify:abc123');
  assert.equal(artistIdentityKey('  Björk! '), 'name:bjork');
});
