const assert = require('node:assert/strict');
const test = require('node:test');

const { scrubUserReactions } = require('../lib/account_deletion.js');

test('scrubUserReactions removes the deleted uid and empty emoji entries', () => {
  assert.deepEqual(
    scrubUserReactions({
      '❤️': ['deleted', 'friend'],
      '🔥': ['deleted'],
      '👏': ['friend'],
    }, 'deleted'),
    {
      '❤️': ['friend'],
      '👏': ['friend'],
    },
  );
});

test('scrubUserReactions tolerates malformed legacy values', () => {
  assert.deepEqual(
    scrubUserReactions({ '❤️': 'deleted', '🔥': [null, 'friend'] }, 'deleted'),
    { '🔥': ['friend'] },
  );
  assert.deepEqual(scrubUserReactions(null, 'deleted'), {});
});
