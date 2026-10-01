"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendDailyFriendDigests = void 0;
exports.friendDigestOffsets = friendDigestOffsets;
exports.localDay = localDay;
exports.friendDigestBody = friendDigestBody;
exports.wantsFriendDigest = wantsFriendDigest;
exports.unblockedFriendIds = unblockedFriendIds;
exports.loadFriendSongs = loadFriendSongs;
exports.sendFriendDigests = sendFriendDigests;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firebase_1 = require("./firebase");
const firestore_values_1 = require("./firestore_values");
const notifications_1 = require("./notifications");
const userPrivateCollection = 'user_private';
const dayMs = 24 * 60 * 60 * 1000;
const dailySongLifetimeMs = dayMs;
const friendDigestLocalMinutes = 21 * 60;
const friendDigestSlotMinutes = 15;
const friendDigestMinFriends = 1;
const friendDigestPageSize = 200;
const friendDigestConcurrency = 20;
const friendProfileBatchSize = 100;
/** UTC offsets, in minutes, where it is 21:00 during the scheduled slot. */
function friendDigestOffsets(scheduledAt) {
    const utcMinutes = scheduledAt.getUTCHours() * 60
        + Math.floor(scheduledAt.getUTCMinutes() / friendDigestSlotMinutes)
            * friendDigestSlotMinutes;
    const offset = friendDigestLocalMinutes - utcMinutes;
    // Offsets span UTC-12:00 to UTC+14:00, so a slot can match two zones on
    // opposite sides of the date line.
    return [offset, offset - 24 * 60].filter((value) => value >= -720 && value <= 840);
}
function localDay(millis, utcOffsetMinutes) {
    return Math.floor((millis + utcOffsetMinutes * 60 * 1000) / dayMs);
}
/** Names up to three friends; larger groups show two and count the rest. */
function friendDigestBody(locale, names) {
    if (names.length === 1)
        return notifications_1.notificationText.friendDigestOne[locale](names[0]);
    const shown = names.length > 3 ? names.slice(0, 2) : names;
    const parts = names.length > shown.length
        ? [...shown, notifications_1.notificationText.friendDigestOthers[locale](String(names.length - shown.length))]
        : shown;
    const friends = new Intl.ListFormat(locale, { style: 'long', type: 'conjunction' })
        .format(parts);
    return notifications_1.notificationText.friendDigest[locale](friends);
}
function wantsFriendDigest(privateData, nowMillis) {
    const offset = privateData?.utcOffsetMinutes;
    if (typeof offset !== 'number' || privateData?.notifFriendDigest === false)
        return false;
    const lastPush = privateData?.[notifications_1.engagementPushField];
    return !(lastPush instanceof firestore_1.Timestamp)
        || localDay(lastPush.toMillis(), offset) !== localDay(nowMillis, offset);
}
function friendSong(data, activeAfter) {
    const updatedAt = data?.dailySongUpdatedAt;
    if (!data?.dailySong
        || !(updatedAt instanceof firestore_1.Timestamp)
        || updatedAt.toMillis() <= activeAfter
        || data.username === 'deleted_user'
        || typeof data.displayName !== 'string'
        || data.displayName.trim().length === 0) {
        return null;
    }
    return { name: data.displayName.trim(), publishedAt: updatedAt.toMillis() };
}
function unblockedFriendIds(privateData) {
    const blocked = new Set((0, firestore_values_1.stringList)(privateData?.blockedUsers));
    return (0, firestore_values_1.stringList)(privateData?.friends).filter((id) => !blocked.has(id));
}
/** Friends with a song published after [activeAfter]; profiles are cached per run. */
async function loadFriendSongs(firestore, friendIds, activeAfter, cache) {
    const missing = friendIds.filter((id) => !cache.has(id));
    for (let index = 0; index < missing.length; index += friendProfileBatchSize) {
        const profiles = await firestore.getAll(...missing
            .slice(index, index + friendProfileBatchSize)
            .map((id) => firestore.collection('users').doc(id)), { fieldMask: ['displayName', 'username', 'dailySong', 'dailySongUpdatedAt'] });
        for (const profile of profiles) {
            cache.set(profile.id, friendSong(profile.data(), activeAfter));
        }
    }
    return friendIds.flatMap((id) => cache.get(id) ?? []);
}
async function sendFriendDigest(firestore, privateProfile, nowMillis, cache, notify) {
    const uid = privateProfile.id;
    const privateData = privateProfile.data();
    if (!wantsFriendDigest(privateData, nowMillis))
        return false;
    const friendIds = unblockedFriendIds(privateData);
    if (friendIds.length < friendDigestMinFriends)
        return false;
    const [profileSnap, deletion] = await Promise.all([
        firestore.doc(`users/${uid}`).get(),
        firestore.doc(`account_deletions/${uid}`).get(),
    ]);
    const profile = profileSnap.data();
    const activeAfter = nowMillis - dailySongLifetimeMs;
    // Any song still on the profile counts. One past its lifetime is waiting for
    // expireDailySongs, whose own reminder follows; a legacy one without a
    // publication time stays visible in the client.
    const hasPublished = Boolean(profile?.dailySong);
    if (deletion.exists || !profile || profile.username === 'deleted_user' || hasPublished) {
        return false;
    }
    const songs = (await loadFriendSongs(firestore, friendIds, activeAfter, cache))
        .sort((a, b) => b.publishedAt - a.publishedAt);
    if (songs.length < friendDigestMinFriends)
        return false;
    // Claim the day before sending: a retried or overlapping run must not
    // deliver the reminder twice, and a missed reminder is harmless.
    const claimed = await firestore.runTransaction(async (transaction) => {
        const current = (await transaction.get(privateProfile.ref)).data();
        if (!wantsFriendDigest(current, nowMillis))
            return false;
        transaction.update(privateProfile.ref, {
            [notifications_1.engagementPushField]: firestore_1.Timestamp.fromMillis(nowMillis),
        });
        return true;
    });
    if (!claimed)
        return false;
    await notify(uid, privateData, {
        title: 'MusiLink',
        body: friendDigestBody((0, notifications_1.preferredLocale)(privateData), songs.map((song) => song.name)),
    }, { type: 'friend_digest' }, 'friend_digest', { quiet: true });
    return true;
}
/** Reminds users at 21:00 local time that their friends have published. */
async function sendFriendDigests(firestore, scheduledAt, notify = notifications_1.sendNotification) {
    const nowMillis = scheduledAt.getTime();
    const cache = new Map();
    let candidates = 0;
    let sent = 0;
    for (const offset of friendDigestOffsets(scheduledAt)) {
        let cursor;
        for (;;) {
            let query = firestore
                .collection(userPrivateCollection)
                .where('utcOffsetMinutes', '==', offset)
                .orderBy(firestore_1.FieldPath.documentId())
                .limit(friendDigestPageSize);
            if (cursor)
                query = query.startAfter(cursor);
            const page = await query.get();
            candidates += page.size;
            for (let index = 0; index < page.docs.length; index += friendDigestConcurrency) {
                const chunk = page.docs.slice(index, index + friendDigestConcurrency);
                const results = await Promise.all(chunk.map(async (privateProfile) => {
                    try {
                        return await sendFriendDigest(firestore, privateProfile, nowMillis, cache, notify);
                    }
                    catch (error) {
                        // One recipient must not prevent the rest of the slot from
                        // receiving their reminder.
                        v2_1.logger.error('sendFriendDigests: recipient failed', {
                            recipientUid: privateProfile.id,
                            error,
                        });
                        return false;
                    }
                }));
                sent += results.filter(Boolean).length;
            }
            if (page.size < friendDigestPageSize)
                break;
            cursor = page.docs[page.docs.length - 1];
        }
    }
    return { candidates, sent };
}
exports.sendDailyFriendDigests = (0, scheduler_1.onSchedule)({
    schedule: '*/15 * * * *',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    retryCount: 3,
}, async (event) => {
    const scheduledAt = new Date(event.scheduleTime);
    const result = await sendFriendDigests(firebase_1.db, scheduledAt);
    v2_1.logger.info('sendDailyFriendDigests: slot completed', {
        ...result,
        scheduledAt: scheduledAt.toISOString(),
    });
});
//# sourceMappingURL=friend_digest.js.map