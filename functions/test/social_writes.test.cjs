'use strict';

const assert = require('node:assert/strict');
const { after, before, beforeEach, test } = require('node:test');
const { getApps, deleteApp } = require('firebase-admin/app');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

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
const {
  cleanUpDeparture,
  deleteGroupContents,
  leaveGroup,
} = require('../lib/group_chats.js');

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

const { friendDigestOffsets, sendFriendDigests } = require('../lib/friend_digest.js');
const digestSlot = new Date('2026-10-01T19:00:00Z'); // 21:00 at UTC+02:00
const beforeDigestSlot = (minutes) => Timestamp.fromMillis(digestSlot.getTime() - minutes * 60000);
async function seedFriendDigest() {
  await Promise.all([
    seedUser('alice', ['bob', 'carol', 'dave']),
    seedUser('bob', ['alice']),
    seedUser('carol', ['alice']),
    seedUser('dave', ['alice']),
  ]);
  await Promise.all([
    db.doc('user_private/alice').update({ utcOffsetMinutes: 120, preferredLocale: 'es' }),
    db.doc('users/bob').update({ displayName: 'Bob', dailySong: replyTrack, dailySongUpdatedAt: beforeDigestSlot(120) }),
    db.doc('users/carol').update({ displayName: 'Carol', dailySong: replyTrack, dailySongUpdatedAt: beforeDigestSlot(30) }),
  ]);
}

test('the friend digest is sent quietly once per local day at 21:00', async () => {
  await seedFriendDigest();
  const sent = [];
  const notify = async (...args) => { sent.push(args); };
  assert.deepEqual(await sendFriendDigests(db, digestSlot, notify), { candidates: 1, sent: 1 });
  assert.equal(sent[0][0], 'alice');
  assert.equal(sent[0][2].body, 'Carol y Bob han publicado su canción del día. ¡Publica la tuya!');
  assert.deepEqual(sent[0].slice(3), [{ type: 'friend_digest' }, 'friend_digest', { quiet: true }]);
  assert.deepEqual(await sendFriendDigests(db, digestSlot, notify), { candidates: 1, sent: 0 });

  const nextDay = new Date(digestSlot.getTime() + 86400000);
  const republished = Timestamp.fromMillis(nextDay.getTime() - 3600000);
  await Promise.all(['bob', 'carol'].map((uid) => db.doc(`users/${uid}`).update({ dailySongUpdatedAt: republished })));
  assert.deepEqual(await sendFriendDigests(db, nextDay, notify), { candidates: 1, sent: 1 });
  assert.equal(sent.length, 2);
});

test('the friend digest names a single friend in the singular', async () => {
  await seedFriendDigest();
  await db.doc('user_private/alice').update({ blockedUsers: ['carol'] });
  const sent = [];
  await sendFriendDigests(db, digestSlot, async (...args) => { sent.push(args); });
  assert.equal(sent.length, 1);
  assert.equal(sent[0][2].body, 'Bob ha publicado su canción del día. ¡Publica la tuya!');
});

test('the friend digest skips users who should not be reminded', async () => {
  let sends = 0;
  const notify = async () => { sends++; };
  for (const mutate of [
    () => db.doc('user_private/alice').update({ notifFriendDigest: false }),
    () => db.doc('users/alice').update({ dailySong: replyTrack, dailySongUpdatedAt: beforeDigestSlot(60) }),
    // A song past its lifetime is still waiting for its own expiry reminder.
    () => db.doc('users/alice').update({ dailySong: replyTrack, dailySongUpdatedAt: beforeDigestSlot(25 * 60) }),
    () => Promise.all(['bob', 'carol'].map((uid) => db.doc(`users/${uid}`).update({ dailySongUpdatedAt: beforeDigestSlot(25 * 60) }))),
    () => db.doc('user_private/alice').update({ blockedUsers: ['bob', 'carol'] }),
    () => db.doc('user_private/alice').update({ utcOffsetMinutes: 60 }),
    () => db.doc('account_deletions/alice').set({ status: 'requested' }),
    // The song expiry reminder was already sent earlier today.
    () => db.doc('user_private/alice').update({ engagementPushAt: beforeDigestSlot(180) }),
  ]) {
    await clearFirestore();
    await seedFriendDigest();
    await mutate();
    assert.equal((await sendFriendDigests(db, digestSlot, notify)).sent, 0);
  }
  assert.equal(sends, 0);
});

test('a failed friend digest neither blocks other recipients nor repeats', async () => {
  await seedFriendDigest();
  await seedUser('erin', ['bob', 'carol']);
  await db.doc('user_private/erin').update({ utcOffsetMinutes: 120 });
  const delivered = [];
  const notify = async (uid) => {
    if (uid === 'alice') throw new Error('FCM unavailable');
    delivered.push(uid);
  };
  assert.deepEqual(await sendFriendDigests(db, digestSlot, notify), { candidates: 2, sent: 1 });
  assert.deepEqual(await sendFriendDigests(db, digestSlot, notify), { candidates: 2, sent: 0 });
  assert.deepEqual(delivered, ['erin']);
});

const { expireDailySong, notifyDailySongExpired } = require('../lib/daily_song.js');
test('the expiry reminder counts friends who have published', async () => {
  await seedFriendDigest();
  const activeAfter = digestSlot.getTime() - 86400000;
  const bodies = [];
  const notify = async (uid, privateData, notification) => { bodies.push(notification.body); };

  await notifyDailySongExpired(db, 'alice', activeAfter, new Map(), notify);
  await db.doc('user_private/alice').update({ blockedUsers: ['carol'] });
  await notifyDailySongExpired(db, 'alice', activeAfter, new Map(), notify);
  // Nobody among Dave's friends has an active song.
  await db.doc('user_private/dave').update({ preferredLocale: 'es' });
  await notifyDailySongExpired(db, 'dave', activeAfter, new Map(), notify);

  assert.deepEqual(bodies, [
    'Tu canción del día ha caducado y 2 amigos ya han publicado la suya. ¡Publica una nueva!',
    'Tu canción del día ha caducado y un amigo ya ha publicado la suya. ¡Publica una nueva!',
    '¡Tu canción del día ha caducado! Publica una nueva.',
  ]);
});

test('expiring a song claims the daily reminder so the digest cannot follow it', async () => {
  const now = new Date();
  const hoursAgo = (hours) => Timestamp.fromMillis(now.getTime() - hours * 3600000);
  await seedFriendDigest();
  await Promise.all([
    db.doc('user_private/alice').update({ utcOffsetMinutes: friendDigestOffsets(now)[0] }),
    db.doc('users/alice').update({ dailySong: replyTrack, dailySongUpdatedAt: hoursAgo(25) }),
    ...['bob', 'carol'].map((uid) => db.doc(`users/${uid}`).update({ dailySongUpdatedAt: hoursAgo(1) })),
  ]);
  let sends = 0;
  const notify = async () => { sends++; };

  assert.equal(await expireDailySong(db.doc('users/alice'), hoursAgo(24)), true);
  assert.equal((await db.doc('users/alice').get()).data().dailySong, undefined);
  assert.ok((await db.doc('user_private/alice').get()).data().engagementPushAt instanceof Timestamp);
  assert.equal((await sendFriendDigests(db, now, notify)).sent, 0);
  assert.equal(sends, 0);

  // Without the claim the same user would receive the digest.
  await db.doc('user_private/alice').update({ engagementPushAt: FieldValue.delete() });
  assert.equal((await sendFriendDigests(db, now, notify)).sent, 1);
});

async function seedGroup(chatId, participants, messageCount = 1) {
  const members = Object.fromEntries(participants.map((uid) => [uid, 0]));
  await db.doc(`chats/${chatId}`).set({
    type: 'group',
    name: 'Grupo',
    createdBy: participants[0],
    participants,
    createdAt: Timestamp.fromMillis(1),
    lastMessage: 'hola',
    lastMessageTime: Timestamp.fromMillis(2),
    unreadCounts: members,
    deletedAt: Object.fromEntries(participants.map((uid) => [uid, Timestamp.fromMillis(1)])),
    lastReadAt: Object.fromEntries(participants.map((uid) => [uid, Timestamp.fromMillis(1)])),
  });
  for (let index = 1; index <= messageCount; index += 1) {
    await db.doc(`chats/${chatId}/messages/message-${index}`).set({
      senderId: participants[0],
      text: 'hola',
      timestamp: Timestamp.fromMillis(2),
      groupMessage: true,
      reactions: { '❤️': participants, '🔥': [participants[0]] },
    });
  }
}

async function groupReactions(chatId, messageId = 'message-1') {
  return (await db.doc(`chats/${chatId}/messages/${messageId}`).get()).data().reactions;
}

test('leaveGroupChat retira al miembro y deja registrada la limpieza de sus reacciones', async () => {
  const chatId = 'GroupChat00000000001';
  const otherChatId = 'GroupChat00000000002';
  const departure = db.doc(`chats/${chatId}/departures/alice`);
  await seedGroup(chatId, ['alice', 'bob', 'carol']);
  await seedGroup(otherChatId, ['alice', 'bob', 'carol']);

  await leaveGroup(db, chatId, 'alice');

  const chat = (await db.doc(`chats/${chatId}`).get()).data();
  assert.deepEqual(chat.participants, ['bob', 'carol']);
  for (const field of ['unreadCounts', 'deletedAt', 'lastReadAt']) {
    assert.deepEqual(Object.keys(chat[field]).sort(), ['bob', 'carol']);
  }
  // La limpieza queda pendiente en el mismo commit que retira al miembro.
  assert.equal((await departure.get()).exists, true);

  await cleanUpDeparture(db, chatId, 'alice');
  assert.deepEqual(await groupReactions(chatId), { '❤️': ['bob', 'carol'] });
  assert.equal((await departure.get()).exists, false);
  assert.deepEqual(
    await groupReactions(otherChatId),
    { '❤️': ['alice', 'bob', 'carol'], '🔥': ['alice'] },
  );
  assert.deepEqual(
    (await db.doc(`chats/${otherChatId}`).get()).data().participants,
    ['alice', 'bob', 'carol'],
  );

  // Un reintento, o una llamada de quien no es miembro, no altera el grupo
  // ni registra limpiezas; repetir el trigger tampoco.
  await leaveGroup(db, chatId, 'alice');
  await leaveGroup(db, chatId, 'mallory');
  await cleanUpDeparture(db, chatId, 'alice');
  assert.deepEqual(
    (await db.doc(`chats/${chatId}`).get()).data().participants,
    ['bob', 'carol'],
  );
  assert.equal((await db.collection(`chats/${chatId}/departures`).get()).empty, true);
  assert.deepEqual(await groupReactions(chatId), { '❤️': ['bob', 'carol'] });
});

test('las salidas simultáneas no restauran las reacciones que limpia la otra', async () => {
  const chatId = 'GroupChat00000000001';
  const messageCount = 12;
  await seedGroup(chatId, ['alice', 'bob', 'carol'], messageCount);

  await Promise.all([leaveGroup(db, chatId, 'alice'), leaveGroup(db, chatId, 'bob')]);
  await Promise.all([
    cleanUpDeparture(db, chatId, 'alice'),
    cleanUpDeparture(db, chatId, 'bob'),
  ]);

  assert.deepEqual((await db.doc(`chats/${chatId}`).get()).data().participants, ['carol']);
  for (let index = 1; index <= messageCount; index += 1) {
    assert.deepEqual(await groupReactions(chatId, `message-${index}`), { '❤️': ['carol'] });
  }
});

test('leaveGroupChat elimina el grupo cuando sale el último miembro y su limpieza borra el resto', async () => {
  const chatId = 'GroupChat00000000001';
  await seedGroup(chatId, ['alice', 'bob']);

  // Los últimos miembros pueden salir a la vez: solo uno elimina el grupo.
  await Promise.all([leaveGroup(db, chatId, 'alice'), leaveGroup(db, chatId, 'bob')]);
  assert.equal((await db.doc(`chats/${chatId}`).get()).exists, false);
  assert.equal((await db.collection(`chats/${chatId}/departures`).get()).size, 1);

  await deleteGroupContents(db, chatId);
  assert.equal((await db.collection(`chats/${chatId}/messages`).get()).empty, true);
  assert.equal((await db.collection(`chats/${chatId}/departures`).get()).empty, true);

  // Reintentos tardíos sobre un grupo ya eliminado.
  await leaveGroup(db, chatId, 'bob');
  await cleanUpDeparture(db, chatId, 'alice');
  assert.equal((await db.doc(`chats/${chatId}`).get()).exists, false);
});

test('leaveGroupChat no modifica los chats individuales', async () => {
  await db.doc('chats/DirectChat0000000001').set({ participants: ['alice', 'bob'] });

  await assert.rejects(
    leaveGroup(db, 'DirectChat0000000001', 'alice'),
    { code: 'failed-precondition' },
  );
  assert.deepEqual(
    (await db.doc('chats/DirectChat0000000001').get()).data().participants,
    ['alice', 'bob'],
  );
});
