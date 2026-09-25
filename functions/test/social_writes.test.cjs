'use strict';

const assert = require('node:assert/strict');
const { after, before, beforeEach, test } = require('node:test');
const { getApps, deleteApp } = require('firebase-admin/app');
const { Timestamp } = require('firebase-admin/firestore');

const { db } = require('../lib/firebase.js');
const {
  deleteFriendRequestVersion,
  establishAcceptedFriendship,
} = require('../lib/friendships.js');
const {
  createChatMessage,
  createFriendRequest,
  parseChatMessagePayload,
} = require('../lib/social_writes.js');
const {
  advanceFixedWindow,
  consumeCatalogSearchQuota,
  maxCatalogSearchesPerWindow,
} = require('../lib/rate_limits.js');
const { createModerationReport } = require('../lib/moderation_reports.js');

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('FIRESTORE_EMULATOR_HOST is required for this test.');
  }
});

async function clearFirestore() {
  const collections = await db.listCollections();
  for (const collection of collections) {
    const snapshot = await collection.get();
    for (const document of snapshot.docs) await db.recursiveDelete(document.ref);
  }
}

async function seedUser(uid, friends = [], blockedUsers = []) {
  await Promise.all([
    db.doc(`users/${uid}`).set({
      displayName: uid,
      username: `${uid}_name`,
      photoUrl: '',
    }),
    db.doc(`user_private/${uid}`).set({
      friends,
      blockedUsers,
    }),
  ]);
}

async function seedChat() {
  await Promise.all([
    seedUser('alice', ['bob']),
    seedUser('bob', ['alice']),
  ]);
  await db.doc('chats/alice_bob').set({
    participants: ['alice', 'bob'],
    lastMessage: '',
    lastMessageTime: Timestamp.fromMillis(1),
    createdAt: Timestamp.fromMillis(1),
    unreadCounts: { alice: 0, bob: 0 },
  });
}

beforeEach(clearFirestore);

after(async () => {
  await clearFirestore();
  await Promise.all(getApps().map((app) => deleteApp(app)));
});

test('advanceFixedWindow usa exclusivamente el tiempo recibido del backend', () => {
  const start = Timestamp.fromMillis(1_000);
  const inside = advanceFixedWindow(start, 19, Timestamp.fromMillis(11_000), 10_000, 20);
  assert.equal(inside.limited, false);
  assert.equal(inside.count, 20);
  assert.equal(inside.windowStart.toMillis(), 1_000);

  const exhausted = advanceFixedWindow(start, 20, Timestamp.fromMillis(11_000), 10_000, 20);
  assert.equal(exhausted.limited, true);

  const expired = advanceFixedWindow(start, 20, Timestamp.fromMillis(11_001), 10_000, 20);
  assert.equal(expired.limited, false);
  assert.equal(expired.count, 1);
  assert.equal(expired.windowStart.toMillis(), 11_001);
});

test('catalog searches atomically reserve the last slot under concurrent requests', async () => {
  const now = Timestamp.fromMillis(1_000);
  await db.doc('rate_limits/alice').set({
    spotifySearchWindowStart: now,
    spotifySearchCount: maxCatalogSearchesPerWindow - 1,
    messageCount: 7,
  });
  const results = await Promise.allSettled(Array.from({ length: 8 }, () => (
    consumeCatalogSearchQuota(db, 'alice', 'spotifySearch', now)
  )));
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  for (const result of results.filter((result) => result.status === 'rejected')) {
    assert.equal(result.reason.code, 'resource-exhausted');
  }
  const limiter = (await db.doc('rate_limits/alice').get()).data();
  assert.equal(limiter.spotifySearchCount, maxCatalogSearchesPerWindow);
  assert.equal(limiter.messageCount, 7);
  await consumeCatalogSearchQuota(db, 'alice', 'lastFmSimilar', now);
  assert.equal((await db.doc('rate_limits/alice').get()).data().lastFmSimilarCount, 1);
  await consumeCatalogSearchQuota(db, 'bob', 'spotifySearch', now);
  assert.equal((await db.doc('rate_limits/bob').get()).data().spotifySearchCount, 1);
});

test('sendChatMessage valida estrictamente texto y metadatos de Spotify', () => {
  assert.deepEqual(parseChatMessagePayload({
    chatId: 'alice_bob',
    messageId: 'aaaaaaaaaaaaaaaaaaaa',
    type: 'text',
    text: '  hola  ',
  }), {
    chatId: 'alice_bob',
    messageId: 'aaaaaaaaaaaaaaaaaaaa',
    type: 'text',
    text: 'hola',
  });

  const validTrack = {
    title: 'Song',
    artist: 'Artist',
    imageUrl: 'https://i.scdn.co/image/abc123',
    spotifyUrl: 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
  };
  const parsedTrack = parseChatMessagePayload({
    chatId: 'alice_bob',
    messageId: 'bbbbbbbbbbbbbbbbbbbb',
    type: 'track',
    trackData: validTrack,
  });
  assert.equal(parsedTrack.text, 'Song - Artist');
  assert.deepEqual(parsedTrack.trackData, validTrack);

  for (const invalidPayload of [
    {
      chatId: 'alice_bob',
      messageId: 'cccccccccccccccccccc',
      type: 'text',
      text: 'hola',
      injected: true,
    },
    {
      chatId: 'alice_bob',
      messageId: 'dddddddddddddddddddd',
      type: 'track',
      trackData: { ...validTrack, spotifyUrl: 'https://phishing.example/track/id' },
    },
    {
      chatId: 'alice_bob',
      messageId: 'eeeeeeeeeeeeeeeeeeee',
      type: 'track',
      trackData: { ...validTrack, injected: true },
    },
  ]) {
    assert.throws(
      () => parseChatMessagePayload(invalidPayload),
      (error) => error.code === 'invalid-argument',
    );
  }
});

test('sendFriendRequest es idempotente y reinicia la ventana con tiempo de servidor', async () => {
  await Promise.all([seedUser('alice'), seedUser('bob')]);
  const start = Timestamp.fromMillis(1_000);

  assert.equal(await createFriendRequest(db, 'alice', 'bob', start), true);
  assert.equal(
    await createFriendRequest(db, 'alice', 'bob', Timestamp.fromMillis(2_000)),
    false,
  );
  assert.equal((await db.doc('rate_limits/alice').get()).data().friendRequestCount, 1);

  await db.doc('friend_requests/alice_bob').delete();
  await db.doc('rate_limits/alice').set({
    friendRequestWindowStart: start,
    friendRequestCount: 20,
  }, { merge: true });
  await assert.rejects(
    createFriendRequest(db, 'alice', 'bob', Timestamp.fromMillis(601_000)),
    (error) => error.code === 'resource-exhausted',
  );

  assert.equal(
    await createFriendRequest(db, 'alice', 'bob', Timestamp.fromMillis(601_001)),
    true,
  );
  const limiter = (await db.doc('rate_limits/alice').get()).data();
  assert.equal(limiter.friendRequestCount, 1);
  assert.equal(limiter.friendRequestWindowStart.toMillis(), 601_001);
});

test('un evento de aceptación antiguo no afecta a una solicitud recreada', async () => {
  await Promise.all([seedUser('alice'), seedUser('bob')]);
  const requestRef = db.doc('friend_requests/alice_bob');

  await createFriendRequest(db, 'alice', 'bob', Timestamp.fromMillis(1_000));
  await requestRef.update({
    status: 'accepted',
    updatedAt: Timestamp.fromMillis(2_000),
  });
  const acceptedRequest = await requestRef.get();
  const acceptedUpdateTime = acceptedRequest.updateTime;
  assert.ok(acceptedUpdateTime);

  await establishAcceptedFriendship(
    'alice_bob',
    'bob',
    'alice',
    acceptedUpdateTime,
  );
  await requestRef.delete();
  await Promise.all([
    db.doc('user_private/alice').update({ friends: [] }),
    db.doc('user_private/bob').update({ friends: [] }),
  ]);
  assert.equal(
    await createFriendRequest(db, 'alice', 'bob', Timestamp.fromMillis(3_000)),
    true,
  );

  await assert.rejects(
    establishAcceptedFriendship(
      'alice_bob',
      'bob',
      'alice',
      acceptedUpdateTime,
    ),
    (error) => error.code === 'failed-precondition',
  );
  await deleteFriendRequestVersion('alice_bob', acceptedUpdateTime);

  assert.deepEqual(
    (await db.doc('user_private/alice').get()).data().friends,
    [],
  );
  assert.deepEqual(
    (await db.doc('user_private/bob').get()).data().friends,
    [],
  );
  assert.equal((await requestRef.get()).data().status, 'pending');
});

test('sendChatMessage aplica el límite, reinicia la ventana y tolera reintentos', async () => {
  await seedChat();
  const start = Timestamp.fromMillis(1_000);
  await db.doc('rate_limits/alice').set({
    messageWindowStart: start,
    messageCount: 19,
  });

  const firstPayload = {
    chatId: 'alice_bob',
    messageId: 'aaaaaaaaaaaaaaaaaaaa',
    type: 'text',
    text: 'veinte',
  };
  await createChatMessage(db, 'alice', firstPayload, Timestamp.fromMillis(2_000));
  const sent = (await db.doc('chats/alice_bob/messages/aaaaaaaaaaaaaaaaaaaa').get()).data();
  assert.equal(sent.delivered, false);
  assert.equal(sent.read, false);
  await assert.rejects(
    createChatMessage(db, 'alice', {
      ...firstPayload,
      messageId: 'bbbbbbbbbbbbbbbbbbbb',
      text: 'veintiuno',
    }, Timestamp.fromMillis(3_000)),
    (error) => error.code === 'resource-exhausted',
  );

  const resetPayload = {
    ...firstPayload,
    messageId: 'cccccccccccccccccccc',
    text: 'nueva ventana',
  };
  await createChatMessage(db, 'alice', resetPayload, Timestamp.fromMillis(11_001));
  await createChatMessage(db, 'alice', resetPayload, Timestamp.fromMillis(11_500));

  const limiter = (await db.doc('rate_limits/alice').get()).data();
  assert.equal(limiter.messageCount, 1);
  assert.equal(limiter.messageWindowStart.toMillis(), 11_001);
  assert.equal((await db.doc('chats/alice_bob/messages/cccccccccccccccccccc').get()).exists, true);
});

test('sendChatMessage comprueba amistad y bloqueos en el backend', async () => {
  await seedChat();
  await db.doc('user_private/bob').update({ blockedUsers: ['alice'] });

  await assert.rejects(
    createChatMessage(db, 'alice', {
      chatId: 'alice_bob',
      messageId: 'dddddddddddddddddddd',
      type: 'text',
      text: 'no permitido',
    }, Timestamp.fromMillis(1_000)),
    (error) => error.code === 'permission-denied',
  );
  assert.equal(
    (await db.doc('chats/alice_bob/messages/dddddddddddddddddddd').get()).exists,
    false,
  );
});

test('las denuncias validan el contexto, conservan el mensaje y se deduplican', async () => {
  await Promise.all([seedChat(), seedUser('carol')]);
  await db.doc('chats/alice_bob/messages/message-1').set({
    senderId: 'bob',
    text: 'contenido denunciado',
    type: 'text',
    timestamp: Timestamp.fromMillis(1_000),
    read: false,
  });
  const payload = {
    type: 'message',
    reason: 'harassment',
    chatId: 'alice_bob',
    messageId: 'message-1',
  };

  const created = await createModerationReport(
    db,
    'alice',
    payload,
    Timestamp.fromMillis(2_000),
  );
  assert.equal(created.created, true);
  const report = (await db.doc(`moderation_reports/${created.reportId}`).get()).data();
  assert.equal(report.reportedUserId, 'bob');
  assert.equal(report.message.text, 'contenido denunciado');
  assert.equal(report.message.timestamp.toMillis(), 1_000);
  assert.equal(report.status, 'open');

  const duplicate = await createModerationReport(
    db,
    'alice',
    { ...payload, reason: 'other' },
    Timestamp.fromMillis(3_000),
  );
  assert.equal(duplicate.created, false);
  assert.equal((await db.doc('rate_limits/alice').get()).data().reportCount, 1);

  await assert.rejects(
    createModerationReport(db, 'carol', payload, Timestamp.fromMillis(4_000)),
    (error) => error.code === 'not-found',
  );
  await assert.rejects(
    createModerationReport(db, 'bob', payload, Timestamp.fromMillis(4_000)),
    (error) => error.code === 'invalid-argument',
  );
});

const replyTrack = {
  title: 'Daily song', artist: 'Artist', imageUrl: '',
  spotifyUrl: 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
};
function dailyReply(publishedAt, overrides = {}) {
  return parseChatMessagePayload({
    chatId: 'alice_bob', messageId: 'daily_reply_message_01', type: 'daily_song_reply',
    text: ' Great choice! ',
    dailySongReply: { ownerId: 'bob', publishedAtMicros: publishedAt.seconds * 1_000_000 + Math.floor(publishedAt.nanoseconds / 1000) },
    ...overrides,
  });
}

test('daily song reply: stores authoritative context, sends once and uses the chat quota', async () => {
  await seedChat();
  const publishedAt = new Timestamp(100, 123456000);
  await db.doc('users/bob').update({ dailySong: replyTrack, dailySongUpdatedAt: publishedAt });
  const payload = dailyReply(publishedAt);
  await createChatMessage(db, 'alice', payload, Timestamp.fromMillis(101000));
  // A retry of an already accepted message stays idempotent after expiry.
  await createChatMessage(db, 'alice', payload, Timestamp.fromMillis(100000000));
  const message = (await db.doc('chats/alice_bob/messages/daily_reply_message_01').get()).data();
  assert.equal(message.text, 'Great choice!');
  assert.equal(message.dailySongReply.formatVersion, 2);
  assert.equal(message.type, 'text');
  assert.equal(message.dailySongReply.publishedAtMicros, 100123456);
  assert.equal((await db.doc('rate_limits/alice').get()).data().messageCount, 1);
});

test('daily song reply: rejects expired, replaced, missing and wrong-owner publications', async () => {
  await seedChat();
  const publishedAt = Timestamp.fromMillis(100000);
  const payload = dailyReply(publishedAt);
  await assert.rejects(createChatMessage(db, 'alice', payload), { code: 'failed-precondition' });
  await db.doc('users/bob').update({ dailySong: replyTrack, dailySongUpdatedAt: publishedAt });
  await assert.rejects(createChatMessage(db, 'alice', payload, Timestamp.fromMillis(100000 + 86400000)), { code: 'failed-precondition' });
  await assert.rejects(createChatMessage(db, 'alice', { ...payload, dailySongReply: { ...payload.dailySongReply, ownerId: 'alice' } }, publishedAt), { code: 'failed-precondition' });
  await db.doc('users/bob').update({ dailySongUpdatedAt: Timestamp.fromMillis(101000) });
  await assert.rejects(createChatMessage(db, 'alice', payload, Timestamp.fromMillis(102000)), { code: 'failed-precondition' });
  assert.equal((await db.collection('chats/alice_bob/messages').get()).size, 0);
});

test('daily song reply: blocks removed friendships and blocked users', async () => {
  const now = Timestamp.now();
  for (const data of [{ friends: [] }, { friends: ['alice'], blockedUsers: ['alice'] }]) {
    await seedChat();
    await db.doc('users/bob').update({ dailySong: replyTrack, dailySongUpdatedAt: now });
    await db.doc('user_private/bob').update(data);
    await assert.rejects(createChatMessage(db, 'alice', dailyReply(now), now), { code: 'permission-denied' });
  }
});

const { notifyDailySongLike } = require('../lib/daily_song_likes.js');
async function seedDailyLike(now) {
  await seedChat();
  await db.doc('users/bob').update({ dailySong: replyTrack, dailySongUpdatedAt: now });
  await db.doc('user_private/bob').update({ preferredLocale: 'es' });
  await db.doc('users/alice').update({ displayName: 'Alice' });
  await db.doc('users/bob/daily_song_likes/alice').set({ senderId: 'alice', publishedAt: now, createdAt: now });
}

test('daily song likes notify the owner, deduplicate retries and notify a new publication', async () => {
  const now = Timestamp.now();
  await seedDailyLike(now);
  const sent = [];
  const notify = async (...args) => { sent.push(args); };
  assert.equal(await notifyDailySongLike(db, 'bob', 'alice', now, now, notify, now), true);
  assert.equal(await notifyDailySongLike(db, 'bob', 'alice', now, now, notify, now), false);
  assert.equal(sent.length, 1);
  assert.equal(sent[0][0], 'bob');
  assert.equal(sent[0][2].body, 'A Alice le ha gustado tu canción del día');
  assert.equal(sent[0][3].type, 'daily_song_liked');
  const newer = Timestamp.fromMillis(now.toMillis() + 1000);
  await db.doc('users/bob').update({ dailySongUpdatedAt: newer });
  await db.doc('users/bob/daily_song_likes/alice').set({ senderId: 'alice', publishedAt: newer, createdAt: newer }, { merge: true });
  assert.equal(await notifyDailySongLike(db, 'bob', 'alice', now, now, notify, newer), false);
  assert.equal(await notifyDailySongLike(db, 'bob', 'alice', newer, newer, notify, newer), true);
  assert.equal(sent.length, 2);
});

test('daily song likes skip removed, expired, blocked or non-friend likes', async () => {
  const now = Timestamp.now();
  let sends = 0;
  const notify = async () => { sends++; };
  for (const mutate of [
    () => db.doc('users/bob/daily_song_likes/alice').delete(),
    () => db.doc('user_private/bob').update({ blockedUsers: ['alice'] }),
    () => db.doc('user_private/alice').update({ friends: [] }),
    () => db.doc('users/bob').update({ dailySongUpdatedAt: Timestamp.fromMillis(now.toMillis() + 1) }),
    () => db.doc('account_deletions/alice').set({ status: 'requested' }),
  ]) {
    await seedDailyLike(now);
    await mutate();
    assert.equal(await notifyDailySongLike(db, 'bob', 'alice', now, now, notify, now), false);
  }
  await db.doc('account_deletions/alice').delete();
  await seedDailyLike(now);
  assert.equal(await notifyDailySongLike(db, 'bob', 'alice', now, now, notify, Timestamp.fromMillis(now.toMillis() + 86400000)), false);
  assert.equal(sends, 0);
});

test('a failed like notification remains retryable', async () => {
  const now = Timestamp.now();
  await seedDailyLike(now);
  await assert.rejects(notifyDailySongLike(db, 'bob', 'alice', now, now, async () => { throw new Error('FCM unavailable'); }, now), /FCM unavailable/);
  assert.equal((await db.doc('users/bob/daily_song_likes/alice').get()).data().notificationSentFor, undefined);
  assert.equal(await notifyDailySongLike(db, 'bob', 'alice', now, now, async () => {}, now), true);
});
