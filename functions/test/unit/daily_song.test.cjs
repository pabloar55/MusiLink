const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const { hasExpiredDailySong } = require('../../lib/daily_song.js');

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
