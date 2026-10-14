"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.searchSpotifyTracks = exports.searchSpotifyArtists = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const v2_1 = require("firebase-functions/v2");
const firebase_1 = require("./firebase");
const rate_limits_1 = require("./rate_limits");
const lastfm_request_1 = require("./lastfm_request");
const catalog_request_1 = require("./catalog_request");
const catalog_genres_1 = require("./catalog_genres");
const spotify_artist_ranking_1 = require("./spotify_artist_ranking");
const spotifyClientId = (0, params_1.defineSecret)('SPOTIFY_CLIENT_ID');
const spotifyClientSecret = (0, params_1.defineSecret)('SPOTIFY_CLIENT_SECRET');
const lastFmApiKey = (0, params_1.defineSecret)('LASTFM_API_KEY');
const spotifyRequestTimeoutMs = 8_000;
// Module-level cache — reused across warm instances (Spotify tokens last 3600 s).
let cachedToken = null;
let tokenExpiresAt = 0;
async function fetchExternal(input, init, timeoutMs, service) {
    try {
        return await fetch(input, {
            ...init,
            signal: AbortSignal.timeout(timeoutMs),
        });
    }
    catch (error) {
        v2_1.logger.warn(`${service} request failed before receiving a response`, {
            reason: error instanceof Error ? error.name : 'unknown',
        });
        throw new https_1.HttpsError('unavailable', `${service} is temporarily unavailable`);
    }
}
async function getSpotifyToken(clientId, clientSecret) {
    const now = Date.now();
    if (cachedToken && now < tokenExpiresAt - 60_000)
        return cachedToken;
    if (!clientId.trim() || !clientSecret.trim()) {
        v2_1.logger.error('Spotify credentials are not configured');
        throw new https_1.HttpsError('failed-precondition', 'Spotify credentials are not configured');
    }
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
    const res = await fetchExternal('https://accounts.spotify.com/api/token', {
        method: 'POST',
        headers: {
            Authorization: `Basic ${credentials}`,
            'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
    }, spotifyRequestTimeoutMs, 'Spotify');
    if (!res.ok) {
        const errorBody = await readResponseSnippet(res);
        v2_1.logger.error('Spotify token request failed', { status: res.status, errorBody });
        throw new https_1.HttpsError('failed-precondition', 'Failed to obtain Spotify token', { status: res.status });
    }
    const data = await res.json();
    if (!(0, catalog_request_1.isRecord)(data) ||
        typeof data.access_token !== 'string' ||
        !data.access_token ||
        typeof data.expires_in !== 'number' ||
        !Number.isFinite(data.expires_in) ||
        data.expires_in <= 0) {
        v2_1.logger.error('Spotify token response was malformed');
        throw new https_1.HttpsError('unavailable', 'Spotify returned an invalid token response');
    }
    cachedToken = data.access_token;
    tokenExpiresAt = now + data.expires_in * 1000;
    return cachedToken;
}
async function readResponseSnippet(res) {
    try {
        return (await res.text()).slice(0, 500);
    }
    catch {
        return '';
    }
}
function spotifyArtistQuery(query) {
    return `artist:${query.replace(/"/g, '').trim()}`;
}
function isSpotifyArtistItem(value) {
    if (!(0, catalog_request_1.isRecord)(value) || typeof value.id !== 'string' || typeof value.name !== 'string') {
        return false;
    }
    if (value.genres !== undefined && (!Array.isArray(value.genres) || !value.genres.every((genre) => typeof genre === 'string'))) {
        return false;
    }
    if (value.images !== undefined && (!Array.isArray(value.images) ||
        !value.images.every((image) => (0, catalog_request_1.isRecord)(image) && typeof image.url === 'string'))) {
        return false;
    }
    if (value.popularity !== undefined && typeof value.popularity !== 'number')
        return false;
    if (value.followers !== undefined && (!(0, catalog_request_1.isRecord)(value.followers) ||
        (value.followers.total !== undefined && typeof value.followers.total !== 'number'))) {
        return false;
    }
    return true;
}
async function getLastFmGenres(artistName, apiKey) {
    try {
        const data = await (0, lastfm_request_1.fetchLastFm)('artist.getTopTags', artistName, apiKey);
        const tags = (0, catalog_request_1.isRecord)(data) && (0, catalog_request_1.isRecord)(data.toptags) ? data.toptags.tag : undefined;
        if (!Array.isArray(tags)) {
            throw new https_1.HttpsError('unavailable', 'Last.fm returned an invalid tag list');
        }
        const validTags = tags.filter((tag) => ((0, catalog_request_1.isRecord)(tag) &&
            typeof tag.name === 'string' && tag.name.trim().length > 0 &&
            (tag.count === undefined || typeof tag.count === 'number' || typeof tag.count === 'string')));
        if (validTags.length !== tags.length) {
            throw new https_1.HttpsError('unavailable', 'Last.fm returned an invalid tag list');
        }
        return (0, catalog_genres_1.normalizeLastFmTags)(validTags);
    }
    catch {
        return [];
    }
}
// ── Function 1 — Search artists ───────────────────────────────────────────────
exports.searchSpotifyArtists = (0, https_1.onCall)({
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [spotifyClientId, spotifyClientSecret, lastFmApiKey],
}, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Login required');
    const { value: query, limit, market } = (0, catalog_request_1.parseSpotifyArtistSearchRequest)(request.data);
    await (0, rate_limits_1.consumeCatalogSearchQuota)(firebase_1.db, request.auth.uid, 'spotifySearch');
    const spotifyLimit = 10;
    const token = await getSpotifyToken(spotifyClientId.value(), spotifyClientSecret.value());
    const url = new URL('https://api.spotify.com/v1/search');
    url.searchParams.set('q', spotifyArtistQuery(query));
    url.searchParams.set('type', 'artist');
    url.searchParams.set('market', market);
    url.searchParams.set('limit', String(spotifyLimit));
    const res = await fetchExternal(url.toString(), {
        headers: { Authorization: `Bearer ${token}` },
    }, spotifyRequestTimeoutMs, 'Spotify');
    if (!res.ok) {
        v2_1.logger.error('Spotify searchArtists failed', { status: res.status, query });
        if (res.status === 429) {
            throw new https_1.HttpsError('resource-exhausted', 'Spotify rate limit reached');
        }
        throw new https_1.HttpsError('internal', 'Spotify search failed');
    }
    const data = await res.json();
    if (!(0, catalog_request_1.isRecord)(data) || !(0, catalog_request_1.isRecord)(data.artists) || !Array.isArray(data.artists.items)) {
        v2_1.logger.error('Spotify searchArtists returned malformed response', { query });
        throw new https_1.HttpsError('internal', 'Spotify search returned malformed response');
    }
    const items = data.artists.items.filter(isSpotifyArtistItem);
    const filtered = (0, spotify_artist_ranking_1.rankSpotifyArtists)(items, query, limit)
        .map((item) => ({
        name: item.name ?? 'Unknown Artist',
        imageUrl: item.images?.[0]?.url ?? '',
        genres: (0, catalog_genres_1.normalizeSpotifyGenres)(item.genres),
        spotifyId: item.id ?? null,
    }));
    const apiKey = lastFmApiKey.value();
    return await Promise.all(filtered.map(async (artist) => {
        if (artist.genres.length > 0)
            return artist;
        const genres = await getLastFmGenres(artist.name, apiKey);
        return { ...artist, genres };
    }));
});
// ── Function 2 — Search tracks ────────────────────────────────────────────────
exports.searchSpotifyTracks = (0, https_1.onCall)({
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [spotifyClientId, spotifyClientSecret],
}, async (request) => {
    try {
        if (!request.auth)
            throw new https_1.HttpsError('unauthenticated', 'Login required');
        const { value: query, limit } = (0, catalog_request_1.parseSpotifySearchRequest)(request.data);
        await (0, rate_limits_1.consumeCatalogSearchQuota)(firebase_1.db, request.auth.uid, 'spotifySearch');
        const token = await getSpotifyToken(spotifyClientId.value(), spotifyClientSecret.value());
        const url = new URL('https://api.spotify.com/v1/search');
        url.searchParams.set('q', query);
        url.searchParams.set('type', 'track');
        url.searchParams.set('limit', String(limit));
        const res = await fetchExternal(url.toString(), {
            headers: { Authorization: `Bearer ${token}` },
        }, spotifyRequestTimeoutMs, 'Spotify');
        if (!res.ok) {
            const errorBody = await readResponseSnippet(res);
            v2_1.logger.error('Spotify searchTracks failed', { status: res.status, query, errorBody });
            if (res.status === 429) {
                throw new https_1.HttpsError('resource-exhausted', 'Spotify rate limit reached');
            }
            throw new https_1.HttpsError('unavailable', 'Spotify search failed', { status: res.status });
        }
        const data = await res.json();
        const items = (0, catalog_request_1.isRecord)(data) && (0, catalog_request_1.isRecord)(data.tracks) ? data.tracks.items : undefined;
        if (!Array.isArray(items)) {
            v2_1.logger.error('Spotify searchTracks returned malformed response', { query });
            throw new https_1.HttpsError('internal', 'Spotify search returned malformed response');
        }
        return items.filter(catalog_request_1.isRecord).map((item) => {
            const artists = Array.isArray(item.artists) ? item.artists.filter(catalog_request_1.isRecord) : [];
            const album = (0, catalog_request_1.isRecord)(item.album) ? item.album : undefined;
            const images = album && Array.isArray(album.images) ? album.images.filter(catalog_request_1.isRecord) : [];
            const id = typeof item.id === 'string' ? item.id : '';
            return {
                title: typeof item.name === 'string' ? item.name : 'Unknown',
                artist: typeof artists[0]?.name === 'string' ? artists[0].name : 'Unknown Artist',
                imageUrl: typeof images[0]?.url === 'string' ? images[0].url : '',
                spotifyUrl: id ? `https://open.spotify.com/track/${id}` : '',
            };
        });
    }
    catch (error) {
        if (error instanceof https_1.HttpsError)
            throw error;
        v2_1.logger.error('Spotify searchTracks crashed', { error });
        throw new https_1.HttpsError('internal', 'Spotify search crashed');
    }
});
//# sourceMappingURL=spotify.js.map