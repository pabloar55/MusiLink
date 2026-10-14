import {
  DocumentData,
  DocumentReference,
  FieldValue,
  QuerySnapshot,
  Timestamp,
  Transaction,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import {
  onDocumentCreated,
  onDocumentUpdated,
} from 'firebase-functions/v2/firestore';

import { db } from './firebase';
import { timestampMillis } from './firestore_values';
import {
  CandidateProfile,
  RecommendationResult,
  UserMusicProfile,
  artistMatchKeys,
  calculateRecommendation,
  candidateProfileFromData,
  genreMatchKeys,
  readMusicProfile,
} from './recommendation_scoring';

const recommendationProfilesCollection = 'music_recommendation_profiles';
const recommendationsCollection = 'recommendations';
const recommendationSyncStateCollection = 'recommendation_sync_state';
const maxArtistCandidateProfiles = 300;
const maxGenreCandidateProfiles = 100;
const maxStoredRecommendations = 100;
const maxRecommendationPublicationWrites = 500;
const maxReciprocalRecommendationUsers = 100;
const recommendationSnapshotVersion = 1;
const recommendationProfileSchemaVersion = 2;

interface PublicProfileSnapshot extends UserMusicProfile {
  displayName: string;
  username: string;
  photoUrl: string;
}

function readPublicProfileSnapshot(
  data: DocumentData | undefined,
): PublicProfileSnapshot | undefined {
  const displayName = typeof data?.displayName === 'string' ? data.displayName.trim() : '';
  const username = typeof data?.username === 'string' ? data.username.trim() : '';
  const photoUrl = typeof data?.photoUrl === 'string' ? data.photoUrl.trim() : '';
  if (displayName.length === 0 || username.length === 0) return undefined;

  return {
    displayName,
    username,
    photoUrl,
    ...readMusicProfile(data),
  };
}

function publicProfileIdentityChanged(
  before: PublicProfileSnapshot | undefined,
  after: PublicProfileSnapshot | undefined,
): boolean {
  if (!before || !after) return before !== after;
  return before.displayName !== after.displayName ||
    before.username !== after.username ||
    before.photoUrl !== after.photoUrl;
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
    !sameStringList(before.topArtistKeys, after.topArtistKeys) ||
    !sameStringList(before.topGenreNames, after.topGenreNames);
}

function recommendationRefreshRequestedAtMillis(
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): number | undefined {
  const beforeMillis = timestampMillis(before?.recommendationsRefreshRequestedAt);
  const afterMillis = timestampMillis(after?.recommendationsRefreshRequestedAt);
  return afterMillis !== undefined && afterMillis !== beforeMillis
    ? afterMillis
    : undefined;
}

function musicProfileVersion(data: DocumentData | undefined): number {
  const value = data?.musicProfileVersion;
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : 0;
}

export function recommendationGenerationCovers(
  data: DocumentData | undefined,
  sourceVersion: number,
  refreshRequestedAtMillis?: number,
): boolean {
  const generatedVersion = data?.recommendationsGeneratedForMusicProfileVersion;
  if (typeof generatedVersion !== 'number'
      || !Number.isInteger(generatedVersion)
      || generatedVersion < sourceVersion) {
    return false;
  }
  if (refreshRequestedAtMillis === undefined) return true;

  const generatedAtMillis = timestampMillis(data?.recommendationsGeneratedAt);
  return generatedAtMillis !== undefined
    && generatedAtMillis >= refreshRequestedAtMillis;
}

function compareTimestamps(left: Timestamp, right: Timestamp): number {
  if (left.seconds !== right.seconds) return left.seconds - right.seconds;
  return left.nanoseconds - right.nanoseconds;
}

function chunks<T>(values: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

async function addCandidateMatches(
  uid: string,
  field: 'artistMatchKeys' | 'genreMatchKeys',
  values: string[],
  limitPerQuery: number,
  candidates: Map<string, CandidateProfile>,
): Promise<number> {
  if (values.length === 0) return 0;

  const snapshots = await Promise.all(chunks(values, 30).map((page) =>
    db
      .collection(recommendationProfilesCollection)
      .where(field, 'array-contains-any', page)
      .orderBy('updatedAt', 'desc')
      .limit(limitPerQuery)
      .get(),
  ));

  let documentsRead = 0;
  for (const snapshot of snapshots) {
    documentsRead += snapshot.size;
    for (const doc of snapshot.docs) {
      if (doc.id === uid || candidates.has(doc.id)) continue;
      const candidate = candidateProfileFromData(doc.id, doc.data());
      if (candidate) candidates.set(doc.id, candidate);
    }
  }
  return documentsRead;
}

async function findCandidateProfiles(
  uid: string,
  profiles: UserMusicProfile[],
): Promise<{ candidates: Map<string, CandidateProfile>; documentsRead: number }> {
  const artists = [...new Set(profiles.flatMap(artistMatchKeys))];
  const genres = [...new Set(profiles.flatMap(genreMatchKeys))];
  const candidates = new Map<string, CandidateProfile>();
  const [artistDocumentsRead, genreDocumentsRead] = await Promise.all([
    addCandidateMatches(
      uid,
      'artistMatchKeys',
      artists,
      maxArtistCandidateProfiles,
      candidates,
    ),
    addCandidateMatches(
      uid,
      'genreMatchKeys',
      genres,
      maxGenreCandidateProfiles,
      candidates,
    ),
  ]);
  return {
    candidates,
    documentsRead: artistDocumentsRead + genreDocumentsRead,
  };
}

function userDocRef(uid: string): DocumentReference {
  return db.collection('users').doc(uid);
}

async function keepDeletedProfileMinimal(
  uid: string,
  data: DocumentData | undefined,
): Promise<void> {
  if (data?.username !== 'deleted_user') return;
  const current = await userDocRef(uid).get();
  const currentData = current.data();
  const minimal =
    currentData?.displayName === 'Deleted user' &&
    currentData?.username === 'deleted_user' &&
    currentData?.photoUrl === '' &&
    Object.keys(currentData ?? {}).length === 3;
  if (minimal) return;
  await userDocRef(uid).set({
    displayName: 'Deleted user',
    username: 'deleted_user',
    photoUrl: '',
  });
}

function recommendationSnapshotData(
  snapshot: PublicProfileSnapshot,
  generatedAt: Timestamp,
): DocumentData {
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

async function loadPublicProfileSnapshots(
  uids: string[],
): Promise<Map<string, PublicProfileSnapshot>> {
  if (uids.length === 0) return new Map();

  const snapshots = await db.getAll(...uids.map(userDocRef));
  const profiles = new Map<string, PublicProfileSnapshot>();
  for (const snapshot of snapshots) {
    const profile = readPublicProfileSnapshot(snapshot.data());
    if (snapshot.exists && profile) profiles.set(snapshot.id, profile);
  }
  return profiles;
}

async function updateStoredProfileSnapshots(
  uid: string,
  snapshot: PublicProfileSnapshot,
  eventId: string,
  eventUpdatedAt: Timestamp,
): Promise<void> {
  const userRef = userDocRef(uid);
  const syncRef = db.collection(recommendationSyncStateCollection).doc(uid);
  const claimed = await db.runTransaction(async (transaction) => {
    const [current, sync] = await Promise.all([
      transaction.get(userRef),
      transaction.get(syncRef),
    ]);
    const currentSnapshot = readPublicProfileSnapshot(current.data());
    if (!currentSnapshot || publicProfileIdentityChanged(currentSnapshot, snapshot)) return false;

    const syncData = sync.data();
    if (syncData?.completedIdentityEventId === eventId) return false;
    const targetAt = syncData?.targetIdentityEventUpdatedAt;
    if (targetAt instanceof Timestamp && compareTimestamps(targetAt, eventUpdatedAt) > 0) {
      return false;
    }

    transaction.set(syncRef, {
      targetIdentityEventId: eventId,
      targetIdentityEventUpdatedAt: eventUpdatedAt,
      targetIdentityRequestedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  });
  if (!claimed) return;

  const recommendations = await db
    .collectionGroup(recommendationsCollection)
    .where('userId', '==', uid)
    .get();
  for (const page of chunks(recommendations.docs, 300)) {
    const applied = await db.runTransaction(async (transaction) => {
      const [current, sync, ...targets] = await transaction.getAll(
        userRef,
        syncRef,
        ...page.map((doc) => doc.ref),
      );
      const currentSnapshot = readPublicProfileSnapshot(current.data());
      if (!currentSnapshot || publicProfileIdentityChanged(currentSnapshot, snapshot)) {
        return false;
      }
      if (sync.data()?.targetIdentityEventId !== eventId) return false;

      const generatedAt = Timestamp.now();
      targets.forEach((target) => {
        if (!target.exists) return;
        transaction.update(target.ref, {
          'profileSnapshot.displayName': snapshot.displayName,
          'profileSnapshot.username': snapshot.username,
          'profileSnapshot.photoUrl': snapshot.photoUrl,
          snapshotGeneratedAt: generatedAt,
        });
      });
      return true;
    });
    if (!applied) return;
  }

  await db.runTransaction(async (transaction) => {
    const sync = await transaction.get(syncRef);
    if (sync.data()?.targetIdentityEventId !== eventId) return;
    transaction.set(syncRef, {
      completedIdentityEventId: eventId,
      completedIdentityEventUpdatedAt: eventUpdatedAt,
      completedIdentityAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  logger.info('updateStoredProfileSnapshots: updated recommendation snapshots', {
    uid,
    recommendationCount: recommendations.size,
  });
}

interface RecommendationWrite {
  ref: DocumentReference;
  data?: DocumentData;
}

interface OwnRecommendationPlan {
  writes: RecommendationWrite[];
  count: number;
  candidateDocumentsRead: number;
  candidateCount: number;
}

async function planOwnRecommendations(
  uid: string,
  profile: UserMusicProfile,
  sourceVersion: number,
  generatedAt: Timestamp,
): Promise<OwnRecommendationPlan> {
  if (profile.topArtistNames.length === 0 && profile.topGenreNames.length === 0) {
    return {
      writes: [],
      count: 0,
      candidateDocumentsRead: 0,
      candidateCount: 0,
    };
  }

  const { candidates, documentsRead } = await findCandidateProfiles(uid, [profile]);
  const calculatedRecommendations = [...candidates.values()]
    .map((candidate) => calculateRecommendation(profile, candidate))
    .filter((result): result is RecommendationResult => result !== null)
    .sort((a, b) => b.score - a.score || a.uid.localeCompare(b.uid))
    .slice(0, maxStoredRecommendations);
  const profilesByUid = await loadPublicProfileSnapshots(
    calculatedRecommendations.map((recommendation) => recommendation.uid),
  );
  const recommendations = calculatedRecommendations.flatMap((recommendation) => {
    const profileSnapshot = profilesByUid.get(recommendation.uid);
    return profileSnapshot ? [{ recommendation, profileSnapshot }] : [];
  });
  return {
    writes: recommendations.map(({ recommendation, profileSnapshot }) => ({
      ref: db.doc(`users/${uid}/${recommendationsCollection}/${recommendation.uid}`),
      data: {
        userId: recommendation.uid,
        score: recommendation.score,
        sharedArtistNames: recommendation.sharedArtistNames,
        sharedGenreNames: recommendation.sharedGenreNames,
        generatedAt,
        sourceMusicProfileVersion: sourceVersion,
        ...recommendationSnapshotData(profileSnapshot, generatedAt),
      },
    })),
    count: recommendations.length,
    candidateDocumentsRead: documentsRead,
    candidateCount: candidates.size,
  };
}

async function matchingCandidateProfiles(
  uid: string,
  profiles: UserMusicProfile[],
): Promise<Map<string, CandidateProfile>> {
  const { candidates } = await findCandidateProfiles(uid, profiles);
  return new Map([...candidates.entries()].slice(0, maxReciprocalRecommendationUsers));
}

function planReciprocalRecommendations(
  uid: string,
  profile: UserMusicProfile,
  profileSnapshot: PublicProfileSnapshot,
  candidates: Map<string, CandidateProfile>,
  sourceVersion: number,
  generatedAt: Timestamp,
): RecommendationWrite[] {
  return [...candidates.values()].map((candidate) => {
    const recommendation = calculateRecommendation(candidate, {
      uid,
      topArtistNames: profile.topArtistNames,
      topArtistKeys: profile.topArtistKeys,
      topGenreNames: profile.topGenreNames,
    });
    const ref = db.doc(`users/${candidate.uid}/${recommendationsCollection}/${uid}`);

    if (recommendation === null) {
      return { ref };
    }

    return {
      ref,
      data: {
        userId: uid,
        score: recommendation.score,
        sharedArtistNames: recommendation.sharedArtistNames,
        sharedGenreNames: recommendation.sharedGenreNames,
        generatedAt,
        sourceMusicProfileVersion: sourceVersion,
        ...recommendationSnapshotData(profileSnapshot, generatedAt),
      },
    };
  });
}

function cappedReciprocalWrites(
  incoming: RecommendationWrite,
  existing: QuerySnapshot,
): RecommendationWrite[] {
  const candidates = existing.docs
    .filter((doc) => doc.id !== incoming.ref.id)
    .map((doc) => ({ ref: doc.ref, data: doc.data() }));
  if (incoming.data) candidates.push({ ref: incoming.ref, data: incoming.data });
  const score = (data: DocumentData): number =>
    typeof data.score === 'number' && Number.isFinite(data.score) ? data.score : 0;
  candidates.sort((a, b) => score(b.data) - score(a.data)
    || a.ref.id.localeCompare(b.ref.id));
  const retainedIds = new Set(
    candidates.slice(0, maxStoredRecommendations).map((candidate) => candidate.ref.id),
  );
  const writes: RecommendationWrite[] = existing.docs
    .filter((doc) => !retainedIds.has(doc.id))
    .map((doc) => ({ ref: doc.ref }));
  if (incoming.data && retainedIds.has(incoming.ref.id)) writes.push(incoming);
  return writes;
}

function writeRecommendationProfile(
  transaction: Transaction,
  uid: string,
  profile: UserMusicProfile,
  sourceVersion: number,
): void {
  const ref = db.collection(recommendationProfilesCollection).doc(uid);
  const artistKeys = artistMatchKeys(profile);
  const genreKeys = genreMatchKeys(profile);
  if (artistKeys.length === 0 && genreKeys.length === 0) {
    transaction.delete(ref);
    return;
  }
  transaction.set(ref, {
    uid,
    schemaVersion: recommendationProfileSchemaVersion,
    sourceMusicProfileVersion: sourceVersion,
    artistMatchKeys: artistKeys,
    genreMatchKeys: genreKeys,
    topArtistNames: profile.topArtistNames,
    topArtistKeys: profile.topArtistKeys,
    topGenreNames: profile.topGenreNames,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function rebuildMusicRecommendations(
  uid: string,
  before: UserMusicProfile,
  after: UserMusicProfile,
  profileSnapshot: PublicProfileSnapshot,
  sourceVersion: number,
  options: { refreshRequestedAtMillis?: number } = {},
): Promise<void> {
  const profileChanged = musicProfileChanged(before, after);
  const refreshRequestedAtMillis = options.refreshRequestedAtMillis;
  const forceSelfRefresh = refreshRequestedAtMillis !== undefined;
  if (!profileChanged && !forceSelfRefresh) return;

  const initial = await userDocRef(uid).get();
  const initialData = initial.data();
  if (musicProfileVersion(initialData) !== sourceVersion
      || musicProfileChanged(readMusicProfile(initialData), after)) {
    logger.info('rebuildMusicRecommendations: coalesced obsolete event', {
      uid,
      sourceVersion,
    });
    return;
  }
  if (recommendationGenerationCovers(
    initialData,
    sourceVersion,
    refreshRequestedAtMillis,
  )) {
    logger.info('rebuildMusicRecommendations: skipped duplicate event', {
      uid,
      sourceVersion,
    });
    return;
  }

  const reciprocalCandidates = profileChanged
    ? await matchingCandidateProfiles(uid, [before, after])
    : new Map<string, CandidateProfile>();
  const generatedAt = Timestamp.now();
  const ownPlan = await planOwnRecommendations(uid, after, sourceVersion, generatedAt);
  const reciprocalWrites = profileChanged
    ? planReciprocalRecommendations(
      uid,
      after,
      profileSnapshot,
      reciprocalCandidates,
      sourceVersion,
      generatedAt,
    )
    : [];
  let publication: 'pruned' | 'published' | 'obsolete';
  do {
    publication = await db.runTransaction(async (transaction) => {
      const current = await transaction.get(userDocRef(uid));
      const currentData = current.data();
      if (musicProfileVersion(currentData) !== sourceVersion
          || musicProfileChanged(readMusicProfile(currentData), after)
          || recommendationGenerationCovers(
            currentData,
            sourceVersion,
            refreshRequestedAtMillis,
          )) {
        return 'obsolete';
      }

      // Read every affected list inside the transaction so concurrent reciprocal
      // updates and rebuilds cannot race past the cap or escape stale cleanup.
      const [ownExisting, ...reciprocalExisting] = await Promise.all([
        transaction.get(db.collection(`users/${uid}/${recommendationsCollection}`)),
        ...reciprocalWrites.map((write) => transaction.get(write.ref.parent)),
      ]);
      const ownIds = new Set(ownPlan.writes.map((write) => write.ref.id));
      const writes: RecommendationWrite[] = [
        ...ownPlan.writes,
        ...ownExisting.docs.filter((doc) => !ownIds.has(doc.id))
          .map((doc) => ({ ref: doc.ref })),
        ...reciprocalWrites.flatMap((write, index) =>
          cappedReciprocalWrites(write, reciprocalExisting[index])),
      ];
      const writeCount = writes.length + (profileChanged ? 1 : 0) + 1;
      if (writeCount > maxRecommendationPublicationWrites) {
        // Legacy lists may already contain arbitrarily many entries. Remove only
        // stale entries in bounded, version-checked steps; publish the generation
        // marker only after the remaining writes fit in one atomic transaction.
        writes.filter((write) => !write.data)
          .slice(0, maxRecommendationPublicationWrites)
          .forEach((write) => transaction.delete(write.ref));
        return 'pruned';
      }

      if (profileChanged) writeRecommendationProfile(transaction, uid, after, sourceVersion);
      writes.forEach((write) => {
        if (write.data) transaction.set(write.ref, write.data);
        else transaction.delete(write.ref);
      });
      transaction.update(userDocRef(uid), {
        recommendationsGeneratedAt: generatedAt,
        recommendationsGeneratedForMusicProfileVersion: sourceVersion,
        recommendationsCount: ownPlan.count,
      });
      return 'published';
    });
  } while (publication === 'pruned');

  logger.info('rebuildMusicRecommendations: publication finished', {
    uid,
    sourceVersion,
    published: publication === 'published',
    candidateDocumentsRead: ownPlan.candidateDocumentsRead,
    candidateCount: ownPlan.candidateCount,
    recommendationCount: ownPlan.count,
    reciprocalCount: reciprocalWrites.length,
  });
}

// ── Función 2 — Recomendaciones musicales ─────────────────────────────────────

// Rebuilds recommendation lists when a user's music taste changes.
// The changed user's full list is rebuilt, and matching existing users get a
// reciprocal recommendation upsert/delete so discovery does not wait for them
// to edit their own profile.
export const onUserMusicProfileCreated = onDocumentCreated(
  { document: 'users/{userId}', region: 'europe-southwest1' },
  async (event) => {
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
      }, after, profileSnapshot, musicProfileVersion(afterData));
      await keepDeletedProfileMinimal(event.params.userId, afterData);
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
      const beforeSnapshot = readPublicProfileSnapshot(beforeData);
      const afterSnapshot = readPublicProfileSnapshot(afterData);
      if (!afterSnapshot) {
        throw new Error('A valid public profile is required to update recommendations.');
      }
      const refreshRequestedAtMillis = recommendationRefreshRequestedAtMillis(
        beforeData,
        afterData,
      );
      await rebuildMusicRecommendations(
        event.params.userId,
        before,
        after,
        afterSnapshot,
        musicProfileVersion(afterData),
        { refreshRequestedAtMillis },
      );
      if (afterSnapshot.username !== 'deleted_user'
          && publicProfileIdentityChanged(beforeSnapshot, afterSnapshot)) {
        await updateStoredProfileSnapshots(
          event.params.userId,
          afterSnapshot,
          event.id,
          event.data!.after.updateTime,
        );
      }
      await keepDeletedProfileMinimal(event.params.userId, afterData);
    } catch (error) {
      logger.error('onUserMusicProfileChanged: unhandled error', {
        userId: event.params.userId,
        error,
      });
      throw error;
    }
  },
);
