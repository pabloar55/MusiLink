const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const {
  allParticipantsDeletedBefore,
  messageSummary,
  onNewMessage,
  shouldIncrementUnreadCount,
} = require('../../lib/chat.js');

test('onNewMessage retries failed event deliveries', () => {
  assert.equal(onNewMessage.__endpoint.eventTrigger.retry, true);
});

test('messageSummary formats tracks and tolerates malformed messages', () => {
  assert.equal(messageSummary({ type: 'track', trackData: { title: 'Midnight' } }), '🎵 Midnight');
  assert.equal(messageSummary({ type: 'text', text: 'Hello' }), 'Hello');
  assert.equal(messageSummary({ type: 'track', trackData: {} }), '');
});

test('allParticipantsDeletedBefore returns the earliest deletion boundary', () => {
  const boundary = allParticipantsDeletedBefore({
    participants: ['a', 'b'],
    deletedAt: {
      a: Timestamp.fromMillis(5_000),
      b: Timestamp.fromMillis(3_000),
    },
  });
  assert.equal(boundary?.toMillis(), 3_000);
  assert.equal(allParticipantsDeletedBefore({ participants: ['a', 'b'] }), undefined);
});

test('shouldIncrementUnreadCount ignores messages hidden by a deletion', () => {
  const deletedAt = Timestamp.fromMillis(2_000);
  const chat = { deletedAt: { alice: deletedAt } };

  assert.equal(
    shouldIncrementUnreadCount(chat, 'alice', Timestamp.fromMillis(1_999)),
    false,
  );
  assert.equal(
    shouldIncrementUnreadCount(chat, 'alice', Timestamp.fromMillis(2_000)),
    false,
  );
  assert.equal(
    shouldIncrementUnreadCount(chat, 'alice', Timestamp.fromMillis(2_001)),
    true,
  );
  assert.equal(
    shouldIncrementUnreadCount(chat, 'bob', Timestamp.fromMillis(1_000)),
    true,
  );
});
