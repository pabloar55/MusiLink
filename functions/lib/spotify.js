"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.searchSpotifyTracks = exports.searchSpotifyArtists = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const v2_1 = require("firebase-functions/v2");
const spotifyClientId = (0, params_1.defineSecret)('SPOTIFY_CLIENT_ID');
const spotifyClientSecret = (0, params_1.defineSecret)('SPOTIFY_CLIENT_SECRET');
const lastFmApiKey = (0, params_1.defineSecret)('LASTFM_API_KEY');
const defaultSpotifyMarket = 'ES';
const maxSpotifyGenresPerArtist = 5;
const maxLastFmGenresPerArtist = 2;
const minLastFmTagCount = 10;
const spotifyRetryStatuses = new Set([429, 502, 503, 504]);
// Module-level cache — reused across warm instances (Spotify tokens last 3600 s).
let cachedToken = null;
let tokenExpiresAt = 0;
async function getSpotifyToken(clientId, clientSecret) {
    const now = Date.now();
    if (cachedToken && now < tokenExpiresAt - 60_000)
        return cachedToken;
    if (!clientId.trim() || !clientSecret.trim()) {
        v2_1.logger.error('Spotify credentials are not configured');
        throw new https_1.HttpsError('failed-precondition', 'Spotify credentials are not configured');
    }
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
    const res = await fetch('https://accounts.spotify.com/api/token', {
        method: 'POST',
        headers: {
            Authorization: `Basic ${credentials}`,
            'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
    });
    if (!res.ok) {
        const errorBody = await readResponseSnippet(res);
        v2_1.logger.error('Spotify token request failed', { status: res.status, errorBody });
        throw new https_1.HttpsError('failed-precondition', 'Failed to obtain Spotify token', { status: res.status });
    }
    const data = await res.json();
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
async function sleep(ms) {
    await new Promise((resolve) => setTimeout(resolve, ms));
}
function retryDelayMs(res, attempt) {
    const retryAfter = Number(res.headers.get('retry-after'));
    if (Number.isFinite(retryAfter) && retryAfter > 0) {
        return Math.min(retryAfter * 1000, 3000);
    }
    return 300 * (attempt + 1);
}
async function fetchSpotifyWithRetry(url, token) {
    let lastResponse = null;
    for (let attempt = 0; attempt < 3; attempt++) {
        const res = await fetch(url, {
            headers: { Authorization: `Bearer ${token}` },
        });
        if (!spotifyRetryStatuses.has(res.status) || attempt === 2)
            return res;
        lastResponse = res;
        await sleep(retryDelayMs(res, attempt));
    }
    return lastResponse;
}
function sanitizeSpotifyMarket(value) {
    if (typeof value !== 'string')
        return defaultSpotifyMarket;
    const market = value.trim().toUpperCase();
    return /^[A-Z]{2}$/.test(market) ? market : defaultSpotifyMarket;
}
function spotifyArtistQuery(query) {
    return `artist:${query.replace(/"/g, '').trim()}`;
}
function normalizeArtistName(value) {
    return value
        .normalize('NFKD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/'/g, '')
        .replace(/&/g, ' and ')
        .replace(/[^a-z0-9]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}
const genreAliases = new Map([
    ['alt rock', 'alternative rock'],
    ['alternative music', 'alternative'],
    ['corridos belicos', 'corridos belicos'],
    ['drum and bass', 'drum and bass'],
    ['dnb', 'drum and bass'],
    ['edm', 'electronic'],
    ['electro', 'electronic'],
    ['electronica', 'electronic'],
    ['electronic music', 'electronic'],
    ['hiphop', 'hip hop'],
    ['hip hop music', 'hip hop'],
    ['rap', 'hip hop'],
    ['rhythm and blues', 'r&b'],
    ['rnb', 'r&b'],
    ['singer songwriter', 'singer-songwriter'],
    ['synth pop', 'synthpop'],
]);
const blockedGenreTags = new Set([
    '00s',
    '10s',
    '20s',
    '60s',
    '70s',
    '80s',
    '90s',
    'american',
    'australian',
    'belgian',
    'brazilian',
    'british',
    'canadian',
    'chilean',
    'chinese',
    'colombian',
    'danish',
    'dutch',
    'english',
    'favorite',
    'favorites',
    'favourite',
    'female vocalists',
    'finnish',
    'french',
    'german',
    'greek',
    'icelandic',
    'irish',
    'italian',
    'japanese',
    'korean',
    'male vocalists',
    'mexican',
    'mexico',
    'new zealand',
    'norwegian',
    'polish',
    'portuguese',
    'puerto rican',
    'puerto rico',
    'romanian',
    'russian',
    'scottish',
    'seen live',
    'spanish',
    'spain',
    'swedish',
    'turkish',
    'uk',
    'ukrainian',
    'usa',
    'vocalists',
    'welsh',
]);
const lastFmGenreKeywords = [
    'afrobeat',
    'afrobeats',
    'alternative',
    'ambient',
    'americana',
    'bachata',
    'bluegrass',
    'blues',
    'bebop',
    'classical',
    'corrido',
    'corridos',
    'country',
    'dance',
    'dancehall',
    'disco',
    'drill',
    'dub',
    'dubstep',
    'electronic',
    'emo',
    'experimental',
    'flamenco',
    'folk',
    'funk',
    'fusion',
    'gospel',
    'grunge',
    'hardcore',
    'hip hop',
    'house',
    'indie',
    'industrial',
    'jazz',
    'latin',
    'metal',
    'new wave',
    'opera',
    'pop',
    'post punk',
    'punk',
    'r&b',
    'regional mexicano',
    'reggae',
    'reggaeton',
    'rock',
    'salsa',
    'shoegaze',
    'ska',
    'soul',
    'synthpop',
    'techno',
    'trance',
    'trap',
];
function normalizeGenreName(value) {
    const key = value
        .trim()
        .normalize('NFKD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/\br\s*&\s*b\b/g, 'rnb')
        .replace(/&/g, ' and ')
        .replace(/[\-_/]+/g, ' ')
        .replace(/[^a-z0-9&]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
    if (!key)
        return null;
    const normalized = genreAliases.get(key) ?? key;
    if (!isUsefulGenreName(normalized))
        return null;
    return normalized;
}
function isUsefulGenreName(value) {
    if (value.length < 2)
        return false;
    if (blockedGenreTags.has(value))
        return false;
    if (/^(?:[0-9]{2}s|[12][0-9]{3}s?)$/.test(value))
        return false;
    if (value.includes('seen live') || value.includes('favorite'))
        return false;
    return true;
}
function hasLastFmGenreKeyword(value) {
    return lastFmGenreKeywords.some((keyword) => {
        if (value === keyword)
            return true;
        return value.startsWith(`${keyword} `) ||
            value.endsWith(` ${keyword}`) ||
            value.includes(` ${keyword} `);
    });
}
function normalizeSpotifyGenres(values) {
    if (!Array.isArray(values))
        return [];
    const genres = new Map();
    for (const value of values) {
        const normalized = normalizeGenreName(value);
        if (!normalized)
            continue;
        genres.set(normalized, normalized);
        if (genres.size >= maxSpotifyGenresPerArtist)
            break;
    }
    return [...genres.values()];
}
function normalizeLastFmTags(tags) {
    const genres = new Map();
    for (const tag of tags) {
        const count = Number(tag.count ?? 0);
        if (!tag.name || count < minLastFmTagCount)
            continue;
        const normalized = normalizeGenreName(tag.name);
        if (!normalized || !hasLastFmGenreKeyword(normalized))
            continue;
        genres.set(normalized, normalized);
        if (genres.size >= maxLastFmGenresPerArtist)
            break;
    }
    return [...genres.values()];
}
function scoreArtistMatch(item, queryKey, queryTokens) {
    const nameKey = normalizeArtistName(item.name ?? '');
    if (!nameKey)
        return Number.NEGATIVE_INFINITY;
    let score = 0;
    if (nameKey === queryKey) {
        score += 350;
    }
    else if (nameKey.startsWith(`${queryKey} `)) {
        score += 300;
    }
    else if (nameKey.includes(queryKey)) {
        score += 180;
    }
    else {
        const nameTokens = new Set(nameKey.split(' '));
        const matchingTokens = queryTokens.filter((token) => nameTokens.has(token)).length;
        if (matchingTokens === 0)
            score -= 200;
        score += (matchingTokens / Math.max(queryTokens.length, 1)) * 120;
    }
    const popularity = Math.max(0, Math.min(item.popularity ?? 0, 100));
    const followers = Math.max(0, item.followers?.total ?? 0);
    const hasImage = Boolean(item.images?.[0]?.url);
    const hasGenres = Boolean(item.genres?.length);
    score += popularity * 9;
    score += Math.log10(followers + 1) * 45;
    if (hasImage)
        score += 30;
    if (hasGenres)
        score += 20;
    if (nameKey !== queryKey && popularity < 10 && followers < 10_000)
        score -= 250;
    if (!hasImage && popularity < 20)
        score -= 80;
    return score;
}
async function getLastFmGenres(artistName, apiKey) {
    try {
        const url = new URL('https://ws.audioscrobbler.com/2.0/');
        url.searchParams.set('method', 'artist.getTopTags');
        url.searchParams.set('artist', artistName);
        url.searchParams.set('api_key', apiKey);
        url.searchParams.set('format', 'json');
        url.searchParams.set('autocorrect', '1');
        const res = await fetch(url.toString());
        if (!res.ok)
            return [];
        const data = await res.json();
        const tags = data.toptags?.tag;
        if (!Array.isArray(tags))
            return [];
        return normalizeLastFmTags(tags);
    }
    catch {
        return [];
    }
}
// ── Function 1 — Search artists ───────────────────────────────────────────────
exports.searchSpotifyArtists = (0, https_1.onCall)({ region: 'europe-southwest1', secrets: [spotifyClientId, spotifyClientSecret, lastFmApiKey] }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Login required');
    const query = request.data.query?.trim() ?? '';
    const limit = Math.min(Number(request.data.limit) || 20, 50);
    if (!query)
        return [];
    const market = sanitizeSpotifyMarket(request.data.market);
    const spotifyLimit = Math.min(Math.max(limit * 3, 20), 50);
    const token = await getSpotifyToken(spotifyClientId.value(), spotifyClientSecret.value());
    const url = new URL('https://api.spotify.com/v1/search');
    url.searchParams.set('q', spotifyArtistQuery(query));
    url.searchParams.set('type', 'artist');
    url.searchParams.set('market', market);
    url.searchParams.set('limit', String(spotifyLimit));
    const res = await fetch(url.toString(), {
        headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
        v2_1.logger.error('Spotify searchArtists failed', { status: res.status, query });
        throw new https_1.HttpsError('internal', 'Spotify search failed');
    }
    const data = await res.json();
    const queryKey = normalizeArtistName(query);
    const queryTokens = queryKey.split(' ').filter(Boolean);
    const rankedItems = data.artists.items.map((item) => ({
        item,
        nameKey: normalizeArtistName(item.name ?? ''),
        score: scoreArtistMatch(item, queryKey, queryTokens),
    }));
    const hasExactMatch = rankedItems.some(({ nameKey }) => nameKey === queryKey);
    const filtered = rankedItems
        .filter(({ nameKey, score }) => {
        if (score <= 0)
            return false;
        if (!hasExactMatch)
            return true;
        return nameKey === queryKey || nameKey.startsWith(`${queryKey} `) || nameKey.includes(queryKey) || score >= 500;
    })
        .sort((a, b) => b.score - a.score)
        .slice(0, limit)
        .map(({ item }) => ({
        name: item.name ?? 'Unknown Artist',
        imageUrl: item.images?.[0]?.url ?? '',
        genres: normalizeSpotifyGenres(item.genres),
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
exports.searchSpotifyTracks = (0, https_1.onCall)({ region: 'europe-southwest1', secrets: [spotifyClientId, spotifyClientSecret] }, async (request) => {
    try {
        if (!request.auth)
            throw new https_1.HttpsError('unauthenticated', 'Login required');
        const query = request.data.query?.trim() ?? '';
        const limit = Math.min(Number(request.data.limit) || 20, 50);
        if (!query)
            return [];
        const market = sanitizeSpotifyMarket(request.data.market);
        const token = await getSpotifyToken(spotifyClientId.value(), spotifyClientSecret.value());
        const url = new URL('https://api.spotify.com/v1/search');
        url.searchParams.set('q', query);
        url.searchParams.set('type', 'track');
        url.searchParams.set('market', market);
        url.searchParams.set('limit', String(limit));
        const res = await fetchSpotifyWithRetry(url.toString(), token);
        if (!res.ok) {
            const errorBody = await readResponseSnippet(res);
            v2_1.logger.error('Spotify searchTracks failed', { status: res.status, query, errorBody });
            throw new https_1.HttpsError('unavailable', 'Spotify search failed', { status: res.status });
        }
        const data = await res.json();
        const items = data.tracks?.items;
        if (!Array.isArray(items)) {
            v2_1.logger.error('Spotify searchTracks returned malformed response', { query });
            throw new https_1.HttpsError('internal', 'Spotify search returned malformed response');
        }
        return items.map((item) => ({
            title: item.name ?? 'Unknown',
            artist: item.artists?.[0]?.name ?? 'Unknown Artist',
            imageUrl: item.album?.images?.[0]?.url ?? '',
            spotifyUrl: item.id ? `https://open.spotify.com/track/${item.id}` : '',
        }));
    }
    catch (error) {
        if (error instanceof https_1.HttpsError)
            throw error;
        v2_1.logger.error('Spotify searchTracks crashed', { error });
        throw new https_1.HttpsError('internal', 'Spotify search crashed');
    }
});
//# sourceMappingURL=spotify.js.map