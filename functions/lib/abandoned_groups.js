"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.everyAccountDeleted = everyAccountDeleted;
exports.deleteGroupIfAbandoned = deleteGroupIfAbandoned;
const firestore_values_1 = require("./firestore_values");
/**
 * Whether nobody in `ids` can use a group any more: every account has been
 * anonymized by the deletion job, which keeps its tombstone in `participants`.
 * A missing profile is not proof of deletion and keeps the group. Reading the
 * profiles in the caller's transaction keeps the answer consistent with a
 * deletion or a departure that commits at the same time.
 */
async function everyAccountDeleted(firestore, tx, ids) {
    const profiles = await Promise.all(ids.map((uid) => tx.get(firestore.doc(`users/${uid}`))));
    return profiles.every((profile) => profile.data()?.username === 'deleted_user');
}
/**
 * Deletes a group whose members are all deleted accounts and returns whether
 * the group is gone, including when it had already been deleted. Its messages
 * and photo are removed by `onGroupChatDeleted`, which Firestore retries.
 */
async function deleteGroupIfAbandoned(firestore, chatId) {
    const chatRef = firestore.doc(`chats/${chatId}`);
    return firestore.runTransaction(async (tx) => {
        const chat = await tx.get(chatRef);
        if (!chat.exists)
            return true;
        if (chat.data()?.type !== 'group')
            return false;
        if (!await everyAccountDeleted(firestore, tx, (0, firestore_values_1.chatParticipants)(chat.data())))
            return false;
        tx.delete(chatRef);
        return true;
    });
}
//# sourceMappingURL=abandoned_groups.js.map