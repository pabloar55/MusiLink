import {
  DocumentData,
  Firestore,
  Timestamp,
} from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { db } from './firebase';
import { chatParticipants, stringList, timestampValue } from './firestore_values';

const callableOptions = {
  region: 'europe-southwest1',
  enforceAppCheck: true,
} as const;

const deletedUsername = 'deleted_user';
const messageWindowMs = 10 * 1000;
const friendRequestWindowMs = 10 * 60 * 1000;
const maxMessagesPerWindow = 20;
const maxFriendRequestsPerWindow = 20;

interface FixedWindowResult {
  limited: boolean;
  windowStart: Timestamp;
  count: number;
}

interface TrackPayload {
  title: string;
  artist: string;
  imageUrl: string;
  spotifyUrl: string;
}

interface ChatMessagePayload {
  chatId: string;
  messageId: string;
  type: 'text' | 'track';
  text: string;
  trackData?: TrackPayload;
}

function utf8Length(value: string): number {
  return Buffer.byteLength(value, 'utf8');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: string[]): boolean {
  const keys = Object.keys(value);
  return keys.length === expected.length && keys.every((key) => expected.includes(key));
}

function validDocumentId(value: unknown, maxBytes: number): value is string {
  return typeof value === 'string'
    && value.length > 0
    && value !== '.'
    && value !== '..'
    && !value.includes('/')
    && utf8Length(value) <= maxBytes;
}

function parseTrack(value: unknown): TrackPayload {
  if (!isRecord(value)) {
    throw new HttpsError('invalid-argument', 'Valid trackData is required.');
  }
  const allowedKeys = ['artist', 'imageUrl', 'spotifyUrl', 'title'];
  if (
    Object.keys(value).length !== allowedKeys.length
    || !Object.keys(value).every((key) => allowedKeys.includes(key))
  ) {
    throw new HttpsError('invalid-argument', 'Invalid trackData fields.');
  }

  const { title, artist, imageUrl, spotifyUrl } = value;
  const validImage = typeof imageUrl === 'string'
    && utf8Length(imageUrl) <= 2048
    && (
      imageUrl.length === 0
      || /^https:\/\/i[.]scdn[.]co\/image\/[A-Za-z0-9]+$/.test(imageUrl)
    );
  if (
    typeof title !== 'string'
    || title.trim().length === 0
    || utf8Length(title) > 300
    || typeof artist !== 'string'
    || artist.trim().length === 0
    || utf8Length(artist) > 300
    || !validImage
    || typeof spotifyUrl !== 'string'
    || !/^https:\/\/open[.]spotify[.]com\/track\/[A-Za-z0-9]{22}$/.test(spotifyUrl)
  ) {
    throw new HttpsError('invalid-argument', 'Invalid trackData values.');
  }

  return { title, artist, imageUrl, spotifyUrl };
}

export function parseChatMessagePayload(value: unknown): ChatMessagePayload {
  if (!isRecord(value)) {
    throw new HttpsError('invalid-argument', 'Message data is required.');
  }
  if (!validDocumentId(value.chatId, 300)) {
    throw new HttpsError('invalid-argument', 'A valid chatId is required.');
  }
  if (
    typeof value.messageId !== 'string'
    || !/^[A-Za-z0-9_-]{20,64}$/.test(value.messageId)
  ) {
    throw new HttpsError('invalid-argument', 'A valid messageId is required.');
  }

  if (value.type === 'text') {
    if (
      !hasExactKeys(value, ['chatId', 'messageId', 'text', 'type'])
      || typeof value.text !== 'string'
    ) {
      throw new HttpsError('invalid-argument', 'Message text is required.');
    }
    const text = value.text.trim();
    if (text.length === 0 || utf8Length(text) > 2000) {
      throw new HttpsError('invalid-argument', 'Message text is invalid.');
    }
    return {
      chatId: value.chatId,
      messageId: value.messageId,
      type: 'text',
      text,
    };
  }

  if (value.type === 'track') {
    if (!hasExactKeys(value, ['chatId', 'messageId', 'trackData', 'type'])) {
      throw new HttpsError('invalid-argument', 'Invalid track message fields.');
    }
    const trackData = parseTrack(value.trackData);
    const text = `${trackData.title} - ${trackData.artist}`.trim();
    if (utf8Length(text) > 2000) {
      throw new HttpsError('invalid-argument', 'Track message text is invalid.');
    }
    return {
      chatId: value.chatId,
      messageId: value.messageId,
      type: 'track',
      text,
      trackData,
    };
  }

  throw new HttpsError('invalid-argument', 'Message type is invalid.');
}

export function advanceFixedWindow(
  windowStartValue: unknown,
  countValue: unknown,
  now: Timestamp,
  windowMs: number,
  maximum: number,
): FixedWindowResult {
  const windowStart = timestampValue(windowStartValue);
  const count = typeof countValue === 'number'
    && Number.isInteger(countValue)
    && countValue >= 0
    ? countValue
    : 0;
  if (!windowStart || now.toMillis() - windowStart.toMillis() > windowMs) {
    return { limited: false, windowStart: now, count: 1 };
  }
  if (count >= maximum) {
    return { limited: true, windowStart, count };
  }
  return { limited: false, windowStart, count: count + 1 };
}

function isActiveUser(
  publicData: DocumentData | undefined,
  deletionExists: boolean,
): boolean {
  return publicData !== undefined
    && publicData.username !== deletedUsername
    && !deletionExists;
}

function usersCanInteract(
  firstPrivate: DocumentData | undefined,
  firstId: string,
  secondPrivate: DocumentData | undefined,
  secondId: string,
): boolean {
  return firstPrivate !== undefined
    && secondPrivate !== undefined
    && !stringList(firstPrivate.blockedUsers).includes(secondId)
    && !stringList(secondPrivate.blockedUsers).includes(firstId);
}

export async function createFriendRequest(
  firestore: Firestore,
  senderId: string,
  receiverId: string,
  now = Timestamp.now(),
): Promise<boolean> {
  if (!validDocumentId(receiverId, 128) || receiverId === senderId) {
    throw new HttpsError('invalid-argument', 'A valid receiverId is required.');
  }

  const requestRef = firestore.doc(`friend_requests/${senderId}_${receiverId}`);
  const inverseRef = firestore.doc(`friend_requests/${receiverId}_${senderId}`);
  const senderPublicRef = firestore.doc(`users/${senderId}`);
  const receiverPublicRef = firestore.doc(`users/${receiverId}`);
  const senderPrivateRef = firestore.doc(`user_private/${senderId}`);
  const receiverPrivateRef = firestore.doc(`user_private/${receiverId}`);
  const senderDeletionRef = firestore.doc(`account_deletions/${senderId}`);
  const receiverDeletionRef = firestore.doc(`account_deletions/${receiverId}`);
  const limiterRef = firestore.doc(`rate_limits/${senderId}`);

  return firestore.runTransaction(async (tx) => {
    const [
      requestSnap,
      inverseSnap,
      senderPublicSnap,
      receiverPublicSnap,
      senderPrivateSnap,
      receiverPrivateSnap,
      senderDeletionSnap,
      receiverDeletionSnap,
      limiterSnap,
    ] = await Promise.all([
      tx.get(requestRef),
      tx.get(inverseRef),
      tx.get(senderPublicRef),
      tx.get(receiverPublicRef),
      tx.get(senderPrivateRef),
      tx.get(receiverPrivateRef),
      tx.get(senderDeletionRef),
      tx.get(receiverDeletionRef),
      tx.get(limiterRef),
    ]);

    if (
      !isActiveUser(senderPublicSnap.data(), senderDeletionSnap.exists)
      || !senderPrivateSnap.exists
    ) {
      throw new HttpsError('failed-precondition', 'The sender is not active.');
    }
    if (
      !isActiveUser(receiverPublicSnap.data(), receiverDeletionSnap.exists)
      || !receiverPrivateSnap.exists
    ) {
      return false;
    }

    const senderPrivate = senderPrivateSnap.data();
    const receiverPrivate = receiverPrivateSnap.data();
    if (
      !usersCanInteract(senderPrivate, senderId, receiverPrivate, receiverId)
      || stringList(senderPrivate?.friends).includes(receiverId)
      || requestSnap.exists
      || inverseSnap.exists
    ) {
      return false;
    }

    const limiterData = limiterSnap.data();
    const next = advanceFixedWindow(
      limiterData?.friendRequestWindowStart,
      limiterData?.friendRequestCount,
      now,
      friendRequestWindowMs,
      maxFriendRequestsPerWindow,
    );
    if (next.limited) {
      throw new HttpsError('resource-exhausted', 'Friend request rate limit reached.');
    }

    tx.create(requestRef, {
      senderId,
      receiverId,
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    });
    tx.set(limiterRef, {
      lastFriendRequestAt: now,
      friendRequestWindowStart: next.windowStart,
      friendRequestCount: next.count,
    }, { merge: true });
    return true;
  });
}

export async function createChatMessage(
  firestore: Firestore,
  senderId: string,
  payload: ChatMessagePayload,
  now = Timestamp.now(),
): Promise<string> {
  const chatRef = firestore.doc(`chats/${payload.chatId}`);
  const messageRef = chatRef.collection('messages').doc(payload.messageId);
  const limiterRef = firestore.doc(`rate_limits/${senderId}`);

  return firestore.runTransaction(async (tx) => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) {
      throw new HttpsError('not-found', 'Chat not found.');
    }
    const participants = chatParticipants(chatSnap.data());
    if (
      participants.length !== 2
      || new Set(participants).size !== 2
      || !participants.includes(senderId)
    ) {
      throw new HttpsError('permission-denied', 'The sender is not a chat participant.');
    }
    const recipientId = participants.find((uid) => uid !== senderId)!;
    const senderPublicRef = firestore.doc(`users/${senderId}`);
    const recipientPublicRef = firestore.doc(`users/${recipientId}`);
    const senderPrivateRef = firestore.doc(`user_private/${senderId}`);
    const recipientPrivateRef = firestore.doc(`user_private/${recipientId}`);
    const senderDeletionRef = firestore.doc(`account_deletions/${senderId}`);
    const recipientDeletionRef = firestore.doc(`account_deletions/${recipientId}`);

    const [
      messageSnap,
      senderPublicSnap,
      recipientPublicSnap,
      senderPrivateSnap,
      recipientPrivateSnap,
      senderDeletionSnap,
      recipientDeletionSnap,
      limiterSnap,
    ] = await Promise.all([
      tx.get(messageRef),
      tx.get(senderPublicRef),
      tx.get(recipientPublicRef),
      tx.get(senderPrivateRef),
      tx.get(recipientPrivateRef),
      tx.get(senderDeletionRef),
      tx.get(recipientDeletionRef),
      tx.get(limiterRef),
    ]);

    if (
      !isActiveUser(senderPublicSnap.data(), senderDeletionSnap.exists)
      || !isActiveUser(recipientPublicSnap.data(), recipientDeletionSnap.exists)
    ) {
      throw new HttpsError('failed-precondition', 'Both users must be active.');
    }
    const senderPrivate = senderPrivateSnap.data();
    const recipientPrivate = recipientPrivateSnap.data();
    if (
      !usersCanInteract(senderPrivate, senderId, recipientPrivate, recipientId)
      || !stringList(senderPrivate?.friends).includes(recipientId)
      || !stringList(recipientPrivate?.friends).includes(senderId)
    ) {
      throw new HttpsError('permission-denied', 'The users cannot interact in chat.');
    }

    if (messageSnap.exists) {
      if (messageSnap.data()?.senderId !== senderId) {
        throw new HttpsError('already-exists', 'The messageId is already in use.');
      }
      return messageRef.id;
    }

    const limiterData = limiterSnap.data();
    const next = advanceFixedWindow(
      limiterData?.messageWindowStart,
      limiterData?.messageCount,
      now,
      messageWindowMs,
      maxMessagesPerWindow,
    );
    if (next.limited) {
      throw new HttpsError('resource-exhausted', 'Message rate limit reached.');
    }

    tx.create(messageRef, {
      senderId,
      text: payload.text,
      timestamp: now,
      read: false,
      type: payload.type,
      ...(payload.trackData ? { trackData: payload.trackData } : {}),
    });
    tx.set(limiterRef, {
      lastMessageAt: now,
      messageWindowStart: next.windowStart,
      messageCount: next.count,
    }, { merge: true });
    return messageRef.id;
  });
}

export const sendFriendRequest = onCall(callableOptions, async (request) => {
  const senderId = request.auth?.uid;
  if (!senderId) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const data = isRecord(request.data) ? request.data : {};
  const receiverId = data.receiverId;
  if (typeof receiverId !== 'string') {
    throw new HttpsError('invalid-argument', 'A valid receiverId is required.');
  }
  const created = await createFriendRequest(db, senderId, receiverId);
  return { created };
});

export const sendChatMessage = onCall(callableOptions, async (request) => {
  const senderId = request.auth?.uid;
  if (!senderId) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const payload = parseChatMessagePayload(request.data);
  const messageId = await createChatMessage(db, senderId, payload);
  return { messageId };
});
