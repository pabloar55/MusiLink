import * as admin from 'firebase-admin';
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
export { searchSpotifyArtists, searchSpotifyTracks } from './spotify';
export { getSimilarArtists } from './lastfm';

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

type TokenType = 'artist' | 'genre';
type SupportedLocale = 'en' | 'es' | 'fr';

interface MusicToken {
  key: string;
  type: TokenType;
  value: string;
}

interface UserMusicProfile {
  topArtistNames: string[];
  topGenreNames: string[];
}

interface CandidateProfile extends UserMusicProfile {
  uid: string;
}

interface RecommendationResult {
  uid: string;
  score: number;
  sharedArtistNames: string[];
  sharedGenreNames: string[];
}

const defaultLocale: SupportedLocale = 'en';
const supportedLocales = new Set<SupportedLocale>(['en', 'es', 'fr']);

const notificationText = {
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
} satisfies Record<string, Record<SupportedLocale, (name: string) => string>>;

// ── Helper ────────────────────────────────────────────────────────────────────

function notifChannelId(sound: boolean, vibration: boolean): string {
  if (sound && vibration) return 'musilink_high';
  if (sound && !vibration) return 'musilink_high_no_vibration';
  if (!sound && vibration) return 'musilink_high_no_sound';
  return 'musilink_high_silent';
}

async function sendNotification(
  recipientUid: string,
  recipientPrivateData: admin.firestore.DocumentData | undefined,
  token: string,
  notification: { title: string; body: string },
  data: Record<string, string>,
  // Notifications with the same tag replace each other in the drawer,
  // keeping one entry per conversation instead of an unbounded stack.
  tag?: string,
): Promise<void> {
  const sound = recipientPrivateData?.notifSound !== false;
  const vibration = recipientPrivateData?.notifVibration !== false;
  const channelId = notifChannelId(sound, vibration);
  const isChatMessage = data.type === 'new_message';
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
        ...(tag ? { headers: { 'apns-collapse-id': tag.slice(0, 64) } } : {}),
        payload: {
          aps: {
            // iOS cannot build Android's MessagingStyle notification, so it
            // keeps its native grouped alert per conversation.
            ...(isChatMessage ? { alert: notification } : {}),
            ...(sound ? { sound: 'default' } : {}),
          },
        },
      },
    });
  } catch (error: unknown) {
    const fcmError = error as { code?: string };
    if (fcmError.code === 'messaging/registration-token-not-registered') {
      await db.doc(`${userPrivateCollection}/${recipientUid}`).update({ fcmToken: FieldValue.delete() });
      return;
    }
    logger.error('sendNotification: unexpected FCM error', { recipientUid, error });
    throw error;
  }
}

function preferredLocale(data: admin.firestore.DocumentData | undefined): SupportedLocale {
  const locale = data?.preferredLocale;
  if (typeof locale !== 'string') return defaultLocale;

  const languageCode = locale.toLowerCase().split(/[-_]/)[0];
  return supportedLocales.has(languageCode as SupportedLocale)
    ? languageCode as SupportedLocale
    : defaultLocale;
}

async function shouldNotifyFriendRequest(
  senderId: string,
  receiverId: string,
): Promise<boolean> {
  const limitRef = db
    .collection(friendRequestNotificationLimitsCollection)
    .doc(`${senderId}_${receiverId}`);

  return db.runTransaction(async (tx) => {
    const limitSnap = await tx.get(limitRef);
    const lastNotifiedAt = limitSnap.data()?.lastNotifiedAt as Timestamp | undefined;
    const now = Timestamp.now();

    if (
      lastNotifiedAt &&
      now.toMillis() - lastNotifiedAt.toMillis() < friendRequestNotificationCooldownMs
    ) {
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

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function readMusicProfile(data: admin.firestore.DocumentData | undefined): UserMusicProfile {
  return {
    topArtistNames: stringList(data?.topArtistNames).slice(0, maxRecommendationInputArtists),
    topGenreNames: stringList(data?.topGenreNames).slice(0, maxRecommendationInputGenres),
  };
}

function sameStringList(left: string[], right: string[]): boolean {
  if (left.length !== right.length) return false;
  return left.every((value, index) => value === right[index]);
}

function musicProfileChanged(
  before: UserMusicProfile,
  after: UserMusicProfile,
): boolean {
  return !sameStringList(before.topArtistNames, after.topArtistNames) ||
    !sameStringList(before.topGenreNames, after.topGenreNames);
}

function timestampMillis(value: unknown): number | undefined {
  return value instanceof Timestamp ? value.toMillis() : undefined;
}

function timestampValue(value: unknown): Timestamp | undefined {
  return value instanceof Timestamp ? value : undefined;
}

function chatParticipants(data: admin.firestore.DocumentData | undefined): string[] {
  if (!Array.isArray(data?.participants)) return [];
  return data.participants.filter((value: unknown): value is string => typeof value === 'string');
}

function fullySoftDeletedChat(data: admin.firestore.DocumentData | undefined): boolean {
  const participants = chatParticipants(data);
  if (participants.length !== 2) return false;

  const lastMessageTime = timestampValue(data?.lastMessageTime);
  const deletedAt = data?.deletedAt as Record<string, unknown> | undefined;
  if (!lastMessageTime || !deletedAt) return false;

  return participants.every((uid) => {
    const deletedTime = timestampValue(deletedAt[uid]);
    return deletedTime !== undefined && lastMessageTime.toMillis() <= deletedTime.toMillis();
  });
}

function allParticipantsDeletedBefore(
  data: admin.firestore.DocumentData | undefined,
): Timestamp | undefined {
  const participants = chatParticipants(data);
  if (participants.length !== 2) return undefined;

  const deletedAt = data?.deletedAt as Record<string, unknown> | undefined;
  if (!deletedAt) return undefined;

  const deletedTimes = participants
    .map((uid) => timestampValue(deletedAt[uid]))
    .filter((value): value is Timestamp => value !== undefined);
  if (deletedTimes.length !== participants.length) return undefined;

  return deletedTimes.reduce((earliest, value) =>
    value.toMillis() < earliest.toMillis() ? value : earliest,
  deletedTimes[0]);
}

async function deleteChatMessages(
  chatRef: admin.firestore.DocumentReference,
): Promise<void> {
  const messagesRef = chatRef.collection(messagesCollection);
  while (true) {
    const snapshot = await messagesRef.limit(chatCleanupBatchSize).get();
    if (snapshot.empty) return;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    if (snapshot.size < chatCleanupBatchSize) return;
  }
}

async function hardDeleteChat(
  chatRef: admin.firestore.DocumentReference,
): Promise<void> {
  await deleteChatMessages(chatRef);
  await chatRef.delete();
}

async function pruneMessagesDeletedForAllParticipants(
  chatRef: admin.firestore.DocumentReference,
  chatData: admin.firestore.DocumentData | undefined,
): Promise<number> {
  const pruneBefore = allParticipantsDeletedBefore(chatData);
  if (!pruneBefore) return 0;

  const messagesRef = chatRef.collection(messagesCollection);
  let deletedCount = 0;

  while (true) {
    const snapshot = await messagesRef
      .where('timestamp', '<=', pruneBefore)
      .orderBy('timestamp')
      .limit(chatCleanupBatchSize)
      .get();
    if (snapshot.empty) return deletedCount;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deletedCount += snapshot.size;

    if (snapshot.size < chatCleanupBatchSize) return deletedCount;
  }
}

async function latestMessageSnapshot(
  chatRef: admin.firestore.DocumentReference,
): Promise<admin.firestore.QueryDocumentSnapshot | undefined> {
  const snapshot = await chatRef
    .collection(messagesCollection)
    .orderBy('timestamp', 'desc')
    .limit(1)
    .get();
  return snapshot.docs[0];
}

async function refreshChatSummaryFromLatestMessage(
  chatRef: admin.firestore.DocumentReference,
): Promise<boolean> {
  const latest = await latestMessageSnapshot(chatRef);
  if (!latest) {
    await chatRef.delete();
    return false;
  }

  const latestData = latest.data();
  await chatRef.update({
    lastMessage: (latestData.text as string | undefined) ?? '',
    lastMessageTime: timestampValue(latestData.timestamp) ?? FieldValue.serverTimestamp(),
  });
  return true;
}

function recommendationRefreshRequested(
  before: admin.firestore.DocumentData | undefined,
  after: admin.firestore.DocumentData | undefined,
): boolean {
  const beforeMillis = timestampMillis(before?.recommendationsRefreshRequestedAt);
  const afterMillis = timestampMillis(after?.recommendationsRefreshRequestedAt);
  return afterMillis !== undefined && afterMillis !== beforeMillis;
}

function tokenKey(type: TokenType, value: string): string {
  return `${type}_${Buffer.from(value.toLowerCase(), 'utf8').toString('base64url')}`;
}

function normalizedMusicKey(value: string): string {
  return value.trim().toLowerCase();
}

function uniqueMusicNames(values: string[]): string[] {
  const namesByKey = new Map<string, string>();
  for (const value of values) {
    const trimmed = value.trim();
    const key = normalizedMusicKey(trimmed);
    if (key.length > 0 && !namesByKey.has(key)) namesByKey.set(key, trimmed);
  }
  return [...namesByKey.values()];
}

function similarityScore(
  sharedCount: number,
  leftCount: number,
  rightCount: number,
  evidenceTarget: number,
  weight: number,
): number {
  if (sharedCount === 0) return 0;

  const comparableCount = Math.min(leftCount, rightCount);
  const coverage = comparableCount === 0 ? 0 : sharedCount / comparableCount;
  const evidence = Math.min(sharedCount / evidenceTarget, 1);
  return Math.max(coverage, evidence) * weight;
}

function musicTokens(profile: UserMusicProfile): MusicToken[] {
  return [
    ...profile.topArtistNames.map((value) => ({
      key: tokenKey('artist', value),
      type: 'artist' as const,
      value,
    })),
    ...profile.topGenreNames.map((value) => ({
      key: tokenKey('genre', value),
      type: 'genre' as const,
      value,
    })),
  ];
}

function indexUserRef(token: MusicToken, uid: string): admin.firestore.DocumentReference {
  return db
    .collection(recommendationIndexCollection)
    .doc(token.key)
    .collection('users')
    .doc(uid);
}

function userDocRef(uid: string): admin.firestore.DocumentReference {
  return db.collection('users').doc(uid);
}

async function commitBatches(
  operations: Array<(batch: admin.firestore.WriteBatch) => void>,
): Promise<void> {
  const batchSize = 400;
  for (let i = 0; i < operations.length; i += batchSize) {
    const batch = db.batch();
    operations.slice(i, i + batchSize).forEach((operation) => operation(batch));
    await batch.commit();
  }
}

async function updateRecommendationIndex(
  uid: string,
  before: UserMusicProfile,
  after: UserMusicProfile,
): Promise<void> {
  const previousTokens = new Map(musicTokens(before).map((token) => [token.key, token]));
  const nextTokens = new Map(musicTokens(after).map((token) => [token.key, token]));
  const now = FieldValue.serverTimestamp();
  const operations: Array<(batch: admin.firestore.WriteBatch) => void> = [];

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

  if (operations.length > 0) await commitBatches(operations);
}

function calculateRecommendation(
  myProfile: UserMusicProfile,
  candidate: CandidateProfile,
): RecommendationResult | null {
  const myArtistNames = uniqueMusicNames(myProfile.topArtistNames);
  const candidateArtistNames = uniqueMusicNames(candidate.topArtistNames);
  const myGenreNames = uniqueMusicNames(myProfile.topGenreNames);
  const candidateGenreNames = uniqueMusicNames(candidate.topGenreNames);
  const myArtists = new Set(myArtistNames.map(normalizedMusicKey));
  const myGenres = new Set(myGenreNames.map(normalizedMusicKey));
  const sharedArtistNames = candidateArtistNames.filter((artist) =>
    myArtists.has(normalizedMusicKey(artist)));
  const sharedGenreNames = candidateGenreNames.filter((genre) =>
    myGenres.has(normalizedMusicKey(genre)));

  if (sharedArtistNames.length === 0 && sharedGenreNames.length === 0) return null;

  const artistScore = similarityScore(
    sharedArtistNames.length,
    myArtistNames.length,
    candidateArtistNames.length,
    artistEvidenceTarget,
    artistScoreWeight,
  );
  const genreScore = similarityScore(
    sharedGenreNames.length,
    myGenreNames.length,
    candidateGenreNames.length,
    genreEvidenceTarget,
    genreScoreWeight,
  );

  return {
    uid: candidate.uid,
    score: Math.round(artistScore + genreScore),
    sharedArtistNames,
    sharedGenreNames,
  };
}

async function deleteExistingRecommendations(uid: string): Promise<void> {
  const existing = await db
    .collection(`users/${uid}/${recommendationsCollection}`)
    .get();
  if (existing.empty) return;

  await commitBatches(
    existing.docs.map((doc) => (batch) => batch.delete(doc.ref)),
  );
}

async function deleteStaleRecommendations(
  uid: string,
  currentRecommendationIds: Set<string>,
): Promise<void> {
  const existing = await db
    .collection(`users/${uid}/${recommendationsCollection}`)
    .get();
  const staleDocs = existing.docs.filter((doc) => !currentRecommendationIds.has(doc.id));
  if (staleDocs.length === 0) return;

  await commitBatches(staleDocs.map((doc) => (batch) => batch.delete(doc.ref)));
}

async function refreshRecommendations(uid: string, profile: UserMusicProfile): Promise<void> {
  const tokens = musicTokens(profile);
  const generatedAt = Timestamp.now();

  if (tokens.length === 0) {
    await deleteExistingRecommendations(uid);
    await userDocRef(uid).update({ recommendationsGeneratedAt: generatedAt });
    return;
  }

  const snapshots = await Promise.all(tokens.map((token) =>
    db
      .collection(recommendationIndexCollection)
      .doc(token.key)
      .collection('users')
      .orderBy('updatedAt', 'desc')
      .limit(maxIndexUsersPerToken)
      .get(),
  ));

  const candidates = new Map<string, CandidateProfile>();
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      if (doc.id === uid || candidates.has(doc.id)) continue;
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
    .filter((result): result is RecommendationResult => result !== null)
    .sort((a, b) => b.score - a.score)
    .slice(0, maxStoredRecommendations);

  const recommendationIds = new Set(recommendations.map((recommendation) => recommendation.uid));
  await commitBatches(recommendations.map((recommendation) => (batch) => {
    batch.set(
      db.doc(`users/${uid}/${recommendationsCollection}/${recommendation.uid}`),
      {
        userId: recommendation.uid,
        score: recommendation.score,
        sharedArtistNames: recommendation.sharedArtistNames,
        sharedGenreNames: recommendation.sharedGenreNames,
        generatedAt,
      },
    );
  }));
  await deleteStaleRecommendations(uid, recommendationIds);
  await userDocRef(uid).update({ recommendationsGeneratedAt: generatedAt });

  logger.info('refreshRecommendations: generated recommendations', {
    uid,
    candidateCount: candidates.size,
    recommendationCount: recommendations.length,
  });
}

async function matchingCandidateProfiles(
  uid: string,
  profiles: UserMusicProfile[],
): Promise<Map<string, CandidateProfile>> {
  const tokenMap = new Map<string, MusicToken>();
  profiles
    .flatMap((profile) => musicTokens(profile))
    .forEach((token) => tokenMap.set(token.key, token));

  const tokens = [...tokenMap.values()];
  if (tokens.length === 0) return new Map();

  const snapshots = await Promise.all(tokens.map((token) =>
    db
      .collection(recommendationIndexCollection)
      .doc(token.key)
      .collection('users')
      .orderBy('updatedAt', 'desc')
      .limit(maxIndexUsersPerToken)
      .get(),
  ));

  const candidates = new Map<string, CandidateProfile>();
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      if (doc.id === uid || candidates.has(doc.id)) continue;
      const data = doc.data();
      candidates.set(doc.id, {
        uid: doc.id,
        topArtistNames: stringList(data.topArtistNames),
        topGenreNames: stringList(data.topGenreNames),
      });
      if (candidates.size >= maxReciprocalRecommendationUsers) return candidates;
    }
  }

  return candidates;
}

async function updateReciprocalRecommendations(
  uid: string,
  profile: UserMusicProfile,
  candidates: Map<string, CandidateProfile>,
): Promise<void> {
  const generatedAt = Timestamp.now();
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

  logger.info('updateReciprocalRecommendations: updated candidates', {
    uid,
    candidateCount: candidates.size,
  });
}

async function rebuildMusicRecommendations(
  uid: string,
  before: UserMusicProfile,
  after: UserMusicProfile,
  options: { forceSelfRefresh?: boolean } = {},
): Promise<void> {
  const profileChanged = musicProfileChanged(before, after);
  const forceSelfRefresh = options.forceSelfRefresh === true;
  if (!profileChanged && !forceSelfRefresh) return;

  const reciprocalCandidates = profileChanged || forceSelfRefresh
    ? await matchingCandidateProfiles(uid, [before, after])
    : new Map<string, CandidateProfile>();
  if (profileChanged || forceSelfRefresh) await updateRecommendationIndex(uid, before, after);
  await refreshRecommendations(uid, after);
  if (profileChanged || forceSelfRefresh) {
    await updateReciprocalRecommendations(uid, after, reciprocalCandidates);
  }
}

// ── Función 1 — Nuevo mensaje ─────────────────────────────────────────────────

export const onNewMessage = onDocumentCreated(
  { document: 'chats/{chatId}/messages/{messageId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const message = event.data?.data();
      if (!message) return;

      const chatId = event.params.chatId;
      const senderId = message.senderId as string;

      const chatSnap = await db.doc(`chats/${chatId}`).get();
      const chatData = chatSnap.data();
      if (!chatData) return;

      const participants = chatData.participants as string[];
      if (participants.length !== 2) return;
      const recipientId = participants.find((p) => p !== senderId);
      if (!recipientId) return;

      const [recipientSnap, senderSnap] = await Promise.all([
        db.doc(`${userPrivateCollection}/${recipientId}`).get(),
        db.doc(`users/${senderId}`).get(),
      ]);

      const fcmToken = recipientSnap.data()?.fcmToken as string | undefined;
      const senderName = senderSnap.data()?.displayName as string | undefined;
      if (!fcmToken || !senderName) return;

      // Android receives this as a data-only message so the app can render a
      // single MessagingStyle notification containing the recent messages of
      // this conversation. iOS still receives a regular APNs alert below.
      await sendNotification(
        recipientId,
        recipientSnap.data(),
        fcmToken,
        { title: senderName, body: (message.text as string | undefined) ?? '📎' },
        {
          type: 'new_message',
          chatId,
          otherUserId: senderId,
          otherUserName: senderName,
          messageText: (message.text as string | undefined) ?? '📎',
        },
        chatId,
      );
    } catch (error) {
      logger.error('onNewMessage: unhandled error', { chatId: event.params.chatId, error });
      throw error;
    }
  },
);

// ── Función 2 — Recomendaciones musicales ─────────────────────────────────────

// Rebuilds recommendation lists when a user's music taste changes.
// The changed user's full list is rebuilt, and matching existing users get a
// reciprocal recommendation upsert/delete so discovery does not wait for them
// to edit their own profile.
export const onUserMusicProfileCreated = onDocumentCreated(
  { document: 'users/{userId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const after = readMusicProfile(event.data?.data());
      await rebuildMusicRecommendations(event.params.userId, {
        topArtistNames: [],
        topGenreNames: [],
      }, after);
    } catch (error) {
      logger.error('onUserMusicProfileCreated: unhandled error', {
        userId: event.params.userId,
        error,
      });
      throw error;
    }
  },
);

export const onUserMusicProfileChanged = onDocumentUpdated(
  { document: 'users/{userId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const beforeData = event.data?.before.data();
      const afterData = event.data?.after.data();
      const before = readMusicProfile(beforeData);
      const after = readMusicProfile(afterData);
      await rebuildMusicRecommendations(event.params.userId, before, after, {
        forceSelfRefresh: recommendationRefreshRequested(beforeData, afterData),
      });
    } catch (error) {
      logger.error('onUserMusicProfileChanged: unhandled error', {
        userId: event.params.userId,
        error,
      });
      throw error;
    }
  },
);

// ── Función 3 — Nueva solicitud de amistad ────────────────────────────────────

export const onFriendRequest = onDocumentCreated(
  { document: 'friend_requests/{requestId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const request = event.data?.data();
      if (!request) return;
      if (request.status !== 'pending') return;

      const senderId = request.senderId as string;
      const receiverId = request.receiverId as string;

      if (!await shouldNotifyFriendRequest(senderId, receiverId)) return;

      const [receiverSnap, senderSnap] = await Promise.all([
        db.doc(`${userPrivateCollection}/${receiverId}`).get(),
        db.doc(`users/${senderId}`).get(),
      ]);

      const receiver = receiverSnap.data();
      const fcmToken = receiver?.fcmToken as string | undefined;
      const senderName = senderSnap.data()?.displayName as string | undefined;
      if (!fcmToken || !senderName) return;
      const locale = preferredLocale(receiver);

      await sendNotification(
        receiverId,
        receiver,
        fcmToken,
        { title: 'MusiLink', body: notificationText.friendRequest[locale](senderName) },
        { type: 'friend_request', senderId },
        `friend_request_${senderId}`,
      );
    } catch (error) {
      logger.error('onFriendRequest: unhandled error', { requestId: event.params.requestId, error });
      throw error;
    }
  },
);

// ── Función 4 — Solicitud de amistad aceptada ─────────────────────────────────

export const onFriendRequestAccepted = onDocumentUpdated(
  { document: 'friend_requests/{requestId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;
      if (before.status !== 'pending' || after.status !== 'accepted') return;

      const senderId = after.senderId as string;
      const receiverId = after.receiverId as string;

      const [senderSnap, receiverSnap] = await Promise.all([
        db.doc(`${userPrivateCollection}/${senderId}`).get(),
        db.doc(`users/${receiverId}`).get(),
      ]);

      const sender = senderSnap.data();
      const fcmToken = sender?.fcmToken as string | undefined;
      const accepterName = receiverSnap.data()?.displayName as string | undefined;
      if (!fcmToken || !accepterName) return;
      const locale = preferredLocale(sender);

      await sendNotification(
        senderId,
        sender,
        fcmToken,
        { title: 'MusiLink', body: notificationText.friendRequestAccepted[locale](accepterName) },
        { type: 'friend_request_accepted', accepterId: receiverId },
      );

      await db.doc(event.document).delete();
    } catch (error) {
      logger.error('onFriendRequestAccepted: unhandled error', { requestId: event.params.requestId, error });
      throw error;
    }
  },
);

// ── Funcion 5 - Limpieza segura de chats ─────────────────

// Clientes nuevos solo escriben deletedAt[uid]. El backend elimina mensajes
// que ya estan ocultos para ambos usuarios; si ya no hay mensajes visibles
// para nadie, elimina fisicamente mensajes y documento del chat.
export const onChatSoftDeleted = onDocumentUpdated(
  { document: `${chatsCollection}/{chatId}`, region: 'europe-southwest1' },
  async (event) => {
    try {
      const after = event.data?.after.data();
      if (!after) return;
      if (fullySoftDeletedChat(after)) {
        await hardDeleteChat(event.data!.after.ref);
        logger.info('onChatSoftDeleted: hard-deleted fully soft-deleted chat', {
          chatId: event.params.chatId,
        });
        return;
      }

      const prunedMessages = await pruneMessagesDeletedForAllParticipants(
        event.data!.after.ref,
        after,
      );
      if (prunedMessages > 0) {
        logger.info('onChatSoftDeleted: pruned messages hidden for all participants', {
          chatId: event.params.chatId,
          prunedMessages,
        });
      }
    } catch (error) {
      logger.error('onChatSoftDeleted: unhandled error', {
        chatId: event.params.chatId,
        error,
      });
      throw error;
    }
  },
);

// Si un cliente antiguo borra el documento del chat directamente, no rompemos
// la app: si ya no quedan mensajes o ambos lo habian borrado, dejamos que
// desaparezca; si aun quedan mensajes y no habia borrado suave doble, se
// restaura el doc del chat para que la conversacion siga disponible.
export const onChatDeleted = onDocumentDeleted(
  { document: `${chatsCollection}/{chatId}`, region: 'europe-southwest1' },
  async (event) => {
    try {
      const chatData = event.data?.data();
      if (!chatData || fullySoftDeletedChat(chatData)) return;

      const chatRef = db.doc(event.document);
      const latest = await latestMessageSnapshot(chatRef);
      if (!latest) return;

      const latestData = latest.data();
      await chatRef.set({
        ...chatData,
        lastMessage: (latestData.text as string | undefined) ?? '',
        lastMessageTime: timestampValue(latestData.timestamp) ??
          timestampValue(chatData.lastMessageTime) ??
          FieldValue.serverTimestamp(),
      });

      logger.warn('onChatDeleted: restored non-empty chat deleted by client', {
        chatId: event.params.chatId,
      });
    } catch (error) {
      logger.error('onChatDeleted: unhandled error', {
        chatId: event.params.chatId,
        error,
      });
      throw error;
    }
  },
);

// Cuando se borran mensajes (por limpieza de cuenta o por un cliente antiguo),
// el resumen del chat se mantiene coherente. Si el chat queda vacio, el backend
// elimina el documento padre.
export const onChatMessageDeleted = onDocumentDeleted(
  { document: `${chatsCollection}/{chatId}/${messagesCollection}/{messageId}`, region: 'europe-southwest1' },
  async (event) => {
    try {
      const deletedMessage = event.data?.data();
      if (!deletedMessage) return;

      const chatRef = db.doc(`${chatsCollection}/${event.params.chatId}`);
      const chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;

      const currentLastMessageTime = timestampValue(chatSnap.data()?.lastMessageTime);
      const deletedMessageTime = timestampValue(deletedMessage.timestamp);
      if (
        currentLastMessageTime &&
        deletedMessageTime &&
        deletedMessageTime.toMillis() < currentLastMessageTime.toMillis()
      ) {
        return;
      }

      const stillExists = await refreshChatSummaryFromLatestMessage(chatRef);
      logger.info('onChatMessageDeleted: refreshed chat after message delete', {
        chatId: event.params.chatId,
        messageId: event.params.messageId,
        stillExists,
      });
    } catch (error) {
      logger.error('onChatMessageDeleted: unhandled error', {
        chatId: event.params.chatId,
        messageId: event.params.messageId,
        error,
      });
      throw error;
    }
  },
);

// ── Funcion 6 - Limpieza del cooldown al borrar una solicitud ─────────────────

// Cuando una solicitud se elimina (rechazo, cancelación o aceptación), borrar
// el doc de rate-limit por par (sender, receiver) para que una nueva solicitud
// legítima vuelva a notificar sin esperar al cooldown.
export const onFriendRequestDeleted = onDocumentDeleted(
  { document: 'friend_requests/{requestId}', region: 'europe-southwest1' },
  async (event) => {
    try {
      const request = event.data?.data();
      if (!request) return;
      const senderId = request.senderId as string | undefined;
      const receiverId = request.receiverId as string | undefined;
      if (!senderId || !receiverId) return;

      await db
        .collection(friendRequestNotificationLimitsCollection)
        .doc(`${senderId}_${receiverId}`)
        .delete();
    } catch (error) {
      logger.error('onFriendRequestDeleted: unhandled error', {
        requestId: event.params.requestId,
        error,
      });
      throw error;
    }
  },
);
