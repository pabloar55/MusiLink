"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onChatMessageDeleted = exports.onChatSoftDeleted = exports.onNewMessage = void 0;
exports.messageSummary = messageSummary;
exports.fullySoftDeletedChat = fullySoftDeletedChat;
exports.allParticipantsDeletedBefore = allParticipantsDeletedBefore;
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
function fullySoftDeletedChat(data) {
    const participants = (0, firestore_values_1.chatParticipants)(data);
    if (participants.length !== 2)
        return false;
    const lastMessageTime = (0, firestore_values_1.timestampValue)(data?.lastMessageTime);
    const deletedAt = data?.deletedAt;
    if (!lastMessageTime || !deletedAt)
        return false;
    return participants.every((uid) => {
        const deletedTime = (0, firestore_values_1.timestampValue)(deletedAt[uid]);
        return deletedTime !== undefined &&
            lastMessageTime.toMillis() <= deletedTime.toMillis();
    });
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
async function deleteChatMessages(chatRef) {
    const messagesRef = chatRef.collection(messagesCollection);
    while (true) {
        const snapshot = await messagesRef.limit(chatCleanupBatchSize).get();
        if (snapshot.empty)
            return;
        const batch = firebase_1.db.batch();
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
async function refreshChatSummaryFromLatestMessage(chatRef) {
    const latest = await latestMessageSnapshot(chatRef);
    if (!latest) {
        await chatRef.delete();
        return false;
    }
    const latestData = latest.data();
    await chatRef.update({
        lastMessage: messageSummary(latestData),
        lastMessageTime: (0, firestore_values_1.timestampValue)(latestData.timestamp) ?? firestore_1.FieldValue.serverTimestamp(),
    });
    return true;
}
exports.onNewMessage = (0, firestore_2.onDocumentCreated)({ document: 'chats/{chatId}/messages/{messageId}', region: 'europe-southwest1' }, async (event) => {
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
            if (!chatData || !currentMessage || currentMessage.summaryApplied === true) {
                return undefined;
            }
            const participants = (0, firestore_values_1.chatParticipants)(chatData);
            if (participants.length !== 2 || !participants.includes(senderId))
                return undefined;
            const recipientId = participants.find((uid) => uid !== senderId);
            const messageTime = (0, firestore_values_1.timestampValue)(currentMessage.timestamp);
            if (!recipientId || !messageTime)
                return undefined;
            const updates = {};
            const currentLastMessageTime = (0, firestore_values_1.timestampValue)(chatData.lastMessageTime);
            const summary = messageSummary(currentMessage);
            if (!currentLastMessageTime || messageTime.toMillis() >= currentLastMessageTime.toMillis()) {
                updates.lastMessage = summary;
                updates.lastMessageTime = messageTime;
            }
            if (currentMessage.read !== true) {
                updates[`unreadCounts.${recipientId}`] = firestore_1.FieldValue.increment(1);
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
//# sourceMappingURL=chat.js.map