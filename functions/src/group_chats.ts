import {
  DocumentData, FieldPath, FieldValue, Firestore, Timestamp, Transaction,
} from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions/v2';
import { onDocumentCreated, onDocumentDeleted } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { deletedGroupsCollection, deleteGroup, everyAccountDeleted } from './abandoned_groups';
import { reactionEmojis, scrubUserReactions } from './account_deletion';
import { db } from './firebase';
import { chatParticipants, stringList } from './firestore_values';
import { advanceFixedWindow } from './rate_limits';

const options = { region: 'europe-southwest1', enforceAppCheck: true } as const;
export const maxGroupParticipants = 20;
// Groups use random Firestore IDs; direct chats never match this pattern.
const groupChatIdPattern = /^[A-Za-z0-9]{20}$/;
const departuresCollection = 'departures';
const reactionScrubConcurrency = 20;
const maxGroupAddsPerHour = 30;

function isMemberId(id: unknown): id is string {
  return typeof id === 'string' && id !== '' && id !== '.' && id !== '..'
    && !id.includes('/') && id.length <= 128;
}

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
    || !participantIds.every(isMemberId)) {
    throw new HttpsError('invalid-argument', 'Invalid group details.');
  }
  const ids = [...new Set<string>([uid, ...participantIds])].sort();
  if (ids.length < 3 || ids.length > maxGroupParticipants) {
    throw new HttpsError('invalid-argument', 'Groups need between 3 and 20 members.');
  }
  const chatRef = db.doc(`chats/${chatId}`);
  const limiterRef = db.doc(`rate_limits/${uid}`);
  await db.runTransaction(async (tx) => {
    const [existing, deleted] = await Promise.all([
      tx.get(chatRef), tx.get(db.doc(`${deletedGroupsCollection}/${chatId}`)),
    ]);
    if (existing.exists) {
      // Retrying a lost callable response must not create another group.
      if (existing.data()?.type === 'group' && existing.data()?.createdBy === uid
        && existing.data()?.name === name.trim()
        && JSON.stringify(chatParticipants(existing.data())) === JSON.stringify(ids)) return;
      throw new HttpsError('already-exists', 'The chat ID is already in use.');
    }
    // The ID of a deleted group is never reused; see `deleteGroup`.
    if (deleted.exists) throw new HttpsError('already-exists', 'The chat ID is already in use.');
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

/**
 * Any member can add their own mutual friends, who need not be friends with
 * the rest of the group. Blocks are checked against every current member,
 * because a block prevents both sides from sending to the group.
 */
export async function addGroupMembers(
  firestore: Firestore, chatId: string, uid: string, participantIds: string[],
  now = Timestamp.now(),
): Promise<void> {
  const chatRef = firestore.doc(`chats/${chatId}`);
  const limiterRef = firestore.doc(`rate_limits/${uid}`);
  await firestore.runTransaction(async (tx) => {
    const chat = await tx.get(chatRef);
    const ids = chatParticipants(chat.data());
    if (chat.data()?.type !== 'group' || !ids.includes(uid)) {
      throw new HttpsError('permission-denied', 'Not a group member.');
    }
    // Retrying a lost callable response finds the members already added.
    const added = [...new Set(participantIds)].filter((id) => !ids.includes(id));
    if (added.length === 0) return;
    if (ids.length + added.length > maxGroupParticipants) {
      throw new HttpsError('failed-precondition', 'The group is full.');
    }
    const [members, limiter] = await Promise.all([
      memberProfiles(firestore, tx, [...ids, ...added]), tx.get(limiterRef),
    ]);
    const adder = members.find((member) => member.uid === uid)!;
    if (!adder.active) throw new HttpsError('failed-precondition', 'Inactive member.');
    for (const member of members.filter((candidate) => added.includes(candidate.uid))) {
      if (!member.active) throw new HttpsError('failed-precondition', 'Inactive member.');
      if (!adder.friends.includes(member.uid) || !member.friends.includes(uid)) {
        throw new HttpsError('permission-denied', 'Only mutual friends can be added.');
      }
      // Deleted accounts stay in the group but can no longer interact.
      if (members.some((other) => other.active
        && (member.blocked.includes(other.uid) || other.blocked.includes(member.uid)))) {
        throw new HttpsError('permission-denied', 'Some members cannot interact.');
      }
    }
    const next = advanceFixedWindow(limiter.data()?.groupAddWindowStart,
      limiter.data()?.groupAddCount, now, 60 * 60 * 1000, maxGroupAddsPerHour);
    if (next.limited) throw new HttpsError('resource-exhausted', 'Member addition limit reached.');
    // The read mark is the joining time: a trigger that runs late for an
    // earlier message must neither count it as pending nor notify it.
    tx.update(chatRef,
      'participants', FieldValue.arrayUnion(...added),
      ...added.flatMap((id) => [
        new FieldPath('unreadCounts', id), 0,
        new FieldPath('lastReadAt', id), now,
      ]));
    // A returning member's remaining reactions are valid again, so a cleanup
    // still pending from their departure is cancelled.
    for (const id of added) tx.delete(chatRef.collection(departuresCollection).doc(id));
    tx.set(limiterRef,
      { groupAddWindowStart: next.windowStart, groupAddCount: next.count }, { merge: true });
  });
}

/**
 * Removes the member together with every per-member field, or deletes the
 * group once no usable account is left. The remaining cleanup is slower and
 * can fail, so it is left to triggers that Firestore retries: the departure
 * record written here starts `onGroupMemberLeft`, and the deletion starts
 * `onGroupChatDeleted`.
 */
export async function leaveGroup(firestore: Firestore, chatId: string, uid: string): Promise<void> {
  const chatRef = firestore.doc(`chats/${chatId}`);
  await firestore.runTransaction(async (tx) => {
    const chat = await tx.get(chatRef);
    if (!chat.exists) return;
    if (chat.data()?.type !== 'group') {
      throw new HttpsError('failed-precondition', 'Not a group chat.');
    }
    const ids = chatParticipants(chat.data());
    // Retrying a lost callable response finds the member already removed.
    if (!ids.includes(uid)) return;
    // Deleted accounts stay in `participants`; once only they remain, nobody
    // can open the group again.
    const remaining = ids.filter((id) => id !== uid);
    if (await everyAccountDeleted(firestore, tx, remaining)) {
      deleteGroup(firestore, tx, chatId);
      return;
    }
    tx.update(chatRef,
      'participants', FieldValue.arrayRemove(uid),
      new FieldPath('unreadCounts', uid), FieldValue.delete(),
      new FieldPath('deletedAt', uid), FieldValue.delete(),
      new FieldPath('lastReadAt', uid), FieldValue.delete());
    tx.set(chatRef.collection(departuresCollection).doc(uid), { leftAt: Timestamp.now() });
  });
}

/**
 * Firestore Rules validate reactions against `participants`, so a reaction
 * left behind would block the remaining members from reacting to that message.
 * Each message is rewritten in its own transaction: members leaving at the
 * same time, or reacting meanwhile, must not restore each other's old values.
 * The departure record is read in those transactions too: adding the member
 * back deletes it, which stops the cleanup before it touches new reactions.
 */
export async function cleanUpDeparture(firestore: Firestore, chatId: string, uid: string): Promise<void> {
  const departureRef = firestore.doc(`chats/${chatId}/${departuresCollection}/${uid}`);
  // Missing once cleaned up or cancelled. A member who left again has a newer
  // record, which this run then serves like the trigger started for it.
  const departure = (await departureRef.get()).updateTime;
  if (!departure) return;
  let superseded = false;
  for (const emoji of reactionEmojis) {
    // The reaction indexes only exist at collection-group scope.
    const snapshot = await firestore.collectionGroup('messages')
      .where(new FieldPath('reactions', emoji), 'array-contains', uid)
      .get();
    const messages = snapshot.docs
      .map((message) => message.ref)
      .filter((message) => message.parent.parent?.id === chatId);
    for (let start = 0; start < messages.length; start += reactionScrubConcurrency) {
      await Promise.all(messages.slice(start, start + reactionScrubConcurrency).map((message) =>
        firestore.runTransaction(async (tx) => {
          const [pending, current] = await Promise.all([tx.get(departureRef), tx.get(message)]);
          if (!pending.updateTime?.isEqual(departure)) {
            superseded = true;
            return;
          }
          if (!current.exists) return;
          tx.update(message, { reactions: scrubUserReactions(current.data()?.reactions, uid) });
        })));
      if (superseded) return;
    }
  }
  // Kept until the reactions are gone, as the record of a pending cleanup.
  await firestore.runTransaction(async (tx) => {
    const pending = await tx.get(departureRef);
    if (pending.updateTime?.isEqual(departure)) tx.delete(departureRef);
  });
}

/**
 * Removes what a deleted group leaves behind: messages and pending departures.
 * Returns false, without deleting anything, if a group exists under this ID.
 * That is only possible for a group deleted outside the backend and created
 * again before this ran, so the ID is retired here when it was not already.
 */
export async function cleanUpDeletedGroup(firestore: Firestore, chatId: string): Promise<boolean> {
  const chatRef = firestore.doc(`chats/${chatId}`);
  const deletedRef = firestore.doc(`${deletedGroupsCollection}/${chatId}`);
  const gone = await firestore.runTransaction(async (tx) => {
    const [chat, deleted] = await Promise.all([tx.get(chatRef), tx.get(deletedRef)]);
    if (chat.exists) return false;
    if (!deleted.exists) tx.set(deletedRef, { deletedAt: Timestamp.now() });
    return true;
  });
  if (gone) await firestore.recursiveDelete(chatRef);
  return gone;
}

export const addGroupChatMembers = onCall(options, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const { chatId, participantIds } = request.data ?? {};
  if (typeof chatId !== 'string' || !groupChatIdPattern.test(chatId)
    || !Array.isArray(participantIds) || participantIds.length === 0
    || participantIds.length > maxGroupParticipants - 1
    || !participantIds.every(isMemberId)) {
    throw new HttpsError('invalid-argument', 'Invalid members.');
  }
  await addGroupMembers(db, chatId, uid, participantIds);
  return { chatId };
});

export const leaveGroupChat = onCall(options, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const chatId = request.data?.chatId;
  if (typeof chatId !== 'string' || !groupChatIdPattern.test(chatId)) {
    throw new HttpsError('invalid-argument', 'Invalid group.');
  }
  await leaveGroup(db, chatId, uid);
  return { chatId };
});

export const onGroupMemberLeft = onDocumentCreated(
  {
    document: `chats/{chatId}/${departuresCollection}/{uid}`,
    region: options.region,
    retry: true,
  },
  async (event) => {
    try {
      await cleanUpDeparture(db, event.params.chatId, event.params.uid);
    } catch (error) {
      logger.error('onGroupMemberLeft: cleanup failed, will retry', {
        chatId: event.params.chatId,
        uid: event.params.uid,
        error,
      });
      throw error;
    }
  },
);

export const onGroupChatDeleted = onDocumentDeleted(
  { document: 'chats/{chatId}', region: options.region, retry: true },
  async (event) => {
    // Direct chats are only deleted once they have no messages.
    if (event.data?.data()?.type !== 'group') return;
    const chatId = event.params.chatId;
    try {
      if (!await cleanUpDeletedGroup(db, chatId)) {
        logger.warn('onGroupChatDeleted: a group exists under this ID, nothing deleted', { chatId });
        return;
      }
      await getStorage().bucket().file(`group_photos/${chatId}`).delete({ ignoreNotFound: true });
    } catch (error) {
      logger.error('onGroupChatDeleted: cleanup failed, will retry', { chatId, error });
      throw error;
    }
  },
);
