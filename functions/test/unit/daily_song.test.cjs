const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const { dailySongExpiredBody, hasExpiredDailySong } = require('../../lib/daily_song.js');

test('hasExpiredDailySong checks the timestamp boundary and song presence', () => {
  const boundary = Timestamp.fromMillis(10_000);
  assert.equal(hasExpiredDailySong({
    dailySong: { title: 'Song' },
    dailySongUpdatedAt: Timestamp.fromMillis(10_000),
  }, boundary), true);
  assert.equal(hasExpiredDailySong({
    dailySong: { title: 'Song' },
    dailySongUpdatedAt: Timestamp.fromMillis(10_001),
  }, boundary), false);
  assert.equal(hasExpiredDailySong({
    dailySongUpdatedAt: Timestamp.fromMillis(9_000),
  }, boundary), false);
  assert.equal(hasExpiredDailySong(undefined, boundary), false);
});

test('dailySongExpiredBody mentions friends who have already published', () => {
  assert.equal(dailySongExpiredBody('es', 0), '¡Tu canción del día ha caducado! Publica una nueva.');
  assert.equal(
    dailySongExpiredBody('es', 1),
    'Tu canción del día ha caducado y un amigo ya ha publicado la suya. ¡Publica una nueva!',
  );
  assert.equal(
    dailySongExpiredBody('es', 4),
    'Tu canción del día ha caducado y 4 amigos ya han publicado la suya. ¡Publica una nueva!',
  );
  for (const locale of ['en', 'es', 'fr', 'el']) {
    assert.match(dailySongExpiredBody(locale, 12), /12/);
    assert.notEqual(dailySongExpiredBody(locale, 1), dailySongExpiredBody(locale, 0));
  }
});
