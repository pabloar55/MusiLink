"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.engagementPushField = exports.quietChannelId = exports.notificationText = void 0;
exports.notifChannelId = notifChannelId;
exports.notificationPath = notificationPath;
exports.preferredLocale = preferredLocale;
exports.chatNotification = chatNotification;
exports.sendNotification = sendNotification;
const v2_1 = require("firebase-functions/v2");
const firebase_1 = require("./firebase");
const userPrivateCollection = 'user_private';
const pushTokensSubcollection = 'push_tokens';
const defaultLocale = 'en';
const supportedLocales = new Set(['el', 'en', 'es', 'fr']);
exports.notificationText = {
    friendRequest: {
        el: (name) => `${name} σας έστειλε αίτημα φιλίας`,
        en: (name) => `${name} sent you a friend request`,
        es: (name) => `${name} te envió una solicitud de amistad`,
        fr: (name) => `${name} vous a envoyé une demande d'amitié`,
    },
    friendRequestAccepted: {
        el: (name) => `${name} αποδέχτηκε το αίτημα φιλίας σας`,
        en: (name) => `${name} accepted your friend request`,
        es: (name) => `${name} aceptó tu solicitud de amistad`,
        fr: (name) => `${name} a accepté votre demande d'amitié`,
    },
    dailySongExpired: {
        el: () => 'Το τραγούδι της ημέρας σας έληξε. Μοιραστείτε ένα νέο!',
        en: () => 'Your song of the day has expired. Share a new one!',
        es: () => '¡Tu canción del día ha caducado! Publica una nueva.',
        fr: () => 'Votre chanson du jour a expiré. Partagez-en une nouvelle !',
    },
    dailySongExpiredFriend: {
        el: () => 'Το τραγούδι της ημέρας σας έληξε και ένας φίλος σας μοιράστηκε ήδη το δικό του. Μοιραστείτε ένα νέο!',
        en: () => 'Your song of the day has expired and a friend has already shared theirs. Share a new one!',
        es: () => 'Tu canción del día ha caducado y un amigo ya ha publicado la suya. ¡Publica una nueva!',
        fr: () => 'Votre chanson du jour a expiré et un ami a déjà partagé la sienne. Partagez-en une nouvelle !',
    },
    dailySongExpiredFriends: {
        el: (count) => `Το τραγούδι της ημέρας σας έληξε και ${count} φίλοι σας μοιράστηκαν ήδη το δικό τους. Μοιραστείτε ένα νέο!`,
        en: (count) => `Your song of the day has expired and ${count} friends have already shared theirs. Share a new one!`,
        es: (count) => `Tu canción del día ha caducado y ${count} amigos ya han publicado la suya. ¡Publica una nueva!`,
        fr: (count) => `Votre chanson du jour a expiré et ${count} amis ont déjà partagé la leur. Partagez-en une nouvelle !`,
    },
    dailySongReply: {
        el: (name) => `${name} απάντησε στο τραγούδι σας`,
        en: (name) => `${name} replied to your song`,
        es: (name) => `${name} ha respondido a tu canción`,
        fr: (name) => `${name} a répondu à votre chanson`,
    },
    dailySongLiked: {
        el: (name) => `Στον χρήστη ${name} άρεσε το τραγούδι της ημέρας σας`,
        en: (name) => `${name} liked your song of the day`,
        es: (name) => `A ${name} le ha gustado tu canción del día`,
        fr: (name) => `${name} a aimé votre chanson du jour`,
    },
    friendDigestOne: {
        el: (name) => `Ο χρήστης ${name} μοιράστηκε το τραγούδι της ημέρας του. Μοιραστείτε το δικό σας!`,
        en: (name) => `${name} shared their song of the day. Share yours!`,
        es: (name) => `${name} ha publicado su canción del día. ¡Publica la tuya!`,
        fr: (name) => `${name} a partagé sa chanson du jour. Partagez la vôtre !`,
    },
    friendDigest: {
        el: (friends) => `Οι φίλοι σας ${friends} μοιράστηκαν το τραγούδι της ημέρας τους. Μοιραστείτε το δικό σας!`,
        en: (friends) => `${friends} shared their song of the day. Share yours!`,
        es: (friends) => `${friends} han publicado su canción del día. ¡Publica la tuya!`,
        fr: (friends) => `${friends} ont partagé leur chanson du jour. Partagez la vôtre !`,
    },
    friendDigestOthers: {
        el: (count) => `${count} ακόμη`,
        en: (count) => `${count} others`,
        es: (count) => `${count} más`,
        fr: (count) => `${count} autres`,
    },
};
function notifChannelId(sound, vibration) {
    if (sound && vibration)
        return 'musilink_high';
    if (sound && !vibration)
        return 'musilink_high_no_vibration';
    if (!sound && vibration)
        return 'musilink_high_no_sound';
    return 'musilink_high_silent';
}
// Low-importance Android channel for reminders that must not interrupt.
exports.quietChannelId = 'musilink_digest';
// Written to user_private whenever a reminder to publish is sent, so the
// different reminders share a budget of one per local day.
exports.engagementPushField = 'engagementPushAt';
function notificationPath(data) {
    if (data.type === 'new_message' && data.chatId && data.chatType === 'group') {
        return `/group-chat/${encodeURIComponent(data.chatId)}`;
    }
    if (data.type === 'new_message' && data.chatId && data.otherUserId) {
        const query = new URLSearchParams({
            chatId: data.chatId,
            otherUserId: data.otherUserId,
            ...(data.otherUserName ? { otherUserName: data.otherUserName } : {}),
        });
        return `/chat?${query.toString()}`;
    }
    if (data.type === 'friend_request' || data.type === 'friend_request_accepted') {
        return '/?tab=friends';
    }
    if (data.type === 'daily_song_expired' ||
        data.type === 'daily_song_liked' ||
        data.type === 'friend_digest') {
        return '/?tab=daily-song';
    }
    return '/';
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
function chatNotification(message, senderName, recipient) {
    const reply = message.dailySongReply;
    let body = typeof message.text === 'string' ? message.text : '📎';
    if (reply && reply.formatVersion !== 2 && body.startsWith('🎵 “')) {
        const separator = body.indexOf('\n\n');
        if (separator >= 0)
            body = body.slice(separator + 2);
    }
    return {
        title: reply ? exports.notificationText.dailySongReply[preferredLocale(recipient)](senderName) : senderName,
        body,
    };
}
// Notifications with the same tag replace each other in the drawer, keeping
// one entry per conversation instead of an unbounded stack. A quiet
// notification is delivered without sound, vibration or heads-up display.
async function sendNotification(recipientUid, recipientPrivateData, notification, data, tag, options = {}) {
    const quiet = options.quiet === true;
    const sound = !quiet && recipientPrivateData?.notifSound !== false;
    const vibration = recipientPrivateData?.notifVibration !== false;
    const channelId = quiet ? exports.quietChannelId : notifChannelId(sound, vibration);
    const isChatMessage = data.type === 'new_message';
    const privateUserRef = firebase_1.db.doc(`${userPrivateCollection}/${recipientUid}`);
    const pushTokensSnapshot = await privateUserRef
        .collection(pushTokensSubcollection)
        .limit(20)
        .get();
    const targets = new Map();
    for (const tokenDoc of pushTokensSnapshot.docs) {
        const token = tokenDoc.data().token;
        if (typeof token === 'string' && token.length > 0)
            targets.set(token, tokenDoc.ref);
    }
    if (targets.size === 0)
        return;
    await Promise.all([...targets].map(async ([token, tokenRef]) => {
        try {
            await firebase_1.messaging.send({
                token,
                // Android chat notifications are data-only so the client can maintain
                // one MessagingStyle notification per conversation.
                ...(!isChatMessage ? { notification } : {}),
                data,
                android: {
                    priority: quiet ? 'normal' : 'high',
                    ...(!isChatMessage
                        ? { notification: { channelId, ...(tag ? { tag } : {}) } }
                        : {}),
                },
                apns: {
                    ...(tag ? { headers: { 'apns-collapse-id': tag.slice(0, 64) } } : {}),
                    payload: {
                        aps: {
                            ...(isChatMessage ? { alert: notification, contentAvailable: true } : {}),
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
                    data: { ...data, notificationPath: notificationPath(data) },
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
//# sourceMappingURL=notifications.js.map