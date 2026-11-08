import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { db } from './firebase';
import { consumeCatalogSearchQuota } from './rate_limits';
import { fetchLastFm } from './lastfm_request';
import {
  fetchExternal,
  getSpotifyToken,
  readResponseSnippet,
  spotifyClientId,
  spotifyClientSecret,
  spotifyRequestTimeoutMs,
} from './spotify_client';
import {
  isRecord,
  parseSpotifyArtistSearchRequest,
  parseSpotifySearchRequest,
} from './catalog_request';
import { normalizeLastFmTags, normalizeSpotifyGenres } from './catalog_genres';
import { rankSpotifyArtists, SpotifyArtistItem } from './spotify_artist_ranking';

const lastFmApiKey = defineSecret('LASTFM_API_KEY');

function spotifyArtistQuery(query: string): string {
  return `artist:${query.replace(/"/g, '').trim()}`;
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
