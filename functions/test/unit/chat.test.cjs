const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');

const {
  allParticipantsDeletedBefore,
  fullySoftDeletedChat,
  messageSummary,
} = require('../../lib/chat.js');

test('messageSummary formats tracks and tolerates malformed messages', () => {
  assert.equal(messageSummary({ type: 'track', trackData: { title: 'Midnight' } }), '🎵 Midnight');
  assert.equal(messageSummary({ type: 'text', text: 'Hello' }), 'Hello');
  assert.equal(messageSummary({ type: 'track', trackData: {} }), '');
});

test('fullySoftDeletedChat requires both participants to delete the latest message', () => {
  const latest = Timestamp.fromMillis(1_000);
  assert.equal(fullySoftDeletedChat({
    participants: ['a', 'b'],
    lastMessageTime: latest,
    deletedAt: {
      a: Timestamp.fromMillis(1_000),
      b: Timestamp.fromMillis(1_001),
    },
  }), true);
  assert.equal(fullySoftDeletedChat({
    participants: ['a', 'b'],
    lastMessageTime: latest,
    deletedAt: {
      a: Timestamp.fromMillis(999),
      b: Timestamp.fromMillis(1_001),
    },
  }), false);
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
