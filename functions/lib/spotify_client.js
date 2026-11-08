"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.spotifyRequestTimeoutMs = exports.spotifyClientSecret = exports.spotifyClientId = void 0;
exports.fetchExternal = fetchExternal;
exports.readResponseSnippet = readResponseSnippet;
exports.getSpotifyToken = getSpotifyToken;
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const catalog_request_1 = require("./catalog_request");
// Catálogo de Spotify con credenciales de la app (client credentials), sin
// OAuth de usuario. Compartido por las búsquedas y la detección de lanzamientos.
exports.spotifyClientId = (0, params_1.defineSecret)('SPOTIFY_CLIENT_ID');
exports.spotifyClientSecret = (0, params_1.defineSecret)('SPOTIFY_CLIENT_SECRET');
exports.spotifyRequestTimeoutMs = 8_000;
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
async function readResponseSnippet(res) {
    try {
        return (await res.text()).slice(0, 500);
    }
    catch {
        return '';
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
    }, exports.spotifyRequestTimeoutMs, 'Spotify');
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
//# sourceMappingURL=spotify_client.js.map