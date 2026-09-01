"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.saveMusicProfile = void 0;
exports.parseMusicProfilePayload = parseMusicProfilePayload;
exports.buildMusicProfileFields = buildMusicProfileFields;
exports.writeMusicProfile = writeMusicProfile;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const https_1 = require("firebase-functions/v2/https");
const firebase_1 = require("./firebase");
const genre_normalizer_1 = require("./genre_normalizer");
const recommendations_1 = require("./recommendations");
const maxArtists = 30;
const maxGenres = 10;
const maxArtistGenres = 50;
const maxArtistNameBytes = 300;
const maxGenreNameBytes = 200;
const maxImageUrlBytes = 2048;
const spotifyArtistIdPattern = /^[A-Za-z0-9]{22}$/;
const spotifyImageUrlPattern = /^https:\/\/i[.]scdn[.]co\/image\/[A-Za-z0-9]+$/;
function utf8Length(value) {
    return Buffer.byteLength(value, 'utf8');
}
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function hasOnlyKeys(value, allowed) {
    return Object.keys(value).every((key) => allowed.includes(key));
}
function invalid(message) {
    throw new https_1.HttpsError('invalid-argument', message);
}
function parseArtist(value) {
    if (!isRecord(value)
        || !hasOnlyKeys(value, ['genres', 'imageUrl', 'name', 'spotifyId'])) {
        return invalid('Each artist must contain only supported fields.');
    }
    const { name, imageUrl, genres, spotifyId } = value;
    if (typeof name !== 'string'
        || name.trim().length === 0
        || utf8Length(name.trim()) > maxArtistNameBytes) {
        return invalid('Each artist must have a valid name.');
    }
    if (typeof imageUrl !== 'string'
        || utf8Length(imageUrl) > maxImageUrlBytes
        || (imageUrl.length > 0 && !spotifyImageUrlPattern.test(imageUrl))) {
        return invalid('Each artist must have a valid image URL.');
    }
    if (!Array.isArray(genres) || genres.length > maxArtistGenres) {
        return invalid('Each artist must have a valid genre list.');
    }
    const parsedGenres = genres.map((genre) => {
        if (typeof genre !== 'string'
            || genre.trim().length === 0
            || utf8Length(genre.trim()) > maxGenreNameBytes) {
            return invalid('Each artist genre must be a bounded string.');
        }
        return genre.trim();
    });
    if (spotifyId !== undefined
        && (typeof spotifyId !== 'string' || !spotifyArtistIdPattern.test(spotifyId))) {
        return invalid('Each Spotify artist ID must be valid.');
    }
    return {
        name: name.trim(),
        imageUrl,
        genres: parsedGenres,
        ...(typeof spotifyId === 'string' ? { spotifyId } : {}),
    };
}
function parseMusicProfilePayload(value) {
    if (!isRecord(value) || !hasOnlyKeys(value, ['artists'])) {
        return invalid('A valid music profile payload is required.');
    }
    if (!Array.isArray(value.artists) || value.artists.length > maxArtists) {
        return invalid(`artists must contain at most ${maxArtists} entries.`);
    }
    const artists = value.artists.map(parseArtist);
    const identities = new Set();
    for (const artist of artists) {
        const identity = artist.spotifyId
            ? `spotify:${artist.spotifyId}`
            : `name:${(0, recommendations_1.normalizeArtistIdentityName)(artist.name)}`;
        if (identity.endsWith(':') || identities.has(identity)) {
            return invalid('artists must not contain duplicates.');
        }
        identities.add(identity);
    }
    return artists;
}
function deriveTopGenres(artists) {
    const counts = new Map();
    let firstSeen = 0;
    for (const artist of artists) {
        for (const rawGenre of artist.genres) {
            const genre = (0, genre_normalizer_1.normalizeGenreName)(rawGenre);
            if (!genre)
                continue;
            const existing = counts.get(genre);
            if (existing) {
                existing.count++;
            }
            else {
                counts.set(genre, { count: 1, firstSeen: firstSeen++ });
            }
        }
    }
    const sorted = [...counts.entries()].sort((left, right) => right[1].count - left[1].count || left[1].firstSeen - right[1].firstSeen);
    const totalMentions = sorted.reduce((sum, entry) => sum + entry[1].count, 0);
    if (totalMentions === 0)
        return [];
    return sorted.slice(0, maxGenres).map(([name, value]) => ({
        name,
        count: value.count,
        percentage: value.count / totalMentions * 100,
    }));
}
function buildMusicProfileFields(artists, updatedAt = firestore_1.FieldValue.serverTimestamp()) {
    const topGenres = deriveTopGenres(artists);
    return {
        topArtists: artists,
        topGenres,
        topArtistNames: artists.map((artist) => artist.name),
        topArtistKeys: artists.map((artist) => artist.spotifyId
            ? `spotify:${artist.spotifyId}`
            : `name:${(0, recommendations_1.normalizeArtistIdentityName)(artist.name)}`),
        topGenreNames: topGenres.map((genre) => genre.name),
        artistIdentityVersion: 1,
        musicDataUpdatedAt: updatedAt,
        recommendationsRefreshRequestedAt: updatedAt,
    };
}
async function writeMusicProfile(firestore, uid, artists) {
    const userRef = firestore.doc(`users/${uid}`);
    const deletionRef = firestore.doc(`account_deletions/${uid}`);
    await firestore.runTransaction(async (transaction) => {
        const [userSnapshot, deletionSnapshot] = await Promise.all([
            transaction.get(userRef),
            transaction.get(deletionRef),
        ]);
        if (!userSnapshot.exists
            || userSnapshot.get('username') === 'deleted_user'
            || deletionSnapshot.exists) {
            throw new https_1.HttpsError('failed-precondition', 'An active user profile is required.');
        }
        transaction.update(userRef, buildMusicProfileFields(artists));
    });
}
exports.saveMusicProfile = (0, https_1.onCall)({ region: 'europe-southwest1', enforceAppCheck: true }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    try {
        const artists = parseMusicProfilePayload(request.data);
        await writeMusicProfile(firebase_1.db, uid, artists);
        return { updated: true };
    }
    catch (error) {
        if (error instanceof https_1.HttpsError)
            throw error;
        v2_1.logger.error('saveMusicProfile: unhandled error', { uid, error });
        throw new https_1.HttpsError('internal', 'Could not save the music profile.');
    }
});
//# sourceMappingURL=music_profile_write.js.map