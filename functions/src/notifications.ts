import { DocumentData, DocumentReference } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { db, messaging } from './firebase';

const userPrivateCollection = 'user_private';
const pushTokensSubcollection = 'push_tokens';

export type SupportedLocale = 'en' | 'es' | 'fr';

const defaultLocale: SupportedLocale = 'en';
const supportedLocales = new Set<SupportedLocale>(['en', 'es', 'fr']);

export const notificationText = {
  friendRequest: {
    en: (name: string) => `${name} sent you a friend request`,
    es: (name: string) => `${name} te envió una solicitud de amistad`,
    fr: (name: string) => `${name} vous a envoyé une demande d'amitié`,
  },
  friendRequestAccepted: {
    en: (name: string) => `${name} accepted your friend request`,
    es: (name: string) => `${name} aceptó tu solicitud de amistad`,
    fr: (name: string) => `${name} a accepté votre demande d'amitié`,
  },
  dailySongExpired: {
    en: () => 'Your song of the day has expired. Share a new one!',
    es: () => '¡Tu canción del día ha caducado! Publica una nueva.',
    fr: () => 'Votre chanson du jour a expiré. Partagez-en une nouvelle !',
  },
} satisfies Record<string, Record<SupportedLocale, (name: string) => string>>;

export function notifChannelId(sound: boolean, vibration: boolean): string {
  if (sound && vibration) return 'musilink_high';
  if (sound && !vibration) return 'musilink_high_no_vibration';
  if (!sound && vibration) return 'musilink_high_no_sound';
  return 'musilink_high_silent';
}

export function notificationPath(data: Record<string, string>): string {
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
  if (data.type === 'daily_song_expired') return '/?tab=daily-song';
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

// Notifications with the same tag replace each other in the drawer, keeping
// one entry per conversation instead of an unbounded stack.
export async function sendNotification(
  recipientUid: string,
  recipientPrivateData: DocumentData | undefined,
  notification: { title: string; body: string },
  data: Record<string, string>,
  tag?: string,
): Promise<void> {
  const sound = recipientPrivateData?.notifSound !== false;
  const vibration = recipientPrivateData?.notifVibration !== false;
  const channelId = notifChannelId(sound, vibration);
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
          priority: 'high',
          ...(!isChatMessage
            ? { notification: { channelId, ...(tag ? { tag } : {}) } }
            : {}),
        },
        apns: {
          ...(tag ? { headers: { 'apns-collapse-id': tag.slice(0, 64) } } : {}),
          payload: {
            aps: {
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
