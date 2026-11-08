import { defineSecret } from 'firebase-functions/params';
import { HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { isRecord } from './catalog_request';

// Catálogo de Spotify con credenciales de la app (client credentials), sin
// OAuth de usuario. Compartido por las búsquedas y la detección de lanzamientos.
export const spotifyClientId = defineSecret('SPOTIFY_CLIENT_ID');
export const spotifyClientSecret = defineSecret('SPOTIFY_CLIENT_SECRET');
export const spotifyRequestTimeoutMs = 8_000;

// Module-level cache — reused across warm instances (Spotify tokens last 3600 s).
let cachedToken: string | null = null;
let tokenExpiresAt = 0;

export async function fetchExternal(
  input: string,
  init: RequestInit,
  timeoutMs: number,
  service: 'Spotify' | 'Last.fm',
): Promise<Response> {
  try {
    return await fetch(input, {
      ...init,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error: unknown) {
    logger.warn(`${service} request failed before receiving a response`, {
      reason: error instanceof Error ? error.name : 'unknown',
    });
    throw new HttpsError('unavailable', `${service} is temporarily unavailable`);
  }
}

export async function readResponseSnippet(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 500);
  } catch {
    return '';
  }
}

export async function getSpotifyToken(clientId: string, clientSecret: string): Promise<string> {
  const now = Date.now();
  if (cachedToken && now < tokenExpiresAt - 60_000) return cachedToken;

  if (!clientId.trim() || !clientSecret.trim()) {
    logger.error('Spotify credentials are not configured');
    throw new HttpsError('failed-precondition', 'Spotify credentials are not configured');
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
    logger.error('Spotify token request failed', { status: res.status, errorBody });
    throw new HttpsError('failed-precondition', 'Failed to obtain Spotify token', { status: res.status });
  }

  const data: unknown = await res.json();
  if (
    !isRecord(data) ||
    typeof data.access_token !== 'string' ||
    !data.access_token ||
    typeof data.expires_in !== 'number' ||
    !Number.isFinite(data.expires_in) ||
    data.expires_in <= 0
  ) {
    logger.error('Spotify token response was malformed');
    throw new HttpsError('unavailable', 'Spotify returned an invalid token response');
  }
  cachedToken = data.access_token;
  tokenExpiresAt = now + data.expires_in * 1000;
  return cachedToken;
}
