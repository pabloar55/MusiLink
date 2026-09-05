import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { db } from './firebase';
import { stringList } from './firestore_values';
import {
  notificationText,
  preferredLocale,
  sendNotification,
} from './notifications';

const userPrivateCollection = 'user_private';
const friendRequestNotificationLimitsCollection =
  'friend_request_notification_limits';
const friendRequestNotificationCooldownMs = 60 * 60 * 1000;

interface AcceptedFriendship {
  senderId: string;
  receiverId: string;
}

export function userHasBlocked(data: unknown, otherUid: string): boolean {
  const blockedUsers = (data as { blockedUsers?: unknown } | undefined)?.blockedUsers;
  return stringList(blockedUsers).includes(otherUid);
}

export function friendRequestNotificationIsCoolingDown(
  lastNotifiedAt: unknown,
  now: Timestamp,
): boolean {
  if (!(lastNotifiedAt instanceof Timestamp)) return false;
  return now.toMillis() - lastNotifiedAt.toMillis()
    < friendRequestNotificationCooldownMs;
}

async function shouldNotifyFriendRequest(
  senderId: string,
  receiverId: string,
): Promise<boolean> {
  const limitRef = db
    .collection(friendRequestNotificationLimitsCollection)
    .doc(`${senderId}_${receiverId}`);

  return db.runTransaction(async (tx) => {
    const limitSnap = await tx.get(limitRef);
    const lastNotifiedAt = limitSnap.data()?.lastNotifiedAt as Timestamp | undefined;
    const now = Timestamp.now();

    if (friendRequestNotificationIsCoolingDown(lastNotifiedAt, now)) {
      return false;
    }

    tx.set(limitRef, { senderId, receiverId, lastNotifiedAt: now }, { merge: true });
    return true;
  });
}

export async function establishAcceptedFriendship(
  requestId: string,
  expectedReceiverId?: string,
  expectedSenderId?: string,
  expectedUpdateTime?: Timestamp,
): Promise<AcceptedFriendship> {
  const requestRef = db.collection('friend_requests').doc(requestId);

  return db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists) {
      throw new HttpsError('not-found', 'Friend request not found.');
    }
    if (
      expectedUpdateTime !== undefined
      && requestSnap.updateTime?.isEqual(expectedUpdateTime) !== true
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Friend request version no longer matches the accepted event.',
      );
    }

    const requestData = requestSnap.data();
    const senderId = requestData?.senderId;
    const receiverId = requestData?.receiverId;
    const status = requestData?.status;
    if (
      typeof senderId !== 'string' ||
      typeof receiverId !== 'string' ||
      senderId === receiverId ||
      (status !== 'pending' && status !== 'accepted')
    ) {
      throw new HttpsError('failed-precondition', 'Invalid friend request.');
    }
    if (expectedReceiverId !== undefined && receiverId !== expectedReceiverId) {
      throw new HttpsError('permission-denied', 'Only the receiver can accept this request.');
    }
    if (expectedSenderId !== undefined && senderId !== expectedSenderId) {
      throw new HttpsError('failed-precondition', 'Unexpected friend request sender.');
    }

    const senderPrivateRef = db.doc(`${userPrivateCollection}/${senderId}`);
    const receiverPrivateRef = db.doc(`${userPrivateCollection}/${receiverId}`);
    const senderPublicRef = db.doc(`users/${senderId}`);
    const receiverPublicRef = db.doc(`users/${receiverId}`);
    const inverseRef = db.collection('friend_requests').doc(`${receiverId}_${senderId}`);
    const [senderPrivate, receiverPrivate, senderPublic, receiverPublic, inverse] =
      await Promise.all([
        tx.get(senderPrivateRef),
        tx.get(receiverPrivateRef),
        tx.get(senderPublicRef),
        tx.get(receiverPublicRef),
        tx.get(inverseRef),
      ]);

    if (
      !senderPrivate.exists ||
      !receiverPrivate.exists ||
      !senderPublic.exists ||
      !receiverPublic.exists ||
      senderPublic.data()?.username === 'deleted_user' ||
      receiverPublic.data()?.username === 'deleted_user'
    ) {
      throw new HttpsError('failed-precondition', 'Both users must be active.');
    }
    if (
      userHasBlocked(senderPrivate.data(), receiverId) ||
      userHasBlocked(receiverPrivate.data(), senderId)
    ) {
      throw new HttpsError('failed-precondition', 'Blocked users cannot become friends.');
    }

    tx.update(senderPrivateRef, { friends: FieldValue.arrayUnion(receiverId) });
    tx.update(receiverPrivateRef, { friends: FieldValue.arrayUnion(senderId) });
    if (status === 'pending') {
      tx.update(requestRef, {
        status: 'accepted',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (inverse.exists && inverseRef.path !== requestRef.path) tx.delete(inverseRef);

    return { senderId, receiverId };
  });
}

export async function deleteFriendRequestVersion(
  requestId: string,
  expectedUpdateTime: Timestamp,
): Promise<void> {
  const requestRef = db.collection('friend_requests').doc(requestId);
  await db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    if (
      requestSnap.exists
      && requestSnap.updateTime?.isEqual(expectedUpdateTime) === true
    ) {
      tx.delete(requestRef);
    }
  });
}

export const acceptFriendRequest = onCall(
  { region: 'europe-southwest1', enforceAppCheck: true },
  async (request) => {
    const receiverId = request.auth?.uid;
    if (!receiverId) {
      throw new HttpsError('unauthenticated', 'Authentication is required.');
    }

    const data = request.data as { requestId?: unknown; senderId?: unknown } | null;
    const requestId = data?.requestId;
    const senderId = data?.senderId;
    if (
      typeof requestId !== 'string' || requestId.length === 0 || requestId.length > 300 ||
      typeof senderId !== 'string' || senderId.length === 0 || senderId.length > 128
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Valid requestId and senderId values are required.',
      );
    }

    await establishAcceptedFriendship(requestId, receiverId, senderId);
    return { ok: true };
  },
);

export const onFriendRequest = onDocumentCreated(
  { document: 'friend_requests/{requestId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const request = event.data?.data();
      if (!request || request.status !== 'pending') return;

      const senderId = request.senderId as string;
      const receiverId = request.receiverId as string;
      if (!await shouldNotifyFriendRequest(senderId, receiverId)) return;

      const [receiverSnap, senderSnap] = await Promise.all([
        db.doc(`${userPrivateCollection}/${receiverId}`).get(),
        db.doc(`users/${senderId}`).get(),
      ]);
      const receiver = receiverSnap.data();
      const senderName = senderSnap.data()?.displayName as string | undefined;
      if (!senderName) return;
      const locale = preferredLocale(receiver);

      await sendNotification(
        receiverId,
        receiver,
        { title: 'MusiLink', body: notificationText.friendRequest[locale](senderName) },
        { type: 'friend_request', senderId },
        `friend_request_${senderId}`,
      );
    } catch (error) {
      logger.error('onFriendRequest: unhandled error', {
        requestId: event.params.requestId,
        error,
      });
      throw error;
    }
  },
);

export const onFriendRequestAccepted = onDocumentUpdated(
  { document: 'friend_requests/{requestId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const change = event.data;
      if (!change) return;
      const before = change.before.data();
      const after = change.after.data();
      if (!before || !after) return;
      if (before.status !== 'pending' || after.status !== 'accepted') return;
      const acceptedUpdateTime = change.after.updateTime;

      const senderId = after.senderId as string;
      const receiverId = after.receiverId as string;
      try {
        await establishAcceptedFriendship(
          event.params.requestId,
          receiverId,
          undefined,
          acceptedUpdateTime,
        );
      } catch (error) {
        if (!(error instanceof HttpsError)) throw error;
        logger.warn('onFriendRequestAccepted: friendship rejected', {
          requestId: event.params.requestId,
          error,
        });
        await deleteFriendRequestVersion(
          event.params.requestId,
          acceptedUpdateTime,
        );
        return;
      }

      const [senderSnap, receiverSnap] = await Promise.all([
        db.doc(`${userPrivateCollection}/${senderId}`).get(),
        db.doc(`users/${receiverId}`).get(),
      ]);
      const sender = senderSnap.data();
      const accepterName = receiverSnap.data()?.displayName as string | undefined;
      if (accepterName) {
        const locale = preferredLocale(sender);
        await sendNotification(
          senderId,
          sender,
          {
            title: 'MusiLink',
            body: notificationText.friendRequestAccepted[locale](accepterName),
          },
          { type: 'friend_request_accepted', accepterId: receiverId },
        );
      }

      await deleteFriendRequestVersion(
        event.params.requestId,
        acceptedUpdateTime,
      );
    } catch (error) {
      logger.error('onFriendRequestAccepted: unhandled error', {
        requestId: event.params.requestId,
        error,
      });
      throw error;
    }
  },
);

export const onFriendRequestDeleted = onDocumentDeleted(
  { document: 'friend_requests/{requestId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const request = event.data?.data();
      if (!request) return;
      const senderId = request.senderId as string | undefined;
      const receiverId = request.receiverId as string | undefined;
      if (!senderId || !receiverId) return;

      const limitRef = db
        .collection(friendRequestNotificationLimitsCollection)
        .doc(`${senderId}_${receiverId}`);
      await db.runTransaction(async (tx) => {
        const limitSnap = await tx.get(limitRef);
        if (!limitSnap.exists) return;

        const lastNotifiedAt = limitSnap.data()?.lastNotifiedAt;
        if (!friendRequestNotificationIsCoolingDown(lastNotifiedAt, Timestamp.now())) {
          tx.delete(limitRef);
        }
      });
    } catch (error) {
      logger.error('onFriendRequestDeleted: unhandled error', {
        requestId: event.params.requestId,
        error,
      });
      throw error;
    }
  },
);
