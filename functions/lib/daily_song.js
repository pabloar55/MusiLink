"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.expireDailySongs = void 0;
exports.hasExpiredDailySong = hasExpiredDailySong;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firebase_1 = require("./firebase");
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
async function expireDailySong(userRef, expiresBefore) {
    return firebase_1.db.runTransaction(async (transaction) => {
        const current = await transaction.get(userRef);
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
        return true;
    });
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
    const concurrency = 20;
    for (let index = 0; index < expiredProfiles.docs.length; index += concurrency) {
        const chunk = expiredProfiles.docs.slice(index, index + concurrency);
        await Promise.all(chunk.map(async (profile) => {
            const expired = await expireDailySong(profile.ref, expiresBefore);
            if (!expired)
                return;
            expiredCount += 1;
            const privateProfile = await firebase_1.db
                .doc(`${userPrivateCollection}/${profile.id}`)
                .get();
            const privateData = privateProfile.data();
            const locale = (0, notifications_1.preferredLocale)(privateData);
            await (0, notifications_1.sendNotification)(profile.id, privateData, {
                title: 'MusiLink',
                body: notifications_1.notificationText.dailySongExpired[locale](),
            }, { type: 'daily_song_expired' }, 'daily_song_expired');
        }));
    }
    v2_1.logger.info('expireDailySongs: expiry cycle completed', {
        candidates: expiredProfiles.size,
        expired: expiredCount,
        expiresBefore: expiresBefore.toDate().toISOString(),
    });
});
//# sourceMappingURL=daily_song.js.map