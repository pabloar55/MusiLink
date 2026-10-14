import { DocumentData } from 'firebase-admin/firestore';

import {
  ArtistIdentity,
  artistIdentitiesMatch,
  artistIdentityKey,
  normalizeArtistIdentityName,
  normalizedStoredArtistKey,
} from './artist_identity';
import { stringList } from './firestore_values';

// Reglas puras de las recomendaciones: lectura del perfil musical, puntuación
// y claves con las que se buscan candidatos. El cliente calcula la misma
// puntuación en `lib/utils/music_compatibility.dart`.

const maxRecommendationInputArtists = 30;
const maxRecommendationInputGenres = 10;
const artistScoreWeight = 70;
const genreScoreWeight = 30;
const artistEvidenceTarget = 7;
const genreEvidenceTarget = 4;

export interface UserMusicProfile {
  topArtistNames: string[];
  topArtistKeys: string[];
  topGenreNames: string[];
}

export interface CandidateProfile extends UserMusicProfile {
  uid: string;
}

export interface RecommendationResult {
  uid: string;
  score: number;
  sharedArtistNames: string[];
  sharedGenreNames: string[];
}

export function readMusicProfile(data: DocumentData | undefined): UserMusicProfile {
  const topArtistNames =
    stringList(data?.topArtistNames).slice(0, maxRecommendationInputArtists);
  return {
    topArtistNames,
    topArtistKeys: readArtistIdentityKeys(data, topArtistNames),
    topGenreNames: stringList(data?.topGenreNames).slice(0, maxRecommendationInputGenres),
  };
}

function readArtistIdentityKeys(
  data: DocumentData | undefined,
  names: string[],
): string[] {
  const storedKeys = stringList(data?.topArtistKeys)
    .slice(0, maxRecommendationInputArtists);
  const storedArtists = Array.isArray(data?.topArtists) ? data.topArtists : [];

  return names.map((name, index) => {
    const rawArtist = storedArtists[index];
    const rawName = typeof rawArtist?.name === 'string' ? rawArtist.name.trim() : '';
    const spotifyId =
      typeof rawArtist?.spotifyId === 'string' ? rawArtist.spotifyId.trim() : '';
    if (normalizeArtistIdentityName(rawName) === normalizeArtistIdentityName(name)) {
      return artistIdentityKey(name, spotifyId);
    }

    const storedKey = normalizedStoredArtistKey(storedKeys[index] ?? '');
    if (storedKey) return storedKey;
    return artistIdentityKey(name);
  });
}

/** Perfil de un documento de `music_recommendation_profiles`. */
export function candidateProfileFromData(
  uid: string,
  data: DocumentData,
): CandidateProfile | undefined {
  const topArtistNames = stringList(data.topArtistNames)
    .slice(0, maxRecommendationInputArtists);
  const topArtistKeys = stringList(data.topArtistKeys)
    .slice(0, maxRecommendationInputArtists);
  const topGenreNames = stringList(data.topGenreNames)
    .slice(0, maxRecommendationInputGenres);
  if (topArtistNames.length === 0 && topGenreNames.length === 0) return undefined;
  return { uid, topArtistNames, topArtistKeys, topGenreNames };
}

function normalizedMusicKey(value: string): string {
  return value.trim().toLowerCase();
}

function artistIdentities(profile: UserMusicProfile): ArtistIdentity[] {
  const artistsByKey = new Map<string, ArtistIdentity>();
  profile.topArtistNames.forEach((rawName, index) => {
    const name = rawName.trim();
    const normalizedName = normalizeArtistIdentityName(name);
    if (!normalizedName) return;
    const key =
      normalizedStoredArtistKey(profile.topArtistKeys[index] ?? '') ??
      `name:${normalizedName}`;
    if (!artistsByKey.has(key)) artistsByKey.set(key, { name, key, normalizedName });
  });
  return [...artistsByKey.values()];
}

function sharedArtistNames(
  leftArtists: ArtistIdentity[],
  rightArtists: ArtistIdentity[],
): string[] {
  const usedLeftIndexes = new Set<number>();
  const shared: string[] = [];
  for (const rightArtist of rightArtists) {
    const leftIndex = leftArtists.findIndex((leftArtist, index) =>
      !usedLeftIndexes.has(index) &&
      artistIdentitiesMatch(leftArtist, rightArtist));
    if (leftIndex < 0) continue;
    usedLeftIndexes.add(leftIndex);
    shared.push(rightArtist.name);
  }
  return shared;
}

function uniqueMusicNames(values: string[]): string[] {
  const namesByKey = new Map<string, string>();
  for (const value of values) {
    const trimmed = value.trim();
    const key = normalizedMusicKey(trimmed);
    if (key.length > 0 && !namesByKey.has(key)) namesByKey.set(key, trimmed);
  }
  return [...namesByKey.values()];
}

export function similarityScore(
  sharedCount: number,
  leftCount: number,
  rightCount: number,
  evidenceTarget: number,
  weight: number,
): number {
  if (sharedCount === 0) return 0;

  const comparableCount = Math.min(leftCount, rightCount);
  const coverage = comparableCount === 0 ? 0 : sharedCount / comparableCount;
  const evidence = Math.min(sharedCount / evidenceTarget, 1);
  return Math.max(coverage, evidence) * weight;
}

export function calculateRecommendation(
  myProfile: UserMusicProfile,
  candidate: CandidateProfile,
): RecommendationResult | null {
  const myArtists = artistIdentities(myProfile);
  const candidateArtists = artistIdentities(candidate);
  const myGenreNames = uniqueMusicNames(myProfile.topGenreNames);
  const candidateGenreNames = uniqueMusicNames(candidate.topGenreNames);
  const myGenres = new Set(myGenreNames.map(normalizedMusicKey));
  const matchingArtistNames = sharedArtistNames(myArtists, candidateArtists);
  const sharedGenreNames = candidateGenreNames.filter((genre) =>
    myGenres.has(normalizedMusicKey(genre)));

  if (matchingArtistNames.length === 0 && sharedGenreNames.length === 0) return null;

  const artistScore = similarityScore(
    matchingArtistNames.length,
    myArtists.length,
    candidateArtists.length,
    artistEvidenceTarget,
    artistScoreWeight,
  );
  const genreScore = similarityScore(
    sharedGenreNames.length,
    myGenreNames.length,
    candidateGenreNames.length,
    genreEvidenceTarget,
    genreScoreWeight,
  );

  return {
    uid: candidate.uid,
    score: Math.round(artistScore + genreScore),
    sharedArtistNames: matchingArtistNames,
    sharedGenreNames,
  };
}

/** Claves con las que el perfil aparece en las búsquedas de artistas. */
export function artistMatchKeys(profile: UserMusicProfile): string[] {
  return [...new Set(
    artistIdentities(profile)
      .map((artist) => artist.normalizedName)
      .filter((value) => value.length > 0),
  )].slice(0, maxRecommendationInputArtists);
}

/** Claves con las que el perfil aparece en las búsquedas de géneros. */
export function genreMatchKeys(profile: UserMusicProfile): string[] {
  return [...new Set(
    profile.topGenreNames
      .map(normalizedMusicKey)
      .filter((value) => value.length > 0),
  )].slice(0, maxRecommendationInputGenres);
}
