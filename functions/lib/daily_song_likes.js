"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onDailySongLiked = void 0;
exports.notifyDailySongLike = notifyDailySongLike;
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const firebase_1 = require("./firebase");
const firestore_values_1 = require("./firestore_values");
const notifications_1 = require("./notifications");
/** Recheck delayed events against the current publication and relationship. */
async function notifyDailySongLike(firestore, ownerId, senderId, publishedAt, createdAt, notify = notifications_1.sendNotification, now = firestore_1.Timestamp.now()) {
    if (ownerId === senderId || now.toMillis() < publishedAt.toMillis()
        || now.toMillis() >= publishedAt.toMillis() + 86400000)
        return false;
    const likeRef = firestore.doc(`users/${ownerId}/daily_song_likes/${senderId}`);
    const [likeSnap, ownerSnap, senderSnap, ownerPrivateSnap, senderPrivateSnap, ownerDeletion, senderDeletion] = await Promise.all([
        likeRef.get(),
        firestore.doc(`users/${ownerId}`).get(),
        firestore.doc(`users/${senderId}`).get(),
        firestore.doc(`user_private/${ownerId}`).get(),
        firestore.doc(`user_private/${senderId}`).get(),
        firestore.doc(`account_deletions/${ownerId}`).get(),
        firestore.doc(`account_deletions/${senderId}`).get(),
    ]);
    const like = likeSnap.data();
    const owner = ownerSnap.data();
    const sender = senderSnap.data();
    const ownerPrivate = ownerPrivateSnap.data();
    const senderPrivate = senderPrivateSnap.data();
    if (!(like?.publishedAt instanceof firestore_1.Timestamp) || !like.publishedAt.isEqual(publishedAt)
        || !(like.createdAt instanceof firestore_1.Timestamp) || !like.createdAt.isEqual(createdAt)
        || (like.notificationSentFor instanceof firestore_1.Timestamp && like.notificationSentFor.isEqual(publishedAt))
        || !owner?.dailySong || !(owner.dailySongUpdatedAt instanceof firestore_1.Timestamp)
        || !owner.dailySongUpdatedAt.isEqual(publishedAt)
        || !sender || sender.username === 'deleted_user' || owner.username === 'deleted_user'
        || ownerDeletion.exists || senderDeletion.exists
        || !(0, firestore_values_1.stringList)(ownerPrivate?.friends).includes(senderId)
        || !(0, firestore_values_1.stringList)(senderPrivate?.friends).includes(ownerId)
        || (0, firestore_values_1.stringList)(ownerPrivate?.blockedUsers).includes(senderId)
        || (0, firestore_values_1.stringList)(senderPrivate?.blockedUsers).includes(ownerId)
        || typeof sender.displayName !== 'string')
        return false;
    await notify(ownerId, ownerPrivate, {
        title: 'MusiLink',
        body: notifications_1.notificationText.dailySongLiked[(0, notifications_1.preferredLocale)(ownerPrivate)](sender.displayName),
    }, { type: 'daily_song_liked', senderId }, `daily_song_like_${senderId}`);
    // A failure before this marker remains retryable. A repeated event uses the
    // same notification tag, replacing rather than stacking drawer entries.
    await firestore.runTransaction(async (tx) => {
        const current = (await tx.get(likeRef)).data();
        if (current?.publishedAt instanceof firestore_1.Timestamp && current.publishedAt.isEqual(publishedAt)
            && current.createdAt instanceof firestore_1.Timestamp && current.createdAt.isEqual(createdAt)) {
            tx.update(likeRef, { notificationSentFor: publishedAt });
        }
    });
    return true;
}
exports.onDailySongLiked = (0, firestore_2.onDocumentWritten)({ document: 'users/{ownerId}/daily_song_likes/{senderId}', region: 'europe-southwest1', retry: true }, async (event) => {
    const after = event.data?.after.data();
    if (!(after?.publishedAt instanceof firestore_1.Timestamp) || !(after.createdAt instanceof firestore_1.Timestamp))
        return;
    if (after.notificationSentFor instanceof firestore_1.Timestamp && after.notificationSentFor.isEqual(after.publishedAt))
        return;
    await notifyDailySongLike(firebase_1.db, event.params.ownerId, event.params.senderId, after.publishedAt, after.createdAt);
});
//# sourceMappingURL=daily_song_likes.js.map