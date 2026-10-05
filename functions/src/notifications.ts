import { DocumentData, DocumentReference } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { db, messaging } from './firebase';

const userPrivateCollection = 'user_private';
const pushTokensSubcollection = 'push_tokens';

export type SupportedLocale = 'el' | 'en' | 'es' | 'fr';

const defaultLocale: SupportedLocale = 'en';
const supportedLocales = new Set<SupportedLocale>(['el', 'en', 'es', 'fr']);

export const notificationText = {
  friendRequest: {
    el: (name: string) => `${name} σας έστειλε αίτημα φιλίας`,
    en: (name: string) => `${name} sent you a friend request`,
    es: (name: string) => `${name} te envió una solicitud de amistad`,
    fr: (name: string) => `${name} vous a envoyé une demande d'amitié`,
  },
  friendRequestAccepted: {
    el: (name: string) => `${name} αποδέχτηκε το αίτημα φιλίας σας`,
    en: (name: string) => `${name} accepted your friend request`,
    es: (name: string) => `${name} aceptó tu solicitud de amistad`,
    fr: (name: string) => `${name} a accepté votre demande d'amitié`,
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
    el: (count: string) => `Το τραγούδι της ημέρας σας έληξε και ${count} φίλοι σας μοιράστηκαν ήδη το δικό τους. Μοιραστείτε ένα νέο!`,
    en: (count: string) => `Your song of the day has expired and ${count} friends have already shared theirs. Share a new one!`,
    es: (count: string) => `Tu canción del día ha caducado y ${count} amigos ya han publicado la suya. ¡Publica una nueva!`,
    fr: (count: string) => `Votre chanson du jour a expiré et ${count} amis ont déjà partagé la leur. Partagez-en une nouvelle !`,
  },
  dailySongReply: {
    el: (name: string) => `${name} απάντησε στο τραγούδι σας`,
    en: (name: string) => `${name} replied to your song`,
    es: (name: string) => `${name} ha respondido a tu canción`,
    fr: (name: string) => `${name} a répondu à votre chanson`,
  },
  dailySongLiked: {
    el: (name: string) => `Στον χρήστη ${name} άρεσε το τραγούδι της ημέρας σας`,
    en: (name: string) => `${name} liked your song of the day`,
    es: (name: string) => `A ${name} le ha gustado tu canción del día`,
    fr: (name: string) => `${name} a aimé votre chanson du jour`,
  },
  friendDigestOne: {
    el: (name: string) => `Ο χρήστης ${name} μοιράστηκε το τραγούδι της ημέρας του. Μοιραστείτε το δικό σας!`,
    en: (name: string) => `${name} shared their song of the day. Share yours!`,
    es: (name: string) => `${name} ha publicado su canción del día. ¡Publica la tuya!`,
    fr: (name: string) => `${name} a partagé sa chanson du jour. Partagez la vôtre !`,
  },
  friendDigest: {
    el: (friends: string) => `Οι φίλοι σας ${friends} μοιράστηκαν το τραγούδι της ημέρας τους. Μοιραστείτε το δικό σας!`,
    en: (friends: string) => `${friends} shared their song of the day. Share yours!`,
    es: (friends: string) => `${friends} han publicado su canción del día. ¡Publica la tuya!`,
    fr: (friends: string) => `${friends} ont partagé leur chanson du jour. Partagez la vôtre !`,
  },
  friendDigestOthers: {
    el: (count: string) => `${count} ακόμη`,
    en: (count: string) => `${count} others`,
    es: (count: string) => `${count} más`,
    fr: (count: string) => `${count} autres`,
  },
} satisfies Record<string, Record<SupportedLocale, (name: string) => string>>;

export function notifChannelId(sound: boolean, vibration: boolean): string {
  if (sound && vibration) return 'musilink_high';
  if (sound && !vibration) return 'musilink_high_no_vibration';
  if (!sound && vibration) return 'musilink_high_no_sound';
  return 'musilink_high_silent';
}

// Low-importance Android channel for reminders that must not interrupt.
export const quietChannelId = 'musilink_digest';

// Written to user_private whenever a reminder to publish is sent, so the
// different reminders share a budget of one per local day.
export const engagementPushField = 'engagementPushAt';

export function notificationPath(data: Record<string, string>): string {
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
  if (
    data.type === 'daily_song_expired' ||
    data.type === 'daily_song_liked' ||
    data.type === 'friend_digest'
  ) {
    return '/?tab=daily-song';
  }
  return '/';
}

export function preferredLocale(data: DocumentData | undefined): SupportedLocale {
  const locale = data?.preferredLocale;
  if (typeof locale !== 'string') return defaultLocale;

  const languageCode = locale.toLowerCase().split(/[-_]/)[0];
  return supportedLocales.has(languageCode as SupportedLocale)
    ? languageCode as SupportedLocale
    : defaultLocale;
}

/** Older daily song replies included the song caption in the message body. */
export function messageBodyText(message: DocumentData, fallback = ''): string {
  const reply = message.dailySongReply;
  let body = typeof message.text === 'string' ? message.text : fallback;
  if (reply && reply.formatVersion !== 2 && body.startsWith('🎵 “')) {
    const separator = body.indexOf('\n\n');
    if (separator >= 0) body = body.slice(separator + 2);
  }
  return body;
}

export function chatNotification(
  message: DocumentData,
  senderName: string,
  recipient: DocumentData | undefined,
): { title: string; body: string } {
  return {
    title: message.dailySongReply
      ? notificationText.dailySongReply[preferredLocale(recipient)](senderName)
      : senderName,
    body: messageBodyText(message, '📎'),
  };
}

// Notifications with the same tag replace each other in the drawer, keeping
// one entry per conversation instead of an unbounded stack. A quiet
// notification is delivered without sound, vibration or heads-up display.
export async function sendNotification(
  recipientUid: string,
  recipientPrivateData: DocumentData | undefined,
  notification: { title: string; body: string },
  data: Record<string, string>,
  tag?: string,
  options: { quiet?: boolean } = {},
): Promise<void> {
  const quiet = options.quiet === true;
  const sound = !quiet && recipientPrivateData?.notifSound !== false;
  const vibration = recipientPrivateData?.notifVibration !== false;
  const channelId = quiet ? quietChannelId : notifChannelId(sound, vibration);
  const isChatMessage = data.type === 'new_message';
  const privateUserRef = db.doc(`${userPrivateCollection}/${recipientUid}`);
  const pushTokensSnapshot = await privateUserRef
    .collection(pushTokensSubcollection)
    .limit(20)
    .get();
  const targets = new Map<string, DocumentReference>();
  for (const tokenDoc of pushTokensSnapshot.docs) {
    const token = tokenDoc.data().token;
    if (typeof token === 'string' && token.length > 0) targets.set(token, tokenDoc.ref);
  }
  if (targets.size === 0) return;

  await Promise.all([...targets].map(async ([token, tokenRef]) => {
    try {
      await messaging.send({
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
    } catch (error: unknown) {
      const fcmError = error as { code?: string };
      if (fcmError.code === 'messaging/registration-token-not-registered') {
        await tokenRef.delete();
        return;
      }
      logger.error('sendNotification: unexpected FCM error', {
        recipientUid,
        error,
      });
      throw error;
    }
  }));
}
