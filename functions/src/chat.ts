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

export function shouldIncrementUnreadCount(
  chatData: DocumentData,
  recipientId: string,
  messageTime: Timestamp,
): boolean {
  const deletedAt = chatData.deletedAt as Record<string, unknown> | undefined;
  const recipientDeletedAt = timestampValue(deletedAt?.[recipientId]);
  return !recipientDeletedAt || messageTime.toMillis() > recipientDeletedAt.toMillis();
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
  deletedMessageTime: Timestamp | undefined,
): Promise<boolean> {
  const latest = await latestMessageSnapshot(chatRef);
  if (!latest) {
    // Keep the deterministic parent document even when the conversation is
    // empty. Deleting it here would race with a concurrent message creation:
    // Firestore does not delete subcollections atomically with their parent.
    if (!deletedMessageTime) return false;
    await db.runTransaction(async (tx) => {
      const chatSnap = await tx.get(chatRef);
      const chatData = chatSnap.data();
      if (!chatData) return;

      // A newer message may already have refreshed the summary after the
      // empty query. Do not clear that newer state when triggers run late.
      const currentLastMessageTime = timestampValue(chatData.lastMessageTime);
      if (
        currentLastMessageTime &&
        currentLastMessageTime.toMillis() > deletedMessageTime.toMillis()
      ) {
        return;
      }

      const participants = chatParticipants(chatData);
      tx.update(chatRef, {
        lastMessage: '',
        unreadCounts: Object.fromEntries(participants.map((uid) => [uid, 0])),
      });
    });
    return false;
  }

  const latestData = latest.data();
  const latestMessageTime = timestampValue(latestData.timestamp);
  await db.runTransaction(async (tx) => {
    const [chatSnap, latestSnap] = await Promise.all([
      tx.get(chatRef),
      tx.get(latest.ref),
    ]);
    const chatData = chatSnap.data();
    const currentLatestData = latestSnap.data();
    if (!chatData || !currentLatestData) return;

    // If another message has already advanced the summary beyond the message
    // whose deletion caused this refresh, this delayed trigger must not
    // overwrite it with an older value.
    const currentLastMessageTime = timestampValue(chatData.lastMessageTime);
    if (
      deletedMessageTime &&
      currentLastMessageTime &&
      currentLastMessageTime.toMillis() > deletedMessageTime.toMillis()
    ) {
      return;
    }

    tx.update(chatRef, {
      lastMessage: messageSummary(currentLatestData),
      lastMessageTime: latestMessageTime ?? FieldValue.serverTimestamp(),
    });
  });
  return true;
}

export const onNewMessage = onDocumentCreated(
  {
    document: 'chats/{chatId}/messages/{messageId}',
    region: 'europe-southwest1',
    retry: true,
  },
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
        if (!chatData || !currentMessage) {
          return undefined;
        }

        const participants = chatParticipants(chatData);
        if (participants.length !== 2 || !participants.includes(senderId)) return undefined;
        const recipientId = participants.find((uid) => uid !== senderId);
        const messageTime = timestampValue(currentMessage.timestamp);
        if (!recipientId || !messageTime) return undefined;

        if (currentMessage.summaryApplied !== true) {
          const updates: UpdateData<DocumentData> = {};
          const currentLastMessageTime = timestampValue(chatData.lastMessageTime);
          const summary = messageSummary(currentMessage);
          if (
            !currentLastMessageTime ||
            messageTime.toMillis() >= currentLastMessageTime.toMillis()
          ) {
            updates.lastMessage = summary;
            updates.lastMessageTime = messageTime;
          }
          // A delayed trigger must not restore unread messages that the recipient
          // already hid by deleting the conversation.
          if (
            currentMessage.read !== true &&
            shouldIncrementUnreadCount(chatData, recipientId, messageTime)
          ) {
            updates[`unreadCounts.${recipientId}`] = FieldValue.increment(1);
          }

          if (Object.keys(updates).length > 0) tx.update(chatRef, updates);
          tx.update(messageRef, { summaryApplied: true });
        }

        return {
          recipientId,
          shouldSendNotification: currentMessage.notificationSent !== true,
        };
      });
      if (!summaryResult) return;
      const { recipientId, shouldSendNotification } = summaryResult;
      if (!shouldSendNotification) return;

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
      await messageRef.update({ notificationSent: true });
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

      // lastMessageTime is an asynchronously maintained summary and can lag
      // behind the messages collection. Only prune up to the earliest point
      // both participants deleted; messages committed after that boundary are
      // never eligible, even if this trigger runs late or out of order.
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

      const stillExists = await refreshChatSummaryFromLatestMessage(
        chatRef,
        deletedMessageTime,
      );
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
