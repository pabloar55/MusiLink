"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.expireDailySongs = void 0;
exports.hasExpiredDailySong = hasExpiredDailySong;
exports.expireDailySong = expireDailySong;
exports.dailySongExpiredBody = dailySongExpiredBody;
exports.notifyDailySongExpired = notifyDailySongExpired;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firebase_1 = require("./firebase");
const friend_digest_1 = require("./friend_digest");
const notifications_1 = require("./notifications");
const userPrivateCollection = 'user_private';
const dailySongLifetimeMs = 24 * 60 * 60 * 1000;
const dailySongExpiryBatchSize = 200;
function hasExpiredDailySong(data, expiresBefore) {
    const updatedAt = data?.dailySongUpdatedAt;
    return updatedAt instanceof firestore_1.Timestamp &&
        updatedAt.toMillis() <= expiresBefore.toMillis() &&
        Boolean(data?.dailySong);
}
// Removing the song and claiming the day's reminder are one write: the friend
// digest sees either the song still published or the reminder already taken,
// so it can never be sent alongside the expiry notice.
async function expireDailySong(userRef, expiresBefore) {
    const privateRef = firebase_1.db.doc(`${userPrivateCollection}/${userRef.id}`);
    return firebase_1.db.runTransaction(async (transaction) => {
        const [current, privateProfile] = await Promise.all([
            transaction.get(userRef),
            transaction.get(privateRef),
        ]);
        const data = current.data();
        const updatedAt = data?.dailySongUpdatedAt;
        if (!(updatedAt instanceof firestore_1.Timestamp) ||
            updatedAt.toMillis() > expiresBefore.toMillis()) {
            return false;
        }
        // Avoid an orphaned legacy timestamp blocking the oldest-results query.
        if (!hasExpiredDailySong(data, expiresBefore)) {
            transaction.update(userRef, { dailySongUpdatedAt: firestore_1.FieldValue.delete() });
            return false;
        }
        transaction.update(userRef, {
            dailySong: firestore_1.FieldValue.delete(),
            dailySongUpdatedAt: firestore_1.FieldValue.delete(),
        });
        if (privateProfile.exists) {
            transaction.update(privateRef, {
                [notifications_1.engagementPushField]: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        return true;
    });
}
function dailySongExpiredBody(locale, friendCount) {
    if (friendCount <= 0)
        return notifications_1.notificationText.dailySongExpired[locale]();
    if (friendCount === 1)
        return notifications_1.notificationText.dailySongExpiredFriend[locale]();
    return notifications_1.notificationText.dailySongExpiredFriends[locale](String(friendCount));
}
/** Tells the owner their song expired, mentioning friends who have published. */
async function notifyDailySongExpired(firestore, uid, activeAfter, cache, notify = notifications_1.sendNotification) {
    const privateProfile = await firestore.doc(`${userPrivateCollection}/${uid}`).get();
    const privateData = privateProfile.data();
    let friendCount = 0;
    try {
        const songs = await (0, friend_digest_1.loadFriendSongs)(firestore, (0, friend_digest_1.unblockedFriendIds)(privateData), activeAfter, cache);
        friendCount = songs.length;
    }
    catch (error) {
        // The song is already gone, so the reminder must not depend on this count.
        v2_1.logger.warn('notifyDailySongExpired: friend songs unavailable', { uid, error });
    }
    await notify(uid, privateData, {
        title: 'MusiLink',
        body: dailySongExpiredBody((0, notifications_1.preferredLocale)(privateData), friendCount),
    }, { type: 'daily_song_expired' }, 'daily_song_expired');
}
// Firestore keeps the publication time on the public profile. The transaction
// protects a replacement song published while this query is running.
exports.expireDailySongs = (0, scheduler_1.onSchedule)({
    schedule: 'every 1 minutes',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 300,
    retryCount: 3,
}, async () => {
    const expiresBefore = firestore_1.Timestamp.fromMillis(Date.now() - dailySongLifetimeMs);
    const expiredProfiles = await firebase_1.db
        .collection('users')
        .where('dailySongUpdatedAt', '<=', expiresBefore)
        .orderBy('dailySongUpdatedAt')
        .limit(dailySongExpiryBatchSize)
        .get();
    let expiredCount = 0;
    const friendSongs = new Map();
    const concurrency = 20;
    for (let index = 0; index < expiredProfiles.docs.length; index += concurrency) {
        const chunk = expiredProfiles.docs.slice(index, index + concurrency);
        await Promise.all(chunk.map(async (profile) => {
            const expired = await expireDailySong(profile.ref, expiresBefore);
            if (!expired)
                return;
            expiredCount += 1;
            await notifyDailySongExpired(firebase_1.db, profile.id, expiresBefore.toMillis(), friendSongs);
        }));
    }
    v2_1.logger.info('expireDailySongs: expiry cycle completed', {
        candidates: expiredProfiles.size,
        expired: expiredCount,
        expiresBefore: expiresBefore.toDate().toISOString(),
    });
});
//# sourceMappingURL=daily_song.js.map