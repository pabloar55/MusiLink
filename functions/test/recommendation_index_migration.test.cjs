'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  migrationProfile,
  normalizeArtistIdentityName,
  normalizeGenreName,
} = require('../scripts/migrate-recommendation-index-v2.cjs');

function artist(index, genres = []) {
  return {
    name: `Artist ${index}`,
    imageUrl: `https://example.com/${index}.jpg`,
    genres,
    spotifyId: `spotify-${index}`,
  };
}

test('migrationProfile keeps the first 30 artists and discards the rest', () => {
  const profile = migrationProfile('user-1', {
    username: 'user_1',
    topArtists: Array.from({ length: 50 }, (_, index) => artist(index)),
  });

  assert.ok(profile);
  assert.equal(profile.originalCount, 50);
  assert.equal(profile.removedCount, 20);
  assert.equal(profile.names.length, 30);
  assert.equal(profile.names.at(-1), 'Artist 29');
  assert.equal(profile.keys.at(-1), 'spotify:spotify-29');
  assert.equal(profile.indexData.artistMatchKeys.length, 30);
});

test('migrationProfile recalculates genres using only retained artists', () => {
  const retained = Array.from({ length: 30 }, (_, index) =>
    artist(index, index < 20 ? ['Rock'] : ['Pop']));
  const removed = Array.from({ length: 20 }, (_, index) =>
    artist(index + 30, ['Jazz']));

  const profile = migrationProfile('user-1', {
    username: 'user_1',
    topArtists: [...retained, ...removed],
    topGenres: [{ name: 'jazz', count: 20, percentage: 40 }],
    topGenreNames: ['jazz'],
  });

  assert.ok(profile);
  assert.deepEqual(profile.genreNames, ['rock', 'pop']);
  assert.deepEqual(profile.genres.map((genre) => genre.count), [20, 10]);
  assert.equal(profile.indexData.genreMatchKeys.includes('jazz'), false);
});

test('normalizers match the application identity rules', () => {
  assert.equal(normalizeArtistIdentityName('Beyoncé & Jay-Z'), 'beyonce and jay z');
  assert.equal(normalizeGenreName('Hip-Hop'), 'hip hop');
  assert.equal(normalizeGenreName('seen live'), undefined);
});
