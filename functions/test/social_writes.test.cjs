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
  advanceFixedWindow,
  createChatMessage,
  createFriendRequest,
  parseChatMessagePayload,
} = require('../lib/social_writes.js');

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
