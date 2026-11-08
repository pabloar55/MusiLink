const assert = require('node:assert/strict');
const { after, before, beforeEach, test } = require('node:test');
const { getApps, deleteApp } = require('firebase-admin/app');
const { Timestamp } = require('firebase-admin/firestore');

const { db } = require('../lib/firebase.js');
const {
  checkDueArtistReleases,
  SpotifyRateLimitedError,
  sendWeeklyReleaseNotificationsAt,
  syncWatchedArtistsAt,
} = require('../lib/artist_releases.js');

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

const rosalia = 'R'.repeat(22);
const aitana = 'A'.repeat(22);
const hour = 3600000;
const day = 24 * hour;
// Monday 2026-11-02 and Saturday 2026-11-07 11:30 at UTC+01:00.
const monday = new Date('2026-11-02T04:00:00Z');
const saturday = new Date('2026-11-07T10:30:00Z');
const at = (date, hours) => date.getTime() + hours * hour;

async function seedFollower(uid = 'alice', artists = [{ name: 'Rosalía', spotifyId: rosalia }]) {
  await Promise.all([
    db.doc(`users/${uid}`).set({
      displayName: uid,
      username: `${uid}_name`,
      topArtists: artists.map((artist) => ({ ...artist, imageUrl: '', genres: [] })),
      topArtistKeys: artists.map((artist) => `spotify:${artist.spotifyId}`),
    }),
    db.doc(`user_private/${uid}`).set({ utcOffsetMinutes: 60, preferredLocale: 'es' }),
  ]);
}

const catalog = (releasesByArtist) => async (artistId) => releasesByArtist[artistId] ?? [];
const single = (char, releaseDate) => ({
  id: char.repeat(22),
  name: `Canción ${char}`,
  type: 'single',
  releaseDate,
  imageUrl: `https://i.scdn.co/image/${char.repeat(10)}`,
});

test('a followed artist is watched, baselined and announced once on Saturday', async () => {
  await seedFollower();
  await seedFollower('bob', [{ name: 'Rosalía', spotifyId: rosalia }, { name: 'Sin id' }]);
  const sent = [];
  const notify = async (...args) => { sent.push(args); };

  assert.deepEqual(await syncWatchedArtistsAt(db, monday.getTime()), { profiles: 2, artists: 1, added: 1 });
  assert.equal((await syncWatchedArtistsAt(db, monday.getTime())).added, 0);

  // The first check keeps last week's single for the app without announcing it.
  const old = single('o', '2026-10-30');
  let result = await checkDueArtistReleases(db, at(monday, 1), catalog({ [rosalia]: [old] }));
  assert.equal(result.baseline, 1);
  const baseline = (await db.doc(`artist_releases/${rosalia}`).get()).data();
  assert.equal(baseline.recentReleases.length, 1);
  assert.equal(baseline.recentReleases[0].announce, false);

  // Not due again until a day later.
  assert.equal((await checkDueArtistReleases(db, at(monday, 12), catalog({}))).due, 0);

  const fresh = single('n', '2026-11-06');
  result = await checkDueArtistReleases(db, at(saturday, -10), catalog({ [rosalia]: [fresh, old] }));
  assert.equal(result.new, 1);

  // No notification on other days, then a single one on Saturday at 11:30.
  assert.equal((await sendWeeklyReleaseNotificationsAt(db, new Date(at(saturday, -24)), notify)).candidates, 0);
  assert.deepEqual(await sendWeeklyReleaseNotificationsAt(db, saturday, notify), { candidates: 2, sent: 2 });
  assert.deepEqual(sent.map((args) => args[0]).sort(), ['alice', 'bob']);
  assert.deepEqual(sent[0][2], { title: 'Escucha la nueva canción de Rosalía', body: 'Canción n' });
  assert.deepEqual(sent[0].slice(3), [{ type: 'new_release' }, 'new_release']);

  // Neither a retried slot nor the following Saturday repeat it.
  await sendWeeklyReleaseNotificationsAt(db, saturday, notify);
  await sendWeeklyReleaseNotificationsAt(db, new Date(saturday.getTime() + 7 * day), notify);
  assert.equal(sent.length, 2);
});

test('the weekly notification respects the opt-out and inactive accounts', async () => {
  const detectedAt = Timestamp.fromMillis(at(saturday, -30));
  for (const mutate of [
    () => db.doc('user_private/alice').update({ notifNewReleases: false }),
    () => db.doc('account_deletions/alice').set({ status: 'requested' }),
    () => db.doc('user_private/alice').update({ utcOffsetMinutes: 120 }),
    () => db.doc('user_private/alice').update({ newReleasePushAt: Timestamp.fromMillis(at(saturday, -1)) }),
  ]) {
    await clearFirestore();
    await seedFollower();
    await db.doc(`artist_releases/${rosalia}`).set({
      name: 'Rosalía',
      nextCheckAt: Timestamp.fromMillis(at(saturday, 24)),
      knownReleaseIds: ['n'.repeat(22)],
      recentReleases: [{ ...single('n', '2026-11-06'), detectedAt, announce: true }],
    });
    await mutate();
    let sends = 0;
    assert.equal((await sendWeeklyReleaseNotificationsAt(db, saturday, async () => { sends++; })).sent, 0);
    assert.equal(sends, 0);
  }
});

test('artists nobody follows are dropped and a rate limit stops the cycle', async () => {
  await seedFollower();
  const due = Timestamp.fromMillis(at(monday, -1));
  await Promise.all([
    db.doc(`artist_releases/${aitana}`).set({ name: 'Aitana', nextCheckAt: due }),
    db.doc(`artist_releases/${rosalia}`).set({ name: 'Rosalía', nextCheckAt: due }),
  ]);
  let fetches = 0;
  const result = await checkDueArtistReleases(db, monday.getTime(), async () => {
    fetches++;
    throw new SpotifyRateLimitedError(30, false);
  });
  assert.equal(result.orphan, 1);
  assert.equal(result.rateLimited, true);
  assert.equal(result.quotaExceeded, false);
  assert.equal(fetches, 1);
  assert.equal((await db.doc(`artist_releases/${aitana}`).get()).exists, false);
  // The rate-limited artist stays due and checks are not paused.
  assert.deepEqual((await db.doc(`artist_releases/${rosalia}`).get()).data().nextCheckAt, due);
  assert.equal((await db.doc('scheduler_state/artist_release_checks').get()).exists, false);
});

test('an exhausted Spotify quota pauses every check until it recovers', async () => {
  await seedFollower();
  await db.doc(`artist_releases/${rosalia}`).set({
    name: 'Rosalía',
    nextCheckAt: Timestamp.fromMillis(at(monday, -1)),
  });
  const result = await checkDueArtistReleases(db, monday.getTime(), async () => {
    throw new SpotifyRateLimitedError(undefined, true);
  });
  assert.equal(result.quotaExceeded, true);
  assert.equal(result.pausedUntil, new Date(at(monday, 6)).toISOString());

  let fetches = 0;
  const counting = async () => { fetches++; return []; };
  const paused = await checkDueArtistReleases(db, at(monday, 5), counting);
  assert.equal(paused.due, 0);
  assert.equal(fetches, 0);
  assert.equal((await checkDueArtistReleases(db, at(monday, 6), counting)).baseline, 1);
});
