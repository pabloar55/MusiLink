const assert = require('node:assert/strict');
const test = require('node:test');

const { userHasBlocked } = require('../../lib/friendships.js');

test('userHasBlocked normalizes list entries and ignores malformed values', () => {
  assert.equal(userHasBlocked({ blockedUsers: [' other-user ', null] }, 'other-user'), true);
  assert.equal(userHasBlocked({ blockedUsers: 'other-user' }, 'other-user'), false);
  assert.equal(userHasBlocked(undefined, 'other-user'), false);
});
