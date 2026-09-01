import {
  DocumentData,
  FieldValue,
  Firestore,
  Timestamp,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { db } from './firebase';
import { normalizeGenreName } from './genre_normalizer';
import { normalizeArtistIdentityName } from './recommendations';

const maxArtists = 30;
const maxGenres = 10;
const maxArtistGenres = 50;
const maxArtistNameBytes = 300;
const maxGenreNameBytes = 200;
const maxImageUrlBytes = 2048;
const spotifyArtistIdPattern = /^[A-Za-z0-9]{22}$/;
const spotifyImageUrlPattern = /^https:\/\/i[.]scdn[.]co\/image\/[A-Za-z0-9]+$/;
const musicProfileRateCapacity = 6;
const musicProfileTokenRefillMs = 10_000;

interface ArtistPayload {
  name: string;
  imageUrl: string;
  genres: string[];
  spotifyId?: string;
}

function utf8Length(value: string): number {
  return Buffer.byteLength(value, 'utf8');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function invalid(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

function parseArtist(value: unknown): ArtistPayload {
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

export function parseMusicProfilePayload(value: unknown): ArtistPayload[] {
  if (!isRecord(value) || !hasOnlyKeys(value, ['artists'])) {
    return invalid('A valid music profile payload is required.');
  }
  if (!Array.isArray(value.artists) || value.artists.length > maxArtists) {
    return invalid(`artists must contain at most ${maxArtists} entries.`);
  }

  const artists = value.artists.map(parseArtist);
  const identities = new Set<string>();
  for (const artist of artists) {
    const identity = artist.spotifyId
      ? `spotify:${artist.spotifyId}`
      : `name:${normalizeArtistIdentityName(artist.name)}`;
    if (identity.endsWith(':') || identities.has(identity)) {
      return invalid('artists must not contain duplicates.');
    }
    identities.add(identity);
  }
  return artists;
}

interface DerivedGenre {
  name: string;
  count: number;
  percentage: number;
}

function deriveTopGenres(artists: ArtistPayload[]): DerivedGenre[] {
  const counts = new Map<string, { count: number; firstSeen: number }>();
  let firstSeen = 0;
  for (const artist of artists) {
    for (const rawGenre of artist.genres) {
      const genre = normalizeGenreName(rawGenre);
      if (!genre) continue;
      const existing = counts.get(genre);
      if (existing) {
        existing.count++;
      } else {
        counts.set(genre, { count: 1, firstSeen: firstSeen++ });
      }
    }
  }

  const sorted = [...counts.entries()].sort((left, right) =>
    right[1].count - left[1].count || left[1].firstSeen - right[1].firstSeen);
  const totalMentions = sorted.reduce((sum, entry) => sum + entry[1].count, 0);
  if (totalMentions === 0) return [];
  return sorted.slice(0, maxGenres).map(([name, value]) => ({
    name,
    count: value.count,
    percentage: value.count / totalMentions * 100,
  }));
}

export function buildMusicProfileFields(
  artists: ArtistPayload[],
  updatedAt: unknown = FieldValue.serverTimestamp(),
): DocumentData {
  const topGenres = deriveTopGenres(artists);
  return {
    topArtists: artists,
    topGenres,
    topArtistNames: artists.map((artist) => artist.name),
    topArtistKeys: artists.map((artist) => artist.spotifyId
      ? `spotify:${artist.spotifyId}`
      : `name:${normalizeArtistIdentityName(artist.name)}`),
    topGenreNames: topGenres.map((genre) => genre.name),
    artistIdentityVersion: 1,
    musicDataUpdatedAt: updatedAt,
    recommendationsRefreshRequestedAt: updatedAt,
  };
}

function sameStringArray(left: unknown, right: unknown): boolean {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => value === right[index]);
}

function sameRecommendationProfile(current: DocumentData, next: DocumentData): boolean {
  return sameStringArray(current.topArtistNames, next.topArtistNames)
    && sameStringArray(current.topArtistKeys, next.topArtistKeys)
    && sameStringArray(current.topGenreNames, next.topGenreNames);
}

function sameMusicProfile(current: DocumentData, next: DocumentData): boolean {
  return sameRecommendationProfile(current, next)
    && JSON.stringify(current.topArtists ?? null) === JSON.stringify(next.topArtists ?? null)
    && JSON.stringify(current.topGenres ?? null) === JSON.stringify(next.topGenres ?? null);
}

function nonNegativeInteger(value: unknown): number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : 0;
}

function availableMusicProfileTokens(
  limiterData: DocumentData,
  now: Timestamp,
): number {
  const storedTokens = limiterData.musicProfileTokens;
  const storedAt = limiterData.musicProfileTokensUpdatedAt;
  if (typeof storedTokens !== 'number'
      || !Number.isFinite(storedTokens)
      || storedTokens < 0
      || !(storedAt instanceof Timestamp)) {
    return musicProfileRateCapacity;
  }

  const elapsedMs = Math.max(0, now.toMillis() - storedAt.toMillis());
  return Math.min(
    musicProfileRateCapacity,
    storedTokens + elapsedMs / musicProfileTokenRefillMs,
  );
}

export async function writeMusicProfile(
  firestore: Firestore,
  uid: string,
  artists: ArtistPayload[],
  now = Timestamp.now(),
): Promise<boolean> {
  const userRef = firestore.doc(`users/${uid}`);
  const deletionRef = firestore.doc(`account_deletions/${uid}`);
  const limiterRef = firestore.doc(`rate_limits/${uid}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, deletionSnapshot, limiterSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(deletionRef),
      transaction.get(limiterRef),
    ]);
    if (!userSnapshot.exists
        || userSnapshot.get('username') === 'deleted_user'
        || deletionSnapshot.exists) {
      throw new HttpsError('failed-precondition', 'An active user profile is required.');
    }
    const fields = buildMusicProfileFields(artists, now);
    const userData = userSnapshot.data() ?? {};
    if (sameMusicProfile(userData, fields)) return false;

    const limiterData = limiterSnapshot.data() ?? {};
    const availableTokens = availableMusicProfileTokens(limiterData, now);
    if (availableTokens < 1) {
      throw new HttpsError('resource-exhausted', 'Music profile rate limit reached.');
    }

    const recommendationProfileChanged = !sameRecommendationProfile(userData, fields);
    const userUpdates = { ...fields };
    if (recommendationProfileChanged) {
      userUpdates.musicProfileVersion = nonNegativeInteger(userData.musicProfileVersion) + 1;
    } else {
      delete userUpdates.recommendationsRefreshRequestedAt;
    }
    transaction.update(userRef, userUpdates);
    transaction.set(limiterRef, {
      musicProfileTokens: availableTokens - 1,
      musicProfileTokensUpdatedAt: now,
      musicProfileWindowStart: FieldValue.delete(),
      musicProfileWriteCount: FieldValue.delete(),
    }, { merge: true });
    return true;
  });
}

export const saveMusicProfile = onCall(
  { region: 'europe-southwest1', enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Authentication is required.');

    try {
      const artists = parseMusicProfilePayload(request.data);
      const updated = await writeMusicProfile(db, uid, artists);
      return { updated };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error('saveMusicProfile: unhandled error', { uid, error });
      throw new HttpsError('internal', 'Could not save the music profile.');
    }
  },
);
