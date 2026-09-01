const assert = require('node:assert/strict');
const test = require('node:test');

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

function fakeFirestore({ userExists = true, deleted = false, deletionPending = false } = {}) {
  const updates = [];
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
              get(field) {
                return field === 'username' && deleted ? 'deleted_user' : 'alice';
              },
            };
          }
          return { exists: deletionPending };
        },
        update(ref, fields) {
          updates.push({ ref, fields });
        },
      });
    },
  };
  return { firestore, updates };
}

test('writes only the authenticated user profile through one transaction', async () => {
  const { firestore, updates } = fakeFirestore();
  const artists = parseMusicProfilePayload({ artists: [] });

  await writeMusicProfile(firestore, 'alice', artists);

  assert.equal(updates.length, 1);
  assert.equal(updates[0].ref.path, 'users/alice');
  assert.deepEqual(updates[0].fields.topArtists, []);
  assert.deepEqual(updates[0].fields.topGenres, []);
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
