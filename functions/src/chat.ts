import {
  DocumentData,
  DocumentReference,
  FieldValue,
  QueryDocumentSnapshot,
  Timestamp,
  UpdateData,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from 'firebase-functions/v2/firestore';

import { db } from './firebase';
import { chatParticipants, timestampValue } from './firestore_values';
import { sendNotification } from './notifications';

const userPrivateCollection = 'user_private';
const chatsCollection = 'chats';
const messagesCollection = 'messages';
const chatCleanupBatchSize = 400;

export function messageSummary(data: DocumentData): string {
  if (data.type === 'track') {
    const title = data.trackData?.title;
    if (typeof title === 'string' && title.length > 0) return `🎵 ${title}`;
  }
  return typeof data.text === 'string' ? data.text : '';
}

export function fullySoftDeletedChat(data: DocumentData | undefined): boolean {
  const participants = chatParticipants(data);
  if (participants.length !== 2) return false;

  const lastMessageTime = timestampValue(data?.lastMessageTime);
  const deletedAt = data?.deletedAt as Record<string, unknown> | undefined;
  if (!lastMessageTime || !deletedAt) return false;

  return participants.every((uid) => {
    const deletedTime = timestampValue(deletedAt[uid]);
    return deletedTime !== undefined &&
      lastMessageTime.toMillis() <= deletedTime.toMillis();
  });
}

export function allParticipantsDeletedBefore(
  data: DocumentData | undefined,
): Timestamp | undefined {
  const participants = chatParticipants(data);
  if (participants.length !== 2) return undefined;

  const deletedAt = data?.deletedAt as Record<string, unknown> | undefined;
  if (!deletedAt) return undefined;

  const deletedTimes = participants
    .map((uid) => timestampValue(deletedAt[uid]))
    .filter((value): value is Timestamp => value !== undefined);
  if (deletedTimes.length !== participants.length) return undefined;

  return deletedTimes.reduce((earliest, value) =>
    value.toMillis() < earliest.toMillis() ? value : earliest,
  deletedTimes[0]);
}

async function deleteChatMessages(chatRef: DocumentReference): Promise<void> {
  const messagesRef = chatRef.collection(messagesCollection);
  while (true) {
    const snapshot = await messagesRef.limit(chatCleanupBatchSize).get();
    if (snapshot.empty) return;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    if (snapshot.size < chatCleanupBatchSize) return;
  }
}

async function hardDeleteChat(chatRef: DocumentReference): Promise<void> {
  await deleteChatMessages(chatRef);
  await chatRef.delete();
}

async function pruneMessagesDeletedForAllParticipants(
  chatRef: DocumentReference,
  chatData: DocumentData | undefined,
): Promise<number> {
  const pruneBefore = allParticipantsDeletedBefore(chatData);
  if (!pruneBefore) return 0;

  const messagesRef = chatRef.collection(messagesCollection);
  let deletedCount = 0;
  while (true) {
    const snapshot = await messagesRef
      .where('timestamp', '<=', pruneBefore)
      .orderBy('timestamp')
      .limit(chatCleanupBatchSize)
      .get();
    if (snapshot.empty) return deletedCount;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deletedCount += snapshot.size;
    if (snapshot.size < chatCleanupBatchSize) return deletedCount;
  }
}

async function latestMessageSnapshot(
  chatRef: DocumentReference,
): Promise<QueryDocumentSnapshot | undefined> {
  const snapshot = await chatRef
    .collection(messagesCollection)
    .orderBy('timestamp', 'desc')
    .limit(1)
    .get();
  return snapshot.docs[0];
}

async function refreshChatSummaryFromLatestMessage(
  chatRef: DocumentReference,
): Promise<boolean> {
  const latest = await latestMessageSnapshot(chatRef);
  if (!latest) {
    await chatRef.delete();
    return false;
  }

  const latestData = latest.data();
  await chatRef.update({
    lastMessage: messageSummary(latestData),
    lastMessageTime: timestampValue(latestData.timestamp) ?? FieldValue.serverTimestamp(),
  });
  return true;
}

export const onNewMessage = onDocumentCreated(
  { document: 'chats/{chatId}/messages/{messageId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const messageSnapshot = event.data;
      if (!messageSnapshot) return;
      const message = messageSnapshot.data();
      if (!message) return;

      const chatId = event.params.chatId;
      const senderId = message.senderId as string;
      const chatRef = db.doc(`chats/${chatId}`);
      const messageRef = messageSnapshot.ref;

      const summaryResult = await db.runTransaction(async (tx) => {
        const [chatSnap, currentMessageSnap] = await Promise.all([
          tx.get(chatRef),
          tx.get(messageRef),
        ]);
        const chatData = chatSnap.data();
        const currentMessage = currentMessageSnap.data();
        if (!chatData || !currentMessage || currentMessage.summaryApplied === true) {
          return undefined;
        }

        const participants = chatParticipants(chatData);
        if (participants.length !== 2 || !participants.includes(senderId)) return undefined;
        const recipientId = participants.find((uid) => uid !== senderId);
        const messageTime = timestampValue(currentMessage.timestamp);
        if (!recipientId || !messageTime) return undefined;

        const updates: UpdateData<DocumentData> = {};
        const currentLastMessageTime = timestampValue(chatData.lastMessageTime);
        const summary = messageSummary(currentMessage);
        if (!currentLastMessageTime || messageTime.toMillis() >= currentLastMessageTime.toMillis()) {
          updates.lastMessage = summary;
          updates.lastMessageTime = messageTime;
        }
        if (currentMessage.read !== true) {
          updates[`unreadCounts.${recipientId}`] = FieldValue.increment(1);
        }

        if (Object.keys(updates).length > 0) tx.update(chatRef, updates);
        tx.update(messageRef, { summaryApplied: true });
        return { recipientId };
      });
      if (!summaryResult) return;
      const { recipientId } = summaryResult;

      const [recipientSnap, senderSnap] = await Promise.all([
        db.doc(`${userPrivateCollection}/${recipientId}`).get(),
        db.doc(`users/${senderId}`).get(),
      ]);
      const senderName = senderSnap.data()?.displayName as string | undefined;
      const senderPhotoUrl = senderSnap.data()?.photoUrl as string | undefined;
      if (!senderName) return;

      await sendNotification(
        recipientId,
        recipientSnap.data(),
        { title: senderName, body: (message.text as string | undefined) ?? '📎' },
        {
          type: 'new_message',
          chatId,
          otherUserId: senderId,
          otherUserName: senderName,
          messageText: (message.text as string | undefined) ?? '📎',
          ...(senderPhotoUrl ? { senderPhotoUrl } : {}),
        },
        chatId,
      );
    } catch (error) {
      logger.error('onNewMessage: unhandled error', {
        chatId: event.params.chatId,
        error,
      });
      throw error;
    }
  },
);

export const onChatSoftDeleted = onDocumentUpdated(
  { document: `${chatsCollection}/{chatId}`, region: 'europe-southwest1' },
  async (event) => {
    try {
      const after = event.data?.after.data();
      if (!after) return;
      if (fullySoftDeletedChat(after)) {
        await hardDeleteChat(event.data!.after.ref);
        logger.info('onChatSoftDeleted: hard-deleted fully soft-deleted chat', {
          chatId: event.params.chatId,
        });
        return;
      }

      const prunedMessages = await pruneMessagesDeletedForAllParticipants(
        event.data!.after.ref,
        after,
      );
      if (prunedMessages > 0) {
        logger.info('onChatSoftDeleted: pruned messages hidden for all participants', {
          chatId: event.params.chatId,
          prunedMessages,
        });
      }
    } catch (error) {
      logger.error('onChatSoftDeleted: unhandled error', {
        chatId: event.params.chatId,
        error,
      });
      throw error;
    }
  },
);

export const onChatMessageDeleted = onDocumentDeleted(
  {
    document: `${chatsCollection}/{chatId}/${messagesCollection}/{messageId}`,
    region: 'europe-southwest1',
  },
  async (event) => {
    try {
      const deletedMessage = event.data?.data();
      if (!deletedMessage) return;

      const chatRef = db.doc(`${chatsCollection}/${event.params.chatId}`);
      const chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;

      const currentLastMessageTime = timestampValue(chatSnap.data()?.lastMessageTime);
      const deletedMessageTime = timestampValue(deletedMessage.timestamp);
      if (
        currentLastMessageTime &&
        deletedMessageTime &&
        deletedMessageTime.toMillis() < currentLastMessageTime.toMillis()
      ) {
        return;
      }

      const stillExists = await refreshChatSummaryFromLatestMessage(chatRef);
      logger.info('onChatMessageDeleted: refreshed chat after message delete', {
        chatId: event.params.chatId,
        messageId: event.params.messageId,
        stillExists,
      });
    } catch (error) {
      logger.error('onChatMessageDeleted: unhandled error', {
        chatId: event.params.chatId,
        messageId: event.params.messageId,
        error,
      });
      throw error;
    }
  },
);
