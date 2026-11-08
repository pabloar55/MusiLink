import {
  DocumentData,
  FieldPath,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { isRecord } from './catalog_request';
import { db } from './firebase';
import { timestampMillis } from './firestore_values';
import { localDay, utcOffsetsAtLocalTime } from './local_time';
import {
  notificationText,
  preferredLocale,
  sendNotification,
  SupportedLocale,
} from './notifications';
import {
  fetchExternal,
  getSpotifyToken,
  readResponseSnippet,
  spotifyClientId,
  spotifyClientSecret,
  spotifyRequestTimeoutMs,
} from './spotify_client';

// Lanzamientos recientes por artista de Spotify. Los clientes autenticados los
// leen para la sección «Novedades»; solo el backend los escribe. Ver
// docs/new_release_notifications.md y lib/models/artist_release.dart.
export const artistReleasesCollection = 'artist_releases';
// Pausa global de las revisiones cuando se agota la cuota de Spotify.
export const releaseChecksStatePath = 'scheduler_state/artist_release_checks';
// Último aviso semanal enviado; evita repetirlo el mismo día.
export const newReleasePushField = 'newReleasePushAt';

const userPrivateCollection = 'user_private';
const hourMs = 60 * 60 * 1000;
const dayMs = 24 * hourMs;

export const releaseCheckIntervalMs = dayMs;
const releaseRetryDelayMs = hourMs;
const unavailableArtistRetryMs = 7 * dayMs;
// Sin Retry-After, la cuota agotada pausa las revisiones este tiempo para no
// competir con las búsquedas de los usuarios, que comparten la misma cuota.
export const quotaExceededPauseMs = 6 * hourMs;
const releaseCheckBatchSize = 150;
const releaseCheckConcurrency = 3;
const spotifyReleasePageSize = 10;
const knownReleaseIdsLimit = 50;
const recentReleasesLimit = 10;
// Se conservan para la sección de la app aunque sean de antes de vigilar al
// artista. Solo se anuncian los que aparecen después y no superan
// newReleaseMaxAgeDays: así se descartan reediciones o cambios de orden.
const recentReleaseMaxAgeDays = 30;
export const newReleaseMaxAgeDays = 7;

// Sábado a las 11:30 hora local.
const weeklyReleaseLocalMinutes = 11 * 60 + 30;
const weeklyReleaseWeekday = 6;
const weeklyReleaseSlotMinutes = 15;
// Algo más de una semana para tolerar retrasos; newReleasePushAt impide
// anunciar dos veces lo mismo.
export const weeklyReleaseWindowMs = 8 * dayMs;
const weeklyReleasePageSize = 200;
const weeklyReleaseConcurrency = 20;
const artistStateBatchSize = 100;
const watchSyncPageSize = 300;
// gRPC status returned by Firestore when a document already exists.
const alreadyExistsCode = 6;

const spotifyIdPattern = /^[A-Za-z0-9]{22}$/;
const spotifyImageUrlPattern = /^https:\/\/i[.]scdn[.]co\/image\/[A-Za-z0-9]+$/;
const isoDayPattern = /^\d{4}-\d{2}-\d{2}$/;
const preferredImageWidth = 300;

export type ReleaseType = 'single' | 'album';
const releaseTypes: ReleaseType[] = ['single', 'album'];

export interface SpotifyRelease {
  id: string;
  name: string;
  type: ReleaseType;
  /** `YYYY-MM-DD` solo cuando Spotify da precisión de día. */
  releaseDate: string | null;
  imageUrl: string;
}

/** Elemento de `recentReleases`; mismo contrato que `ArtistRelease` en Dart. */
export interface StoredRelease {
  id: string;
  name: string;
  type: ReleaseType;
  releaseDate: string;
  imageUrl: string;
  detectedAt: number;
  /** Se detectó como novedad y entra en el aviso semanal. */
  announce: boolean;
}

export interface FollowedArtist {
  id: string;
  name: string;
}

export interface PendingRelease {
  artist: FollowedArtist;
  release: StoredRelease;
}

export class SpotifyRateLimitedError extends Error {
  constructor(
    readonly retryAfterSeconds: number | undefined,
    readonly quotaExceeded: boolean,
  ) {
    super(quotaExceeded ? 'Spotify quota exceeded' : 'Spotify rate limit reached');
  }
}

export class SpotifyArtistUnavailableError extends Error {
  constructor(readonly status: number) {
    super('Spotify artist is unavailable');
  }
}

export type ReleaseFetcher = (artistId: string) => Promise<SpotifyRelease[]>;

// ── Detección ─────────────────────────────────────────────────────────────────

function isoDay(millis: number): string {
  return new Date(millis).toISOString().slice(0, 10);
}

function releaseImageUrl(images: unknown): string {
  if (!Array.isArray(images)) return '';
  const valid = images.filter((image): image is { url: string; width?: unknown } =>
    isRecord(image) && typeof image.url === 'string' && spotifyImageUrlPattern.test(image.url));
  const preferred = valid.find((image) => image.width === preferredImageWidth);
  return (preferred ?? valid[0])?.url ?? '';
}

/** Valida la respuesta de `GET /v1/artists/{id}/albums` para un grupo. */
export function parseSpotifyReleases(data: unknown, type: ReleaseType): SpotifyRelease[] {
  const items = isRecord(data) ? data.items : undefined;
  if (!Array.isArray(items)) throw new Error('Spotify returned a malformed release list');
  return items.flatMap((item): SpotifyRelease[] => {
    if (
      !isRecord(item) ||
      typeof item.id !== 'string' ||
      !spotifyIdPattern.test(item.id) ||
      typeof item.name !== 'string' ||
      item.name.trim().length === 0
    ) {
      return [];
    }
    const releaseDate = item.release_date_precision === 'day' &&
      typeof item.release_date === 'string' &&
      isoDayPattern.test(item.release_date)
      ? item.release_date
      : null;
    return [{
      id: item.id,
      name: item.name.trim(),
      type,
      releaseDate,
      imageUrl: releaseImageUrl(item.images),
    }];
  });
}

function compareReleases(
  left: { releaseDate: string; type: ReleaseType },
  right: { releaseDate: string; type: ReleaseType },
): number {
  // Más reciente primero; el mismo día, el álbum antes que el single.
  return right.releaseDate.localeCompare(left.releaseDate) ||
    releaseTypes.indexOf(right.type) - releaseTypes.indexOf(left.type);
}

/**
 * Actualiza los lanzamientos recientes de un artista con su catálogo actual.
 * Sin historial previo (`knownReleaseIds` ausente) nada se anuncia: un artista
 * recién vigilado no genera avisos por lo que ya había publicado.
 */
export function updateRecentReleases(
  knownReleaseIds: string[] | undefined,
  previous: StoredRelease[],
  releases: SpotifyRelease[],
  nowMillis: number,
): { knownReleaseIds: string[]; recentReleases: StoredRelease[]; newReleases: number } {
  const known = new Set(knownReleaseIds ?? []);
  const previousById = new Map(previous.map((release) => [release.id, release]));
  const earliestRecent = isoDay(nowMillis - recentReleaseMaxAgeDays * dayMs);
  const earliestAnnounced = isoDay(nowMillis - newReleaseMaxAgeDays * dayMs);
  // Spotify publica a medianoche de cada mercado: admite un día por delante.
  const latest = isoDay(nowMillis + dayMs);

  let newReleases = 0;
  const seen = new Set<string>();
  const recentReleases = releases
    .filter((release): release is SpotifyRelease & { releaseDate: string } =>
      release.releaseDate !== null &&
      release.releaseDate >= earliestRecent &&
      release.releaseDate <= latest)
    .sort(compareReleases)
    .flatMap((release): StoredRelease[] => {
      if (seen.has(release.id)) return [];
      seen.add(release.id);
      const stored = previousById.get(release.id);
      const announce = stored?.announce ?? (
        knownReleaseIds !== undefined &&
        !known.has(release.id) &&
        release.releaseDate >= earliestAnnounced
      );
      if (!stored && announce) newReleases += 1;
      return [{
        ...release,
        detectedAt: stored?.detectedAt ?? nowMillis,
        announce,
      }];
    })
    .slice(0, recentReleasesLimit);

  return {
    knownReleaseIds: [...new Set([...releases.map((release) => release.id), ...known])]
      .slice(0, knownReleaseIdsLimit),
    recentReleases,
    newReleases,
  };
}

export function parseStoredReleases(value: unknown): StoredRelease[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): StoredRelease[] => {
    if (
      !isRecord(item) ||
      typeof item.id !== 'string' ||
      !spotifyIdPattern.test(item.id) ||
      typeof item.name !== 'string' ||
      !releaseTypes.includes(item.type as ReleaseType) ||
      typeof item.releaseDate !== 'string' ||
      !isoDayPattern.test(item.releaseDate)
    ) {
      return [];
    }
    const detectedAt = timestampMillis(item.detectedAt);
    if (detectedAt === undefined) return [];
    return [{
      id: item.id,
      name: item.name,
      type: item.type as ReleaseType,
      releaseDate: item.releaseDate,
      imageUrl: typeof item.imageUrl === 'string' && spotifyImageUrlPattern.test(item.imageUrl)
        ? item.imageUrl
        : '',
      detectedAt,
      announce: item.announce === true,
    }];
  });
}

function retryAfterSeconds(res: Response): number | undefined {
  const header = res.headers.get('retry-after');
  const value = header === null ? NaN : Number(header);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
}

/** Spotify distingue la cuota agotada del límite de velocidad con `reason`. */
export async function isQuotaExceeded(res: Response): Promise<boolean> {
  try {
    const body: unknown = await res.json();
    return isRecord(body) && isRecord(body.error) && body.error.reason === 'QUOTA_EXCEEDED';
  } catch {
    return false;
  }
}

async function fetchReleaseGroup(
  token: string,
  artistId: string,
  type: ReleaseType,
): Promise<SpotifyRelease[]> {
  const url = new URL(`https://api.spotify.com/v1/artists/${artistId}/albums`);
  url.searchParams.set('include_groups', type);
  // Máximo admitido por Spotify en Development Mode.
  url.searchParams.set('limit', String(spotifyReleasePageSize));
  const res = await fetchExternal(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  }, spotifyRequestTimeoutMs, 'Spotify');

  if (res.status === 429) {
    throw new SpotifyRateLimitedError(retryAfterSeconds(res), await isQuotaExceeded(res));
  }
  if (res.status === 400 || res.status === 404) {
    throw new SpotifyArtistUnavailableError(res.status);
  }
  if (!res.ok) {
    const errorBody = await readResponseSnippet(res);
    throw new Error(`Spotify artist releases failed with status ${res.status}: ${errorBody}`);
  }
  return parseSpotifyReleases(await res.json(), type);
}

/** Singles y álbumes por separado: un grupo numeroso no oculta al otro. */
export function spotifyReleaseFetcher(token: string): ReleaseFetcher {
  return async (artistId) => {
    const groups = await Promise.all(
      releaseTypes.map((type) => fetchReleaseGroup(token, artistId, type)),
    );
    return groups.flat();
  };
}

type ReleaseCheckResult = 'baseline' | 'new' | 'unchanged' | 'orphan';

async function checkArtistRelease(
  firestore: Firestore,
  snapshot: QueryDocumentSnapshot,
  nowMillis: number,
  fetchReleases: ReleaseFetcher,
): Promise<ReleaseCheckResult> {
  const artistId = snapshot.id;
  // Nadie lo sigue ya: se retira antes de gastar cuota de Spotify.
  const followers = await firestore
    .collection('users')
    .where('topArtistKeys', 'array-contains', `spotify:${artistId}`)
    .select()
    .limit(1)
    .get();
  if (followers.empty) {
    await snapshot.ref.delete({ lastUpdateTime: snapshot.updateTime });
    return 'orphan';
  }

  const data = snapshot.data();
  const storedKnown = Array.isArray(data.knownReleaseIds)
    ? data.knownReleaseIds.filter((id: unknown): id is string => typeof id === 'string')
    : undefined;
  const releases = await fetchReleases(artistId);
  const update = updateRecentReleases(
    storedKnown,
    parseStoredReleases(data.recentReleases),
    releases,
    nowMillis,
  );
  const now = Timestamp.fromMillis(nowMillis);
  await snapshot.ref.update({
    knownReleaseIds: update.knownReleaseIds,
    recentReleases: update.recentReleases.map((release) => ({
      ...release,
      detectedAt: Timestamp.fromMillis(release.detectedAt),
    })),
    checkedAt: now,
    nextCheckAt: Timestamp.fromMillis(nowMillis + releaseCheckIntervalMs),
  });
  if (!storedKnown) return 'baseline';
  return update.newReleases > 0 ? 'new' : 'unchanged';
}

export interface ReleaseCheckSummary {
  due: number;
  baseline: number;
  new: number;
  unchanged: number;
  orphan: number;
  failed: number;
  rateLimited: boolean;
  quotaExceeded: boolean;
  pausedUntil?: string;
}

/** Revisa los artistas pendientes, empezando por los que llevan más tiempo sin revisar. */
export async function checkDueArtistReleases(
  firestore: Firestore,
  nowMillis: number,
  fetchReleases: ReleaseFetcher,
): Promise<ReleaseCheckSummary> {
  const summary: ReleaseCheckSummary = {
    due: 0, baseline: 0, new: 0, unchanged: 0, orphan: 0, failed: 0,
    rateLimited: false, quotaExceeded: false,
  };
  const stateRef = firestore.doc(releaseChecksStatePath);
  const pausedUntil = timestampMillis((await stateRef.get()).get('pausedUntil'));
  if (pausedUntil !== undefined && pausedUntil > nowMillis) {
    return { ...summary, pausedUntil: new Date(pausedUntil).toISOString() };
  }

  const due = await firestore
    .collection(artistReleasesCollection)
    .where('nextCheckAt', '<=', Timestamp.fromMillis(nowMillis))
    .orderBy('nextCheckAt')
    .limit(releaseCheckBatchSize)
    .get();
  summary.due = due.size;
  let stop: SpotifyRateLimitedError | undefined;

  const postpone = async (snapshot: QueryDocumentSnapshot, delayMs: number) => {
    try {
      await snapshot.ref.update({ nextCheckAt: Timestamp.fromMillis(nowMillis + delayMs) });
    } catch (error) {
      logger.warn('checkArtistReleases: could not postpone artist', {
        artistId: snapshot.id,
        error,
      });
    }
  };

  for (let index = 0; index < due.docs.length && !stop; index += releaseCheckConcurrency) {
    const chunk = due.docs.slice(index, index + releaseCheckConcurrency);
    await Promise.all(chunk.map(async (snapshot) => {
      try {
        summary[await checkArtistRelease(firestore, snapshot, nowMillis, fetchReleases)] += 1;
      } catch (error) {
        if (error instanceof SpotifyRateLimitedError) {
          // El resto sigue pendiente para la próxima ejecución.
          if (!stop || error.quotaExceeded) stop = error;
          return;
        }
        summary.failed += 1;
        if (error instanceof SpotifyArtistUnavailableError) {
          logger.warn('checkArtistReleases: artist unavailable', {
            artistId: snapshot.id,
            status: error.status,
          });
          await postpone(snapshot, unavailableArtistRetryMs);
          return;
        }
        logger.error('checkArtistReleases: artist check failed', {
          artistId: snapshot.id,
          error,
        });
        await postpone(snapshot, releaseRetryDelayMs);
      }
    }));
  }

  if (stop) {
    summary.rateLimited = true;
    summary.quotaExceeded = stop.quotaExceeded;
    if (stop.quotaExceeded) {
      const pauseMs = stop.retryAfterSeconds !== undefined
        ? Math.max(stop.retryAfterSeconds * 1000, hourMs)
        : quotaExceededPauseMs;
      const resumeAt = nowMillis + pauseMs;
      await stateRef.set({ pausedUntil: Timestamp.fromMillis(resumeAt) }, { merge: true });
      summary.pausedUntil = new Date(resumeAt).toISOString();
      logger.warn('checkArtistReleases: Spotify quota exceeded, checks paused', {
        retryAfterSeconds: stop.retryAfterSeconds,
        pausedUntil: summary.pausedUntil,
      });
    } else {
      logger.warn('checkArtistReleases: Spotify rate limit reached', {
        retryAfterSeconds: stop.retryAfterSeconds,
      });
    }
  }
  return summary;
}

export const checkArtistReleases = onSchedule(
  {
    schedule: '7 * * * *',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    retryCount: 1,
    secrets: [spotifyClientId, spotifyClientSecret],
  },
  async (event) => {
    const nowMillis = new Date(event.scheduleTime).getTime();
    const token = await getSpotifyToken(spotifyClientId.value(), spotifyClientSecret.value());
    const result = await checkDueArtistReleases(db, nowMillis, spotifyReleaseFetcher(token));
    logger.info('checkArtistReleases: cycle completed', result);
  },
);

// ── Artistas vigilados ────────────────────────────────────────────────────────

/** Artistas del perfil con identificador de Spotify, sin duplicados. */
export function followedSpotifyArtists(profile: DocumentData | undefined): FollowedArtist[] {
  const artists = Array.isArray(profile?.topArtists) ? profile.topArtists : [];
  const seen = new Set<string>();
  return artists.flatMap((artist: unknown): FollowedArtist[] => {
    if (
      !isRecord(artist) ||
      typeof artist.spotifyId !== 'string' ||
      !spotifyIdPattern.test(artist.spotifyId) ||
      typeof artist.name !== 'string' ||
      artist.name.trim().length === 0 ||
      seen.has(artist.spotifyId)
    ) {
      return [];
    }
    seen.add(artist.spotifyId);
    return [{ id: artist.spotifyId, name: artist.name.trim() }];
  });
}

/**
 * Registra los artistas de todos los perfiles que aún no se vigilan, con
 * revisión inmediata. Las bajas se retiran en `checkArtistReleases`.
 */
export async function syncWatchedArtistsAt(
  firestore: Firestore,
  nowMillis: number,
): Promise<{ profiles: number; artists: number; added: number }> {
  const watched = new Set<string>();
  let profiles = 0;
  let added = 0;
  let cursor: QueryDocumentSnapshot | undefined;
  for (;;) {
    let query = firestore
      .collection('users')
      .orderBy(FieldPath.documentId())
      .select('topArtists')
      .limit(watchSyncPageSize);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    profiles += page.size;

    const candidates = new Map<string, FollowedArtist>();
    for (const profile of page.docs) {
      for (const artist of followedSpotifyArtists(profile.data())) {
        if (!watched.has(artist.id)) candidates.set(artist.id, artist);
      }
    }
    const pending = [...candidates.values()];
    for (let index = 0; index < pending.length; index += artistStateBatchSize) {
      const batch = pending.slice(index, index + artistStateBatchSize);
      const snapshots = await firestore.getAll(
        ...batch.map((artist) => firestore.collection(artistReleasesCollection).doc(artist.id)),
        { fieldMask: [] },
      );
      await Promise.all(snapshots.map(async (snapshot, position) => {
        const artist = batch[position];
        watched.add(artist.id);
        if (snapshot.exists) return;
        try {
          await snapshot.ref.create({
            name: artist.name,
            nextCheckAt: Timestamp.fromMillis(nowMillis),
          });
          added += 1;
        } catch (error: unknown) {
          if ((error as { code?: unknown }).code !== alreadyExistsCode) throw error;
        }
      }));
    }

    if (page.size < watchSyncPageSize) break;
    cursor = page.docs[page.docs.length - 1];
  }
  return { profiles, artists: watched.size, added };
}

export const syncWatchedArtists = onSchedule(
  {
    schedule: '20 3 * * *',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    retryCount: 3,
  },
  async (event) => {
    const result = await syncWatchedArtistsAt(db, new Date(event.scheduleTime).getTime());
    logger.info('syncWatchedArtists: sync completed', result);
  },
);

// ── Aviso semanal ─────────────────────────────────────────────────────────────

/** UTC offsets, in minutes, where it is Saturday 11:30 during the scheduled slot. */
export function weeklyReleaseOffsets(scheduledAt: Date): number[] {
  return utcOffsetsAtLocalTime(scheduledAt, weeklyReleaseLocalMinutes, weeklyReleaseSlotMinutes)
    .filter((offset) =>
      new Date(scheduledAt.getTime() + offset * 60 * 1000).getUTCDay() === weeklyReleaseWeekday);
}

export function wantsWeeklyReleaseNotification(
  privateData: DocumentData | undefined,
  nowMillis: number,
): boolean {
  const offset = privateData?.utcOffsetMinutes;
  if (typeof offset !== 'number' || privateData?.notifNewReleases === false) return false;
  const lastPush = privateData?.[newReleasePushField];
  return !(lastPush instanceof Timestamp)
    || localDay(lastPush.toMillis(), offset) !== localDay(nowMillis, offset);
}

/** Novedades detectadas desde el último aviso, de la más reciente a la más antigua. */
export function pendingReleases(
  artists: FollowedArtist[],
  states: Map<string, StoredRelease[]>,
  lastPushMillis: number | undefined,
  nowMillis: number,
): PendingRelease[] {
  const after = Math.max(nowMillis - weeklyReleaseWindowMs, lastPushMillis ?? -Infinity);
  return artists
    .flatMap((artist) => (states.get(artist.id) ?? [])
      .filter((release) =>
        release.announce && release.detectedAt > after && release.detectedAt <= nowMillis)
      .map((release) => ({ artist, release })))
    .sort((left, right) =>
      compareReleases(left.release, right.release) ||
      right.release.detectedAt - left.release.detectedAt);
}

/** Destaca el lanzamiento más reciente y nombra al resto de artistas. */
export function weeklyReleaseNotification(
  locale: SupportedLocale,
  releases: PendingRelease[],
): { title: string; body: string } {
  const [first] = releases;
  const title = (first.release.type === 'album'
    ? notificationText.newReleaseAlbum
    : notificationText.newReleaseSong)[locale](first.artist.name);
  const names = [...new Set(releases
    .filter((pending) => pending.artist.id !== first.artist.id)
    .map((pending) => pending.artist.name))];
  if (names.length === 0) return { title, body: first.release.name };

  const shown = names.length > 2 ? names.slice(0, 1) : names;
  const parts = names.length > shown.length
    ? [...shown, notificationText.friendDigestOthers[locale](String(names.length - shown.length))]
    : shown;
  const artists = new Intl.ListFormat(locale, { style: 'long', type: 'conjunction' })
    .format(parts);
  return {
    title,
    body: `${first.release.name} · ${notificationText.newReleaseOthers[locale](artists)}`,
  };
}

async function loadRecentReleases(
  firestore: Firestore,
  artists: FollowedArtist[],
  cache: Map<string, StoredRelease[]>,
): Promise<Map<string, StoredRelease[]>> {
  const missing = artists.filter((artist) => !cache.has(artist.id));
  for (let index = 0; index < missing.length; index += artistStateBatchSize) {
    const snapshots = await firestore.getAll(
      ...missing
        .slice(index, index + artistStateBatchSize)
        .map((artist) => firestore.collection(artistReleasesCollection).doc(artist.id)),
      { fieldMask: ['recentReleases'] },
    );
    for (const snapshot of snapshots) {
      cache.set(snapshot.id, parseStoredReleases(snapshot.get('recentReleases')));
    }
  }
  return cache;
}

async function sendWeeklyReleaseNotification(
  firestore: Firestore,
  privateProfile: QueryDocumentSnapshot,
  nowMillis: number,
  cache: Map<string, StoredRelease[]>,
  notify: typeof sendNotification,
): Promise<boolean> {
  const uid = privateProfile.id;
  const privateData = privateProfile.data();
  if (!wantsWeeklyReleaseNotification(privateData, nowMillis)) return false;

  const [[profileSnap], deletion] = await Promise.all([
    firestore.getAll(firestore.doc(`users/${uid}`), { fieldMask: ['topArtists', 'username'] }),
    firestore.doc(`account_deletions/${uid}`).get(),
  ]);
  const profile = profileSnap.data();
  if (deletion.exists || !profile || profile.username === 'deleted_user') return false;

  const artists = followedSpotifyArtists(profile);
  if (artists.length === 0) return false;
  const releases = pendingReleases(
    artists,
    await loadRecentReleases(firestore, artists, cache),
    timestampMillis(privateData[newReleasePushField]),
    nowMillis,
  );
  if (releases.length === 0) return false;

  // Claim the slot before sending: a retried or overlapping run must not
  // deliver the notification twice, and a missed one is harmless.
  const claimed = await firestore.runTransaction(async (transaction) => {
    const current = (await transaction.get(privateProfile.ref)).data();
    if (!wantsWeeklyReleaseNotification(current, nowMillis)) return false;
    transaction.update(privateProfile.ref, {
      [newReleasePushField]: Timestamp.fromMillis(nowMillis),
    });
    return true;
  });
  if (!claimed) return false;

  await notify(
    uid,
    privateData,
    weeklyReleaseNotification(preferredLocale(privateData), releases),
    { type: 'new_release' },
    'new_release',
  );
  return true;
}

/** Avisa los sábados a las 11:30 hora local de las novedades de la semana. */
export async function sendWeeklyReleaseNotificationsAt(
  firestore: Firestore,
  scheduledAt: Date,
  notify = sendNotification,
): Promise<{ candidates: number; sent: number }> {
  const nowMillis = scheduledAt.getTime();
  const cache = new Map<string, StoredRelease[]>();
  let candidates = 0;
  let sent = 0;

  for (const offset of weeklyReleaseOffsets(scheduledAt)) {
    let cursor: QueryDocumentSnapshot | undefined;
    for (;;) {
      let query = firestore
        .collection(userPrivateCollection)
        .where('utcOffsetMinutes', '==', offset)
        .orderBy(FieldPath.documentId())
        .limit(weeklyReleasePageSize);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      candidates += page.size;

      for (let index = 0; index < page.docs.length; index += weeklyReleaseConcurrency) {
        const chunk = page.docs.slice(index, index + weeklyReleaseConcurrency);
        const results = await Promise.all(chunk.map(async (privateProfile) => {
          try {
            return await sendWeeklyReleaseNotification(
              firestore,
              privateProfile,
              nowMillis,
              cache,
              notify,
            );
          } catch (error) {
            // One recipient must not prevent the rest of the slot from
            // receiving their notification.
            logger.error('sendWeeklyReleaseNotifications: recipient failed', {
              recipientUid: privateProfile.id,
              error,
            });
            return false;
          }
        }));
        sent += results.filter(Boolean).length;
      }

      if (page.size < weeklyReleasePageSize) break;
      cursor = page.docs[page.docs.length - 1];
    }
  }

  return { candidates, sent };
}

export const sendWeeklyReleaseNotifications = onSchedule(
  {
    // Saturday 11:30 local time falls on Friday or Saturday in UTC.
    schedule: '*/15 * * * 5,6',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    retryCount: 3,
  },
  async (event) => {
    const scheduledAt = new Date(event.scheduleTime);
    const result = await sendWeeklyReleaseNotificationsAt(db, scheduledAt);
    logger.info('sendWeeklyReleaseNotifications: slot completed', {
      ...result,
      scheduledAt: scheduledAt.toISOString(),
    });
  },
);
