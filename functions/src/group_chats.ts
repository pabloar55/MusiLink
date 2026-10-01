import {
  DocumentData, FieldPath, FieldValue, Firestore, Timestamp, Transaction,
} from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { reactionEmojis, scrubUserReactions } from './account_deletion';
import { db } from './firebase';
import { chatParticipants, stringList } from './firestore_values';
import { advanceFixedWindow } from './rate_limits';

const options = { region: 'europe-southwest1', enforceAppCheck: true } as const;
export const maxGroupParticipants = 20;
// Groups use random Firestore IDs; direct chats never match this pattern.
const groupChatIdPattern = /^[A-Za-z0-9]{20}$/;
const reactionScrubBatchSize = 400;

async function memberProfiles(firestore: Firestore, tx: Transaction, ids: string[]) {
  return Promise.all(ids.map(async (uid) => {
    const [profile, privateProfile, deletion] = await Promise.all([
      tx.get(firestore.doc(`users/${uid}`)),
      tx.get(firestore.doc(`user_private/${uid}`)),
      tx.get(firestore.doc(`account_deletions/${uid}`)),
    ]);
    return {
      uid,
      active: profile.exists && profile.data()?.username !== 'deleted_user'
        && privateProfile.exists && !deletion.exists,
      friends: stringList(privateProfile.data()?.friends),
      blocked: stringList(privateProfile.data()?.blockedUsers),
    };
  }));
}

// Group membership authorizes messaging after creation; friendship is checked
// when inviting. Blocking remains effective for every sender/recipient pair.
export async function validateGroupSender(
  firestore: Firestore, tx: Transaction, chat: DocumentData, senderId: string,
): Promise<void> {
  const ids = chatParticipants(chat);
  if (!ids.includes(senderId) || ids.length > maxGroupParticipants) {
    throw new HttpsError('permission-denied', 'Not a group member.');
  }
  const members = await memberProfiles(firestore, tx, ids);
  const sender = members.find((member) => member.uid === senderId)!;
  if (!sender.active) throw new HttpsError('failed-precondition', 'Inactive sender.');
  for (const member of members) {
    if (member.uid === senderId || !member.active) continue;
    if (sender.blocked.includes(member.uid) || member.blocked.includes(senderId)) {
      throw new HttpsError('permission-denied', 'A group member cannot interact with the sender.');
    }
  }
}

export const createGroupChat = onCall(options, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const { chatId, name, participantIds } = request.data ?? {};
  if (typeof chatId !== 'string' || !groupChatIdPattern.test(chatId)
    || typeof name !== 'string' || !name.trim() || name.trim().length > 80
    || !Array.isArray(participantIds) || participantIds.length > maxGroupParticipants - 1
    || participantIds.some((id: unknown) => typeof id !== 'string' || !id
      || id === '.' || id === '..' || id.includes('/') || id.length > 128)) {
    throw new HttpsError('invalid-argument', 'Invalid group details.');
  }
  const ids = [...new Set<string>([uid, ...participantIds])].sort();
  if (ids.length < 3 || ids.length > maxGroupParticipants) {
    throw new HttpsError('invalid-argument', 'Groups need between 3 and 20 members.');
  }
  const chatRef = db.doc(`chats/${chatId}`);
  const limiterRef = db.doc(`rate_limits/${uid}`);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(chatRef);
    if (existing.exists) {
      // Retrying a lost callable response must not create another group.
      if (existing.data()?.type === 'group' && existing.data()?.createdBy === uid
        && existing.data()?.name === name.trim()
        && JSON.stringify(chatParticipants(existing.data())) === JSON.stringify(ids)) return;
      throw new HttpsError('already-exists', 'The chat ID is already in use.');
    }
    const [members, limiter] = await Promise.all([
      memberProfiles(db, tx, ids), tx.get(limiterRef),
    ]);
    const creator = members.find((member) => member.uid === uid)!;
    for (const member of members) {
      if (!member.active) throw new HttpsError('failed-precondition', 'Inactive member.');
      if (member.uid !== uid
        && (!creator.friends.includes(member.uid) || !member.friends.includes(uid))) {
        throw new HttpsError('permission-denied', 'Only mutual friends can be invited.');
      }
      if (members.some((other) => member.blocked.includes(other.uid))) {
        throw new HttpsError('permission-denied', 'Some members cannot interact.');
      }
    }
    const now = Timestamp.now();
    const next = advanceFixedWindow(limiter.data()?.groupWindowStart,
      limiter.data()?.groupCount, now, 60 * 60 * 1000, 5);
    if (next.limited) throw new HttpsError('resource-exhausted', 'Group creation limit reached.');
    tx.create(chatRef, {
      type: 'group', name: name.trim(), createdBy: uid, participants: ids,
      createdAt: now, lastMessage: '', lastMessageTime: now,
      unreadCounts: Object.fromEntries(ids.map((id) => [id, 0])),
      lastReadAt: {},
    });
    tx.set(limiterRef, { groupWindowStart: next.windowStart, groupCount: next.count }, { merge: true });
  });
  return { chatId };
});

// Firestore Rules validate reactions against `participants`, so a reaction
// left behind would block the remaining members from reacting to that message.
async function scrubGroupReactions(firestore: Firestore, chatId: string, uid: string) {
  for (const emoji of reactionEmojis) {
    // The reaction indexes only exist at collection-group scope.
    const snapshot = await firestore.collectionGroup('messages')
      .where(new FieldPath('reactions', emoji), 'array-contains', uid)
      .get();
    const messages = snapshot.docs.filter((message) => message.ref.parent.parent?.id === chatId);
    for (let start = 0; start < messages.length; start += reactionScrubBatchSize) {
      const batch = firestore.batch();
      for (const message of messages.slice(start, start + reactionScrubBatchSize)) {
        batch.update(message.ref, { reactions: scrubUserReactions(message.data().reactions, uid) });
      }
      await batch.commit();
    }
  }
}

/**
 * Removes the member together with every per-member field. The group is
 * deleted with its messages once nobody is left. Returns whether it remains.
 */
export async function leaveGroup(firestore: Firestore, chatId: string, uid: string): Promise<boolean> {
  const chatRef = firestore.doc(`chats/${chatId}`);
  const remains = await firestore.runTransaction(async (tx) => {
    const chat = await tx.get(chatRef);
    if (!chat.exists) return false;
    if (chat.data()?.type !== 'group') {
      throw new HttpsError('failed-precondition', 'Not a group chat.');
    }
    const ids = chatParticipants(chat.data());
    // Retrying a lost callable response finds the member already removed.
    if (!ids.includes(uid)) return true;
    if (ids.length === 1) {
      tx.delete(chatRef);
      return false;
    }
    tx.update(chatRef,
      'participants', FieldValue.arrayRemove(uid),
      new FieldPath('unreadCounts', uid), FieldValue.delete(),
      new FieldPath('deletedAt', uid), FieldValue.delete(),
      new FieldPath('lastReadAt', uid), FieldValue.delete());
    return true;
  });
  // Both cleanups also run on retries, so an interrupted call can be resumed.
  if (remains) {
    await scrubGroupReactions(firestore, chatId, uid);
  } else {
    await firestore.recursiveDelete(chatRef);
  }
  return remains;
}

export const leaveGroupChat = onCall(options, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const chatId = request.data?.chatId;
  if (typeof chatId !== 'string' || !groupChatIdPattern.test(chatId)) {
    throw new HttpsError('invalid-argument', 'Invalid group.');
  }
  if (!await leaveGroup(db, chatId, uid)) {
    await getStorage().bucket().file(`group_photos/${chatId}`).delete({ ignoreNotFound: true });
  }
  return { chatId };
});
