"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onFriendRequestDeleted = exports.onFriendRequestAccepted = exports.onFriendRequest = exports.acceptFriendRequest = void 0;
exports.userHasBlocked = userHasBlocked;
exports.friendRequestNotificationIsCoolingDown = friendRequestNotificationIsCoolingDown;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const firebase_1 = require("./firebase");
const firestore_values_1 = require("./firestore_values");
const notifications_1 = require("./notifications");
const userPrivateCollection = 'user_private';
const friendRequestNotificationLimitsCollection = 'friend_request_notification_limits';
const friendRequestNotificationCooldownMs = 60 * 60 * 1000;
function userHasBlocked(data, otherUid) {
    const blockedUsers = data?.blockedUsers;
    return (0, firestore_values_1.stringList)(blockedUsers).includes(otherUid);
}
function friendRequestNotificationIsCoolingDown(lastNotifiedAt, now) {
    if (!(lastNotifiedAt instanceof firestore_1.Timestamp))
        return false;
    return now.toMillis() - lastNotifiedAt.toMillis()
        < friendRequestNotificationCooldownMs;
}
async function shouldNotifyFriendRequest(senderId, receiverId) {
    const limitRef = firebase_1.db
        .collection(friendRequestNotificationLimitsCollection)
        .doc(`${senderId}_${receiverId}`);
    return firebase_1.db.runTransaction(async (tx) => {
        const limitSnap = await tx.get(limitRef);
        const lastNotifiedAt = limitSnap.data()?.lastNotifiedAt;
        const now = firestore_1.Timestamp.now();
        if (friendRequestNotificationIsCoolingDown(lastNotifiedAt, now)) {
            return false;
        }
        tx.set(limitRef, { senderId, receiverId, lastNotifiedAt: now }, { merge: true });
        return true;
    });
}
async function establishAcceptedFriendship(requestId, expectedReceiverId, expectedSenderId) {
    const requestRef = firebase_1.db.collection('friend_requests').doc(requestId);
    return firebase_1.db.runTransaction(async (tx) => {
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
        const senderPrivateRef = firebase_1.db.doc(`${userPrivateCollection}/${senderId}`);
        const receiverPrivateRef = firebase_1.db.doc(`${userPrivateCollection}/${receiverId}`);
        const senderPublicRef = firebase_1.db.doc(`users/${senderId}`);
        const receiverPublicRef = firebase_1.db.doc(`users/${receiverId}`);
        const inverseRef = firebase_1.db.collection('friend_requests').doc(`${receiverId}_${senderId}`);
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
        tx.update(senderPrivateRef, { friends: firestore_1.FieldValue.arrayUnion(receiverId) });
        tx.update(receiverPrivateRef, { friends: firestore_1.FieldValue.arrayUnion(senderId) });
        if (status === 'pending') {
            tx.update(requestRef, {
                status: 'accepted',
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        if (inverse.exists && inverseRef.path !== requestRef.path)
            tx.delete(inverseRef);
        return { senderId, receiverId };
    });
}
exports.acceptFriendRequest = (0, https_1.onCall)({ region: 'europe-southwest1', enforceAppCheck: true }, async (request) => {
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
exports.onFriendRequest = (0, firestore_2.onDocumentCreated)({ document: 'friend_requests/{requestId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const request = event.data?.data();
        if (!request || request.status !== 'pending')
            return;
        const senderId = request.senderId;
        const receiverId = request.receiverId;
        if (!await shouldNotifyFriendRequest(senderId, receiverId))
            return;
        const [receiverSnap, senderSnap] = await Promise.all([
            firebase_1.db.doc(`${userPrivateCollection}/${receiverId}`).get(),
            firebase_1.db.doc(`users/${senderId}`).get(),
        ]);
        const receiver = receiverSnap.data();
        const senderName = senderSnap.data()?.displayName;
        if (!senderName)
            return;
        const locale = (0, notifications_1.preferredLocale)(receiver);
        await (0, notifications_1.sendNotification)(receiverId, receiver, { title: 'MusiLink', body: notifications_1.notificationText.friendRequest[locale](senderName) }, { type: 'friend_request', senderId }, `friend_request_${senderId}`);
    }
    catch (error) {
        v2_1.logger.error('onFriendRequest: unhandled error', {
            requestId: event.params.requestId,
            error,
        });
        throw error;
    }
});
exports.onFriendRequestAccepted = (0, firestore_2.onDocumentUpdated)({ document: 'friend_requests/{requestId}', region: 'europe-southwest1' }, async (event) => {
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
            firebase_1.db.doc(`${userPrivateCollection}/${senderId}`).get(),
            firebase_1.db.doc(`users/${receiverId}`).get(),
        ]);
        const sender = senderSnap.data();
        const accepterName = receiverSnap.data()?.displayName;
        if (accepterName) {
            const locale = (0, notifications_1.preferredLocale)(sender);
            await (0, notifications_1.sendNotification)(senderId, sender, {
                title: 'MusiLink',
                body: notifications_1.notificationText.friendRequestAccepted[locale](accepterName),
            }, { type: 'friend_request_accepted', accepterId: receiverId });
        }
        await change.after.ref.delete();
    }
    catch (error) {
        v2_1.logger.error('onFriendRequestAccepted: unhandled error', {
            requestId: event.params.requestId,
            error,
        });
        throw error;
    }
});
exports.onFriendRequestDeleted = (0, firestore_2.onDocumentDeleted)({ document: 'friend_requests/{requestId}', region: 'europe-southwest1' }, async (event) => {
    try {
        const request = event.data?.data();
        if (!request)
            return;
        const senderId = request.senderId;
        const receiverId = request.receiverId;
        if (!senderId || !receiverId)
            return;
        const limitRef = firebase_1.db
            .collection(friendRequestNotificationLimitsCollection)
            .doc(`${senderId}_${receiverId}`);
        await firebase_1.db.runTransaction(async (tx) => {
            const limitSnap = await tx.get(limitRef);
            if (!limitSnap.exists)
                return;
            const lastNotifiedAt = limitSnap.data()?.lastNotifiedAt;
            if (!friendRequestNotificationIsCoolingDown(lastNotifiedAt, firestore_1.Timestamp.now())) {
                tx.delete(limitRef);
            }
        });
    }
    catch (error) {
        v2_1.logger.error('onFriendRequestDeleted: unhandled error', {
            requestId: event.params.requestId,
            error,
        });
        throw error;
    }
});
//# sourceMappingURL=friendships.js.map