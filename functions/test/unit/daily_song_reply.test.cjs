const assert = require('node:assert/strict');
const test = require('node:test');
const { parseChatMessagePayload } = require('../../lib/social_writes.js');

const payload = {
  chatId: 'alice_bob', messageId: 'daily_reply_message_01', type: 'daily_song_reply',
  text: ' Hello ', dailySongReply: { ownerId: 'bob', publishedAtMicros: 123456789 },
};
test('daily song reply payload normalizes text and rejects invalid references', () => {
  assert.equal(parseChatMessagePayload(payload).text, 'Hello');
  for (const dailySongReply of [null, {}, { ownerId: 'bob', publishedAtMicros: 0 }, { ownerId: '../bob', publishedAtMicros: 1 }, { ownerId: 'bob', publishedAtMicros: 1.5 }, { ...payload.dailySongReply, trackData: {} }]) {
    assert.throws(() => parseChatMessagePayload({ ...payload, dailySongReply }), { code: 'invalid-argument' });
  }
  for (const text of ['', '   ', '🎵'.repeat(501)]) {
    assert.throws(() => parseChatMessagePayload({ ...payload, text }), { code: 'invalid-argument' });
  }
});
