'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  artistRecords,
  normalizeArtistIdentityName,
} = require('./backfill-artist-identity-keys.cjs');

test('normaliza nombres igual que el cliente', () => {
  assert.equal(normalizeArtistIdentityName('  Beyoncé  '), 'beyonce');
  assert.equal(normalizeArtistIdentityName('AC/DC'), 'ac dc');
  assert.equal(
    normalizeArtistIdentityName('Florence & The Machine'),
    'florence and the machine',
  );
  assert.equal(normalizeArtistIdentityName('宇多田ヒカル'), '宇多田ヒカル');
});

test('reutiliza spotifyId existente y deja fallback determinista', () => {
  const records = artistRecords({
    topArtistNames: ['Radiohead', 'Beyoncé'],
    topArtists: [
      { name: 'Radiohead', spotifyId: 'radiohead-id' },
      { name: 'Beyoncé' },
    ],
  });

  assert.deepEqual(records, [
    {
      name: 'Radiohead',
      normalizedName: 'radiohead',
      spotifyId: 'radiohead-id',
      key: 'spotify:radiohead-id',
    },
    {
      name: 'Beyoncé',
      normalizedName: 'beyonce',
      spotifyId: '',
      key: 'name:beyonce',
    },
  ]);
});

test('encuentra el artista por nombre si las listas antiguas no están alineadas', () => {
  const records = artistRecords({
    topArtistNames: ['Queen', 'Radiohead'],
    topArtists: [
      { name: 'Radiohead', spotifyId: 'radiohead-id' },
      { name: 'Queen', spotifyId: 'queen-id' },
    ],
  });

  assert.deepEqual(
    records.map((record) => record.key),
    ['spotify:queen-id', 'spotify:radiohead-id'],
  );
});
