const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const {
  friendDigestBody,
  friendDigestOffsets,
  wantsFriendDigest,
} = require('../../lib/friend_digest.js');
const { notificationPath } = require('../../lib/notifications.js');

test('friendDigestOffsets selects the zones where it is 21:00', () => {
  assert.deepEqual(friendDigestOffsets(new Date('2026-10-01T19:00:00Z')), [120]);
  // Cloud Scheduler may start a slot late; it still belongs to its quarter.
  assert.deepEqual(friendDigestOffsets(new Date('2026-10-01T19:14:59Z')), [120]);
  assert.deepEqual(friendDigestOffsets(new Date('2026-10-01T15:30:00Z')), [330]);
  assert.deepEqual(friendDigestOffsets(new Date('2026-10-01T15:15:00Z')), [345]);
  assert.deepEqual(friendDigestOffsets(new Date('2026-10-01T00:00:00Z')), [-180]);
  // 21:00 on both sides of the date line: UTC+13:00 and UTC-11:00.
  assert.deepEqual(friendDigestOffsets(new Date('2026-10-01T08:00:00Z')), [780, -660]);
});

test('friendDigestBody names up to three friends and counts the rest', () => {
  assert.equal(
    friendDigestBody('es', ['Ana']),
    'Ana ha publicado su canción del día. ¡Publica la tuya!',
  );
  assert.equal(
    friendDigestBody('fr', ['Ana']),
    'Ana a partagé sa chanson du jour. Partagez la vôtre !',
  );
  assert.match(friendDigestBody('el', ['Ana']), /^Ο χρήστης Ana μοιράστηκε/);
  assert.equal(
    friendDigestBody('es', ['Ana', 'Luis']),
    'Ana y Luis han publicado su canción del día. ¡Publica la tuya!',
  );
  assert.equal(
    friendDigestBody('es', ['Ana', 'Luis', 'Marta']),
    'Ana, Luis y Marta han publicado su canción del día. ¡Publica la tuya!',
  );
  assert.equal(
    friendDigestBody('es', ['Ana', 'Luis', 'Marta', 'Noa', 'Pau']),
    'Ana, Luis y 3 más han publicado su canción del día. ¡Publica la tuya!',
  );
  assert.equal(
    friendDigestBody('en', ['Ana', 'Luis', 'Marta', 'Noa']),
    "Ana, Luis, and 2 others shared their song of the day. Share yours!",
  );
  assert.match(friendDigestBody('fr', ['Ana', 'Luis', 'Marta', 'Noa']), /^Ana, Luis et 2 autres ont/);
  assert.match(friendDigestBody('el', ['Ana', 'Luis', 'Marta', 'Noa']), /Ana, Luis και 2 ακόμη/);
});

test('wantsFriendDigest applies the opt-out and the one-reminder-per-local-day budget', () => {
  const now = Date.parse('2026-10-01T19:00:00Z'); // 21:00 at UTC+02:00
  const at = (iso) => Timestamp.fromMillis(Date.parse(iso));

  assert.equal(wantsFriendDigest({ utcOffsetMinutes: 120 }, now), true);
  assert.equal(wantsFriendDigest({}, now), false);
  assert.equal(wantsFriendDigest(undefined, now), false);
  assert.equal(wantsFriendDigest({ utcOffsetMinutes: 120, notifFriendDigest: false }, now), false);
  // 00:30 local time today.
  assert.equal(wantsFriendDigest({
    utcOffsetMinutes: 120,
    engagementPushAt: at('2026-09-30T22:30:00Z'),
  }, now), false);
  // 23:30 local time yesterday.
  assert.equal(wantsFriendDigest({
    utcOffsetMinutes: 120,
    engagementPushAt: at('2026-09-30T21:30:00Z'),
  }, now), true);
});

test('notificationPath opens the daily song tab from the friend digest', () => {
  assert.equal(notificationPath({ type: 'friend_digest' }), '/?tab=daily-song');
});
