'use strict';

const assert = require('node:assert/strict');
const { after, before, beforeEach, test } = require('node:test');
const { deleteApp, getApps } = require('firebase-admin/app');
const { Timestamp } = require('firebase-admin/firestore');
const { db } = require('../lib/firebase.js');
const {
  onUserMusicProfileCreated,
  onUserMusicProfileChanged,
} = require('../lib/recommendations.js');

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('FIRESTORE_EMULATOR_HOST is required for this test.');
  }
});

async function clearFirestore() {
  for (const collection of await db.listCollections()) {
    for (const document of (await collection.get()).docs) {
      await db.recursiveDelete(document.ref);
    }
  }
}

beforeEach(clearFirestore);
after(async () => {
  await clearFirestore();
  await Promise.all(getApps().map((app) => deleteApp(app)));
});

function profile(uid, genres = ['rock']) {
  return {
    displayName: uid,
    username: uid,
    photoUrl: '',
    topArtistNames: [],
    topArtistKeys: [],
    topGenreNames: genres,
    musicProfileVersion: 1,
  };
}

async function seedCandidate(uid) {
  const data = profile(uid);
  await db.doc(`users/${uid}`).set(data);
  await db.doc(`music_recommendation_profiles/${uid}`).set({
    ...data,
    uid,
    artistMatchKeys: [],
    genreMatchKeys: data.topGenreNames,
    updatedAt: Timestamp.now(),
  });
}

async function seedRecommendations(uid, count, score = 10) {
  for (let start = 0; start < count; start += 400) {
    const batch = db.batch();
    for (let i = start; i < Math.min(start + 400, count); i++) {
      const id = `old-${String(i).padStart(4, '0')}`;
      batch.set(db.doc(`users/${uid}/recommendations/${id}`), { userId: id, score });
    }
    await batch.commit();
  }
}

async function createProfile(uid) {
  const data = profile(uid);
  await db.doc(`users/${uid}`).set(data);
  await onUserMusicProfileCreated.run({ params: { userId: uid }, data: { data: () => data } });
}

async function recommendationIds(uid) {
  return (await db.collection(`users/${uid}/recommendations`).get()).docs.map((doc) => doc.id);
}

test('reciprocal insertion keeps the best 100 and rejects weaker additions', async () => {
  await seedCandidate('bob');
  await seedRecommendations('bob', 100, 10);
  await createProfile('alice');
  let ids = await recommendationIds('bob');
  assert.equal(ids.length, 100);
  assert.ok(ids.includes('alice'));
  assert.ok(!ids.includes('old-0099'));

  await seedRecommendations('bob', 100, 100);
  await db.doc('users/bob/recommendations/alice').delete();
  await createProfile('carol');
  ids = await recommendationIds('bob');
  assert.equal(ids.length, 100);
  assert.ok(!ids.includes('carol'));
});

test('updating an existing reciprocal recommendation does not evict another entry', async () => {
  await seedCandidate('bob');
  await seedRecommendations('bob', 99);
  await db.doc('users/bob/recommendations/alice').set({ userId: 'alice', score: 1 });
  await createProfile('alice');
  assert.equal((await recommendationIds('bob')).length, 100);
  assert.equal((await db.doc('users/bob/recommendations/alice').get()).data().score, 30);
});

test('rebuild cleans legacy overflow in own and reciprocal lists before marking completion', async (t) => {
  await seedCandidate('bob');
  await seedRecommendations('bob', 700);
  await seedRecommendations('alice', 1200);
  const runTransaction = db.runTransaction.bind(db);
  const committed = [];
  t.mock.method(db, 'runTransaction', async (callback) => {
    const result = await runTransaction(async (transaction) => {
      let count = 0;
      const tracked = new Proxy(transaction, {
        get(target, key) {
          const value = target[key];
          if (typeof value !== 'function') return value;
          return (...args) => {
            if (['set', 'update', 'delete'].includes(key)) count++;
            return value.apply(target, args);
          };
        },
      });
      const status = await callback(tracked);
      assert.ok(count <= 500, `transaction attempted ${count} writes`);
      return { status, count };
    });
    committed.push(result);
    if (result.status === 'pruned') {
      assert.equal((await db.doc('users/alice').get()).data()
        .recommendationsGeneratedForMusicProfileVersion, undefined);
    }
    return result.status;
  });

  await createProfile('alice');
  assert.deepEqual(await recommendationIds('alice'), ['bob']);
  const bobIds = await recommendationIds('bob');
  assert.equal(bobIds.length, 100);
  assert.ok(bobIds.includes('alice'));
  assert.ok(committed.filter((entry) => entry.status === 'pruned').length >= 3);
  const alice = (await db.doc('users/alice').get()).data();
  assert.equal(alice.recommendationsCount, 1);
  assert.equal(alice.recommendationsGeneratedForMusicProfileVersion, 1);
});

test('empty profile removes a legacy list and its reciprocal entry', async () => {
  await seedCandidate('bob');
  await seedRecommendations('alice', 700);
  await db.doc('users/bob/recommendations/alice').set({ userId: 'alice', score: 30 });
  const before = profile('alice');
  const after = { ...profile('alice', []), musicProfileVersion: 2 };
  await db.doc('users/alice').set(after);
  await onUserMusicProfileChanged.run({
    params: { userId: 'alice' },
    data: { before: { data: () => before }, after: { data: () => after } },
  });
  assert.deepEqual(await recommendationIds('alice'), []);
  assert.deepEqual(await recommendationIds('bob'), []);
  assert.equal((await db.doc('users/alice').get()).data().recommendationsCount, 0);
});

test('concurrent reciprocal insertions preserve the cap', async () => {
  await seedCandidate('bob');
  await seedRecommendations('bob', 99);
  await Promise.all(['alice', 'carol', 'dave'].map(createProfile));
  const ids = await recommendationIds('bob');
  assert.equal(ids.length, 100);
  for (const uid of ['alice', 'carol', 'dave']) assert.ok(ids.includes(uid));
});

test('cleanup stops if the source profile changes between transactions', async (t) => {
  await seedRecommendations('alice', 1200);
  const runTransaction = db.runTransaction.bind(db);
  let pruned = false;
  t.mock.method(db, 'runTransaction', async (callback) => {
    const result = await runTransaction(callback);
    if (result === 'pruned' && !pruned) {
      pruned = true;
      await db.doc('users/alice').update({ musicProfileVersion: 2 });
    }
    return result;
  });
  await createProfile('alice');
  assert.equal(pruned, true);
  assert.equal((await recommendationIds('alice')).length, 700);
  const alice = (await db.doc('users/alice').get()).data();
  assert.equal(alice.musicProfileVersion, 2);
  assert.equal(alice.recommendationsGeneratedForMusicProfileVersion, undefined);
});
