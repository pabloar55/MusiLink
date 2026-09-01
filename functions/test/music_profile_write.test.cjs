'use strict';

const assert = require('node:assert/strict');
const { after, before, beforeEach, test } = require('node:test');
const { deleteApp, getApps } = require('firebase-admin/app');
const { Timestamp } = require('firebase-admin/firestore');

const { db } = require('../lib/firebase.js');
const {
  parseMusicProfilePayload,
  writeMusicProfile,
} = require('../lib/music_profile_write.js');

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('FIRESTORE_EMULATOR_HOST is required for this test.');
  }
});

async function clearFirestore() {
  const collections = await db.listCollections();
  for (const collection of collections) {
    const snapshot = await collection.get();
    for (const document of snapshot.docs) await db.recursiveDelete(document.ref);
  }
}

beforeEach(clearFirestore);

after(async () => {
  await clearFirestore();
  await Promise.all(getApps().map((app) => deleteApp(app)));
});

test('writes a complete server-owned music profile atomically', async () => {
  await db.doc('users/alice').set({
    displayName: 'Alice',
    username: 'alice_name',
    photoUrl: '',
  });
  const artists = parseMusicProfilePayload({
    artists: [{
      name: 'Radiohead',
      imageUrl: '',
      genres: ['Alternative Rock'],
      spotifyId: '4Z8W4fKeB5YxbusRsdQVPb',
    }],
  });

  await writeMusicProfile(db, 'alice', artists);

  const data = (await db.doc('users/alice').get()).data();
  assert.deepEqual(data.topArtistNames, ['Radiohead']);
  assert.deepEqual(data.topArtistKeys, ['spotify:4Z8W4fKeB5YxbusRsdQVPb']);
  assert.deepEqual(data.topGenreNames, ['alternative rock']);
  assert.equal(data.artistIdentityVersion, 1);
  assert.equal(data.musicProfileVersion, 1);
  assert.ok(data.musicDataUpdatedAt instanceof Timestamp);
  assert.ok(data.recommendationsRefreshRequestedAt instanceof Timestamp);
});

test('rejects writes while account deletion is pending', async () => {
  await Promise.all([
    db.doc('users/alice').set({
      displayName: 'Alice',
      username: 'alice_name',
      photoUrl: '',
    }),
    db.doc('account_deletions/alice').set({ requestedAt: Timestamp.now() }),
  ]);

  await assert.rejects(
    writeMusicProfile(db, 'alice', []),
    (error) => error?.code === 'failed-precondition',
  );
  const data = (await db.doc('users/alice').get()).data();
  assert.equal('topArtists' in data, false);
});
