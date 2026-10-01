"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onGroupChatDeleted = exports.onGroupMemberLeft = exports.leaveGroupChat = exports.createGroupChat = exports.maxGroupParticipants = void 0;
exports.validateGroupSender = validateGroupSender;
exports.leaveGroup = leaveGroup;
exports.cleanUpDeparture = cleanUpDeparture;
exports.deleteGroupContents = deleteGroupContents;
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
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
        || participantIds.some((id) => typeof id !== 'string' || !id
            || id === '.' || id === '..' || id.includes('/') || id.length > 128)) {
        throw new https_1.HttpsError('invalid-argument', 'Invalid group details.');
    }
    const ids = [...new Set([uid, ...participantIds])].sort();
    if (ids.length < 3 || ids.length > exports.maxGroupParticipants) {
        throw new https_1.HttpsError('invalid-argument', 'Groups need between 3 and 20 members.');
    }
    const chatRef = firebase_1.db.doc(`chats/${chatId}`);
    const limiterRef = firebase_1.db.doc(`rate_limits/${uid}`);
    await firebase_1.db.runTransaction(async (tx) => {
        const existing = await tx.get(chatRef);
        if (existing.exists) {
            // Retrying a lost callable response must not create another group.
            if (existing.data()?.type === 'group' && existing.data()?.createdBy === uid
                && existing.data()?.name === name.trim()
                && JSON.stringify((0, firestore_values_1.chatParticipants)(existing.data())) === JSON.stringify(ids))
                return;
            throw new https_1.HttpsError('already-exists', 'The chat ID is already in use.');
        }
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
 * Removes the member together with every per-member field, or deletes the
 * group once nobody is left. The remaining cleanup is slower and can fail, so
 * it is left to triggers that Firestore retries: the departure record written
 * here starts `onGroupMemberLeft`, and the deletion starts `onGroupChatDeleted`.
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
        if (ids.length === 1) {
            tx.delete(chatRef);
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
 * A former member cannot rejoin, so removing the reaction is always correct.
 */
async function cleanUpDeparture(firestore, chatId, uid) {
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
                const current = await tx.get(message);
                if (!current.exists)
                    return;
                tx.update(message, { reactions: (0, account_deletion_1.scrubUserReactions)(current.data()?.reactions, uid) });
            })));
        }
    }
    // Kept until the reactions are gone, as the record of a pending cleanup.
    await firestore.doc(`chats/${chatId}/${departuresCollection}/${uid}`).delete();
}
/** Removes what a deleted group leaves behind: messages and pending departures. */
async function deleteGroupContents(firestore, chatId) {
    await firestore.recursiveDelete(firestore.doc(`chats/${chatId}`));
}
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
        await deleteGroupContents(firebase_1.db, chatId);
        await (0, storage_1.getStorage)().bucket().file(`group_photos/${chatId}`).delete({ ignoreNotFound: true });
    }
    catch (error) {
        v2_1.logger.error('onGroupChatDeleted: cleanup failed, will retry', { chatId, error });
        throw error;
    }
});
//# sourceMappingURL=group_chats.js.map