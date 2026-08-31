const assert = require('node:assert/strict');
const test = require('node:test');

const {
  notificationPath,
  notifChannelId,
  preferredLocale,
} = require('../../lib/notifications.js');

test('notifChannelId reflects sound and vibration preferences', () => {
  assert.equal(notifChannelId(true, true), 'musilink_high');
  assert.equal(notifChannelId(true, false), 'musilink_high_no_vibration');
  assert.equal(notifChannelId(false, true), 'musilink_high_no_sound');
  assert.equal(notifChannelId(false, false), 'musilink_high_silent');
});

test('notificationPath builds encoded chat routes and domain fallbacks', () => {
  assert.equal(
    notificationPath({
      type: 'new_message',
      chatId: 'chat/1',
      otherUserId: 'user 2',
      otherUserName: 'Álex & Sam',
    }),
    '/chat?chatId=chat%2F1&otherUserId=user+2&otherUserName=%C3%81lex+%26+Sam',
  );
  assert.equal(notificationPath({ type: 'friend_request' }), '/?tab=friends');
  assert.equal(notificationPath({ type: 'daily_song_expired' }), '/?tab=daily-song');
  assert.equal(notificationPath({ type: 'unknown' }), '/');
});

test('preferredLocale accepts regional locales and falls back to English', () => {
  assert.equal(preferredLocale({ preferredLocale: 'el-GR' }), 'el');
  assert.equal(preferredLocale({ preferredLocale: 'es-ES' }), 'es');
  assert.equal(preferredLocale({ preferredLocale: 'FR_ca' }), 'fr');
  assert.equal(preferredLocale({ preferredLocale: 'de-DE' }), 'en');
  assert.equal(preferredLocale(undefined), 'en');
});
