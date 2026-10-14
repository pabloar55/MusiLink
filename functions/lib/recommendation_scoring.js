"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.readMusicProfile = readMusicProfile;
exports.candidateProfileFromData = candidateProfileFromData;
exports.similarityScore = similarityScore;
exports.calculateRecommendation = calculateRecommendation;
exports.artistMatchKeys = artistMatchKeys;
exports.genreMatchKeys = genreMatchKeys;
const artist_identity_1 = require("./artist_identity");
const firestore_values_1 = require("./firestore_values");
// Reglas puras de las recomendaciones: lectura del perfil musical, puntuación
// y claves con las que se buscan candidatos. El cliente calcula la misma
// puntuación en `lib/utils/music_compatibility.dart`.
const maxRecommendationInputArtists = 30;
const maxRecommendationInputGenres = 10;
const artistScoreWeight = 70;
const genreScoreWeight = 30;
const artistEvidenceTarget = 7;
const genreEvidenceTarget = 4;
function readMusicProfile(data) {
    const topArtistNames = (0, firestore_values_1.stringList)(data?.topArtistNames).slice(0, maxRecommendationInputArtists);
    return {
        topArtistNames,
        topArtistKeys: readArtistIdentityKeys(data, topArtistNames),
        topGenreNames: (0, firestore_values_1.stringList)(data?.topGenreNames).slice(0, maxRecommendationInputGenres),
    };
}
function readArtistIdentityKeys(data, names) {
    const storedKeys = (0, firestore_values_1.stringList)(data?.topArtistKeys)
        .slice(0, maxRecommendationInputArtists);
    const storedArtists = Array.isArray(data?.topArtists) ? data.topArtists : [];
    return names.map((name, index) => {
        const rawArtist = storedArtists[index];
        const rawName = typeof rawArtist?.name === 'string' ? rawArtist.name.trim() : '';
        const spotifyId = typeof rawArtist?.spotifyId === 'string' ? rawArtist.spotifyId.trim() : '';
        if ((0, artist_identity_1.normalizeArtistIdentityName)(rawName) === (0, artist_identity_1.normalizeArtistIdentityName)(name)) {
            return (0, artist_identity_1.artistIdentityKey)(name, spotifyId);
        }
        const storedKey = (0, artist_identity_1.normalizedStoredArtistKey)(storedKeys[index] ?? '');
        if (storedKey)
            return storedKey;
        return (0, artist_identity_1.artistIdentityKey)(name);
    });
}
/** Perfil de un documento de `music_recommendation_profiles`. */
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
function normalizedMusicKey(value) {
    return value.trim().toLowerCase();
}
function artistIdentities(profile) {
    const artistsByKey = new Map();
    profile.topArtistNames.forEach((rawName, index) => {
        const name = rawName.trim();
        const normalizedName = (0, artist_identity_1.normalizeArtistIdentityName)(name);
        if (!normalizedName)
            return;
        const key = (0, artist_identity_1.normalizedStoredArtistKey)(profile.topArtistKeys[index] ?? '') ??
            `name:${normalizedName}`;
        if (!artistsByKey.has(key))
            artistsByKey.set(key, { name, key, normalizedName });
    });
    return [...artistsByKey.values()];
}
function sharedArtistNames(leftArtists, rightArtists) {
    const usedLeftIndexes = new Set();
    const shared = [];
    for (const rightArtist of rightArtists) {
        const leftIndex = leftArtists.findIndex((leftArtist, index) => !usedLeftIndexes.has(index) &&
            (0, artist_identity_1.artistIdentitiesMatch)(leftArtist, rightArtist));
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
/** Claves con las que el perfil aparece en las búsquedas de artistas. */
function artistMatchKeys(profile) {
    return [...new Set(artistIdentities(profile)
            .map((artist) => artist.normalizedName)
            .filter((value) => value.length > 0))].slice(0, maxRecommendationInputArtists);
}
/** Claves con las que el perfil aparece en las búsquedas de géneros. */
function genreMatchKeys(profile) {
    return [...new Set(profile.topGenreNames
            .map(normalizedMusicKey)
            .filter((value) => value.length > 0))].slice(0, maxRecommendationInputGenres);
}
//# sourceMappingURL=recommendation_scoring.js.map