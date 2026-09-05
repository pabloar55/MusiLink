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
