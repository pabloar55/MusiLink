"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendWeeklyReleaseNotifications = exports.syncWatchedArtists = exports.checkArtistReleases = exports.SpotifyArtistUnavailableError = exports.SpotifyRateLimitedError = exports.weeklyReleaseWindowMs = exports.newReleaseMaxAgeDays = exports.quotaExceededPauseMs = exports.releaseCheckIntervalMs = exports.newReleasePushField = exports.releaseChecksStatePath = exports.artistReleasesCollection = void 0;
exports.parseSpotifyReleases = parseSpotifyReleases;
exports.updateRecentReleases = updateRecentReleases;
exports.parseStoredReleases = parseStoredReleases;
exports.isQuotaExceeded = isQuotaExceeded;
exports.spotifyReleaseFetcher = spotifyReleaseFetcher;
exports.checkDueArtistReleases = checkDueArtistReleases;
exports.scheduledRunMillis = scheduledRunMillis;
exports.followedSpotifyArtists = followedSpotifyArtists;
exports.syncWatchedArtistsAt = syncWatchedArtistsAt;
exports.weeklyReleaseOffsets = weeklyReleaseOffsets;
exports.wantsWeeklyReleaseNotification = wantsWeeklyReleaseNotification;
exports.pendingReleases = pendingReleases;
exports.weeklyReleaseNotification = weeklyReleaseNotification;
exports.sendWeeklyReleaseNotificationsAt = sendWeeklyReleaseNotificationsAt;
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const catalog_request_1 = require("./catalog_request");
const firebase_1 = require("./firebase");
const firestore_values_1 = require("./firestore_values");
const local_time_1 = require("./local_time");
const notifications_1 = require("./notifications");
const spotify_client_1 = require("./spotify_client");
// Lanzamientos recientes por artista de Spotify. Los clientes autenticados los
// leen para la sección «Novedades»; solo el backend los escribe. Ver
// docs/new_release_notifications.md y lib/models/artist_release.dart.
exports.artistReleasesCollection = 'artist_releases';
// Pausa global de las revisiones cuando se agota la cuota de Spotify.
exports.releaseChecksStatePath = 'scheduler_state/artist_release_checks';
// Último aviso semanal enviado; evita repetirlo el mismo día.
exports.newReleasePushField = 'newReleasePushAt';
const userPrivateCollection = 'user_private';
const hourMs = 60 * 60 * 1000;
const dayMs = 24 * hourMs;
exports.releaseCheckIntervalMs = dayMs;
const releaseRetryDelayMs = hourMs;
const unavailableArtistRetryMs = 7 * dayMs;
// Sin Retry-After, la cuota agotada pausa las revisiones este tiempo para no
// competir con las búsquedas de los usuarios, que comparten la misma cuota.
exports.quotaExceededPauseMs = 6 * hourMs;
const releaseCheckBatchSize = 150;
const releaseCheckConcurrency = 3;
const spotifyReleasePageSize = 10;
const knownReleaseIdsLimit = 50;
const recentReleasesLimit = 10;
// Se conservan para la sección de la app aunque sean de antes de vigilar al
// artista. Solo se anuncian los que aparecen después y no superan
// newReleaseMaxAgeDays: así se descartan reediciones o cambios de orden.
const recentReleaseMaxAgeDays = 30;
exports.newReleaseMaxAgeDays = 7;
// Sábado a las 11:30 hora local.
const weeklyReleaseLocalMinutes = 11 * 60 + 30;
const weeklyReleaseWeekday = 6;
const weeklyReleaseSlotMinutes = 15;
// Algo más de una semana para tolerar retrasos; newReleasePushAt impide
// anunciar dos veces lo mismo.
exports.weeklyReleaseWindowMs = 8 * dayMs;
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
const releaseTypes = ['single', 'album'];
class SpotifyRateLimitedError extends Error {
    retryAfterSeconds;
    quotaExceeded;
    constructor(retryAfterSeconds, quotaExceeded) {
        super(quotaExceeded ? 'Spotify quota exceeded' : 'Spotify rate limit reached');
        this.retryAfterSeconds = retryAfterSeconds;
        this.quotaExceeded = quotaExceeded;
    }
}
exports.SpotifyRateLimitedError = SpotifyRateLimitedError;
class SpotifyArtistUnavailableError extends Error {
    status;
    constructor(status) {
        super('Spotify artist is unavailable');
        this.status = status;
    }
}
exports.SpotifyArtistUnavailableError = SpotifyArtistUnavailableError;
// ── Detección ─────────────────────────────────────────────────────────────────
function isoDay(millis) {
    return new Date(millis).toISOString().slice(0, 10);
}
function releaseImageUrl(images) {
    if (!Array.isArray(images))
        return '';
    const valid = images.filter((image) => (0, catalog_request_1.isRecord)(image) && typeof image.url === 'string' && spotifyImageUrlPattern.test(image.url));
    const preferred = valid.find((image) => image.width === preferredImageWidth);
    return (preferred ?? valid[0])?.url ?? '';
}
/** Valida la respuesta de `GET /v1/artists/{id}/albums` para un grupo. */
function parseSpotifyReleases(data, type) {
    const items = (0, catalog_request_1.isRecord)(data) ? data.items : undefined;
    if (!Array.isArray(items))
        throw new Error('Spotify returned a malformed release list');
    return items.flatMap((item) => {
        if (!(0, catalog_request_1.isRecord)(item) ||
            typeof item.id !== 'string' ||
            !spotifyIdPattern.test(item.id) ||
            typeof item.name !== 'string' ||
            item.name.trim().length === 0) {
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
function compareReleases(left, right) {
    // Más reciente primero; el mismo día, el álbum antes que el single.
    return right.releaseDate.localeCompare(left.releaseDate) ||
        releaseTypes.indexOf(right.type) - releaseTypes.indexOf(left.type);
}
/**
 * Actualiza los lanzamientos recientes de un artista con su catálogo actual.
 * Sin historial previo (`knownReleaseIds` ausente) nada se anuncia: un artista
 * recién vigilado no genera avisos por lo que ya había publicado.
 */
function updateRecentReleases(knownReleaseIds, previous, releases, nowMillis) {
    const known = new Set(knownReleaseIds ?? []);
    const previousById = new Map(previous.map((release) => [release.id, release]));
    const earliestRecent = isoDay(nowMillis - recentReleaseMaxAgeDays * dayMs);
    const earliestAnnounced = isoDay(nowMillis - exports.newReleaseMaxAgeDays * dayMs);
    // Spotify publica a medianoche de cada mercado: admite un día por delante.
    const latest = isoDay(nowMillis + dayMs);
    let newReleases = 0;
    const seen = new Set();
    const recentReleases = releases
        .filter((release) => release.releaseDate !== null &&
        release.releaseDate >= earliestRecent &&
        release.releaseDate <= latest)
        .sort(compareReleases)
        .flatMap((release) => {
        if (seen.has(release.id))
            return [];
        seen.add(release.id);
        const stored = previousById.get(release.id);
        const announce = stored?.announce ?? (knownReleaseIds !== undefined &&
            !known.has(release.id) &&
            release.releaseDate >= earliestAnnounced);
        if (!stored && announce)
            newReleases += 1;
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
function parseStoredReleases(value) {
    if (!Array.isArray(value))
        return [];
    return value.flatMap((item) => {
        if (!(0, catalog_request_1.isRecord)(item) ||
            typeof item.id !== 'string' ||
            !spotifyIdPattern.test(item.id) ||
            typeof item.name !== 'string' ||
            !releaseTypes.includes(item.type) ||
            typeof item.releaseDate !== 'string' ||
            !isoDayPattern.test(item.releaseDate)) {
            return [];
        }
        const detectedAt = (0, firestore_values_1.timestampMillis)(item.detectedAt);
        if (detectedAt === undefined)
            return [];
        return [{
                id: item.id,
                name: item.name,
                type: item.type,
                releaseDate: item.releaseDate,
                imageUrl: typeof item.imageUrl === 'string' && spotifyImageUrlPattern.test(item.imageUrl)
                    ? item.imageUrl
                    : '',
                detectedAt,
                announce: item.announce === true,
            }];
    });
}
function retryAfterSeconds(res) {
    const header = res.headers.get('retry-after');
    const value = header === null ? NaN : Number(header);
    return Number.isFinite(value) && value >= 0 ? value : undefined;
}
/** Spotify distingue la cuota agotada del límite de velocidad con `reason`. */
async function isQuotaExceeded(res) {
    try {
        const body = await res.json();
        return (0, catalog_request_1.isRecord)(body) && (0, catalog_request_1.isRecord)(body.error) && body.error.reason === 'QUOTA_EXCEEDED';
    }
    catch {
        return false;
    }
}
async function fetchReleaseGroup(token, artistId, type) {
    const url = new URL(`https://api.spotify.com/v1/artists/${artistId}/albums`);
    url.searchParams.set('include_groups', type);
    // Máximo admitido por Spotify en Development Mode.
    url.searchParams.set('limit', String(spotifyReleasePageSize));
    const res = await (0, spotify_client_1.fetchExternal)(url.toString(), {
        headers: { Authorization: `Bearer ${token}` },
    }, spotify_client_1.spotifyRequestTimeoutMs, 'Spotify');
    if (res.status === 429) {
        throw new SpotifyRateLimitedError(retryAfterSeconds(res), await isQuotaExceeded(res));
    }
    if (res.status === 400 || res.status === 404) {
        throw new SpotifyArtistUnavailableError(res.status);
    }
    if (!res.ok) {
        const errorBody = await (0, spotify_client_1.readResponseSnippet)(res);
        throw new Error(`Spotify artist releases failed with status ${res.status}: ${errorBody}`);
    }
    return parseSpotifyReleases(await res.json(), type);
}
/** Singles y álbumes por separado: un grupo numeroso no oculta al otro. */
function spotifyReleaseFetcher(token) {
    return async (artistId) => {
        const groups = await Promise.all(releaseTypes.map((type) => fetchReleaseGroup(token, artistId, type)));
        return groups.flat();
    };
}
async function checkArtistRelease(firestore, snapshot, nowMillis, fetchReleases) {
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
        ? data.knownReleaseIds.filter((id) => typeof id === 'string')
        : undefined;
    const releases = await fetchReleases(artistId);
    const update = updateRecentReleases(storedKnown, parseStoredReleases(data.recentReleases), releases, nowMillis);
    const now = firestore_1.Timestamp.fromMillis(nowMillis);
    await snapshot.ref.update({
        knownReleaseIds: update.knownReleaseIds,
        recentReleases: update.recentReleases.map((release) => ({
            ...release,
            detectedAt: firestore_1.Timestamp.fromMillis(release.detectedAt),
        })),
        checkedAt: now,
        nextCheckAt: firestore_1.Timestamp.fromMillis(nowMillis + exports.releaseCheckIntervalMs),
    });
    if (!storedKnown)
        return 'baseline';
    return update.newReleases > 0 ? 'new' : 'unchanged';
}
/** Revisa los artistas pendientes, empezando por los que llevan más tiempo sin revisar. */
async function checkDueArtistReleases(firestore, nowMillis, fetchReleases) {
    const summary = {
        due: 0, baseline: 0, new: 0, unchanged: 0, orphan: 0, failed: 0,
        rateLimited: false, quotaExceeded: false,
    };
    const stateRef = firestore.doc(exports.releaseChecksStatePath);
    const pausedUntil = (0, firestore_values_1.timestampMillis)((await stateRef.get()).get('pausedUntil'));
    if (pausedUntil !== undefined && pausedUntil > nowMillis) {
        return { ...summary, pausedUntil: new Date(pausedUntil).toISOString() };
    }
    const due = await firestore
        .collection(exports.artistReleasesCollection)
        .where('nextCheckAt', '<=', firestore_1.Timestamp.fromMillis(nowMillis))
        .orderBy('nextCheckAt')
        .limit(releaseCheckBatchSize)
        .get();
    summary.due = due.size;
    let stop;
    const postpone = async (snapshot, delayMs) => {
        try {
            await snapshot.ref.update({ nextCheckAt: firestore_1.Timestamp.fromMillis(nowMillis + delayMs) });
        }
        catch (error) {
            v2_1.logger.warn('checkArtistReleases: could not postpone artist', {
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
            }
            catch (error) {
                if (error instanceof SpotifyRateLimitedError) {
                    // El resto sigue pendiente para la próxima ejecución.
                    if (!stop || error.quotaExceeded)
                        stop = error;
                    return;
                }
                summary.failed += 1;
                if (error instanceof SpotifyArtistUnavailableError) {
                    v2_1.logger.warn('checkArtistReleases: artist unavailable', {
                        artistId: snapshot.id,
                        status: error.status,
                    });
                    await postpone(snapshot, unavailableArtistRetryMs);
                    return;
                }
                v2_1.logger.error('checkArtistReleases: artist check failed', {
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
                : exports.quotaExceededPauseMs;
            const resumeAt = nowMillis + pauseMs;
            await stateRef.set({ pausedUntil: firestore_1.Timestamp.fromMillis(resumeAt) }, { merge: true });
            summary.pausedUntil = new Date(resumeAt).toISOString();
            v2_1.logger.warn('checkArtistReleases: Spotify quota exceeded, checks paused', {
                retryAfterSeconds: stop.retryAfterSeconds,
                pausedUntil: summary.pausedUntil,
            });
        }
        else {
            v2_1.logger.warn('checkArtistReleases: Spotify rate limit reached', {
                retryAfterSeconds: stop.retryAfterSeconds,
            });
        }
    }
    return summary;
}
/**
 * Momento de la ejecución. Un reintento conserva su `scheduleTime`, pero una
 * ejecución forzada desde Cloud Scheduler recibe la próxima hora programada,
 * así que nunca se usa una hora futura.
 */
function scheduledRunMillis(scheduleTime, nowMillis = Date.now()) {
    const scheduled = Date.parse(scheduleTime);
    return Number.isFinite(scheduled) ? Math.min(scheduled, nowMillis) : nowMillis;
}
exports.checkArtistReleases = (0, scheduler_1.onSchedule)({
    schedule: '7 * * * *',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    retryCount: 1,
    secrets: [spotify_client_1.spotifyClientId, spotify_client_1.spotifyClientSecret],
}, async (event) => {
    const nowMillis = scheduledRunMillis(event.scheduleTime);
    const token = await (0, spotify_client_1.getSpotifyToken)(spotify_client_1.spotifyClientId.value(), spotify_client_1.spotifyClientSecret.value());
    const result = await checkDueArtistReleases(firebase_1.db, nowMillis, spotifyReleaseFetcher(token));
    v2_1.logger.info('checkArtistReleases: cycle completed', result);
});
// ── Artistas vigilados ────────────────────────────────────────────────────────
/** Artistas del perfil con identificador de Spotify, sin duplicados. */
function followedSpotifyArtists(profile) {
    const artists = Array.isArray(profile?.topArtists) ? profile.topArtists : [];
    const seen = new Set();
    return artists.flatMap((artist) => {
        if (!(0, catalog_request_1.isRecord)(artist) ||
            typeof artist.spotifyId !== 'string' ||
            !spotifyIdPattern.test(artist.spotifyId) ||
            typeof artist.name !== 'string' ||
            artist.name.trim().length === 0 ||
            seen.has(artist.spotifyId)) {
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
async function syncWatchedArtistsAt(firestore, nowMillis) {
    const watched = new Set();
    let profiles = 0;
    let added = 0;
    let cursor;
    for (;;) {
        let query = firestore
            .collection('users')
            .orderBy(firestore_1.FieldPath.documentId())
            .select('topArtists')
            .limit(watchSyncPageSize);
        if (cursor)
            query = query.startAfter(cursor);
        const page = await query.get();
        profiles += page.size;
        const candidates = new Map();
        for (const profile of page.docs) {
            for (const artist of followedSpotifyArtists(profile.data())) {
                if (!watched.has(artist.id))
                    candidates.set(artist.id, artist);
            }
        }
        const pending = [...candidates.values()];
        for (let index = 0; index < pending.length; index += artistStateBatchSize) {
            const batch = pending.slice(index, index + artistStateBatchSize);
            const snapshots = await firestore.getAll(...batch.map((artist) => firestore.collection(exports.artistReleasesCollection).doc(artist.id)), { fieldMask: [] });
            await Promise.all(snapshots.map(async (snapshot, position) => {
                const artist = batch[position];
                watched.add(artist.id);
                if (snapshot.exists)
                    return;
                try {
                    await snapshot.ref.create({
                        name: artist.name,
                        nextCheckAt: firestore_1.Timestamp.fromMillis(nowMillis),
                    });
                    added += 1;
                }
                catch (error) {
                    if (error.code !== alreadyExistsCode)
                        throw error;
                }
            }));
        }
        if (page.size < watchSyncPageSize)
            break;
        cursor = page.docs[page.docs.length - 1];
    }
    return { profiles, artists: watched.size, added };
}
exports.syncWatchedArtists = (0, scheduler_1.onSchedule)({
    schedule: '20 3 * * *',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    retryCount: 3,
}, async (event) => {
    const result = await syncWatchedArtistsAt(firebase_1.db, scheduledRunMillis(event.scheduleTime));
    v2_1.logger.info('syncWatchedArtists: sync completed', result);
});
// ── Aviso semanal ─────────────────────────────────────────────────────────────
/** UTC offsets, in minutes, where it is Saturday 11:30 during the scheduled slot. */
function weeklyReleaseOffsets(scheduledAt) {
    return (0, local_time_1.utcOffsetsAtLocalTime)(scheduledAt, weeklyReleaseLocalMinutes, weeklyReleaseSlotMinutes)
        .filter((offset) => new Date(scheduledAt.getTime() + offset * 60 * 1000).getUTCDay() === weeklyReleaseWeekday);
}
function wantsWeeklyReleaseNotification(privateData, nowMillis) {
    const offset = privateData?.utcOffsetMinutes;
    if (typeof offset !== 'number' || privateData?.notifNewReleases === false)
        return false;
    const lastPush = privateData?.[exports.newReleasePushField];
    return !(lastPush instanceof firestore_1.Timestamp)
        || (0, local_time_1.localDay)(lastPush.toMillis(), offset) !== (0, local_time_1.localDay)(nowMillis, offset);
}
/** Novedades detectadas desde el último aviso, de la más reciente a la más antigua. */
function pendingReleases(artists, states, lastPushMillis, nowMillis) {
    const after = Math.max(nowMillis - exports.weeklyReleaseWindowMs, lastPushMillis ?? -Infinity);
    return artists
        .flatMap((artist) => (states.get(artist.id) ?? [])
        .filter((release) => release.announce && release.detectedAt > after && release.detectedAt <= nowMillis)
        .map((release) => ({ artist, release })))
        .sort((left, right) => compareReleases(left.release, right.release) ||
        right.release.detectedAt - left.release.detectedAt);
}
/** Destaca el lanzamiento más reciente y nombra al resto de artistas. */
function weeklyReleaseNotification(locale, releases) {
    const [first] = releases;
    const title = (first.release.type === 'album'
        ? notifications_1.notificationText.newReleaseAlbum
        : notifications_1.notificationText.newReleaseSong)[locale](first.artist.name);
    const names = [...new Set(releases
            .filter((pending) => pending.artist.id !== first.artist.id)
            .map((pending) => pending.artist.name))];
    if (names.length === 0)
        return { title, body: first.release.name };
    const shown = names.length > 2 ? names.slice(0, 1) : names;
    const parts = names.length > shown.length
        ? [...shown, notifications_1.notificationText.friendDigestOthers[locale](String(names.length - shown.length))]
        : shown;
    const artists = new Intl.ListFormat(locale, { style: 'long', type: 'conjunction' })
        .format(parts);
    return {
        title,
        body: `${first.release.name} · ${notifications_1.notificationText.newReleaseOthers[locale](artists)}`,
    };
}
async function loadRecentReleases(firestore, artists, cache) {
    const missing = artists.filter((artist) => !cache.has(artist.id));
    for (let index = 0; index < missing.length; index += artistStateBatchSize) {
        const snapshots = await firestore.getAll(...missing
            .slice(index, index + artistStateBatchSize)
            .map((artist) => firestore.collection(exports.artistReleasesCollection).doc(artist.id)), { fieldMask: ['recentReleases'] });
        for (const snapshot of snapshots) {
            cache.set(snapshot.id, parseStoredReleases(snapshot.get('recentReleases')));
        }
    }
    return cache;
}
async function sendWeeklyReleaseNotification(firestore, privateProfile, nowMillis, cache, notify) {
    const uid = privateProfile.id;
    const privateData = privateProfile.data();
    if (!wantsWeeklyReleaseNotification(privateData, nowMillis))
        return false;
    const [[profileSnap], deletion] = await Promise.all([
        firestore.getAll(firestore.doc(`users/${uid}`), { fieldMask: ['topArtists', 'username'] }),
        firestore.doc(`account_deletions/${uid}`).get(),
    ]);
    const profile = profileSnap.data();
    if (deletion.exists || !profile || profile.username === 'deleted_user')
        return false;
    const artists = followedSpotifyArtists(profile);
    if (artists.length === 0)
        return false;
    const releases = pendingReleases(artists, await loadRecentReleases(firestore, artists, cache), (0, firestore_values_1.timestampMillis)(privateData[exports.newReleasePushField]), nowMillis);
    if (releases.length === 0)
        return false;
    // Claim the slot before sending: a retried or overlapping run must not
    // deliver the notification twice, and a missed one is harmless.
    const claimed = await firestore.runTransaction(async (transaction) => {
        const current = (await transaction.get(privateProfile.ref)).data();
        if (!wantsWeeklyReleaseNotification(current, nowMillis))
            return false;
        transaction.update(privateProfile.ref, {
            [exports.newReleasePushField]: firestore_1.Timestamp.fromMillis(nowMillis),
        });
        return true;
    });
    if (!claimed)
        return false;
    await notify(uid, privateData, weeklyReleaseNotification((0, notifications_1.preferredLocale)(privateData), releases), { type: 'new_release' }, 'new_release');
    return true;
}
/** Avisa los sábados a las 11:30 hora local de las novedades de la semana. */
async function sendWeeklyReleaseNotificationsAt(firestore, scheduledAt, notify = notifications_1.sendNotification) {
    const nowMillis = scheduledAt.getTime();
    const cache = new Map();
    let candidates = 0;
    let sent = 0;
    for (const offset of weeklyReleaseOffsets(scheduledAt)) {
        let cursor;
        for (;;) {
            let query = firestore
                .collection(userPrivateCollection)
                .where('utcOffsetMinutes', '==', offset)
                .orderBy(firestore_1.FieldPath.documentId())
                .limit(weeklyReleasePageSize);
            if (cursor)
                query = query.startAfter(cursor);
            const page = await query.get();
            candidates += page.size;
            for (let index = 0; index < page.docs.length; index += weeklyReleaseConcurrency) {
                const chunk = page.docs.slice(index, index + weeklyReleaseConcurrency);
                const results = await Promise.all(chunk.map(async (privateProfile) => {
                    try {
                        return await sendWeeklyReleaseNotification(firestore, privateProfile, nowMillis, cache, notify);
                    }
                    catch (error) {
                        // One recipient must not prevent the rest of the slot from
                        // receiving their notification.
                        v2_1.logger.error('sendWeeklyReleaseNotifications: recipient failed', {
                            recipientUid: privateProfile.id,
                            error,
                        });
                        return false;
                    }
                }));
                sent += results.filter(Boolean).length;
            }
            if (page.size < weeklyReleasePageSize)
                break;
            cursor = page.docs[page.docs.length - 1];
        }
    }
    return { candidates, sent };
}
exports.sendWeeklyReleaseNotifications = (0, scheduler_1.onSchedule)({
    // Saturday 11:30 local time falls on Friday or Saturday in UTC.
    schedule: '*/15 * * * 5,6',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    retryCount: 3,
}, async (event) => {
    const scheduledAt = new Date(scheduledRunMillis(event.scheduleTime));
    const result = await sendWeeklyReleaseNotificationsAt(firebase_1.db, scheduledAt);
    v2_1.logger.info('sendWeeklyReleaseNotifications: slot completed', {
        ...result,
        scheduledAt: scheduledAt.toISOString(),
    });
});
//# sourceMappingURL=artist_releases.js.map