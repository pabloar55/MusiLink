"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onGroupChatDeleted = exports.onGroupMemberLeft = exports.leaveGroupChat = exports.addGroupChatMembers = exports.createGroupChat = exports.maxGroupParticipants = void 0;
exports.validateGroupSender = validateGroupSender;
exports.addGroupMembers = addGroupMembers;
exports.leaveGroup = leaveGroup;
exports.cleanUpDeparture = cleanUpDeparture;
exports.cleanUpDeletedGroup = cleanUpDeletedGroup;
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const abandoned_groups_1 = require("./abandoned_groups");
const account_deletion_1 = require("./account_deletion");
const firebase_1 = require("./firebase");
const firestore_values_1 = require("./firestore_values");
const rate_limits_1 = require("./rate_limits");
const options = { region: 'europe-southwest1', enforceAppCheck: true };
exports.maxGroupParticipants = 20;
// Groups use random Firestore IDs; direct chats never match this pattern.
const groupChatIdPattern = /^[A-Za-z0-9]{20}$/;
const departuresCollection = 'departures';
const reactionScrubConcurrency = 20;
const maxGroupAddsPerHour = 30;
function isMemberId(id) {
    return typeof id === 'string' && id !== '' && id !== '.' && id !== '..'
        && !id.includes('/') && id.length <= 128;
}
async function memberProfiles(firestore, tx, ids) {
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
            friends: (0, firestore_values_1.stringList)(privateProfile.data()?.friends),
            blocked: (0, firestore_values_1.stringList)(privateProfile.data()?.blockedUsers),
        };
    }));
}
// Group membership authorizes messaging after creation; friendship is checked
// when inviting. Blocking remains effective for every sender/recipient pair.
async function validateGroupSender(firestore, tx, chat, senderId) {
    const ids = (0, firestore_values_1.chatParticipants)(chat);
    if (!ids.includes(senderId) || ids.length > exports.maxGroupParticipants) {
        throw new https_1.HttpsError('permission-denied', 'Not a group member.');
    }
    const members = await memberProfiles(firestore, tx, ids);
    const sender = members.find((member) => member.uid === senderId);
    if (!sender.active)
        throw new https_1.HttpsError('failed-precondition', 'Inactive sender.');
    for (const member of members) {
        if (member.uid === senderId || !member.active)
            continue;
        if (sender.blocked.includes(member.uid) || member.blocked.includes(senderId)) {
            throw new https_1.HttpsError('permission-denied', 'A group member cannot interact with the sender.');
        }
    }
}
exports.createGroupChat = (0, https_1.onCall)(options, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    const { chatId, name, participantIds } = request.data ?? {};
    if (typeof chatId !== 'string' || !groupChatIdPattern.test(chatId)
        || typeof name !== 'string' || !name.trim() || name.trim().length > 80
        || !Array.isArray(participantIds) || participantIds.length > exports.maxGroupParticipants - 1
        || !participantIds.every(isMemberId)) {
        throw new https_1.HttpsError('invalid-argument', 'Invalid group details.');
    }
    const ids = [...new Set([uid, ...participantIds])].sort();
    if (ids.length < 3 || ids.length > exports.maxGroupParticipants) {
        throw new https_1.HttpsError('invalid-argument', 'Groups need between 3 and 20 members.');
    }
    const chatRef = firebase_1.db.doc(`chats/${chatId}`);
    const limiterRef = firebase_1.db.doc(`rate_limits/${uid}`);
    await firebase_1.db.runTransaction(async (tx) => {
        const [existing, deleted] = await Promise.all([
            tx.get(chatRef), tx.get(firebase_1.db.doc(`${abandoned_groups_1.deletedGroupsCollection}/${chatId}`)),
        ]);
        if (existing.exists) {
            // Retrying a lost callable response must not create another group.
            if (existing.data()?.type === 'group' && existing.data()?.createdBy === uid
                && existing.data()?.name === name.trim()
                && JSON.stringify((0, firestore_values_1.chatParticipants)(existing.data())) === JSON.stringify(ids))
                return;
            throw new https_1.HttpsError('already-exists', 'The chat ID is already in use.');
        }
        // The ID of a deleted group is never reused; see `deleteGroup`.
        if (deleted.exists)
            throw new https_1.HttpsError('already-exists', 'The chat ID is already in use.');
        const [members, limiter] = await Promise.all([
            memberProfiles(firebase_1.db, tx, ids), tx.get(limiterRef),
        ]);
        const creator = members.find((member) => member.uid === uid);
        for (const member of members) {
            if (!member.active)
                throw new https_1.HttpsError('failed-precondition', 'Inactive member.');
            if (member.uid !== uid
                && (!creator.friends.includes(member.uid) || !member.friends.includes(uid))) {
                throw new https_1.HttpsError('permission-denied', 'Only mutual friends can be invited.');
            }
            if (members.some((other) => member.blocked.includes(other.uid))) {
                throw new https_1.HttpsError('permission-denied', 'Some members cannot interact.');
            }
        }
        const now = firestore_1.Timestamp.now();
        const next = (0, rate_limits_1.advanceFixedWindow)(limiter.data()?.groupWindowStart, limiter.data()?.groupCount, now, 60 * 60 * 1000, 5);
        if (next.limited)
            throw new https_1.HttpsError('resource-exhausted', 'Group creation limit reached.');
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
async function addGroupMembers(firestore, chatId, uid, participantIds, now = firestore_1.Timestamp.now()) {
    const chatRef = firestore.doc(`chats/${chatId}`);
    const limiterRef = firestore.doc(`rate_limits/${uid}`);
    await firestore.runTransaction(async (tx) => {
        const chat = await tx.get(chatRef);
        const ids = (0, firestore_values_1.chatParticipants)(chat.data());
        if (chat.data()?.type !== 'group' || !ids.includes(uid)) {
            throw new https_1.HttpsError('permission-denied', 'Not a group member.');
        }
        // Retrying a lost callable response finds the members already added.
        const added = [...new Set(participantIds)].filter((id) => !ids.includes(id));
        if (added.length === 0)
            return;
        if (ids.length + added.length > exports.maxGroupParticipants) {
            throw new https_1.HttpsError('failed-precondition', 'The group is full.');
        }
        const [members, limiter] = await Promise.all([
            memberProfiles(firestore, tx, [...ids, ...added]), tx.get(limiterRef),
        ]);
        const adder = members.find((member) => member.uid === uid);
        if (!adder.active)
            throw new https_1.HttpsError('failed-precondition', 'Inactive member.');
        for (const member of members.filter((candidate) => added.includes(candidate.uid))) {
            if (!member.active)
                throw new https_1.HttpsError('failed-precondition', 'Inactive member.');
            if (!adder.friends.includes(member.uid) || !member.friends.includes(uid)) {
                throw new https_1.HttpsError('permission-denied', 'Only mutual friends can be added.');
            }
            // Deleted accounts stay in the group but can no longer interact.
            if (members.some((other) => other.active
                && (member.blocked.includes(other.uid) || other.blocked.includes(member.uid)))) {
                throw new https_1.HttpsError('permission-denied', 'Some members cannot interact.');
            }
        }
        const next = (0, rate_limits_1.advanceFixedWindow)(limiter.data()?.groupAddWindowStart, limiter.data()?.groupAddCount, now, 60 * 60 * 1000, maxGroupAddsPerHour);
        if (next.limited)
            throw new https_1.HttpsError('resource-exhausted', 'Member addition limit reached.');
        // The read mark is the joining time: a trigger that runs late for an
        // earlier message must neither count it as pending nor notify it.
        tx.update(chatRef, 'participants', firestore_1.FieldValue.arrayUnion(...added), ...added.flatMap((id) => [
            new firestore_1.FieldPath('unreadCounts', id), 0,
            new firestore_1.FieldPath('lastReadAt', id), now,
        ]));
        // A returning member's remaining reactions are valid again, so a cleanup
        // still pending from their departure is cancelled.
        for (const id of added)
            tx.delete(chatRef.collection(departuresCollection).doc(id));
        tx.set(limiterRef, { groupAddWindowStart: next.windowStart, groupAddCount: next.count }, { merge: true });
    });
}
/**
 * Removes the member together with every per-member field, or deletes the
 * group once no usable account is left. The remaining cleanup is slower and
 * can fail, so it is left to triggers that Firestore retries: the departure
 * record written here starts `onGroupMemberLeft`, and the deletion starts
 * `onGroupChatDeleted`.
 */
async function leaveGroup(firestore, chatId, uid) {
    const chatRef = firestore.doc(`chats/${chatId}`);
    await firestore.runTransaction(async (tx) => {
        const chat = await tx.get(chatRef);
        if (!chat.exists)
            return;
        if (chat.data()?.type !== 'group') {
            throw new https_1.HttpsError('failed-precondition', 'Not a group chat.');
        }
        const ids = (0, firestore_values_1.chatParticipants)(chat.data());
        // Retrying a lost callable response finds the member already removed.
        if (!ids.includes(uid))
            return;
        // Deleted accounts stay in `participants`; once only they remain, nobody
        // can open the group again.
        const remaining = ids.filter((id) => id !== uid);
        if (await (0, abandoned_groups_1.everyAccountDeleted)(firestore, tx, remaining)) {
            (0, abandoned_groups_1.deleteGroup)(firestore, tx, chatId);
            return;
        }
        tx.update(chatRef, 'participants', firestore_1.FieldValue.arrayRemove(uid), new firestore_1.FieldPath('unreadCounts', uid), firestore_1.FieldValue.delete(), new firestore_1.FieldPath('deletedAt', uid), firestore_1.FieldValue.delete(), new firestore_1.FieldPath('lastReadAt', uid), firestore_1.FieldValue.delete());
        tx.set(chatRef.collection(departuresCollection).doc(uid), { leftAt: firestore_1.Timestamp.now() });
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
async function cleanUpDeparture(firestore, chatId, uid) {
    const departureRef = firestore.doc(`chats/${chatId}/${departuresCollection}/${uid}`);
    // Missing once cleaned up or cancelled. A member who left again has a newer
    // record, which this run then serves like the trigger started for it.
    const departure = (await departureRef.get()).updateTime;
    if (!departure)
        return;
    let superseded = false;
    for (const emoji of account_deletion_1.reactionEmojis) {
        // The reaction indexes only exist at collection-group scope.
        const snapshot = await firestore.collectionGroup('messages')
            .where(new firestore_1.FieldPath('reactions', emoji), 'array-contains', uid)
            .get();
        const messages = snapshot.docs
            .map((message) => message.ref)
            .filter((message) => message.parent.parent?.id === chatId);
        for (let start = 0; start < messages.length; start += reactionScrubConcurrency) {
            await Promise.all(messages.slice(start, start + reactionScrubConcurrency).map((message) => firestore.runTransaction(async (tx) => {
                const [pending, current] = await Promise.all([tx.get(departureRef), tx.get(message)]);
                if (!pending.updateTime?.isEqual(departure)) {
                    superseded = true;
                    return;
                }
                if (!current.exists)
                    return;
                tx.update(message, { reactions: (0, account_deletion_1.scrubUserReactions)(current.data()?.reactions, uid) });
            })));
            if (superseded)
                return;
        }
    }
    // Kept until the reactions are gone, as the record of a pending cleanup.
    await firestore.runTransaction(async (tx) => {
        const pending = await tx.get(departureRef);
        if (pending.updateTime?.isEqual(departure))
            tx.delete(departureRef);
    });
}
/**
 * Removes what a deleted group leaves behind: messages and pending departures.
 * Returns false, without deleting anything, if a group exists under this ID.
 * That is only possible for a group deleted outside the backend and created
 * again before this ran, so the ID is retired here when it was not already.
 */
async function cleanUpDeletedGroup(firestore, chatId) {
    const chatRef = firestore.doc(`chats/${chatId}`);
    const deletedRef = firestore.doc(`${abandoned_groups_1.deletedGroupsCollection}/${chatId}`);
    const gone = await firestore.runTransaction(async (tx) => {
        const [chat, deleted] = await Promise.all([tx.get(chatRef), tx.get(deletedRef)]);
        if (chat.exists)
            return false;
        if (!deleted.exists)
            tx.set(deletedRef, { deletedAt: firestore_1.Timestamp.now() });
        return true;
    });
    if (gone)
        await firestore.recursiveDelete(chatRef);
    return gone;
}
exports.addGroupChatMembers = (0, https_1.onCall)(options, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    const { chatId, participantIds } = request.data ?? {};
    if (typeof chatId !== 'string' || !groupChatIdPattern.test(chatId)
        || !Array.isArray(participantIds) || participantIds.length === 0
        || participantIds.length > exports.maxGroupParticipants - 1
        || !participantIds.every(isMemberId)) {
        throw new https_1.HttpsError('invalid-argument', 'Invalid members.');
    }
    await addGroupMembers(firebase_1.db, chatId, uid, participantIds);
    return { chatId };
});
exports.leaveGroupChat = (0, https_1.onCall)(options, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    const chatId = request.data?.chatId;
    if (typeof chatId !== 'string' || !groupChatIdPattern.test(chatId)) {
        throw new https_1.HttpsError('invalid-argument', 'Invalid group.');
    }
    await leaveGroup(firebase_1.db, chatId, uid);
    return { chatId };
});
exports.onGroupMemberLeft = (0, firestore_2.onDocumentCreated)({
    document: `chats/{chatId}/${departuresCollection}/{uid}`,
    region: options.region,
    retry: true,
}, async (event) => {
    try {
        await cleanUpDeparture(firebase_1.db, event.params.chatId, event.params.uid);
    }
    catch (error) {
        v2_1.logger.error('onGroupMemberLeft: cleanup failed, will retry', {
            chatId: event.params.chatId,
            uid: event.params.uid,
            error,
        });
        throw error;
    }
});
exports.onGroupChatDeleted = (0, firestore_2.onDocumentDeleted)({ document: 'chats/{chatId}', region: options.region, retry: true }, async (event) => {
    // Direct chats are only deleted once they have no messages.
    if (event.data?.data()?.type !== 'group')
        return;
    const chatId = event.params.chatId;
    try {
        if (!await cleanUpDeletedGroup(firebase_1.db, chatId)) {
            v2_1.logger.warn('onGroupChatDeleted: a group exists under this ID, nothing deleted', { chatId });
            return;
        }
        await (0, storage_1.getStorage)().bucket().file(`group_photos/${chatId}`).delete({ ignoreNotFound: true });
    }
    catch (error) {
        v2_1.logger.error('onGroupChatDeleted: cleanup failed, will retry', { chatId, error });
        throw error;
    }
});
//# sourceMappingURL=group_chats.js.map