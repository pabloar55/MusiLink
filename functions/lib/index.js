"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onFriendRequestDeleted = exports.onChatMessageDeleted = exports.onChatDeleted = exports.onChatSoftDeleted = exports.onFriendRequestAccepted = exports.onFriendRequest = exports.onUserMusicProfileChanged = exports.onUserMusicProfileCreated = exports.onNewMessage = exports.getSimilarArtists = exports.searchSpotifyTracks = exports.searchSpotifyArtists = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("firebase-admin/firestore");
var spotify_1 = require("./spotify");
Object.defineProperty(exports, "searchSpotifyArtists", { enumerable: true, get: function () { return spotify_1.searchSpotifyArtists; } });
Object.defineProperty(exports, "searchSpotifyTracks", { enumerable: true, get: function () { return spotify_1.searchSpotifyTracks; } });
var lastfm_1 = require("./lastfm");
Object.defineProperty(exports, "getSimilarArtists", { enumerable: true, get: function () { return lastfm_1.getSimilarArtists; } });
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
const userPrivateCollection = 'user_private';
const friendRequestNotificationLimitsCollection = 'friend_request_notification_limits';
const recommendationIndexCollection = 'music_recommendation_index';
const recommendationsCollection = 'recommendations';
const chatsCollection = 'chats';
const messagesCollection = 'messages';
const friendRequestNotificationCooldownMs = 60 * 60 * 1000;
const maxRecommendationInputArtists = 15;
const maxRecommendationInputGenres = 10;
const maxIndexUsersPerToken = 80;
const maxStoredRecommendations = 100;
const maxReciprocalRecommendationUsers = 100;
const chatCleanupBatchSize = 400;
const artistScoreWeight = 70;
const genreScoreWeight = 30;
const artistEvidenceTarget = 7;
const genreEvidenceTarget = 4;
const defaultLocale = 'en';
const supportedLocales = new Set(['en', 'es', 'fr']);
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
async function sendNotification(recipientUid, recipientPrivateData, token, notification, data, 
// Notifications with the same tag replace each other in the drawer,
// keeping one entry per conversation instead of an unbounded stack.
tag) {
    const sound = recipientPrivateData?.notifSound !== false;
    const vibration = recipientPrivateData?.notifVibration !== false;
    const channelId = notifChannelId(sound, vibration);
    try {
        await messaging.send({
            token,
            notification,
            data,
            android: {
                priority: 'high',
                notification: {
                    channelId,
                    ...(tag ? { tag } : {}),
                },
            },
            apns: {
                ...(tag ? { headers: { 'apns-collapse-id': tag.slice(0, 64) } } : {}),
                payload: { aps: { ...(sound ? { sound: 'default' } : {}) } },
            },
        });
    }
    catch (error) {
        const fcmError = error;
        if (fcmError.code === 'messaging/registration-token-not-registered') {
            await db.doc(`${userPrivateCollection}/${recipientUid}`).update({ fcmToken: firestore_2.FieldValue.delete() });
            return;
        }
        v2_1.logger.error('sendNotification: unexpected FCM error', { recipientUid, error });
        throw error;
    }
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
function readMusicProfile(data) {
    return {
        topArtistNames: stringList(data?.topArtistNames).slice(0, maxRecommendationInputArtists),
        topGenreNames: stringList(data?.topGenreNames).slice(0, maxRecommendationInputGenres),
    };
}
function sameStringList(left, right) {
    if (left.length !== right.length)
        return false;
    return left.every((value, index) => value === right[index]);
}
function musicProfileChanged(before, after) {
    return !sameStringList(before.topArtistNames, after.topArtistNames) ||
        !sameStringList(before.topGenreNames, after.topGenreNames);
}
function timestampMillis(value) {
    return value instanceof firestore_2.Timestamp ? value.toMillis() : undefined;
}
function timestampValue(value) {
    return value instanceof firestore_2.Timestamp ? value : undefined;
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
        lastMessage: latestData.text ?? '',
        lastMessageTime: timestampValue(latestData.timestamp) ?? firestore_2.FieldValue.serverTimestamp(),
    });
    return true;
}
function recommendationRefreshRequested(before, after) {
    const beforeMillis = timestampMillis(before?.recommendationsRefreshRequestedAt);
    const afterMillis = timestampMillis(after?.recommendationsRefreshRequestedAt);
    return afterMillis !== undefined && afterMillis !== beforeMillis;
}
function tokenKey(type, value) {
    return `${type}_${Buffer.from(value.toLowerCase(), 'utf8').toString('base64url')}`;
}
function normalizedMusicKey(value) {
    return value.trim().toLowerCase();
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
function musicTokens(profile) {
    return [
        ...profile.topArtistNames.map((value) => ({
            key: tokenKey('artist', value),
            type: 'artist',
            value,
        })),
        ...profile.topGenreNames.map((value) => ({
            key: tokenKey('genre', value),
            type: 'genre',
            value,
        })),
    ];
}
function indexUserRef(token, uid) {
    return db
        .collection(recommendationIndexCollection)
        .doc(token.key)
        .collection('users')
        .doc(uid);
}
function userDocRef(uid) {
    return db.collection('users').doc(uid);
}
async function commitBatches(operations) {
    const batchSize = 400;
    for (let i = 0; i < operations.length; i += batchSize) {
        const batch = db.batch();
        operations.slice(i, i + batchSize).forEach((operation) => operation(batch));
        await batch.commit();
    }
}
async function updateRecommendationIndex(uid, before, after) {
    const previousTokens = new Map(musicTokens(before).map((token) => [token.key, token]));
    const nextTokens = new Map(musicTokens(after).map((token) => [token.key, token]));
    const now = firestore_2.FieldValue.serverTimestamp();
    const operations = [];
    for (const [key, token] of previousTokens) {
        if (!nextTokens.has(key)) {
            operations.push((batch) => batch.delete(indexUserRef(token, uid)));
        }
    }
    for (const token of nextTokens.values()) {
        operations.push((batch) => batch.set(indexUserRef(token, uid), {
            uid,
            tokenType: token.type,
            tokenValue: token.value,
            topArtistNames: after.topArtistNames,
            topGenreNames: after.topGenreNames,
            updatedAt: now,
        }));
    }
    if (operations.length > 0)
        await commitBatches(operations);
}
function calculateRecommendation(myProfile, candidate) {
    const myArtistNames = uniqueMusicNames(myProfile.topArtistNames);
    const candidateArtistNames = uniqueMusicNames(candidate.topArtistNames);
    const myGenreNames = uniqueMusicNames(myProfile.topGenreNames);
    const candidateGenreNames = uniqueMusicNames(candidate.topGenreNames);
    const myArtists = new Set(myArtistNames.map(normalizedMusicKey));
    const myGenres = new Set(myGenreNames.map(normalizedMusicKey));
    const sharedArtistNames = candidateArtistNames.filter((artist) => myArtists.has(normalizedMusicKey(artist)));
    const sharedGenreNames = candidateGenreNames.filter((genre) => myGenres.has(normalizedMusicKey(genre)));
    if (sharedArtistNames.length === 0 && sharedGenreNames.length === 0)
        return null;
    const artistScore = similarityScore(sharedArtistNames.length, myArtistNames.length, candidateArtistNames.length, artistEvidenceTarget, artistScoreWeight);
    const genreScore = similarityScore(sharedGenreNames.length, myGenreNames.length, candidateGenreNames.length, genreEvidenceTarget, genreScoreWeight);
    return {
        uid: candidate.uid,
        score: Math.round(artistScore + genreScore),
        sharedArtistNames,
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
    const tokens = musicTokens(profile);
    const generatedAt = firestore_2.Timestamp.now();
    if (tokens.length === 0) {
        await deleteExistingRecommendations(uid);
        await userDocRef(uid).update({ recommendationsGeneratedAt: generatedAt });
        return;
    }
    const snapshots = await Promise.all(tokens.map((token) => db
        .collection(recommendationIndexCollection)
        .doc(token.key)
        .collection('users')
        .orderBy('updatedAt', 'desc')
        .limit(maxIndexUsersPerToken)
        .get()));
    const candidates = new Map();
    for (const snapshot of snapshots) {
        for (const doc of snapshot.docs) {
            if (doc.id === uid || candidates.has(doc.id))
                continue;
            const data = doc.data();
            candidates.set(doc.id, {
                uid: doc.id,
                topArtistNames: stringList(data.topArtistNames),
                topGenreNames: stringList(data.topGenreNames),
            });
        }
    }
    const recommendations = [...candidates.values()]
        .map((candidate) => calculateRecommendation(profile, candidate))
        .filter((result) => result !== null)
        .sort((a, b) => b.score - a.score)
        .slice(0, maxStoredRecommendations);
    const recommendationIds = new Set(recommendations.map((recommendation) => recommendation.uid));
    await commitBatches(recommendations.map((recommendation) => (batch) => {
        batch.set(db.doc(`users/${uid}/${recommendationsCollection}/${recommendation.uid}`), {
            userId: recommendation.uid,
            score: recommendation.score,
            sharedArtistNames: recommendation.sharedArtistNames,
            sharedGenreNames: recommendation.sharedGenreNames,
            generatedAt,
        });
    }));
    await deleteStaleRecommendations(uid, recommendationIds);
    await userDocRef(uid).update({ recommendationsGeneratedAt: generatedAt });
    v2_1.logger.info('refreshRecommendations: generated recommendations', {
        uid,
        candidateCount: candidates.size,
        recommendationCount: recommendations.length,
    });
}
async function matchingCandidateProfiles(uid, profiles) {
    const tokenMap = new Map();
    profiles
        .flatMap((profile) => musicTokens(profile))
        .forEach((token) => tokenMap.set(token.key, token));
    const tokens = [...tokenMap.values()];
    if (tokens.length === 0)
        return new Map();
    const snapshots = await Promise.all(tokens.map((token) => db
        .collection(recommendationIndexCollection)
        .doc(token.key)
        .collection('users')
        .orderBy('updatedAt', 'desc')
        .limit(maxIndexUsersPerToken)
        .get()));
    const candidates = new Map();
    for (const snapshot of snapshots) {
        for (const doc of snapshot.docs) {
            if (doc.id === uid || candidates.has(doc.id))
                continue;
            const data = doc.data();
            candidates.set(doc.id, {
                uid: doc.id,
                topArtistNames: stringList(data.topArtistNames),
                topGenreNames: stringList(data.topGenreNames),
            });
            if (candidates.size >= maxReciprocalRecommendationUsers)
                return candidates;
        }
    }
    return candidates;
}
async function updateReciprocalRecommendations(uid, profile, candidates) {
    const generatedAt = firestore_2.Timestamp.now();
    await commitBatches([...candidates.values()].map((candidate) => (batch) => {
        const recommendation = calculateRecommendation(candidate, {
            uid,
            topArtistNames: profile.topArtistNames,
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
        });
    }));
    v2_1.logger.info('updateReciprocalRecommendations: updated candidates', {
        uid,
        candidateCount: candidates.size,
    });
}
async function rebuildMusicRecommendations(uid, before, after, options = {}) {
    const profileChanged = musicProfileChanged(before, after);
    const forceSelfRefresh = options.forceSelfRefresh === true;
    if (!profileChanged && !forceSelfRefresh)
        return;
    const reciprocalCandidates = profileChanged || forceSelfRefresh
        ? await matchingCandidateProfiles(uid, [before, after])
        : new Map();
    if (profileChanged || forceSelfRefresh)
        await updateRecommendationIndex(uid, before, after);
    await refreshRecommendations(uid, after);
    if (profileChanged || forceSelfRefresh) {
        await updateReciprocalRecommendations(uid, after, reciprocalCandidates);
    }
}
// ── Función 1 — Nuevo mensaje ─────────────────────────────────────────────────
exports.onNewMessage = (0, firestore_1.onDocumentCreated)({ document: 'chats/{chatId}/messages/{messageId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const message = event.data?.data();
        if (!message)
            return;
        const chatId = event.params.chatId;
        const senderId = message.senderId;
        const chatSnap = await db.doc(`chats/${chatId}`).get();
        const chatData = chatSnap.data();
        if (!chatData)
            return;
        const participants = chatData.participants;
        if (participants.length !== 2)
            return;
        const recipientId = participants.find((p) => p !== senderId);
        if (!recipientId)
            return;
        const [recipientSnap, senderSnap] = await Promise.all([
            db.doc(`${userPrivateCollection}/${recipientId}`).get(),
            db.doc(`users/${senderId}`).get(),
        ]);
        const fcmToken = recipientSnap.data()?.fcmToken;
        const senderName = senderSnap.data()?.displayName;
        if (!fcmToken || !senderName)
            return;
        await sendNotification(recipientId, recipientSnap.data(), fcmToken, { title: senderName, body: message.text ?? '📎' }, {
            type: 'new_message',
            chatId,
            otherUserId: senderId,
            otherUserName: senderName,
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
        const after = readMusicProfile(event.data?.data());
        await rebuildMusicRecommendations(event.params.userId, {
            topArtistNames: [],
            topGenreNames: [],
        }, after);
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
        await rebuildMusicRecommendations(event.params.userId, before, after, {
            forceSelfRefresh: recommendationRefreshRequested(beforeData, afterData),
        });
    }
    catch (error) {
        v2_1.logger.error('onUserMusicProfileChanged: unhandled error', {
            userId: event.params.userId,
            error,
        });
        throw error;
    }
});
// ── Función 3 — Nueva solicitud de amistad ────────────────────────────────────
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
        const fcmToken = receiver?.fcmToken;
        const senderName = senderSnap.data()?.displayName;
        if (!fcmToken || !senderName)
            return;
        const locale = preferredLocale(receiver);
        await sendNotification(receiverId, receiver, fcmToken, { title: 'MusiLink', body: notificationText.friendRequest[locale](senderName) }, { type: 'friend_request', senderId }, `friend_request_${senderId}`);
    }
    catch (error) {
        v2_1.logger.error('onFriendRequest: unhandled error', { requestId: event.params.requestId, error });
        throw error;
    }
});
// ── Función 4 — Solicitud de amistad aceptada ─────────────────────────────────
exports.onFriendRequestAccepted = (0, firestore_1.onDocumentUpdated)({ document: 'friend_requests/{requestId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const before = event.data?.before.data();
        const after = event.data?.after.data();
        if (!before || !after)
            return;
        if (before.status !== 'pending' || after.status !== 'accepted')
            return;
        const senderId = after.senderId;
        const receiverId = after.receiverId;
        const [senderSnap, receiverSnap] = await Promise.all([
            db.doc(`${userPrivateCollection}/${senderId}`).get(),
            db.doc(`users/${receiverId}`).get(),
        ]);
        const sender = senderSnap.data();
        const fcmToken = sender?.fcmToken;
        const accepterName = receiverSnap.data()?.displayName;
        if (!fcmToken || !accepterName)
            return;
        const locale = preferredLocale(sender);
        await sendNotification(senderId, sender, fcmToken, { title: 'MusiLink', body: notificationText.friendRequestAccepted[locale](accepterName) }, { type: 'friend_request_accepted', accepterId: receiverId });
        await db.doc(event.document).delete();
    }
    catch (error) {
        v2_1.logger.error('onFriendRequestAccepted: unhandled error', { requestId: event.params.requestId, error });
        throw error;
    }
});
// ── Funcion 5 - Limpieza segura de chats ─────────────────
// Clientes nuevos solo escriben deletedAt[uid]. Cuando ambos usuarios han
// borrado su copia y no hay mensajes posteriores a esos timestamps, el backend
// elimina fisicamente mensajes y documento del chat.
exports.onChatSoftDeleted = (0, firestore_1.onDocumentUpdated)({ document: `${chatsCollection}/{chatId}`, region: 'europe-southwest1' }, async (event) => {
    try {
        const after = event.data?.after.data();
        if (!fullySoftDeletedChat(after))
            return;
        await hardDeleteChat(event.data.after.ref);
        v2_1.logger.info('onChatSoftDeleted: hard-deleted fully soft-deleted chat', {
            chatId: event.params.chatId,
        });
    }
    catch (error) {
        v2_1.logger.error('onChatSoftDeleted: unhandled error', {
            chatId: event.params.chatId,
            error,
        });
        throw error;
    }
});
// Si un cliente antiguo borra el documento del chat directamente, no rompemos
// la app: si ya no quedan mensajes o ambos lo habian borrado, dejamos que
// desaparezca; si aun quedan mensajes y no habia borrado suave doble, se
// restaura el doc del chat para que la conversacion siga disponible.
exports.onChatDeleted = (0, firestore_1.onDocumentDeleted)({ document: `${chatsCollection}/{chatId}`, region: 'europe-southwest1' }, async (event) => {
    try {
        const chatData = event.data?.data();
        if (!chatData || fullySoftDeletedChat(chatData))
            return;
        const chatRef = db.doc(event.document);
        const latest = await latestMessageSnapshot(chatRef);
        if (!latest)
            return;
        const latestData = latest.data();
        await chatRef.set({
            ...chatData,
            lastMessage: latestData.text ?? '',
            lastMessageTime: timestampValue(latestData.timestamp) ??
                timestampValue(chatData.lastMessageTime) ??
                firestore_2.FieldValue.serverTimestamp(),
        });
        v2_1.logger.warn('onChatDeleted: restored non-empty chat deleted by client', {
            chatId: event.params.chatId,
        });
    }
    catch (error) {
        v2_1.logger.error('onChatDeleted: unhandled error', {
            chatId: event.params.chatId,
            error,
        });
        throw error;
    }
});
// Cuando se borran mensajes (por limpieza de cuenta o por un cliente antiguo),
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