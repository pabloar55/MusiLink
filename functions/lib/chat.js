"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onChatMessageDeleted = exports.onChatSoftDeleted = exports.onNewMessage = void 0;
exports.messageSummary = messageSummary;
exports.allParticipantsDeletedBefore = allParticipantsDeletedBefore;
exports.shouldIncrementUnreadCount = shouldIncrementUnreadCount;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("firebase-functions/v2/firestore");
const firebase_1 = require("./firebase");
const firestore_values_1 = require("./firestore_values");
const notifications_1 = require("./notifications");
const userPrivateCollection = 'user_private';
const chatsCollection = 'chats';
const messagesCollection = 'messages';
const chatCleanupBatchSize = 400;
function messageSummary(data) {
    if (data.type === 'track') {
        const title = data.trackData?.title;
        if (typeof title === 'string' && title.length > 0)
            return `🎵 ${title}`;
    }
    return typeof data.text === 'string' ? data.text : '';
}
function allParticipantsDeletedBefore(data) {
    const participants = (0, firestore_values_1.chatParticipants)(data);
    if (participants.length !== 2)
        return undefined;
    const deletedAt = data?.deletedAt;
    if (!deletedAt)
        return undefined;
    const deletedTimes = participants
        .map((uid) => (0, firestore_values_1.timestampValue)(deletedAt[uid]))
        .filter((value) => value !== undefined);
    if (deletedTimes.length !== participants.length)
        return undefined;
    return deletedTimes.reduce((earliest, value) => value.toMillis() < earliest.toMillis() ? value : earliest, deletedTimes[0]);
}
function shouldIncrementUnreadCount(chatData, recipientId, messageTime) {
    const deletedAt = chatData.deletedAt;
    const recipientDeletedAt = (0, firestore_values_1.timestampValue)(deletedAt?.[recipientId]);
    return !recipientDeletedAt || messageTime.toMillis() > recipientDeletedAt.toMillis();
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
        const batch = firebase_1.db.batch();
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
async function refreshChatSummaryFromLatestMessage(chatRef, deletedMessageTime) {
    const latest = await latestMessageSnapshot(chatRef);
    if (!latest) {
        // Keep the deterministic parent document even when the conversation is
        // empty. Deleting it here would race with a concurrent message creation:
        // Firestore does not delete subcollections atomically with their parent.
        if (!deletedMessageTime)
            return false;
        await firebase_1.db.runTransaction(async (tx) => {
            const chatSnap = await tx.get(chatRef);
            const chatData = chatSnap.data();
            if (!chatData)
                return;
            // A newer message may already have refreshed the summary after the
            // empty query. Do not clear that newer state when triggers run late.
            const currentLastMessageTime = (0, firestore_values_1.timestampValue)(chatData.lastMessageTime);
            if (currentLastMessageTime &&
                currentLastMessageTime.toMillis() > deletedMessageTime.toMillis()) {
                return;
            }
            const participants = (0, firestore_values_1.chatParticipants)(chatData);
            tx.update(chatRef, {
                lastMessage: '',
                unreadCounts: Object.fromEntries(participants.map((uid) => [uid, 0])),
            });
        });
        return false;
    }
    const latestData = latest.data();
    const latestMessageTime = (0, firestore_values_1.timestampValue)(latestData.timestamp);
    await firebase_1.db.runTransaction(async (tx) => {
        const [chatSnap, latestSnap] = await Promise.all([
            tx.get(chatRef),
            tx.get(latest.ref),
        ]);
        const chatData = chatSnap.data();
        const currentLatestData = latestSnap.data();
        if (!chatData || !currentLatestData)
            return;
        // If another message has already advanced the summary beyond the message
        // whose deletion caused this refresh, this delayed trigger must not
        // overwrite it with an older value.
        const currentLastMessageTime = (0, firestore_values_1.timestampValue)(chatData.lastMessageTime);
        if (deletedMessageTime &&
            currentLastMessageTime &&
            currentLastMessageTime.toMillis() > deletedMessageTime.toMillis()) {
            return;
        }
        tx.update(chatRef, {
            lastMessage: messageSummary(currentLatestData),
            lastMessageTime: latestMessageTime ?? firestore_1.FieldValue.serverTimestamp(),
        });
    });
    return true;
}
exports.onNewMessage = (0, firestore_2.onDocumentCreated)({
    document: 'chats/{chatId}/messages/{messageId}',
    region: 'europe-southwest1',
    retry: true,
}, async (event) => {
    try {
        const messageSnapshot = event.data;
        if (!messageSnapshot)
            return;
        const message = messageSnapshot.data();
        if (!message)
            return;
        const chatId = event.params.chatId;
        const senderId = message.senderId;
        const chatRef = firebase_1.db.doc(`chats/${chatId}`);
        const messageRef = messageSnapshot.ref;
        const summaryResult = await firebase_1.db.runTransaction(async (tx) => {
            const [chatSnap, currentMessageSnap] = await Promise.all([
                tx.get(chatRef),
                tx.get(messageRef),
            ]);
            const chatData = chatSnap.data();
            const currentMessage = currentMessageSnap.data();
            if (!chatData || !currentMessage) {
                return undefined;
            }
            const participants = (0, firestore_values_1.chatParticipants)(chatData);
            if (participants.length !== 2 || !participants.includes(senderId))
                return undefined;
            const recipientId = participants.find((uid) => uid !== senderId);
            const messageTime = (0, firestore_values_1.timestampValue)(currentMessage.timestamp);
            if (!recipientId || !messageTime)
                return undefined;
            if (currentMessage.summaryApplied !== true) {
                const updates = {};
                const currentLastMessageTime = (0, firestore_values_1.timestampValue)(chatData.lastMessageTime);
                const summary = messageSummary(currentMessage);
                if (!currentLastMessageTime ||
                    messageTime.toMillis() >= currentLastMessageTime.toMillis()) {
                    updates.lastMessage = summary;
                    updates.lastMessageTime = messageTime;
                }
                // A delayed trigger must not restore unread messages that the recipient
                // already hid by deleting the conversation.
                if (currentMessage.read !== true &&
                    shouldIncrementUnreadCount(chatData, recipientId, messageTime)) {
                    updates[`unreadCounts.${recipientId}`] = firestore_1.FieldValue.increment(1);
                }
                if (Object.keys(updates).length > 0)
                    tx.update(chatRef, updates);
                tx.update(messageRef, { summaryApplied: true });
            }
            return {
                recipientId,
                shouldSendNotification: currentMessage.notificationSent !== true,
            };
        });
        if (!summaryResult)
            return;
        const { recipientId, shouldSendNotification } = summaryResult;
        if (!shouldSendNotification)
            return;
        const [recipientSnap, senderSnap] = await Promise.all([
            firebase_1.db.doc(`${userPrivateCollection}/${recipientId}`).get(),
            firebase_1.db.doc(`users/${senderId}`).get(),
        ]);
        const senderName = senderSnap.data()?.displayName;
        const senderPhotoUrl = senderSnap.data()?.photoUrl;
        if (!senderName)
            return;
        await (0, notifications_1.sendNotification)(recipientId, recipientSnap.data(), { title: senderName, body: message.text ?? '📎' }, {
            type: 'new_message',
            chatId,
            otherUserId: senderId,
            otherUserName: senderName,
            messageText: message.text ?? '📎',
            ...(senderPhotoUrl ? { senderPhotoUrl } : {}),
        }, chatId);
        await messageRef.update({ notificationSent: true });
    }
    catch (error) {
        v2_1.logger.error('onNewMessage: unhandled error', {
            chatId: event.params.chatId,
            error,
        });
        throw error;
    }
});
exports.onChatSoftDeleted = (0, firestore_2.onDocumentUpdated)({ document: `${chatsCollection}/{chatId}`, region: 'europe-southwest1' }, async (event) => {
    try {
        const after = event.data?.after.data();
        if (!after)
            return;
        // lastMessageTime is an asynchronously maintained summary and can lag
        // behind the messages collection. Only prune up to the earliest point
        // both participants deleted; messages committed after that boundary are
        // never eligible, even if this trigger runs late or out of order.
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
exports.onChatMessageDeleted = (0, firestore_2.onDocumentDeleted)({
    document: `${chatsCollection}/{chatId}/${messagesCollection}/{messageId}`,
    region: 'europe-southwest1',
}, async (event) => {
    try {
        const deletedMessage = event.data?.data();
        if (!deletedMessage)
            return;
        const chatRef = firebase_1.db.doc(`${chatsCollection}/${event.params.chatId}`);
        const chatSnap = await chatRef.get();
        if (!chatSnap.exists)
            return;
        const currentLastMessageTime = (0, firestore_values_1.timestampValue)(chatSnap.data()?.lastMessageTime);
        const deletedMessageTime = (0, firestore_values_1.timestampValue)(deletedMessage.timestamp);
        if (currentLastMessageTime &&
            deletedMessageTime &&
            deletedMessageTime.toMillis() < currentLastMessageTime.toMillis()) {
            return;
        }
        const stillExists = await refreshChatSummaryFromLatestMessage(chatRef, deletedMessageTime);
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
//# sourceMappingURL=chat.js.map