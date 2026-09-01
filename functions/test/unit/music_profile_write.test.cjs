const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const {
  buildMusicProfileFields,
  parseMusicProfilePayload,
  writeMusicProfile,
} = require('../../lib/music_profile_write.js');

function assertInvalidArgument(callback) {
  assert.throws(callback, (error) => error?.code === 'invalid-argument');
}

const spotifyId = '4Z8W4fKeB5YxbusRsdQVPb';
const spotifyImage = 'https://i.scdn.co/image/ab6761610000e5eb440959e022afc20e819050bd';

test('parses artists and derives all server-owned profile fields', () => {
  const artists = parseMusicProfilePayload({
    artists: [{
      name: ' Radiohead ',
      imageUrl: spotifyImage,
      genres: ['Alternative Rock', 'Canadian'],
      spotifyId,
    }],
  });
  const fields = buildMusicProfileFields(artists, 'server-time');

  assert.deepEqual(fields.topArtists, [{
    name: 'Radiohead',
    imageUrl: spotifyImage,
    genres: ['Alternative Rock', 'Canadian'],
    spotifyId,
  }]);
  assert.deepEqual(fields.topArtistNames, ['Radiohead']);
  assert.deepEqual(fields.topArtistKeys, [`spotify:${spotifyId}`]);
  assert.deepEqual(fields.topGenreNames, ['alternative rock']);
  assert.deepEqual(fields.topGenres, [{
    name: 'alternative rock',
    count: 1,
    percentage: 100,
  }]);
  assert.equal(fields.musicDataUpdatedAt, 'server-time');
  assert.equal(fields.recommendationsRefreshRequestedAt, 'server-time');
});

test('rejects primitive and internally malformed artist entries', () => {
  for (const artists of [
    [1],
    [{ name: 'Broken', imageUrl: '', genres: 1 }],
    [{ name: 'Broken', imageUrl: '', genres: [1] }],
    [{ name: 'Broken', imageUrl: '', genres: [], injected: true }],
    [{ name: 'Broken', imageUrl: 'https://tracking.example/a.jpg', genres: [] }],
    [{ name: 'Broken', imageUrl: '', genres: [], spotifyId: 'short' }],
  ]) {
    assertInvalidArgument(() => parseMusicProfilePayload({ artists }));
  }
});

test('rejects oversized lists, duplicate identities, and extra top-level fields', () => {
  const artist = (index) => ({
    name: `Artist ${index}`,
    imageUrl: '',
    genres: [],
  });
  assertInvalidArgument(() => parseMusicProfilePayload({
    artists: Array.from({ length: 31 }, (_, index) => artist(index)),
  }));
  assertInvalidArgument(() => parseMusicProfilePayload({
    artists: [artist(1), artist(1)],
  }));
  assertInvalidArgument(() => parseMusicProfilePayload({ artists: [], uid: 'victim' }));
});

function fakeFirestore({
  userExists = true,
  deleted = false,
  deletionPending = false,
  userData = {},
  limiterData = {},
} = {}) {
  const updates = [];
  const sets = [];
  const refs = new Map();
  const firestore = {
    doc(path) {
      const ref = { path };
      refs.set(path, ref);
      return ref;
    },
    async runTransaction(callback) {
      return callback({
        async get(ref) {
          if (ref.path === 'users/alice') {
            return {
              exists: userExists,
              data() {
                return {
                  username: deleted ? 'deleted_user' : 'alice',
                  ...userData,
                };
              },
              get(field) {
                return field === 'username' && deleted ? 'deleted_user' : 'alice';
              },
            };
          }
          return {
            exists: ref.path === 'account_deletions/alice' && deletionPending,
            data() { return ref.path === 'rate_limits/alice' ? limiterData : {}; },
          };
        },
        update(ref, fields) {
          updates.push({ ref, fields });
        },
        set(ref, fields) {
          sets.push({ ref, fields });
        },
      });
    },
  };
  return { firestore, sets, updates };
}

test('writes only the authenticated user profile through one transaction', async () => {
  const { firestore, updates } = fakeFirestore();
  const artists = parseMusicProfilePayload({ artists: [] });

  await writeMusicProfile(firestore, 'alice', artists);

  assert.equal(updates.length, 1);
  assert.equal(updates[0].ref.path, 'users/alice');
  assert.deepEqual(updates[0].fields.topArtists, []);
  assert.deepEqual(updates[0].fields.topGenres, []);
  assert.equal(updates[0].fields.musicProfileVersion, 1);
});

test('coalesces an identical music profile without requesting recommendations', async () => {
  const fields = buildMusicProfileFields([], Timestamp.fromMillis(1));
  const { firestore, updates } = fakeFirestore({ userData: fields });

  const updated = await writeMusicProfile(
    firestore,
    'alice',
    [],
    Timestamp.fromMillis(2),
  );

  assert.equal(updated, false);
  assert.deepEqual(updates, []);
});

test('rate limits repeated changed music profiles', async () => {
  const now = Timestamp.fromMillis(60_000);
  const { firestore, updates } = fakeFirestore({
    limiterData: {
      musicProfileTokens: 0,
      musicProfileTokensUpdatedAt: Timestamp.fromMillis(55_000),
    },
  });

  await assert.rejects(
    writeMusicProfile(firestore, 'alice', [], now),
    (error) => error?.code === 'resource-exhausted',
  );
  assert.deepEqual(updates, []);
});

test('refills one music profile change every ten seconds', async () => {
  const now = Timestamp.fromMillis(60_000);
  const { firestore, sets, updates } = fakeFirestore({
    limiterData: {
      musicProfileTokens: 0,
      musicProfileTokensUpdatedAt: Timestamp.fromMillis(50_000),
    },
  });

  const updated = await writeMusicProfile(firestore, 'alice', [], now);

  assert.equal(updated, true);
  assert.equal(updates.length, 1);
  assert.equal(sets.length, 1);
  assert.equal(sets[0].ref.path, 'rate_limits/alice');
  assert.equal(sets[0].fields.musicProfileTokens, 0);
  assert.equal(sets[0].fields.musicProfileTokensUpdatedAt, now);
});

test('does not write inactive or deletion-pending profiles', async () => {
  for (const options of [
    { userExists: false },
    { deleted: true },
    { deletionPending: true },
  ]) {
    const { firestore, updates } = fakeFirestore(options);
    await assert.rejects(
      writeMusicProfile(firestore, 'alice', []),
      (error) => error?.code === 'failed-precondition',
    );
    assert.deepEqual(updates, []);
  }
});
