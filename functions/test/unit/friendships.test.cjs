const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const friendships = require('../../lib/friendships.js');
const {
  friendRequestNotificationIsCoolingDown,
  userHasBlocked,
} = friendships;

test('userHasBlocked normalizes list entries and ignores malformed values', () => {
  assert.equal(userHasBlocked({ blockedUsers: [' other-user ', null] }, 'other-user'), true);
  assert.equal(userHasBlocked({ blockedUsers: 'other-user' }, 'other-user'), false);
  assert.equal(userHasBlocked(undefined, 'other-user'), false);
});

test('friend request notification cooldown remains active for one hour', () => {
  const lastNotifiedAt = Timestamp.fromMillis(1_000);

  assert.equal(
    friendRequestNotificationIsCoolingDown(
      lastNotifiedAt,
      Timestamp.fromMillis(3_600_999),
    ),
    true,
  );
  assert.equal(
    friendRequestNotificationIsCoolingDown(
      lastNotifiedAt,
      Timestamp.fromMillis(3_601_000),
    ),
    false,
  );
});
