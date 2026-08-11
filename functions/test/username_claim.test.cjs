'use strict';

const { after, before, beforeEach } = require('node:test');
const test = require('node:test');
const assert = require('node:assert/strict');
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  claimUsernameAndCreateProfile,
} = require('../lib/username_claim.js');

let app;
let db;

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('FIRESTORE_EMULATOR_HOST is required for this test.');
  }
  app = initializeApp({ projectId: 'musilink-functions-test' });
  db = getFirestore(app);
});

beforeEach(async () => {
  for (const collectionName of ['usernames', 'users', 'user_private']) {
    const snapshot = await db.collection(collectionName).get();
    if (snapshot.empty) continue;
    const batch = db.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
  }
});

after(async () => {
  if (app) await deleteApp(app);
});

test('dos claims simultáneos del mismo username producen un solo ganador', async () => {
  const attempts = await Promise.allSettled([
    claimUsernameAndCreateProfile(db, 'alice', 'alice@example.com', {
      displayName: 'Alice',
      username: 'same_name',
    }),
    claimUsernameAndCreateProfile(db, 'bob', 'bob@example.com', {
      displayName: 'Bob',
      username: 'same_name',
    }),
  ]);

  const fulfilled = attempts.filter((attempt) => attempt.status === 'fulfilled');
  const rejected = attempts.filter((attempt) => attempt.status === 'rejected');
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].reason.code, 'already-exists');

  const reservation = await db.doc('usernames/same_name').get();
  const profiles = await db.collection('users').get();
  const privateProfiles = await db.collection('user_private').get();
  assert.equal(reservation.exists, true);
  assert.equal(profiles.size, 1);
  assert.equal(privateProfiles.size, 1);
  assert.equal(profiles.docs[0].id, reservation.data().uid);
});

test('repetir el mismo claim es idempotente', async () => {
  const payload = { displayName: 'Alice', username: 'alice_name' };
  await claimUsernameAndCreateProfile(db, 'alice', 'alice@example.com', payload);
  await claimUsernameAndCreateProfile(db, 'alice', 'alice@example.com', payload);

  assert.equal((await db.collection('usernames').get()).size, 1);
  assert.equal((await db.collection('users').get()).size, 1);
  assert.equal((await db.collection('user_private').get()).size, 1);
});

test('normaliza el ID y rechaza usernames reservados', async () => {
  const result = await claimUsernameAndCreateProfile(
    db,
    'alice',
    'alice@example.com',
    { displayName: ' Alice ', username: ' TestUser ' },
  );
  assert.equal(result.username, 'testuser');
  assert.equal((await db.doc('usernames/testuser').get()).exists, true);

  await assert.rejects(
    claimUsernameAndCreateProfile(db, 'deleted', '', {
      displayName: 'Deleted',
      username: 'deleted_user',
    }),
    (error) => error.code === 'invalid-argument',
  );
});
