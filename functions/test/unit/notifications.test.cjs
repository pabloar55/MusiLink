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

const { chatNotification, notificationText } = require('../../lib/notifications.js');
test('daily song replies notify with the localized context and the plain reply', () => {
  const reply = { ownerId: 'bob', publishedAtMicros: 123, formatVersion: 2 };
  assert.deepEqual(chatNotification({ text: 'Me encanta', dailySongReply: reply }, 'Alice', { preferredLocale: 'es' }), {
    title: 'Alice ha respondido a tu canción', body: 'Me encanta',
  });
  assert.deepEqual(chatNotification({ text: '🎵 “Song” — Artist\n\nMe encanta', dailySongReply: { ownerId: 'bob', publishedAtMicros: 123 } }, 'Alice', { preferredLocale: 'es' }), {
    title: 'Alice ha respondido a tu canción', body: 'Me encanta',
  });
  assert.deepEqual(chatNotification({ text: 'Hola' }, 'Alice', { preferredLocale: 'es' }), { title: 'Alice', body: 'Hola' });
  for (const locale of ['en', 'es', 'fr', 'el']) {
    assert.match(notificationText.dailySongReply[locale]('Alice'), /Alice/);
    assert.match(notificationText.dailySongLiked[locale]('Alice'), /Alice/);
  }
  assert.equal(notificationText.dailySongLiked.es('Alice'), 'A Alice le ha gustado tu canción del día');
  assert.equal(notificationPath({ type: 'daily_song_liked' }), '/?tab=daily-song');
});

const { db, messaging } = require('../../lib/firebase.js');
const { Timestamp } = require('firebase-admin/firestore');
const registrationTime = Timestamp.fromMillis(1000);
const { sendNotification } = require('../../lib/notifications.js');

function mockPushTargets(t, destinations, owner = { uid: 'alice', installationId: 'device' }) {
  const documents = destinations.map((data, i) => ({
    data: () => data,
    updateTime: registrationTime,
    ref: { id: 'device', path: `user_private/alice/push_tokens/device${i}` },
  }));
  const query = { limit() { return this; }, async get() { return { docs: documents }; } };
  t.mock.method(db, 'doc', (path) => path.startsWith('push_installations/')
    ? { async get() { return { data: () => owner }; } }
    : { collection: () => query });
  const sent = [];
  t.mock.method(messaging, 'send', async (message) => { sent.push(message); return 'sent'; });
  return { documents, sent };
}

test('sends to FIDs and legacy tokens with identical notification behavior', async (t) => {
  const { sent } = mockPushTargets(t, [{ fid: 'fid-1' }, { token: 'legacy-1' }]);
  await sendNotification('alice', undefined, { title: 'Hello', body: 'World' }, { type: 'friend_request' }, 'friend');
  assert.equal(sent.length, 2);
  const fidMessage = sent.find((message) => message.fid);
  const tokenMessage = sent.find((message) => message.token);
  const { fid, ...fidPayload } = fidMessage;
  const { token, ...tokenPayload } = tokenMessage;
  assert.equal(fid, 'fid-1');
  assert.equal(token, 'legacy-1');
  assert.deepEqual(fidPayload, tokenPayload);
});

test('FID ownership prevents sends from stale accounts after offline sign-out', async (t) => {
  const { sent } = mockPushTargets(t, [{ fid: 'shared-fid' }], { uid: 'bob', installationId: 'device' });
  await sendNotification('alice', undefined, { title: 'Private', body: 'Message' }, {});
  assert.deepEqual(sent, []);
});

test('missing ownership fails closed instead of reviving an old account registration', async (t) => {
  const { sent } = mockPushTargets(t, [{ fid: 'shared-fid' }], null);
  await sendNotification('alice', undefined, { title: 'Private', body: 'Message' }, {});
  assert.deepEqual(sent, []);
});

test('deduplicates FIDs and keeps Android chat delivery data-only', async (t) => {
  const { sent } = mockPushTargets(t, [{ fid: 'fid-1' }, { fid: 'fid-1' }]);
  await sendNotification('alice', undefined, { title: 'Chat', body: 'Text' }, { type: 'new_message' });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].notification, undefined);
  assert.equal(sent[0].android.notification, undefined);
  assert.deepEqual(sent[0].apns.payload.aps.alert, { title: 'Chat', body: 'Text' });
});

for (const migrated of [false, true]) {
  test(`invalid legacy target cleanup preserves a concurrent FID migration: ${migrated}`, async (t) => {
    const { documents } = mockPushTargets(t, [{ token: 'old-token' }]);
    t.mock.method(messaging, 'send', async () => {
      throw { code: 'messaging/registration-token-not-registered' };
    });
    const deleted = [];
    t.mock.method(db, 'runTransaction', async (callback) => callback({
      async get() { return { updateTime: registrationTime, data: () => migrated ? { fid: 'new-fid' } : { token: 'old-token' } }; },
      delete(ref) { deleted.push(ref); },
    }));
    await sendNotification('alice', undefined, { title: 'Hello', body: 'World' }, {});
    assert.deepEqual(deleted, migrated ? [] : [documents[0].ref]);
  });
}

test('expired FID registrations use the new Admin SDK error code', async (t) => {
  const { documents } = mockPushTargets(t, [{ fid: 'expired-fid' }]);
  t.mock.method(messaging, 'send', async () => {
    throw { code: 'messaging/installation-id-not-registered' };
  });
  const deleted = [];
  t.mock.method(db, 'runTransaction', async (callback) => callback({
    async get() { return { updateTime: registrationTime, data: () => ({ fid: 'expired-fid' }) }; },
    delete(ref) { deleted.push(ref); },
  }));
  await sendNotification('alice', undefined, { title: 'Hello', body: 'World' }, {});
  assert.deepEqual(deleted, [documents[0].ref]);
});

test('duplicate FID records select the owned installation before deduplicating', async (t) => {
  const { documents, sent } = mockPushTargets(t, [{ fid: 'fid-1' }, { fid: 'fid-1' }]);
  documents[1].ref.id = 'stale-device';
  await sendNotification('alice', undefined, { title: 'Hello', body: 'World' }, {});
  assert.equal(sent.length, 1);
});

test('a failed old send cannot erase a renewed registration of the same FID', async (t) => {
  mockPushTargets(t, [{ fid: 'renewed-fid' }]);
  t.mock.method(messaging, 'send', async () => {
    throw { code: 'messaging/installation-id-not-registered' };
  });
  t.mock.method(db, 'runTransaction', async (callback) => callback({
    async get() { return {
      updateTime: Timestamp.fromMillis(2000), data: () => ({ fid: 'renewed-fid' }),
    }; },
    delete() { assert.fail('must preserve the renewed registration'); },
  }));
  await sendNotification('alice', undefined, { title: 'Hello', body: 'World' }, {});
});
