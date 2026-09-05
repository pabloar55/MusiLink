"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onUserMusicProfileChanged = exports.onUserMusicProfileCreated = void 0;
exports.readMusicProfile = readMusicProfile;
exports.recommendationGenerationCovers = recommendationGenerationCovers;
exports.normalizeArtistIdentityName = normalizeArtistIdentityName;
exports.similarityScore = similarityScore;
exports.calculateRecommendation = calculateRecommendation;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const firestore_2 = require("firebase-functions/v2/firestore");
const firebase_1 = require("./firebase");
const firestore_values_1 = require("./firestore_values");
const recommendationProfilesCollection = 'music_recommendation_profiles';
const recommendationsCollection = 'recommendations';
const recommendationSyncStateCollection = 'recommendation_sync_state';
const maxRecommendationInputArtists = 30;
const maxRecommendationInputGenres = 10;
const maxArtistCandidateProfiles = 300;
const maxGenreCandidateProfiles = 100;
const maxStoredRecommendations = 100;
const maxRecommendationPublicationWrites = 500;
const maxReciprocalRecommendationUsers = 100;
const artistScoreWeight = 70;
const genreScoreWeight = 30;
const artistEvidenceTarget = 7;
const genreEvidenceTarget = 4;
const recommendationSnapshotVersion = 1;
const recommendationProfileSchemaVersion = 2;
function readMusicProfile(data) {
    const topArtistNames = (0, firestore_values_1.stringList)(data?.topArtistNames).slice(0, maxRecommendationInputArtists);
    return {
        topArtistNames,
        topArtistKeys: readArtistIdentityKeys(data, topArtistNames),
        topGenreNames: (0, firestore_values_1.stringList)(data?.topGenreNames).slice(0, maxRecommendationInputGenres),
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
function recommendationRefreshRequestedAtMillis(before, after) {
    const beforeMillis = (0, firestore_values_1.timestampMillis)(before?.recommendationsRefreshRequestedAt);
    const afterMillis = (0, firestore_values_1.timestampMillis)(after?.recommendationsRefreshRequestedAt);
    return afterMillis !== undefined && afterMillis !== beforeMillis
        ? afterMillis
        : undefined;
}
function musicProfileVersion(data) {
    const value = data?.musicProfileVersion;
    return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : 0;
}
function recommendationGenerationCovers(data, sourceVersion, refreshRequestedAtMillis) {
    const generatedVersion = data?.recommendationsGeneratedForMusicProfileVersion;
    if (typeof generatedVersion !== 'number'
        || !Number.isInteger(generatedVersion)
        || generatedVersion < sourceVersion) {
        return false;
    }
    if (refreshRequestedAtMillis === undefined)
        return true;
    const generatedAtMillis = (0, firestore_values_1.timestampMillis)(data?.recommendationsGeneratedAt);
    return generatedAtMillis !== undefined
        && generatedAtMillis >= refreshRequestedAtMillis;
}
function compareTimestamps(left, right) {
    if (left.seconds !== right.seconds)
        return left.seconds - right.seconds;
    return left.nanoseconds - right.nanoseconds;
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
    const storedKeys = (0, firestore_values_1.stringList)(data?.topArtistKeys)
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
    const topArtistNames = (0, firestore_values_1.stringList)(data.topArtistNames)
        .slice(0, maxRecommendationInputArtists);
    const topArtistKeys = (0, firestore_values_1.stringList)(data.topArtistKeys)
        .slice(0, maxRecommendationInputArtists);
    const topGenreNames = (0, firestore_values_1.stringList)(data.topGenreNames)
        .slice(0, maxRecommendationInputGenres);
    if (topArtistNames.length === 0 && topGenreNames.length === 0)
        return undefined;
    return { uid, topArtistNames, topArtistKeys, topGenreNames };
}
async function addCandidateMatches(uid, field, values, limitPerQuery, candidates) {
    if (values.length === 0)
        return 0;
    const snapshots = await Promise.all(chunks(values, 30).map((page) => firebase_1.db
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
    return firebase_1.db.collection('users').doc(uid);
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
    const snapshots = await firebase_1.db.getAll(...uids.map(userDocRef));
    const profiles = new Map();
    for (const snapshot of snapshots) {
        const profile = readPublicProfileSnapshot(snapshot.data());
        if (snapshot.exists && profile)
            profiles.set(snapshot.id, profile);
    }
    return profiles;
}
async function updateStoredProfileSnapshots(uid, snapshot, eventId, eventUpdatedAt) {
    const userRef = userDocRef(uid);
    const syncRef = firebase_1.db.collection(recommendationSyncStateCollection).doc(uid);
    const claimed = await firebase_1.db.runTransaction(async (transaction) => {
        const [current, sync] = await Promise.all([
            transaction.get(userRef),
            transaction.get(syncRef),
        ]);
        const currentSnapshot = readPublicProfileSnapshot(current.data());
        if (!currentSnapshot || publicProfileIdentityChanged(currentSnapshot, snapshot))
            return false;
        const syncData = sync.data();
        if (syncData?.completedIdentityEventId === eventId)
            return false;
        const targetAt = syncData?.targetIdentityEventUpdatedAt;
        if (targetAt instanceof firestore_1.Timestamp && compareTimestamps(targetAt, eventUpdatedAt) > 0) {
            return false;
        }
        transaction.set(syncRef, {
            targetIdentityEventId: eventId,
            targetIdentityEventUpdatedAt: eventUpdatedAt,
            targetIdentityRequestedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        return true;
    });
    if (!claimed)
        return;
    const recommendations = await firebase_1.db
        .collectionGroup(recommendationsCollection)
        .where('userId', '==', uid)
        .get();
    for (const page of chunks(recommendations.docs, 300)) {
        const applied = await firebase_1.db.runTransaction(async (transaction) => {
            const [current, sync, ...targets] = await transaction.getAll(userRef, syncRef, ...page.map((doc) => doc.ref));
            const currentSnapshot = readPublicProfileSnapshot(current.data());
            if (!currentSnapshot || publicProfileIdentityChanged(currentSnapshot, snapshot)) {
                return false;
            }
            if (sync.data()?.targetIdentityEventId !== eventId)
                return false;
            const generatedAt = firestore_1.Timestamp.now();
            targets.forEach((target) => {
                if (!target.exists)
                    return;
                transaction.update(target.ref, {
                    'profileSnapshot.displayName': snapshot.displayName,
                    'profileSnapshot.username': snapshot.username,
                    'profileSnapshot.photoUrl': snapshot.photoUrl,
                    snapshotGeneratedAt: generatedAt,
                });
            });
            return true;
        });
        if (!applied)
            return;
    }
    await firebase_1.db.runTransaction(async (transaction) => {
        const sync = await transaction.get(syncRef);
        if (sync.data()?.targetIdentityEventId !== eventId)
            return;
        transaction.set(syncRef, {
            completedIdentityEventId: eventId,
            completedIdentityEventUpdatedAt: eventUpdatedAt,
            completedIdentityAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    v2_1.logger.info('updateStoredProfileSnapshots: updated recommendation snapshots', {
        uid,
        recommendationCount: recommendations.size,
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
async function planOwnRecommendations(uid, profile, sourceVersion, generatedAt) {
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
        .filter((result) => result !== null)
        .sort((a, b) => b.score - a.score || a.uid.localeCompare(b.uid))
        .slice(0, maxStoredRecommendations);
    const profilesByUid = await loadPublicProfileSnapshots(calculatedRecommendations.map((recommendation) => recommendation.uid));
    const recommendations = calculatedRecommendations.flatMap((recommendation) => {
        const profileSnapshot = profilesByUid.get(recommendation.uid);
        return profileSnapshot ? [{ recommendation, profileSnapshot }] : [];
    });
    return {
        writes: recommendations.map(({ recommendation, profileSnapshot }) => ({
            ref: firebase_1.db.doc(`users/${uid}/${recommendationsCollection}/${recommendation.uid}`),
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
async function matchingCandidateProfiles(uid, profiles) {
    const { candidates } = await findCandidateProfiles(uid, profiles);
    return new Map([...candidates.entries()].slice(0, maxReciprocalRecommendationUsers));
}
function planReciprocalRecommendations(uid, profile, profileSnapshot, candidates, sourceVersion, generatedAt) {
    return [...candidates.values()].map((candidate) => {
        const recommendation = calculateRecommendation(candidate, {
            uid,
            topArtistNames: profile.topArtistNames,
            topArtistKeys: profile.topArtistKeys,
            topGenreNames: profile.topGenreNames,
        });
        const ref = firebase_1.db.doc(`users/${candidate.uid}/${recommendationsCollection}/${uid}`);
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
function cappedReciprocalWrites(incoming, existing) {
    const candidates = existing.docs
        .filter((doc) => doc.id !== incoming.ref.id)
        .map((doc) => ({ ref: doc.ref, data: doc.data() }));
    if (incoming.data)
        candidates.push({ ref: incoming.ref, data: incoming.data });
    const score = (data) => typeof data.score === 'number' && Number.isFinite(data.score) ? data.score : 0;
    candidates.sort((a, b) => score(b.data) - score(a.data)
        || a.ref.id.localeCompare(b.ref.id));
    const retainedIds = new Set(candidates.slice(0, maxStoredRecommendations).map((candidate) => candidate.ref.id));
    const writes = existing.docs
        .filter((doc) => !retainedIds.has(doc.id))
        .map((doc) => ({ ref: doc.ref }));
    if (incoming.data && retainedIds.has(incoming.ref.id))
        writes.push(incoming);
    return writes;
}
function writeRecommendationProfile(transaction, uid, profile, sourceVersion) {
    const ref = firebase_1.db.collection(recommendationProfilesCollection).doc(uid);
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
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
}
async function rebuildMusicRecommendations(uid, before, after, profileSnapshot, sourceVersion, options = {}) {
    const profileChanged = musicProfileChanged(before, after);
    const refreshRequestedAtMillis = options.refreshRequestedAtMillis;
    const forceSelfRefresh = refreshRequestedAtMillis !== undefined;
    if (!profileChanged && !forceSelfRefresh)
        return;
    const initial = await userDocRef(uid).get();
    const initialData = initial.data();
    if (musicProfileVersion(initialData) !== sourceVersion
        || musicProfileChanged(readMusicProfile(initialData), after)) {
        v2_1.logger.info('rebuildMusicRecommendations: coalesced obsolete event', {
            uid,
            sourceVersion,
        });
        return;
    }
    if (recommendationGenerationCovers(initialData, sourceVersion, refreshRequestedAtMillis)) {
        v2_1.logger.info('rebuildMusicRecommendations: skipped duplicate event', {
            uid,
            sourceVersion,
        });
        return;
    }
    const reciprocalCandidates = profileChanged
        ? await matchingCandidateProfiles(uid, [before, after])
        : new Map();
    const generatedAt = firestore_1.Timestamp.now();
    const ownPlan = await planOwnRecommendations(uid, after, sourceVersion, generatedAt);
    const reciprocalWrites = profileChanged
        ? planReciprocalRecommendations(uid, after, profileSnapshot, reciprocalCandidates, sourceVersion, generatedAt)
        : [];
    let publication;
    do {
        publication = await firebase_1.db.runTransaction(async (transaction) => {
            const current = await transaction.get(userDocRef(uid));
            const currentData = current.data();
            if (musicProfileVersion(currentData) !== sourceVersion
                || musicProfileChanged(readMusicProfile(currentData), after)
                || recommendationGenerationCovers(currentData, sourceVersion, refreshRequestedAtMillis)) {
                return 'obsolete';
            }
            // Read every affected list inside the transaction so concurrent reciprocal
            // updates and rebuilds cannot race past the cap or escape stale cleanup.
            const [ownExisting, ...reciprocalExisting] = await Promise.all([
                transaction.get(firebase_1.db.collection(`users/${uid}/${recommendationsCollection}`)),
                ...reciprocalWrites.map((write) => transaction.get(write.ref.parent)),
            ]);
            const ownIds = new Set(ownPlan.writes.map((write) => write.ref.id));
            const writes = [
                ...ownPlan.writes,
                ...ownExisting.docs.filter((doc) => !ownIds.has(doc.id))
                    .map((doc) => ({ ref: doc.ref })),
                ...reciprocalWrites.flatMap((write, index) => cappedReciprocalWrites(write, reciprocalExisting[index])),
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
            if (profileChanged)
                writeRecommendationProfile(transaction, uid, after, sourceVersion);
            writes.forEach((write) => {
                if (write.data)
                    transaction.set(write.ref, write.data);
                else
                    transaction.delete(write.ref);
            });
            transaction.update(userDocRef(uid), {
                recommendationsGeneratedAt: generatedAt,
                recommendationsGeneratedForMusicProfileVersion: sourceVersion,
                recommendationsCount: ownPlan.count,
            });
            return 'published';
        });
    } while (publication === 'pruned');
    v2_1.logger.info('rebuildMusicRecommendations: publication finished', {
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
exports.onUserMusicProfileCreated = (0, firestore_2.onDocumentCreated)({ document: 'users/{userId}', region: 'europe-southwest1' }, async (event) => {
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
    }
    catch (error) {
        v2_1.logger.error('onUserMusicProfileCreated: unhandled error', {
            userId: event.params.userId,
            error,
        });
        throw error;
    }
});
exports.onUserMusicProfileChanged = (0, firestore_2.onDocumentUpdated)({ document: 'users/{userId}', region: 'europe-southwest1' }, async (event) => {
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
        const refreshRequestedAtMillis = recommendationRefreshRequestedAtMillis(beforeData, afterData);
        await rebuildMusicRecommendations(event.params.userId, before, after, afterSnapshot, musicProfileVersion(afterData), { refreshRequestedAtMillis });
        if (afterSnapshot.username !== 'deleted_user'
            && publicProfileIdentityChanged(beforeSnapshot, afterSnapshot)) {
            await updateStoredProfileSnapshots(event.params.userId, afterSnapshot, event.id, event.data.after.updateTime);
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
//# sourceMappingURL=recommendations.js.map