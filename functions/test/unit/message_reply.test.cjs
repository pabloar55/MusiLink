const assert = require('node:assert/strict');
const test = require('node:test');
const { parseChatMessagePayload, replyPreview } = require('../../lib/social_writes.js');

const text = { chatId: 'alice_bob', messageId: 'aaaaaaaaaaaaaaaaaaaa', type: 'text', text: ' Hello ' };
const track = {
  chatId: 'alice_bob', messageId: 'bbbbbbbbbbbbbbbbbbbb', type: 'track',
  trackData: { title: 'Song', artist: 'Artist', imageUrl: '', spotifyUrl: 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC' },
};

test('message reply payload accepts only the ID of the quoted message', () => {
  assert.equal(parseChatMessagePayload(text).replyToMessageId, undefined);
  for (const payload of [text, track]) {
    assert.equal(parseChatMessagePayload({ ...payload, replyToMessageId: 'original_message_id_' }).replyToMessageId, 'original_message_id_');
    for (const replyToMessageId of [null, '', 7, '..', 'chats/other', payload.messageId, 'x'.repeat(129)]) {
      assert.throws(() => parseChatMessagePayload({ ...payload, replyToMessageId }), { code: 'invalid-argument' });
    }
    // The quote itself is never taken from the client.
    assert.throws(
      () => parseChatMessagePayload({ ...payload, replyTo: { messageId: 'original_message_id_', senderId: 'bob', text: 'forged' } }),
      { code: 'invalid-argument' },
    );
  }
  assert.throws(() => parseChatMessagePayload({
    ...text, type: 'daily_song_reply', dailySongReply: { ownerId: 'bob', publishedAtMicros: 1 }, replyToMessageId: 'original_message_id_',
  }), { code: 'invalid-argument' });
});

test('message reply preview summarizes the stored message', () => {
  assert.deepEqual(replyPreview('m1', { senderId: 'bob', type: 'text', text: 'Hi' }), {
    messageId: 'm1', senderId: 'bob', type: 'text', text: 'Hi',
  });
  assert.deepEqual(replyPreview('m2', { senderId: 'bob', type: 'track', text: 'Song - Artist', trackData: {} }), {
    messageId: 'm2', senderId: 'bob', type: 'track', text: 'Song - Artist',
  });
  // Truncation keeps whole code points.
  assert.equal(replyPreview('m3', { senderId: 'bob', text: '🎵'.repeat(250) }).text, '🎵'.repeat(200));
  assert.equal(
    replyPreview('m4', { senderId: 'bob', text: '🎵 “Song” — Artist\n\nLove it', dailySongReply: { ownerId: 'alice', publishedAtMicros: 1 } }).text,
    'Love it',
  );
  for (const missing of [undefined, {}, { senderId: '' }, { senderId: 7, text: 'Hi' }]) {
    assert.equal(replyPreview('m5', missing), undefined);
  }
});
