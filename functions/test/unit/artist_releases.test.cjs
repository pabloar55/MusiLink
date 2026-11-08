const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const {
  followedSpotifyArtists,
  isQuotaExceeded,
  parseSpotifyReleases,
  parseStoredReleases,
  pendingReleases,
  updateRecentReleases,
  wantsWeeklyReleaseNotification,
  weeklyReleaseNotification,
  weeklyReleaseOffsets,
} = require('../../lib/artist_releases.js');
const { notificationPath } = require('../../lib/notifications.js');

const now = Date.parse('2026-11-06T10:00:00Z');
const hour = 3600000;
const id = (char) => char.repeat(22);
const image = (char) => `https://i.scdn.co/image/${char.repeat(10)}`;
const release = (char, releaseDate, type = 'single') => ({
  id: id(char), name: `Release ${char}`, type, releaseDate, imageUrl: image(char),
});

test('parseSpotifyReleases keeps valid items, day-precision dates and Spotify images', () => {
  assert.deepEqual(parseSpotifyReleases({
    items: [
      {
        id: id('a'),
        name: ' Nueva ',
        release_date: '2026-11-06',
        release_date_precision: 'day',
        images: [
          { url: image('l'), width: 640 },
          { url: image('m'), width: 300 },
        ],
      },
      { id: id('b'), name: 'Antigua', release_date: '2019', release_date_precision: 'year', images: [{ url: 'https://evil.example/x.jpg' }] },
      { id: 'short', name: 'Inválida', release_date: '2026-11-06', release_date_precision: 'day' },
      { id: id('c'), name: '' },
      null,
    ],
  }, 'album'), [
    { id: id('a'), name: 'Nueva', type: 'album', releaseDate: '2026-11-06', imageUrl: image('m') },
    { id: id('b'), name: 'Antigua', type: 'album', releaseDate: null, imageUrl: '' },
  ]);
  assert.throws(() => parseSpotifyReleases({ error: 'x' }, 'single'), /malformed/);
});

test('a newly watched artist keeps its recent releases without announcing them', () => {
  const result = updateRecentReleases(undefined, [], [
    release('a', '2026-11-06'),
    release('o', '2026-08-01'),
  ], now);
  assert.deepEqual(result.knownReleaseIds, [id('a'), id('o')]);
  assert.deepEqual(result.recentReleases, [{ ...release('a', '2026-11-06'), detectedAt: now, announce: false }]);
  assert.equal(result.newReleases, 0);
});

test('unseen recent releases are announced, newest first, albums before singles', () => {
  const previous = [{ ...release('a', '2026-11-01'), detectedAt: now - 72 * hour, announce: true }];
  const result = updateRecentReleases([id('a'), id('x')], previous, [
    release('a', '2026-11-01'),
    release('b', '2026-11-05'),
    release('c', '2026-11-05', 'album'),
    // Known, or published before the announcement window: shown, not announced.
    release('x', '2026-11-04'),
    release('d', '2026-10-20'),
    release('f', '2026-11-12'),
    release('u', null),
  ], now);
  assert.deepEqual(
    result.recentReleases.map((stored) => [stored.id[0], stored.announce]),
    [['c', true], ['b', true], ['x', false], ['a', true], ['d', false]],
  );
  assert.equal(result.newReleases, 2);
  // Detection keeps its first time and announcement flag on later checks.
  assert.equal(result.recentReleases[3].detectedAt, now - 72 * hour);
  const again = updateRecentReleases(result.knownReleaseIds, result.recentReleases, [release('c', '2026-11-05', 'album')], now + 24 * hour);
  assert.equal(again.newReleases, 0);
  assert.deepEqual(again.recentReleases.map((stored) => [stored.detectedAt, stored.announce]), [[now, true]]);
});

test('release history and recent releases stay bounded', () => {
  const known = Array.from({ length: 60 }, (_, index) => String(index).padStart(22, '0'));
  const many = Array.from({ length: 15 }, (_, index) => ({
    ...release('a', `2026-11-0${(index % 6) + 1}`),
    id: String(index).padStart(22, 'z'),
  }));
  const result = updateRecentReleases(known, [], many, now);
  assert.equal(result.knownReleaseIds.length, 50);
  assert.equal(result.recentReleases.length, 10);
});

test('parseStoredReleases drops malformed entries and untrusted images', () => {
  assert.deepEqual(parseStoredReleases([
    { ...release('a', '2026-11-06'), imageUrl: 'https://evil.example/a.jpg', detectedAt: Timestamp.fromMillis(now), announce: true },
    { ...release('b', '2026-11-06'), detectedAt: now },
    { ...release('c', '2026'), detectedAt: Timestamp.fromMillis(now) },
  ]), [{ ...release('a', '2026-11-06'), imageUrl: '', detectedAt: now, announce: true }]);
  assert.deepEqual(parseStoredReleases(undefined), []);
});

test('isQuotaExceeded tells quota exhaustion from ordinary rate limiting', async () => {
  const response = (body) => new Response(JSON.stringify(body), { status: 429 });
  assert.equal(await isQuotaExceeded(response({ error: { status: 429, reason: 'QUOTA_EXCEEDED' } })), true);
  assert.equal(await isQuotaExceeded(response({ error: { status: 429, message: 'Too many requests' } })), false);
  assert.equal(await isQuotaExceeded(new Response('not json', { status: 429 })), false);
});

test('weeklyReleaseOffsets selects the zones where it is Saturday 11:30', () => {
  // Saturday 2026-11-07, 10:30 UTC: 11:30 at UTC+01:00.
  assert.deepEqual(weeklyReleaseOffsets(new Date('2026-11-07T10:30:00Z')), [60]);
  assert.deepEqual(weeklyReleaseOffsets(new Date('2026-11-07T10:44:59Z')), [60]);
  // UTC+14:00 reaches Saturday 11:30 on Friday in UTC; UTC-10:00 is still Friday.
  assert.deepEqual(weeklyReleaseOffsets(new Date('2026-11-06T21:30:00Z')), [840]);
  // UTC-12:00 is the last zone, on Saturday 23:30 UTC.
  assert.deepEqual(weeklyReleaseOffsets(new Date('2026-11-07T23:30:00Z')), [-720]);
  // India (UTC+05:30) and no Saturday zone on a weekday.
  assert.deepEqual(weeklyReleaseOffsets(new Date('2026-11-07T06:00:00Z')), [330]);
  assert.deepEqual(weeklyReleaseOffsets(new Date('2026-11-05T10:30:00Z')), []);
});

test('followedSpotifyArtists keeps unique artists with a Spotify id', () => {
  assert.deepEqual(followedSpotifyArtists({
    topArtists: [
      { name: ' Rosalía ', spotifyId: id('r') },
      { name: 'Sin id' },
      { name: 'Duplicada', spotifyId: id('r') },
      { name: 'Id inválido', spotifyId: 'x' },
      'raw',
    ],
  }), [{ id: id('r'), name: 'Rosalía' }]);
  assert.deepEqual(followedSpotifyArtists(undefined), []);
});

test('wantsWeeklyReleaseNotification respects the opt-out and repeated slots', () => {
  assert.equal(wantsWeeklyReleaseNotification({ utcOffsetMinutes: 60 }, now), true);
  assert.equal(wantsWeeklyReleaseNotification({}, now), false);
  assert.equal(wantsWeeklyReleaseNotification({ utcOffsetMinutes: 60, notifNewReleases: false }, now), false);
  assert.equal(wantsWeeklyReleaseNotification({
    utcOffsetMinutes: 60,
    newReleasePushAt: Timestamp.fromMillis(now - hour),
  }, now), false);
  assert.equal(wantsWeeklyReleaseNotification({
    utcOffsetMinutes: 60,
    newReleasePushAt: Timestamp.fromMillis(now - 7 * 24 * hour),
  }, now), true);
});

test('pendingReleases returns announced releases detected since the last push', () => {
  const artists = [{ id: id('a'), name: 'A' }, { id: id('b'), name: 'B' }, { id: id('c'), name: 'C' }];
  const stored = (char, releaseDate, hoursAgo, announce = true) => ({
    ...release(char, releaseDate), detectedAt: now - hoursAgo * hour, announce,
  });
  const states = new Map([
    [id('a'), [stored('a', '2026-11-03', 70), stored('x', '2026-10-01', 70, false)]],
    [id('b'), [stored('b', '2026-11-06', 2)]],
    [id('c'), [stored('c', '2026-10-28', 9 * 24)]],
  ]);
  assert.deepEqual(
    pendingReleases(artists, states, undefined, now).map((pending) => pending.release.id[0]),
    ['b', 'a'],
  );
  assert.deepEqual(
    pendingReleases(artists, states, now - 10 * hour, now).map((pending) => pending.release.id[0]),
    ['b'],
  );
});

test('weeklyReleaseNotification headlines the newest release and names the other artists', () => {
  const pending = (name, type = 'single', artistId = name) => ({
    artist: { id: artistId, name },
    release: { ...release('a', '2026-11-06', type), name: `${name} song`, detectedAt: now, announce: true },
  });
  assert.deepEqual(weeklyReleaseNotification('es', [pending('Rosalía')]), {
    title: 'Escucha la nueva canción de Rosalía',
    body: 'Rosalía song',
  });
  assert.equal(weeklyReleaseNotification('es', [pending('Bad Bunny', 'album')]).title, 'Escucha el nuevo álbum de Bad Bunny');
  assert.equal(
    weeklyReleaseNotification('es', [pending('Rosalía'), pending('Rosalía'), pending('Aitana'), pending('Quevedo')]).body,
    'Rosalía song · También hay novedades de Aitana y Quevedo',
  );
  assert.equal(
    weeklyReleaseNotification('en', [pending('A'), pending('B'), pending('C'), pending('D')]).body,
    'A song · New music from B and 2 others too',
  );
  for (const locale of ['el', 'en', 'es', 'fr']) {
    assert.match(weeklyReleaseNotification(locale, [pending('Rosalía')]).title, /Rosalía/);
  }
});

test('the weekly release notification opens the releases section', () => {
  assert.equal(notificationPath({ type: 'new_release' }), '/?tab=releases');
});
