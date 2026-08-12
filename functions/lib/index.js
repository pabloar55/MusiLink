"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onFriendRequestDeleted = exports.onChatMessageDeleted = exports.onChatSoftDeleted = exports.expireDailySongs = exports.onFriendRequestAccepted = exports.onFriendRequest = exports.acceptFriendRequest = exports.createUserProfile = exports.onUserMusicProfileChanged = exports.onUserMusicProfileCreated = exports.onNewMessage = exports.processAccountDeletion = exports.requestAccountDeletion = exports.getSimilarArtists = exports.searchSpotifyTracks = exports.searchSpotifyArtists = void 0;
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firestore_2 = require("firebase-admin/firestore");
const messaging_1 = require("firebase-admin/messaging");
const username_claim_1 = require("./username_claim");
var spotify_1 = require("./spotify");
Object.defineProperty(exports, "searchSpotifyArtists", { enumerable: true, get: function () { return spotify_1.searchSpotifyArtists; } });
Object.defineProperty(exports, "searchSpotifyTracks", { enumerable: true, get: function () { return spotify_1.searchSpotifyTracks; } });
var lastfm_1 = require("./lastfm");
Object.defineProperty(exports, "getSimilarArtists", { enumerable: true, get: function () { return lastfm_1.getSimilarArtists; } });
var account_deletion_1 = require("./account_deletion");
Object.defineProperty(exports, "requestAccountDeletion", { enumerable: true, get: function () { return account_deletion_1.requestAccountDeletion; } });
Object.defineProperty(exports, "processAccountDeletion", { enumerable: true, get: function () { return account_deletion_1.processAccountDeletion; } });
(0, app_1.initializeApp)();
const db = (0, firestore_2.getFirestore)();
const messaging = (0, messaging_1.getMessaging)();
const userPrivateCollection = 'user_private';
const pushTokensSubcollection = 'push_tokens';
const friendRequestNotificationLimitsCollection = 'friend_request_notification_limits';
const recommendationProfilesCollection = 'music_recommendation_profiles';
const recommendationsCollection = 'recommendations';
const chatsCollection = 'chats';
const messagesCollection = 'messages';
const dailySongLifetimeMs = 24 * 60 * 60 * 1000;
const dailySongExpiryBatchSize = 200;
const friendRequestNotificationCooldownMs = 60 * 60 * 1000;
const maxRecommendationInputArtists = 30;
const maxRecommendationInputGenres = 10;
const maxArtistCandidateProfiles = 300;
const maxGenreCandidateProfiles = 100;
const maxStoredRecommendations = 100;
const maxReciprocalRecommendationUsers = 100;
const chatCleanupBatchSize = 400;
const artistScoreWeight = 70;
const genreScoreWeight = 30;
const artistEvidenceTarget = 7;
const genreEvidenceTarget = 4;
const defaultLocale = 'en';
const supportedLocales = new Set(['en', 'es', 'fr']);
const recommendationSnapshotVersion = 1;
const recommendationProfileSchemaVersion = 2;
const notificationText = {
    friendRequest: {
        en: (name) => `${name} sent you a friend request`,
        es: (name) => `${name} te envió una solicitud de amistad`,
        fr: (name) => `${name} vous a envoyé une demande d'amitié`,
    },
    friendRequestAccepted: {
        en: (name) => `${name} accepted your friend request`,
        es: (name) => `${name} aceptó tu solicitud de amistad`,
        fr: (name) => `${name} a accepté votre demande d'amitié`,
    },
    dailySongExpired: {
        en: () => 'Your song of the day has expired. Share a new one!',
        es: () => '¡Tu canción del día ha caducado! Publica una nueva.',
        fr: () => 'Votre chanson du jour a expiré. Partagez-en une nouvelle !',
    },
};
// ── Helper ────────────────────────────────────────────────────────────────────
function notifChannelId(sound, vibration) {
    if (sound && vibration)
        return 'musilink_high';
    if (sound && !vibration)
        return 'musilink_high_no_vibration';
    if (!sound && vibration)
        return 'musilink_high_no_sound';
    return 'musilink_high_silent';
}
function notificationPath(data) {
    if (data.type === 'new_message' && data.chatId && data.otherUserId) {
        const query = new URLSearchParams({
            chatId: data.chatId,
            otherUserId: data.otherUserId,
            ...(data.otherUserName ? { otherUserName: data.otherUserName } : {}),
        });
        return `/chat?${query.toString()}`;
    }
    if (data.type === 'friend_request' ||
        data.type === 'friend_request_accepted') {
        return '/?tab=friends';
    }
    if (data.type === 'daily_song_expired') {
        return '/?tab=daily-song';
    }
    return '/';
}
async function expireDailySong(userRef, expiresBefore) {
    return db.runTransaction(async (transaction) => {
        const current = await transaction.get(userRef);
        const data = current.data();
        const updatedAt = data?.dailySongUpdatedAt;
        if (!(updatedAt instanceof firestore_2.Timestamp) ||
            updatedAt.toMillis() > expiresBefore.toMillis()) {
            return false;
        }
        // Avoid an orphaned legacy timestamp blocking the oldest-results query.
        if (!data?.dailySong) {
            transaction.update(userRef, {
                dailySongUpdatedAt: firestore_2.FieldValue.delete(),
            });
            return false;
        }
        transaction.update(userRef, {
            dailySong: firestore_2.FieldValue.delete(),
            dailySongUpdatedAt: firestore_2.FieldValue.delete(),
        });
        return true;
    });
}
// Notifications with the same tag replace each other in the drawer, keeping
// one entry per conversation instead of an unbounded stack.
async function sendNotification(recipientUid, recipientPrivateData, notification, data, tag) {
    const sound = recipientPrivateData?.notifSound !== false;
    const vibration = recipientPrivateData?.notifVibration !== false;
    const channelId = notifChannelId(sound, vibration);
    const isChatMessage = data.type === 'new_message';
    const privateUserRef = db.doc(`${userPrivateCollection}/${recipientUid}`);
    const pushTokensSnapshot = await privateUserRef
        .collection(pushTokensSubcollection)
        .limit(20)
        .get();
    const targets = new Map();
    for (const tokenDoc of pushTokensSnapshot.docs) {
        const token = tokenDoc.data().token;
        if (typeof token === 'string' && token.length > 0) {
            targets.set(token, tokenDoc.ref);
        }
    }
    if (targets.size === 0)
        return;
    await Promise.all([...targets].map(async ([token, tokenRef]) => {
        try {
            await messaging.send({
                token,
                // A top-level `notification` is rendered by Android's FCM SDK before
                // Flutter can process it. Chat messages must instead be data-only on
                // Android so the client can update one MessagingStyle notification.
                ...(!isChatMessage ? { notification } : {}),
                data,
                android: {
                    priority: 'high',
                    // A platform notification block makes FCM treat the push as a
                    // notification message on Android. For chats that would create an
                    // additional empty system notification before the data-only handler
                    // builds the app's MessagingStyle notification.
                    ...(!isChatMessage
                        ? {
                            notification: {
                                channelId,
                                ...(tag ? { tag } : {}),
                            },
                        }
                        : {}),
                },
                apns: {
                    ...(tag
                        ? { headers: { 'apns-collapse-id': tag.slice(0, 64) } }
                        : {}),
                    payload: {
                        aps: {
                            // iOS cannot build Android's MessagingStyle notification, so it
                            // keeps its native grouped alert per conversation.
                            ...(isChatMessage ? { alert: notification } : {}),
                            ...(sound ? { sound: 'default' } : {}),
                        },
                    },
                },
                webpush: {
                    notification: {
                        ...notification,
                        icon: '/icons/Icon-192.png',
                        badge: '/icons/Icon-192.png',
                        data: { path: notificationPath(data) },
                        ...(tag ? { tag } : {}),
                        ...(!sound ? { silent: true } : {}),
                    },
                    data: {
                        ...data,
                        notificationPath: notificationPath(data),
                    },
                },
            });
        }
        catch (error) {
            const fcmError = error;
            if (fcmError.code === 'messaging/registration-token-not-registered') {
                await tokenRef.delete();
                return;
            }
            v2_1.logger.error('sendNotification: unexpected FCM error', {
                recipientUid,
                error,
            });
            throw error;
        }
    }));
}
function preferredLocale(data) {
    const locale = data?.preferredLocale;
    if (typeof locale !== 'string')
        return defaultLocale;
    const languageCode = locale.toLowerCase().split(/[-_]/)[0];
    return supportedLocales.has(languageCode)
        ? languageCode
        : defaultLocale;
}
async function shouldNotifyFriendRequest(senderId, receiverId) {
    const limitRef = db
        .collection(friendRequestNotificationLimitsCollection)
        .doc(`${senderId}_${receiverId}`);
    return db.runTransaction(async (tx) => {
        const limitSnap = await tx.get(limitRef);
        const lastNotifiedAt = limitSnap.data()?.lastNotifiedAt;
        const now = firestore_2.Timestamp.now();
        if (lastNotifiedAt &&
            now.toMillis() - lastNotifiedAt.toMillis() < friendRequestNotificationCooldownMs) {
            return false;
        }
        tx.set(limitRef, {
            senderId,
            receiverId,
            lastNotifiedAt: now,
        }, { merge: true });
        return true;
    });
}
function stringList(value) {
    if (!Array.isArray(value))
        return [];
    return value
        .filter((item) => typeof item === 'string')
        .map((item) => item.trim())
        .filter((item) => item.length > 0);
}
function userHasBlocked(data, otherUid) {
    return stringList(data?.blockedUsers).includes(otherUid);
}
async function establishAcceptedFriendship(requestId, expectedReceiverId, expectedSenderId) {
    const requestRef = db.collection('friend_requests').doc(requestId);
    return db.runTransaction(async (tx) => {
        const requestSnap = await tx.get(requestRef);
        if (!requestSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Friend request not found.');
        }
        const requestData = requestSnap.data();
        const senderId = requestData?.senderId;
        const receiverId = requestData?.receiverId;
        const status = requestData?.status;
        if (typeof senderId !== 'string' ||
            typeof receiverId !== 'string' ||
            senderId === receiverId ||
            (status !== 'pending' && status !== 'accepted')) {
            throw new https_1.HttpsError('failed-precondition', 'Invalid friend request.');
        }
        if (expectedReceiverId !== undefined && receiverId !== expectedReceiverId) {
            throw new https_1.HttpsError('permission-denied', 'Only the receiver can accept this request.');
        }
        if (expectedSenderId !== undefined && senderId !== expectedSenderId) {
            throw new https_1.HttpsError('failed-precondition', 'Unexpected friend request sender.');
        }
        const senderPrivateRef = db.doc(`${userPrivateCollection}/${senderId}`);
        const receiverPrivateRef = db.doc(`${userPrivateCollection}/${receiverId}`);
        const senderPublicRef = db.doc(`users/${senderId}`);
        const receiverPublicRef = db.doc(`users/${receiverId}`);
        const inverseRef = db.collection('friend_requests').doc(`${receiverId}_${senderId}`);
        const [senderPrivate, receiverPrivate, senderPublic, receiverPublic, inverse] = await Promise.all([
            tx.get(senderPrivateRef),
            tx.get(receiverPrivateRef),
            tx.get(senderPublicRef),
            tx.get(receiverPublicRef),
            tx.get(inverseRef),
        ]);
        if (!senderPrivate.exists ||
            !receiverPrivate.exists ||
            !senderPublic.exists ||
            !receiverPublic.exists ||
            senderPublic.data()?.username === 'deleted_user' ||
            receiverPublic.data()?.username === 'deleted_user') {
            throw new https_1.HttpsError('failed-precondition', 'Both users must be active.');
        }
        if (userHasBlocked(senderPrivate.data(), receiverId) ||
            userHasBlocked(receiverPrivate.data(), senderId)) {
            throw new https_1.HttpsError('failed-precondition', 'Blocked users cannot become friends.');
        }
        tx.update(senderPrivateRef, { friends: firestore_2.FieldValue.arrayUnion(receiverId) });
        tx.update(receiverPrivateRef, { friends: firestore_2.FieldValue.arrayUnion(senderId) });
        if (status === 'pending') {
            tx.update(requestRef, {
                status: 'accepted',
                updatedAt: firestore_2.FieldValue.serverTimestamp(),
            });
        }
        if (inverse.exists && inverseRef.path !== requestRef.path)
            tx.delete(inverseRef);
        return { senderId, receiverId };
    });
}
function readMusicProfile(data) {
    const topArtistNames = stringList(data?.topArtistNames).slice(0, maxRecommendationInputArtists);
    return {
        topArtistNames,
        topArtistKeys: readArtistIdentityKeys(data, topArtistNames),
        topGenreNames: stringList(data?.topGenreNames).slice(0, maxRecommendationInputGenres),
    };
}
function readPublicProfileSnapshot(data) {
    const displayName = typeof data?.displayName === 'string' ? data.displayName.trim() : '';
    const username = typeof data?.username === 'string' ? data.username.trim() : '';
    const photoUrl = typeof data?.photoUrl === 'string' ? data.photoUrl.trim() : '';
    if (displayName.length === 0 || username.length === 0)
        return undefined;
    return {
        displayName,
        username,
        photoUrl,
        ...readMusicProfile(data),
    };
}
function publicProfileIdentityChanged(before, after) {
    if (!before || !after)
        return before !== after;
    return before.displayName !== after.displayName ||
        before.username !== after.username ||
        before.photoUrl !== after.photoUrl;
}
function sameStringList(left, right) {
    if (left.length !== right.length)
        return false;
    return left.every((value, index) => value === right[index]);
}
function musicProfileChanged(before, after) {
    return !sameStringList(before.topArtistNames, after.topArtistNames) ||
        !sameStringList(before.topArtistKeys, after.topArtistKeys) ||
        !sameStringList(before.topGenreNames, after.topGenreNames);
}
function timestampMillis(value) {
    return value instanceof firestore_2.Timestamp ? value.toMillis() : undefined;
}
function timestampValue(value) {
    return value instanceof firestore_2.Timestamp ? value : undefined;
}
function messageSummary(data) {
    if (data.type === 'track') {
        const title = data.trackData?.title;
        if (typeof title === 'string' && title.length > 0)
            return `🎵 ${title}`;
    }
    return typeof data.text === 'string' ? data.text : '';
}
function chatParticipants(data) {
    if (!Array.isArray(data?.participants))
        return [];
    return data.participants.filter((value) => typeof value === 'string');
}
function fullySoftDeletedChat(data) {
    const participants = chatParticipants(data);
    if (participants.length !== 2)
        return false;
    const lastMessageTime = timestampValue(data?.lastMessageTime);
    const deletedAt = data?.deletedAt;
    if (!lastMessageTime || !deletedAt)
        return false;
    return participants.every((uid) => {
        const deletedTime = timestampValue(deletedAt[uid]);
        return deletedTime !== undefined && lastMessageTime.toMillis() <= deletedTime.toMillis();
    });
}
function allParticipantsDeletedBefore(data) {
    const participants = chatParticipants(data);
    if (participants.length !== 2)
        return undefined;
    const deletedAt = data?.deletedAt;
    if (!deletedAt)
        return undefined;
    const deletedTimes = participants
        .map((uid) => timestampValue(deletedAt[uid]))
        .filter((value) => value !== undefined);
    if (deletedTimes.length !== participants.length)
        return undefined;
    return deletedTimes.reduce((earliest, value) => value.toMillis() < earliest.toMillis() ? value : earliest, deletedTimes[0]);
}
async function deleteChatMessages(chatRef) {
    const messagesRef = chatRef.collection(messagesCollection);
    while (true) {
        const snapshot = await messagesRef.limit(chatCleanupBatchSize).get();
        if (snapshot.empty)
            return;
        const batch = db.batch();
        snapshot.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        if (snapshot.size < chatCleanupBatchSize)
            return;
    }
}
async function hardDeleteChat(chatRef) {
    await deleteChatMessages(chatRef);
    await chatRef.delete();
}
async function pruneMessagesDeletedForAllParticipants(chatRef, chatData) {
    const pruneBefore = allParticipantsDeletedBefore(chatData);
    if (!pruneBefore)
        return 0;
    const messagesRef = chatRef.collection(messagesCollection);
    let deletedCount = 0;
    while (true) {
        const snapshot = await messagesRef
            .where('timestamp', '<=', pruneBefore)
            .orderBy('timestamp')
            .limit(chatCleanupBatchSize)
            .get();
        if (snapshot.empty)
            return deletedCount;
        const batch = db.batch();
        snapshot.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deletedCount += snapshot.size;
        if (snapshot.size < chatCleanupBatchSize)
            return deletedCount;
    }
}
async function latestMessageSnapshot(chatRef) {
    const snapshot = await chatRef
        .collection(messagesCollection)
        .orderBy('timestamp', 'desc')
        .limit(1)
        .get();
    return snapshot.docs[0];
}
async function refreshChatSummaryFromLatestMessage(chatRef) {
    const latest = await latestMessageSnapshot(chatRef);
    if (!latest) {
        await chatRef.delete();
        return false;
    }
    const latestData = latest.data();
    await chatRef.update({
        lastMessage: messageSummary(latestData),
        lastMessageTime: timestampValue(latestData.timestamp) ?? firestore_2.FieldValue.serverTimestamp(),
    });
    return true;
}
function recommendationRefreshRequested(before, after) {
    const beforeMillis = timestampMillis(before?.recommendationsRefreshRequestedAt);
    const afterMillis = timestampMillis(after?.recommendationsRefreshRequestedAt);
    return afterMillis !== undefined && afterMillis !== beforeMillis;
}
function normalizedMusicKey(value) {
    return value.trim().toLowerCase();
}
const artistDiacriticGroups = {
    a: 'áàäâãåāăąæ',
    c: 'çćčĉċ',
    d: 'ďđð',
    e: 'éèëêēĕėęě',
    g: 'ğĝġģ',
    h: 'ĥħ',
    i: 'íìïîīĭįı',
    j: 'ĵ',
    k: 'ķ',
    l: 'ĺļľŀł',
    n: 'ñńņňŉŋ',
    o: 'óòöôõōŏőøœ',
    r: 'ŕŗř',
    s: 'śşšŝșß',
    t: 'ťţŧț',
    u: 'úùüûūŭůűų',
    w: 'ŵ',
    y: 'ýÿŷ',
    z: 'źżž',
};
const artistDiacriticReplacements = new Map(Object.entries(artistDiacriticGroups)
    .flatMap(([replacement, characters]) => [...characters].map((character) => [character, replacement])));
function normalizeArtistIdentityName(value) {
    const folded = [...value.trim().toLowerCase()]
        .map((character) => artistDiacriticReplacements.get(character) ?? character)
        .join('');
    return folded
        .replace(/['’]/g, '')
        .replace(/&/g, ' and ')
        .replace(/[-_/.,:;!?()[\]{}"“”+*=|\\]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}
function fallbackArtistIdentityKey(name) {
    return `name:${normalizeArtistIdentityName(name)}`;
}
function normalizedStoredArtistKey(value) {
    const trimmed = value.trim();
    if (trimmed.startsWith('spotify:')) {
        const spotifyId = trimmed.slice('spotify:'.length).trim();
        return spotifyId ? `spotify:${spotifyId}` : undefined;
    }
    if (trimmed.startsWith('name:')) {
        const name = normalizeArtistIdentityName(trimmed.slice('name:'.length));
        return name ? `name:${name}` : undefined;
    }
    return undefined;
}
function readArtistIdentityKeys(data, names) {
    const storedKeys = stringList(data?.topArtistKeys)
        .slice(0, maxRecommendationInputArtists);
    const storedArtists = Array.isArray(data?.topArtists) ? data.topArtists : [];
    return names.map((name, index) => {
        const rawArtist = storedArtists[index];
        const rawName = typeof rawArtist?.name === 'string' ? rawArtist.name.trim() : '';
        const spotifyId = typeof rawArtist?.spotifyId === 'string' ? rawArtist.spotifyId.trim() : '';
        if (normalizeArtistIdentityName(rawName) === normalizeArtistIdentityName(name)) {
            return spotifyId
                ? `spotify:${spotifyId}`
                : fallbackArtistIdentityKey(name);
        }
        const storedKey = normalizedStoredArtistKey(storedKeys[index] ?? '');
        if (storedKey)
            return storedKey;
        return fallbackArtistIdentityKey(name);
    });
}
function artistIdentities(profile) {
    const artistsByKey = new Map();
    profile.topArtistNames.forEach((rawName, index) => {
        const name = rawName.trim();
        const normalizedName = normalizeArtistIdentityName(name);
        if (!normalizedName)
            return;
        const key = normalizedStoredArtistKey(profile.topArtistKeys[index] ?? '') ??
            `name:${normalizedName}`;
        if (!artistsByKey.has(key))
            artistsByKey.set(key, { name, key, normalizedName });
    });
    return [...artistsByKey.values()];
}
function artistIdentitiesMatch(left, right) {
    const leftHasSpotifyId = left.key.startsWith('spotify:');
    const rightHasSpotifyId = right.key.startsWith('spotify:');
    if (leftHasSpotifyId && rightHasSpotifyId)
        return left.key === right.key;
    return left.normalizedName === right.normalizedName;
}
function sharedArtistNames(leftArtists, rightArtists) {
    const usedLeftIndexes = new Set();
    const shared = [];
    for (const rightArtist of rightArtists) {
        const leftIndex = leftArtists.findIndex((leftArtist, index) => !usedLeftIndexes.has(index) &&
            artistIdentitiesMatch(leftArtist, rightArtist));
        if (leftIndex < 0)
            continue;
        usedLeftIndexes.add(leftIndex);
        shared.push(rightArtist.name);
    }
    return shared;
}
function uniqueMusicNames(values) {
    const namesByKey = new Map();
    for (const value of values) {
        const trimmed = value.trim();
        const key = normalizedMusicKey(trimmed);
        if (key.length > 0 && !namesByKey.has(key))
            namesByKey.set(key, trimmed);
    }
    return [...namesByKey.values()];
}
function similarityScore(sharedCount, leftCount, rightCount, evidenceTarget, weight) {
    if (sharedCount === 0)
        return 0;
    const comparableCount = Math.min(leftCount, rightCount);
    const coverage = comparableCount === 0 ? 0 : sharedCount / comparableCount;
    const evidence = Math.min(sharedCount / evidenceTarget, 1);
    return Math.max(coverage, evidence) * weight;
}
function artistMatchKeys(profile) {
    return [...new Set(artistIdentities(profile)
            .map((artist) => artist.normalizedName)
            .filter((value) => value.length > 0))].slice(0, maxRecommendationInputArtists);
}
function genreMatchKeys(profile) {
    return [...new Set(profile.topGenreNames
            .map(normalizedMusicKey)
            .filter((value) => value.length > 0))].slice(0, maxRecommendationInputGenres);
}
function chunks(values, size) {
    const result = [];
    for (let index = 0; index < values.length; index += size) {
        result.push(values.slice(index, index + size));
    }
    return result;
}
function candidateProfileFromData(uid, data) {
    const topArtistNames = stringList(data.topArtistNames)
        .slice(0, maxRecommendationInputArtists);
    const topArtistKeys = stringList(data.topArtistKeys)
        .slice(0, maxRecommendationInputArtists);
    const topGenreNames = stringList(data.topGenreNames)
        .slice(0, maxRecommendationInputGenres);
    if (topArtistNames.length === 0 && topGenreNames.length === 0)
        return undefined;
    return { uid, topArtistNames, topArtistKeys, topGenreNames };
}
async function addCandidateMatches(uid, field, values, limitPerQuery, candidates) {
    if (values.length === 0)
        return 0;
    const snapshots = await Promise.all(chunks(values, 30).map((page) => db
        .collection(recommendationProfilesCollection)
        .where(field, 'array-contains-any', page)
        .orderBy('updatedAt', 'desc')
        .limit(limitPerQuery)
        .get()));
    let documentsRead = 0;
    for (const snapshot of snapshots) {
        documentsRead += snapshot.size;
        for (const doc of snapshot.docs) {
            if (doc.id === uid || candidates.has(doc.id))
                continue;
            const candidate = candidateProfileFromData(doc.id, doc.data());
            if (candidate)
                candidates.set(doc.id, candidate);
        }
    }
    return documentsRead;
}
async function findCandidateProfiles(uid, profiles) {
    const artists = [...new Set(profiles.flatMap(artistMatchKeys))];
    const genres = [...new Set(profiles.flatMap(genreMatchKeys))];
    const candidates = new Map();
    const [artistDocumentsRead, genreDocumentsRead] = await Promise.all([
        addCandidateMatches(uid, 'artistMatchKeys', artists, maxArtistCandidateProfiles, candidates),
        addCandidateMatches(uid, 'genreMatchKeys', genres, maxGenreCandidateProfiles, candidates),
    ]);
    return {
        candidates,
        documentsRead: artistDocumentsRead + genreDocumentsRead,
    };
}
function userDocRef(uid) {
    return db.collection('users').doc(uid);
}
async function keepDeletedProfileMinimal(uid, data) {
    if (data?.username !== 'deleted_user')
        return;
    const current = await userDocRef(uid).get();
    const currentData = current.data();
    const minimal = currentData?.displayName === 'Deleted user' &&
        currentData?.username === 'deleted_user' &&
        currentData?.photoUrl === '' &&
        Object.keys(currentData ?? {}).length === 3;
    if (minimal)
        return;
    await userDocRef(uid).set({
        displayName: 'Deleted user',
        username: 'deleted_user',
        photoUrl: '',
    });
}
async function commitBatches(operations) {
    const batchSize = 400;
    for (let i = 0; i < operations.length; i += batchSize) {
        const batch = db.batch();
        operations.slice(i, i + batchSize).forEach((operation) => operation(batch));
        await batch.commit();
    }
}
function recommendationSnapshotData(snapshot, generatedAt) {
    return {
        snapshotVersion: recommendationSnapshotVersion,
        profileSnapshot: {
            displayName: snapshot.displayName,
            username: snapshot.username,
            photoUrl: snapshot.photoUrl,
            topArtistNames: snapshot.topArtistNames,
            topGenreNames: snapshot.topGenreNames,
        },
        snapshotGeneratedAt: generatedAt,
    };
}
async function loadPublicProfileSnapshots(uids) {
    if (uids.length === 0)
        return new Map();
    const snapshots = await db.getAll(...uids.map(userDocRef));
    const profiles = new Map();
    for (const snapshot of snapshots) {
        const profile = readPublicProfileSnapshot(snapshot.data());
        if (snapshot.exists && profile)
            profiles.set(snapshot.id, profile);
    }
    return profiles;
}
async function updateStoredProfileSnapshots(uid, snapshot) {
    const generatedAt = firestore_2.Timestamp.now();
    const recommendations = await db
        .collectionGroup(recommendationsCollection)
        .where('userId', '==', uid)
        .get();
    if (recommendations.empty)
        return;
    await commitBatches(recommendations.docs.map((doc) => (batch) => {
        batch.set(doc.ref, recommendationSnapshotData(snapshot, generatedAt), { merge: true });
    }));
    v2_1.logger.info('updateStoredProfileSnapshots: updated recommendation snapshots', {
        uid,
        recommendationCount: recommendations.size,
    });
}
async function updateRecommendationProfile(uid, profile) {
    const ref = db.collection(recommendationProfilesCollection).doc(uid);
    const artistKeys = artistMatchKeys(profile);
    const genreKeys = genreMatchKeys(profile);
    if (artistKeys.length === 0 && genreKeys.length === 0) {
        await ref.delete();
        return;
    }
    await ref.set({
        uid,
        schemaVersion: recommendationProfileSchemaVersion,
        artistMatchKeys: artistKeys,
        genreMatchKeys: genreKeys,
        topArtistNames: profile.topArtistNames,
        topArtistKeys: profile.topArtistKeys,
        topGenreNames: profile.topGenreNames,
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
}
function calculateRecommendation(myProfile, candidate) {
    const myArtists = artistIdentities(myProfile);
    const candidateArtists = artistIdentities(candidate);
    const myGenreNames = uniqueMusicNames(myProfile.topGenreNames);
    const candidateGenreNames = uniqueMusicNames(candidate.topGenreNames);
    const myGenres = new Set(myGenreNames.map(normalizedMusicKey));
    const matchingArtistNames = sharedArtistNames(myArtists, candidateArtists);
    const sharedGenreNames = candidateGenreNames.filter((genre) => myGenres.has(normalizedMusicKey(genre)));
    if (matchingArtistNames.length === 0 && sharedGenreNames.length === 0)
        return null;
    const artistScore = similarityScore(matchingArtistNames.length, myArtists.length, candidateArtists.length, artistEvidenceTarget, artistScoreWeight);
    const genreScore = similarityScore(sharedGenreNames.length, myGenreNames.length, candidateGenreNames.length, genreEvidenceTarget, genreScoreWeight);
    return {
        uid: candidate.uid,
        score: Math.round(artistScore + genreScore),
        sharedArtistNames: matchingArtistNames,
        sharedGenreNames,
    };
}
async function deleteExistingRecommendations(uid) {
    const existing = await db
        .collection(`users/${uid}/${recommendationsCollection}`)
        .get();
    if (existing.empty)
        return;
    await commitBatches(existing.docs.map((doc) => (batch) => batch.delete(doc.ref)));
}
async function deleteStaleRecommendations(uid, currentRecommendationIds) {
    const existing = await db
        .collection(`users/${uid}/${recommendationsCollection}`)
        .get();
    const staleDocs = existing.docs.filter((doc) => !currentRecommendationIds.has(doc.id));
    if (staleDocs.length === 0)
        return;
    await commitBatches(staleDocs.map((doc) => (batch) => batch.delete(doc.ref)));
}
async function refreshRecommendations(uid, profile) {
    const generatedAt = firestore_2.Timestamp.now();
    if (profile.topArtistNames.length === 0 && profile.topGenreNames.length === 0) {
        await deleteExistingRecommendations(uid);
        await userDocRef(uid).update({
            recommendationsGeneratedAt: generatedAt,
            recommendationsCount: 0,
        });
        return;
    }
    const { candidates, documentsRead } = await findCandidateProfiles(uid, [profile]);
    const calculatedRecommendations = [...candidates.values()]
        .map((candidate) => calculateRecommendation(profile, candidate))
        .filter((result) => result !== null)
        .sort((a, b) => b.score - a.score)
        .slice(0, maxStoredRecommendations);
    const profilesByUid = await loadPublicProfileSnapshots(calculatedRecommendations.map((recommendation) => recommendation.uid));
    const recommendations = calculatedRecommendations.flatMap((recommendation) => {
        const profileSnapshot = profilesByUid.get(recommendation.uid);
        return profileSnapshot ? [{ recommendation, profileSnapshot }] : [];
    });
    const recommendationIds = new Set(recommendations.map(({ recommendation }) => recommendation.uid));
    await commitBatches(recommendations.map(({ recommendation, profileSnapshot }) => (batch) => {
        batch.set(db.doc(`users/${uid}/${recommendationsCollection}/${recommendation.uid}`), {
            userId: recommendation.uid,
            score: recommendation.score,
            sharedArtistNames: recommendation.sharedArtistNames,
            sharedGenreNames: recommendation.sharedGenreNames,
            generatedAt,
            ...recommendationSnapshotData(profileSnapshot, generatedAt),
        });
    }));
    await deleteStaleRecommendations(uid, recommendationIds);
    await userDocRef(uid).update({
        recommendationsGeneratedAt: generatedAt,
        recommendationsCount: recommendations.length,
    });
    v2_1.logger.info('refreshRecommendations: generated recommendations', {
        uid,
        candidateDocumentsRead: documentsRead,
        candidateCount: candidates.size,
        recommendationCount: recommendations.length,
    });
}
async function matchingCandidateProfiles(uid, profiles) {
    const { candidates } = await findCandidateProfiles(uid, profiles);
    return new Map([...candidates.entries()].slice(0, maxReciprocalRecommendationUsers));
}
async function updateReciprocalRecommendations(uid, profile, profileSnapshot, candidates) {
    const generatedAt = firestore_2.Timestamp.now();
    await commitBatches([...candidates.values()].map((candidate) => (batch) => {
        const recommendation = calculateRecommendation(candidate, {
            uid,
            topArtistNames: profile.topArtistNames,
            topArtistKeys: profile.topArtistKeys,
            topGenreNames: profile.topGenreNames,
        });
        const ref = db.doc(`users/${candidate.uid}/${recommendationsCollection}/${uid}`);
        if (recommendation === null) {
            batch.delete(ref);
            return;
        }
        batch.set(ref, {
            userId: uid,
            score: recommendation.score,
            sharedArtistNames: recommendation.sharedArtistNames,
            sharedGenreNames: recommendation.sharedGenreNames,
            generatedAt,
            ...recommendationSnapshotData(profileSnapshot, generatedAt),
        });
    }));
    v2_1.logger.info('updateReciprocalRecommendations: updated candidates', {
        uid,
        candidateCount: candidates.size,
    });
}
async function rebuildMusicRecommendations(uid, before, after, profileSnapshot, options = {}) {
    const profileChanged = musicProfileChanged(before, after);
    const forceSelfRefresh = options.forceSelfRefresh === true;
    if (!profileChanged && !forceSelfRefresh)
        return;
    const reciprocalCandidates = profileChanged
        ? await matchingCandidateProfiles(uid, [before, after])
        : new Map();
    if (profileChanged)
        await updateRecommendationProfile(uid, after);
    await refreshRecommendations(uid, after);
    if (profileChanged) {
        await updateReciprocalRecommendations(uid, after, profileSnapshot, reciprocalCandidates);
    }
}
// ── Función 1 — Nuevo mensaje ─────────────────────────────────────────────────
exports.onNewMessage = (0, firestore_1.onDocumentCreated)({ document: 'chats/{chatId}/messages/{messageId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const messageSnapshot = event.data;
        if (!messageSnapshot)
            return;
        const message = messageSnapshot.data();
        if (!message)
            return;
        const chatId = event.params.chatId;
        const senderId = message.senderId;
        const chatRef = db.doc(`chats/${chatId}`);
        const messageRef = messageSnapshot.ref;
        const summaryResult = await db.runTransaction(async (tx) => {
            const [chatSnap, currentMessageSnap] = await Promise.all([
                tx.get(chatRef),
                tx.get(messageRef),
            ]);
            const chatData = chatSnap.data();
            const currentMessage = currentMessageSnap.data();
            if (!chatData || !currentMessage || currentMessage.summaryApplied === true) {
                return undefined;
            }
            const participants = chatParticipants(chatData);
            if (participants.length !== 2 || !participants.includes(senderId))
                return undefined;
            const recipientId = participants.find((uid) => uid !== senderId);
            const messageTime = timestampValue(currentMessage.timestamp);
            if (!recipientId || !messageTime)
                return undefined;
            const updates = {};
            const currentLastMessageTime = timestampValue(chatData.lastMessageTime);
            const summary = messageSummary(currentMessage);
            if (!currentLastMessageTime || messageTime.toMillis() >= currentLastMessageTime.toMillis()) {
                updates.lastMessage = summary;
                updates.lastMessageTime = messageTime;
            }
            if (currentMessage.read !== true) {
                updates[`unreadCounts.${recipientId}`] = firestore_2.FieldValue.increment(1);
            }
            if (Object.keys(updates).length > 0)
                tx.update(chatRef, updates);
            tx.update(messageRef, { summaryApplied: true });
            return { recipientId };
        });
        if (!summaryResult)
            return;
        const { recipientId } = summaryResult;
        const [recipientSnap, senderSnap] = await Promise.all([
            db.doc(`${userPrivateCollection}/${recipientId}`).get(),
            db.doc(`users/${senderId}`).get(),
        ]);
        const senderName = senderSnap.data()?.displayName;
        const senderPhotoUrl = senderSnap.data()?.photoUrl;
        if (!senderName)
            return;
        // Android receives this as a data-only message so the app can render a
        // single MessagingStyle notification containing the recent messages of
        // this conversation. iOS still receives a regular APNs alert below.
        await sendNotification(recipientId, recipientSnap.data(), { title: senderName, body: message.text ?? '📎' }, {
            type: 'new_message',
            chatId,
            otherUserId: senderId,
            otherUserName: senderName,
            messageText: message.text ?? '📎',
            ...(senderPhotoUrl ? { senderPhotoUrl } : {}),
        }, chatId);
    }
    catch (error) {
        v2_1.logger.error('onNewMessage: unhandled error', { chatId: event.params.chatId, error });
        throw error;
    }
});
// ── Función 2 — Recomendaciones musicales ─────────────────────────────────────
// Rebuilds recommendation lists when a user's music taste changes.
// The changed user's full list is rebuilt, and matching existing users get a
// reciprocal recommendation upsert/delete so discovery does not wait for them
// to edit their own profile.
exports.onUserMusicProfileCreated = (0, firestore_1.onDocumentCreated)({ document: 'users/{userId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const afterData = event.data?.data();
        const after = readMusicProfile(afterData);
        const profileSnapshot = readPublicProfileSnapshot(afterData);
        if (!profileSnapshot) {
            throw new Error('A valid public profile is required to build recommendations.');
        }
        await rebuildMusicRecommendations(event.params.userId, {
            topArtistNames: [],
            topArtistKeys: [],
            topGenreNames: [],
        }, after, profileSnapshot);
        await keepDeletedProfileMinimal(event.params.userId, afterData);
    }
    catch (error) {
        v2_1.logger.error('onUserMusicProfileCreated: unhandled error', {
            userId: event.params.userId,
            error,
        });
        throw error;
    }
});
exports.onUserMusicProfileChanged = (0, firestore_1.onDocumentUpdated)({ document: 'users/{userId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const beforeData = event.data?.before.data();
        const afterData = event.data?.after.data();
        const before = readMusicProfile(beforeData);
        const after = readMusicProfile(afterData);
        const beforeSnapshot = readPublicProfileSnapshot(beforeData);
        const afterSnapshot = readPublicProfileSnapshot(afterData);
        if (!afterSnapshot) {
            throw new Error('A valid public profile is required to update recommendations.');
        }
        await rebuildMusicRecommendations(event.params.userId, before, after, afterSnapshot, {
            forceSelfRefresh: recommendationRefreshRequested(beforeData, afterData),
        });
        if (publicProfileIdentityChanged(beforeSnapshot, afterSnapshot)) {
            await updateStoredProfileSnapshots(event.params.userId, afterSnapshot);
        }
        await keepDeletedProfileMinimal(event.params.userId, afterData);
    }
    catch (error) {
        v2_1.logger.error('onUserMusicProfileChanged: unhandled error', {
            userId: event.params.userId,
            error,
        });
        throw error;
    }
});
// ── Alta atómica de perfil y reserva de username ─────────────────────────────
exports.createUserProfile = (0, https_1.onCall)({ region: 'europe-southwest1' }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    }
    const email = typeof request.auth?.token.email === 'string'
        ? request.auth.token.email
        : '';
    try {
        return await (0, username_claim_1.claimUsernameAndCreateProfile)(db, uid, email, request.data);
    }
    catch (error) {
        if (error instanceof https_1.HttpsError)
            throw error;
        v2_1.logger.error('createUserProfile: unhandled error', { uid, error });
        throw new https_1.HttpsError('internal', 'Could not create the user profile.');
    }
});
// ── Función 3 — Aceptación privilegiada de amistad ───────────────────────────
exports.acceptFriendRequest = (0, https_1.onCall)({ region: 'europe-southwest1' }, async (request) => {
    const receiverId = request.auth?.uid;
    if (!receiverId) {
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    }
    const data = request.data;
    const requestId = data?.requestId;
    const senderId = data?.senderId;
    if (typeof requestId !== 'string' || requestId.length === 0 || requestId.length > 300 ||
        typeof senderId !== 'string' || senderId.length === 0 || senderId.length > 128) {
        throw new https_1.HttpsError('invalid-argument', 'Valid requestId and senderId values are required.');
    }
    await establishAcceptedFriendship(requestId, receiverId, senderId);
    return { ok: true };
});
// ── Función 4 — Nueva solicitud de amistad ────────────────────────────────────
exports.onFriendRequest = (0, firestore_1.onDocumentCreated)({ document: 'friend_requests/{requestId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const request = event.data?.data();
        if (!request)
            return;
        if (request.status !== 'pending')
            return;
        const senderId = request.senderId;
        const receiverId = request.receiverId;
        if (!await shouldNotifyFriendRequest(senderId, receiverId))
            return;
        const [receiverSnap, senderSnap] = await Promise.all([
            db.doc(`${userPrivateCollection}/${receiverId}`).get(),
            db.doc(`users/${senderId}`).get(),
        ]);
        const receiver = receiverSnap.data();
        const senderName = senderSnap.data()?.displayName;
        if (!senderName)
            return;
        const locale = preferredLocale(receiver);
        await sendNotification(receiverId, receiver, { title: 'MusiLink', body: notificationText.friendRequest[locale](senderName) }, { type: 'friend_request', senderId }, `friend_request_${senderId}`);
    }
    catch (error) {
        v2_1.logger.error('onFriendRequest: unhandled error', { requestId: event.params.requestId, error });
        throw error;
    }
});
// ── Función 5 — Solicitud de amistad aceptada ─────────────────────────────────
exports.onFriendRequestAccepted = (0, firestore_1.onDocumentUpdated)({ document: 'friend_requests/{requestId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const change = event.data;
        if (!change)
            return;
        const before = change.before.data();
        const after = change.after.data();
        if (!before || !after)
            return;
        if (before.status !== 'pending' || after.status !== 'accepted')
            return;
        const senderId = after.senderId;
        const receiverId = after.receiverId;
        // La callable marca la solicitud como aceptada; este trigger completa
        // ambos lados de la amistad y envía la notificación.
        try {
            await establishAcceptedFriendship(event.params.requestId, receiverId);
        }
        catch (error) {
            if (!(error instanceof https_1.HttpsError))
                throw error;
            v2_1.logger.warn('onFriendRequestAccepted: friendship rejected', {
                requestId: event.params.requestId,
                error,
            });
            await change.after.ref.delete();
            return;
        }
        const [senderSnap, receiverSnap] = await Promise.all([
            db.doc(`${userPrivateCollection}/${senderId}`).get(),
            db.doc(`users/${receiverId}`).get(),
        ]);
        const sender = senderSnap.data();
        const accepterName = receiverSnap.data()?.displayName;
        if (accepterName) {
            const locale = preferredLocale(sender);
            await sendNotification(senderId, sender, { title: 'MusiLink', body: notificationText.friendRequestAccepted[locale](accepterName) }, { type: 'friend_request_accepted', accepterId: receiverId });
        }
        await db.doc(event.document).delete();
    }
    catch (error) {
        v2_1.logger.error('onFriendRequestAccepted: unhandled error', { requestId: event.params.requestId, error });
        throw error;
    }
});
// ── Caducidad de canciones del día ──────────────────────────────────────────
// Firestore keeps the publication time on the public profile. This job removes
// every song whose 24-hour window has ended and then reminds its owner to post
// another one. The transaction protects a replacement song published while
// this query is running.
exports.expireDailySongs = (0, scheduler_1.onSchedule)({
    schedule: 'every 1 minutes',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    // Keep this scheduled function in the nearest broadly supported EU region.
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 300,
    retryCount: 3,
}, async () => {
    const expiresBefore = firestore_2.Timestamp.fromMillis(Date.now() - dailySongLifetimeMs);
    const expiredProfiles = await db
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
            const privateProfile = await db
                .doc(`${userPrivateCollection}/${profile.id}`)
                .get();
            const privateData = privateProfile.data();
            const locale = preferredLocale(privateData);
            await sendNotification(profile.id, privateData, {
                title: 'MusiLink',
                body: notificationText.dailySongExpired[locale](),
            }, { type: 'daily_song_expired' }, 'daily_song_expired');
        }));
    }
    v2_1.logger.info('expireDailySongs: expiry cycle completed', {
        candidates: expiredProfiles.size,
        expired: expiredCount,
        expiresBefore: expiresBefore.toDate().toISOString(),
    });
});
// ── Funcion 6 - Limpieza segura de chats ─────────────────
// Clientes nuevos solo escriben deletedAt[uid]. El backend elimina mensajes
// que ya estan ocultos para ambos usuarios; si ya no hay mensajes visibles
// para nadie, elimina fisicamente mensajes y documento del chat.
exports.onChatSoftDeleted = (0, firestore_1.onDocumentUpdated)({ document: `${chatsCollection}/{chatId}`, region: 'europe-southwest1' }, async (event) => {
    try {
        const after = event.data?.after.data();
        if (!after)
            return;
        if (fullySoftDeletedChat(after)) {
            await hardDeleteChat(event.data.after.ref);
            v2_1.logger.info('onChatSoftDeleted: hard-deleted fully soft-deleted chat', {
                chatId: event.params.chatId,
            });
            return;
        }
        const prunedMessages = await pruneMessagesDeletedForAllParticipants(event.data.after.ref, after);
        if (prunedMessages > 0) {
            v2_1.logger.info('onChatSoftDeleted: pruned messages hidden for all participants', {
                chatId: event.params.chatId,
                prunedMessages,
            });
        }
    }
    catch (error) {
        v2_1.logger.error('onChatSoftDeleted: unhandled error', {
            chatId: event.params.chatId,
            error,
        });
        throw error;
    }
});
// Cuando se borran mensajes durante la limpieza de una cuenta,
// el resumen del chat se mantiene coherente. Si el chat queda vacio, el backend
// elimina el documento padre.
exports.onChatMessageDeleted = (0, firestore_1.onDocumentDeleted)({ document: `${chatsCollection}/{chatId}/${messagesCollection}/{messageId}`, region: 'europe-southwest1' }, async (event) => {
    try {
        const deletedMessage = event.data?.data();
        if (!deletedMessage)
            return;
        const chatRef = db.doc(`${chatsCollection}/${event.params.chatId}`);
        const chatSnap = await chatRef.get();
        if (!chatSnap.exists)
            return;
        const currentLastMessageTime = timestampValue(chatSnap.data()?.lastMessageTime);
        const deletedMessageTime = timestampValue(deletedMessage.timestamp);
        if (currentLastMessageTime &&
            deletedMessageTime &&
            deletedMessageTime.toMillis() < currentLastMessageTime.toMillis()) {
            return;
        }
        const stillExists = await refreshChatSummaryFromLatestMessage(chatRef);
        v2_1.logger.info('onChatMessageDeleted: refreshed chat after message delete', {
            chatId: event.params.chatId,
            messageId: event.params.messageId,
            stillExists,
        });
    }
    catch (error) {
        v2_1.logger.error('onChatMessageDeleted: unhandled error', {
            chatId: event.params.chatId,
            messageId: event.params.messageId,
            error,
        });
        throw error;
    }
});
// ── Funcion 6 - Limpieza del cooldown al borrar una solicitud ─────────────────
// Cuando una solicitud se elimina (rechazo, cancelación o aceptación), borrar
// el doc de rate-limit por par (sender, receiver) para que una nueva solicitud
// legítima vuelva a notificar sin esperar al cooldown.
exports.onFriendRequestDeleted = (0, firestore_1.onDocumentDeleted)({ document: 'friend_requests/{requestId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const request = event.data?.data();
        if (!request)
            return;
        const senderId = request.senderId;
        const receiverId = request.receiverId;
        if (!senderId || !receiverId)
            return;
        await db
            .collection(friendRequestNotificationLimitsCollection)
            .doc(`${senderId}_${receiverId}`)
            .delete();
    }
    catch (error) {
        v2_1.logger.error('onFriendRequestDeleted: unhandled error', {
            requestId: event.params.requestId,
            error,
        });
        throw error;
    }
});
//# sourceMappingURL=index.js.map