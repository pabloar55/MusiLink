'use strict';

const assert = require('node:assert/strict');
const { after, before, beforeEach, test } = require('node:test');
const { getApps, deleteApp } = require('firebase-admin/app');
const { Timestamp } = require('firebase-admin/firestore');

const { db } = require('../lib/firebase.js');
const {
  onChatMessageDeleted,
  onChatSoftDeleted,
  onNewMessage,
} = require('../lib/chat.js');

const chatRef = db.doc('chats/alice_bob');
const aliceRef = db.doc('users/alice');

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('FIRESTORE_EMULATOR_HOST is required for this test.');
  }
});

beforeEach(async () => {
  await Promise.all([
    db.recursiveDelete(chatRef),
    aliceRef.delete(),
  ]);
});

after(async () => {
  await Promise.all([
    db.recursiveDelete(chatRef),
    aliceRef.delete(),
  ]);
  await Promise.all(getApps().map((app) => deleteApp(app)));
});

test('reanuda una notificación pendiente sin volver a aplicar el resumen', async () => {
  const messageTime = Timestamp.fromMillis(2_000);
  await chatRef.set({
    participants: ['alice', 'bob'],
    lastMessage: 'mensaje ya resumido',
    lastMessageTime: messageTime,
    unreadCounts: { alice: 0, bob: 1 },
  });
  await aliceRef.set({ displayName: 'Alice' });

  const messageRef = chatRef.collection('messages').doc('pending-notification');
  await messageRef.set({
    senderId: 'alice',
    text: 'mensaje ya resumido',
    timestamp: messageTime,
    summaryApplied: true,
  });

  await onNewMessage.run({
    data: await messageRef.get(),
    params: { chatId: chatRef.id, messageId: messageRef.id },
  });

  const chat = (await chatRef.get()).data();
  const message = (await messageRef.get()).data();
  assert.equal(chat.lastMessage, 'mensaje ya resumido');
  assert.deepEqual(chat.unreadCounts, { alice: 0, bob: 1 });
  assert.equal(message.summaryApplied, true);
  assert.equal(message.notificationSent, true);
});

test('conserva un mensaje nuevo aunque lastMessageTime siga obsoleto', async () => {
  const staleSummaryTime = Timestamp.fromMillis(1_000);
  const aliceDeletedAt = Timestamp.fromMillis(2_000);
  const newMessageTime = Timestamp.fromMillis(3_000);
  const bobDeletedAt = Timestamp.fromMillis(4_000);
  const chatData = {
    participants: ['alice', 'bob'],
    lastMessage: 'mensaje antiguo',
    lastMessageTime: staleSummaryTime,
    deletedAt: {
      alice: aliceDeletedAt,
      bob: bobDeletedAt,
    },
  };

  await chatRef.set(chatData);
  await chatRef.collection('messages').doc('old').set({
    senderId: 'bob',
    text: 'mensaje antiguo',
    timestamp: staleSummaryTime,
  });
  await chatRef.collection('messages').doc('new').set({
    senderId: 'bob',
    text: 'mensaje que llegó durante la carrera',
    timestamp: newMessageTime,
  });

  const chatSnapshot = await chatRef.get();
  await onChatSoftDeleted.run({
    data: { after: chatSnapshot },
    params: { chatId: chatRef.id },
  });

  assert.equal((await chatRef.get()).exists, true);
  assert.equal((await chatRef.collection('messages').doc('old').get()).exists, false);
  assert.equal((await chatRef.collection('messages').doc('new').get()).exists, true);
});

test('mantiene el documento padre cuando ya no quedan mensajes', async () => {
  const deletedAt = Timestamp.fromMillis(2_000);
  const chatData = {
    participants: ['alice', 'bob'],
    lastMessage: 'mensaje antiguo',
    lastMessageTime: Timestamp.fromMillis(1_000),
    deletedAt: { alice: deletedAt, bob: deletedAt },
  };

  await chatRef.set(chatData);
  await chatRef.collection('messages').doc('old').set({
    senderId: 'alice',
    text: 'mensaje antiguo',
    timestamp: Timestamp.fromMillis(1_000),
  });

  const oldMessageRef = chatRef.collection('messages').doc('old');
  const deletedMessageSnapshot = await oldMessageRef.get();
  await oldMessageRef.delete();
  await onChatMessageDeleted.run({
    data: deletedMessageSnapshot,
    params: { chatId: chatRef.id, messageId: oldMessageRef.id },
  });

  assert.equal((await chatRef.get()).exists, true);
  assert.equal((await chatRef.collection('messages').get()).empty, true);
  const retainedChat = (await chatRef.get()).data();
  assert.equal(retainedChat.lastMessage, '');
  assert.deepEqual(retainedChat.unreadCounts, { alice: 0, bob: 0 });
});

test('push delivery capability is message-specific, idempotent and does not mark read', async () => {
  const { createDeliveryToken, confirmPushDelivery } = require('../lib/chat_delivery.js');
  await chatRef.set({ participants: ['alice', 'bob'], unreadCounts: { alice: 0, bob: 1 } });
  const ref = chatRef.collection('messages').doc('delivered-message');
  await ref.set({ senderId: 'alice', read: false, delivered: false });
  const token = await createDeliveryToken(ref);
  const payload = { chatId: chatRef.id, messageId: ref.id, deliveryToken: token };
  const persisted = (await ref.get()).data();
  assert.equal(JSON.stringify(persisted).includes(token), false);
  assert.equal(await confirmPushDelivery({ ...payload, deliveryToken: '0'.repeat(64) }), false);
  assert.equal(await confirmPushDelivery({ ...payload, messageId: 'other' }), false);
  assert.equal(await confirmPushDelivery({ ...payload, chatId: 'other' }), false);
  assert.equal((await ref.get()).data().delivered, false);
  // A trigger retry keeps the earlier notification's capability valid.
  const secondToken = await createDeliveryToken(ref);
  assert.equal(await confirmPushDelivery(payload), true);
  assert.equal(await confirmPushDelivery(payload), true);
  assert.equal(await confirmPushDelivery({ ...payload, deliveryToken: secondToken }), true);
  const received = (await ref.get()).data();
  assert.equal(received.delivered, true);
  assert.equal(received.read, false);
  assert.deepEqual((await chatRef.get()).data().unreadCounts, { alice: 0, bob: 1 });
  await ref.delete();
  assert.equal(await confirmPushDelivery(payload), false);
});

test('un trigger tardío no cuenta ni notifica mensajes anteriores al alta de un miembro', async () => {
  const groupRef = db.doc('chats/GroupChat00000000001');
  const privateRefs = ['bob', 'dave'].map((uid) => db.doc(`user_private/${uid}`));
  try {
    await aliceRef.set({ displayName: 'Alice' });
    await Promise.all(privateRefs.map((ref) => ref.set({})));
    // Dave se incorporó en 3000; los mensajes son de antes y de después.
    await groupRef.set({
      type: 'group',
      name: 'Grupo',
      participants: ['alice', 'bob', 'dave'],
      lastMessage: '',
      lastMessageTime: Timestamp.fromMillis(1_000),
      unreadCounts: { alice: 0, bob: 0, dave: 0 },
      lastReadAt: { dave: Timestamp.fromMillis(3_000) },
    });
    const run = async (id, millis) => {
      const ref = groupRef.collection('messages').doc(id);
      await ref.set({ senderId: 'alice', text: id, timestamp: Timestamp.fromMillis(millis) });
      await onNewMessage.run({
        data: await ref.get(),
        params: { chatId: groupRef.id, messageId: id },
      });
      return (await ref.get()).data();
    };

    const earlier = await run('before-joining', 2_000);
    assert.deepEqual((await groupRef.get()).data().unreadCounts, { alice: 0, bob: 1, dave: 0 });
    assert.deepEqual(earlier.notifiedRecipients, ['bob']);

    const later = await run('after-joining', 4_000);
    assert.deepEqual((await groupRef.get()).data().unreadCounts, { alice: 0, bob: 2, dave: 1 });
    assert.deepEqual(later.notifiedRecipients, ['bob', 'dave']);
  } finally {
    await Promise.all([
      db.recursiveDelete(groupRef),
      ...privateRefs.map((ref) => ref.delete()),
    ]);
  }
});
