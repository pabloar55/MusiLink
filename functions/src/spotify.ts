import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { db } from './firebase';
import { consumeCatalogSearchQuota } from './rate_limits';
import { fetchLastFm } from './lastfm_request';
import {
  isRecord,
  parseSpotifyArtistSearchRequest,
  parseSpotifySearchRequest,
} from './catalog_request';
import { rankSpotifyArtists, SpotifyArtistItem } from './spotify_artist_ranking';

const spotifyClientId = defineSecret('SPOTIFY_CLIENT_ID');
const spotifyClientSecret = defineSecret('SPOTIFY_CLIENT_SECRET');
const lastFmApiKey = defineSecret('LASTFM_API_KEY');
const maxSpotifyGenresPerArtist = 5;
const maxLastFmGenresPerArtist = 2;
const minLastFmTagCount = 10;
const spotifyRequestTimeoutMs = 8_000;

// Module-level cache — reused across warm instances (Spotify tokens last 3600 s).
let cachedToken: string | null = null;
let tokenExpiresAt = 0;

async function fetchExternal(
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

async function getSpotifyToken(clientId: string, clientSecret: string): Promise<string> {
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

async function readResponseSnippet(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 500);
  } catch {
    return '';
  }
}

function spotifyArtistQuery(query: string): string {
  return `artist:${query.replace(/"/g, '').trim()}`;
}

const genreAliases = new Map<string, string>([
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

const blockedGenreTags = new Set<string>([
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

function normalizeGenreName(value: string): string | null {
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

  if (!key) return null;
  const normalized = genreAliases.get(key) ?? key;
  if (!isUsefulGenreName(normalized)) return null;
  return normalized;
}

function isUsefulGenreName(value: string): boolean {
  if (value.length < 2) return false;
  if (blockedGenreTags.has(value)) return false;
  if (/^(?:[0-9]{2}s|[12][0-9]{3}s?)$/.test(value)) return false;
  if (value.includes('seen live') || value.includes('favorite')) return false;
  return true;
}

function hasLastFmGenreKeyword(value: string): boolean {
  return lastFmGenreKeywords.some((keyword) => {
    if (value === keyword) return true;
    return value.startsWith(`${keyword} `) ||
      value.endsWith(` ${keyword}`) ||
      value.includes(` ${keyword} `);
  });
}

function normalizeSpotifyGenres(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  const genres = new Map<string, string>();
  for (const value of values) {
    if (typeof value !== 'string') continue;
    const normalized = normalizeGenreName(value);
    if (!normalized) continue;
    genres.set(normalized, normalized);
    if (genres.size >= maxSpotifyGenresPerArtist) break;
  }
  return [...genres.values()];
}

function normalizeLastFmTags(tags: Array<{ name?: string; count?: number | string }>): string[] {
  const genres = new Map<string, string>();
  for (const tag of tags) {
    const count = Number(tag.count ?? 0);
    if (!tag.name || count < minLastFmTagCount) continue;
    const normalized = normalizeGenreName(tag.name);
    if (!normalized || !hasLastFmGenreKeyword(normalized)) continue;
    genres.set(normalized, normalized);
    if (genres.size >= maxLastFmGenresPerArtist) break;
  }
  return [...genres.values()];
}

function isSpotifyArtistItem(value: unknown): value is SpotifyArtistItem {
  if (!isRecord(value) || typeof value.id !== 'string' || typeof value.name !== 'string') {
    return false;
  }
  if (value.genres !== undefined && (
    !Array.isArray(value.genres) || !value.genres.every((genre) => typeof genre === 'string')
  )) {
    return false;
  }
  if (value.images !== undefined && (
    !Array.isArray(value.images) ||
    !value.images.every((image) => isRecord(image) && typeof image.url === 'string')
  )) {
    return false;
  }
  if (value.popularity !== undefined && typeof value.popularity !== 'number') return false;
  if (value.followers !== undefined && (
    !isRecord(value.followers) ||
    (value.followers.total !== undefined && typeof value.followers.total !== 'number')
  )) {
    return false;
  }
  return true;
}

async function getLastFmGenres(artistName: string, apiKey: string): Promise<string[]> {
  try {
    const data = await fetchLastFm('artist.getTopTags', artistName, apiKey);
    const tags = isRecord(data) && isRecord(data.toptags) ? data.toptags.tag : undefined;
    if (!Array.isArray(tags)) {
      throw new HttpsError('unavailable', 'Last.fm returned an invalid tag list');
    }
    const validTags = tags.filter((tag): tag is { name: string; count?: number | string } => (
      isRecord(tag) &&
      typeof tag.name === 'string' && tag.name.trim().length > 0 &&
      (tag.count === undefined || typeof tag.count === 'number' || typeof tag.count === 'string')
    ));
    if (validTags.length !== tags.length) {
      throw new HttpsError('unavailable', 'Last.fm returned an invalid tag list');
    }
    return normalizeLastFmTags(validTags);
  } catch {
    return [];
  }
}

// ── Exported types (mirror the Flutter app.Artist / app.Track models) ─────────

interface ArtistResult {
  name: string;
  imageUrl: string;
  genres: string[];
  spotifyId: string | null;
}

interface TrackResult {
  title: string;
  artist: string;
  imageUrl: string;
  spotifyUrl: string;
}

// ── Function 1 — Search artists ───────────────────────────────────────────────

export const searchSpotifyArtists = onCall(
  {
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [spotifyClientId, spotifyClientSecret, lastFmApiKey],
  },
  async (request): Promise<ArtistResult[]> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Login required');

    const { value: query, limit, market } = parseSpotifyArtistSearchRequest(request.data);
    await consumeCatalogSearchQuota(db, request.auth.uid, 'spotifySearch');
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
      logger.error('Spotify searchArtists failed', { status: res.status, query });
      if (res.status === 429) {
        throw new HttpsError('resource-exhausted', 'Spotify rate limit reached');
      }
      throw new HttpsError('internal', 'Spotify search failed');
    }

    const data: unknown = await res.json();
    if (!isRecord(data) || !isRecord(data.artists) || !Array.isArray(data.artists.items)) {
      logger.error('Spotify searchArtists returned malformed response', { query });
      throw new HttpsError('internal', 'Spotify search returned malformed response');
    }
    const items = data.artists.items.filter(isSpotifyArtistItem);

    const filtered = rankSpotifyArtists(items, query, limit)
      .map((item) => ({
        name: item.name ?? 'Unknown Artist',
        imageUrl: item.images?.[0]?.url ?? '',
        genres: normalizeSpotifyGenres(item.genres),
        spotifyId: item.id ?? null,
      }));

    const apiKey = lastFmApiKey.value();
    return await Promise.all(
      filtered.map(async (artist) => {
        if (artist.genres.length > 0) return artist;
        const genres = await getLastFmGenres(artist.name, apiKey);
        return { ...artist, genres };
      }),
    );
  },
);

// ── Function 2 — Search tracks ────────────────────────────────────────────────

export const searchSpotifyTracks = onCall(
  {
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [spotifyClientId, spotifyClientSecret],
  },
  async (request): Promise<TrackResult[]> => {
    try {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Login required');

      const { value: query, limit } = parseSpotifySearchRequest(request.data);
      await consumeCatalogSearchQuota(db, request.auth.uid, 'spotifySearch');

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
        logger.error('Spotify searchTracks failed', { status: res.status, query, errorBody });
        if (res.status === 429) {
          throw new HttpsError('resource-exhausted', 'Spotify rate limit reached');
        }
        throw new HttpsError('unavailable', 'Spotify search failed', { status: res.status });
      }

      const data: unknown = await res.json();
      const items = isRecord(data) && isRecord(data.tracks) ? data.tracks.items : undefined;
      if (!Array.isArray(items)) {
        logger.error('Spotify searchTracks returned malformed response', { query });
        throw new HttpsError('internal', 'Spotify search returned malformed response');
      }

      return items.filter(isRecord).map((item) => {
        const artists = Array.isArray(item.artists) ? item.artists.filter(isRecord) : [];
        const album = isRecord(item.album) ? item.album : undefined;
        const images = album && Array.isArray(album.images) ? album.images.filter(isRecord) : [];
        const id = typeof item.id === 'string' ? item.id : '';
        return {
          title: typeof item.name === 'string' ? item.name : 'Unknown',
          artist: typeof artists[0]?.name === 'string' ? artists[0].name : 'Unknown Artist',
          imageUrl: typeof images[0]?.url === 'string' ? images[0].url : '',
          spotifyUrl: id ? `https://open.spotify.com/track/${id}` : '',
        };
      });
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      logger.error('Spotify searchTracks crashed', { error });
      throw new HttpsError('internal', 'Spotify search crashed');
    }
  },
);
