'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { applicationDefault, initializeApp } = require('firebase-admin/app');
const {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} = require('firebase-admin/firestore');

const EXPECTED_PROJECT_ID = 'musi-link-e7759';
const INDEX_COLLECTION = 'music_recommendation_profiles';
const INDEX_SCHEMA_VERSION = 2;
const ARTIST_IDENTITY_VERSION = 1;
const MAX_ARTISTS = 30;
const MAX_GENRES = 10;
const READ_PAGE_SIZE = 500;
const WRITE_BATCH_SIZE = 400;
const DEFAULT_REFRESH_CONCURRENCY = 5;
const REFRESH_TIMEOUT_MS = 120_000;
const DEFAULT_REPORT_PATH = 'recommendation-index-v2-migration-report.json';

const genreAliases = {
  'alt rock': 'alternative rock',
  alternative: 'alternative',
  'alternative music': 'alternative',
  'corridos belicos': 'corridos belicos',
  'drum and bass': 'drum and bass',
  dnb: 'drum and bass',
  edm: 'electronic',
  electro: 'electronic',
  electronica: 'electronic',
  'electronic music': 'electronic',
  hiphop: 'hip hop',
  'hip hop music': 'hip hop',
  rap: 'hip hop',
  'rhythm and blues': 'r&b',
  rnb: 'r&b',
  'singer songwriter': 'singer-songwriter',
  'synth pop': 'synthpop',
};

const blockedGenreTags = new Set([
  '00s', '10s', '20s', '60s', '70s', '80s', '90s', 'american',
  'australian', 'belgian', 'brazilian', 'british', 'canadian', 'chilean',
  'chinese', 'colombian', 'danish', 'dutch', 'english', 'favorite',
  'favorites', 'favourite', 'female vocalists', 'finnish', 'french',
  'german', 'greek', 'icelandic', 'irish', 'italian', 'japanese', 'korean',
  'male vocalists', 'mexican', 'mexico', 'new zealand', 'norwegian',
  'polish', 'portuguese', 'puerto rican', 'puerto rico', 'romanian',
  'russian', 'scottish', 'seen live', 'spanish', 'spain', 'swedish',
  'turkish', 'uk', 'ukrainian', 'usa', 'vocalists', 'welsh',
]);

const artistDiacriticGroups = {
  a: 'áàäâãåāăąæ', c: 'çćčĉċ', d: 'ďđð', e: 'éèëêēĕėęě',
  g: 'ğĝġģ', h: 'ĥħ', i: 'íìïîīĭįı', j: 'ĵ', k: 'ķ', l: 'ĺļľŀł',
  n: 'ñńņňŉŋ', o: 'óòöôõōŏőøœ', r: 'ŕŗř', s: 'śşšŝșß',
  t: 'ťţŧț', u: 'úùüûūŭůűų', w: 'ŵ', y: 'ýÿŷ', z: 'źżž',
};

const artistDiacriticReplacements = new Map(
  Object.entries(artistDiacriticGroups).flatMap(([replacement, characters]) =>
    [...characters].map((character) => [character, replacement])),
);

function readArgument(name) {
  const inline = process.argv.find((argument) => argument.startsWith(`${name}=`));
  if (inline) return inline.slice(name.length + 1);
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function usage() {
  console.log([
    'Uso:',
    `  npm run migrate:recommendation-index-v2 -- --project ${EXPECTED_PROJECT_ID}`,
    `  npm run migrate:recommendation-index-v2 -- --project ${EXPECTED_PROJECT_ID} --backfill-index`,
    `  npm run migrate:recommendation-index-v2 -- --project ${EXPECTED_PROJECT_ID} --migrate-profiles`,
    `  npm run migrate:recommendation-index-v2 -- --project ${EXPECTED_PROJECT_ID} --verify-only`,
    '',
    'Opciones:',
    `  --concurrency <n>  Perfiles actualizados en paralelo (por defecto: ${DEFAULT_REFRESH_CONCURRENCY})`,
    `  --report <ruta>    Informe JSON (por defecto: ${DEFAULT_REPORT_PATH})`,
    '',
    'Sin una fase de escritura, el script solo lee y genera un informe.',
    '--migrate-profiles descarta definitivamente los artistas posteriores al puesto 30.',
  ].join('\n'));
}

function normalizeArtistIdentityName(value) {
  const folded = [...String(value).trim().toLowerCase()]
    .map((character) => artistDiacriticReplacements.get(character) ?? character)
    .join('');
  return folded
    .replace(/['’]/g, '')
    .replace(/&/g, ' and ')
    .replace(/[-_/.,:;!?()[\]{}"“”+*=|\\]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeGenreName(value) {
  const key = String(value)
    .trim()
    .toLowerCase()
    .replace(/[áàäâãåā]/g, 'a')
    .replace(/[éèëêē]/g, 'e')
    .replace(/[íìïîī]/g, 'i')
    .replace(/[óòöôõō]/g, 'o')
    .replace(/[úùüûū]/g, 'u')
    .replace(/ñ/g, 'n')
    .replace(/ç/g, 'c')
    .replace(/\br\s*&\s*b\b/g, 'rnb')
    .replace(/&/g, ' and ')
    .replace(/[\-_/]+/g, ' ')
    .replace(/[^a-z0-9&]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!key) return undefined;
  const normalized = genreAliases[key] ?? key;
  if (normalized.length < 2 || blockedGenreTags.has(normalized)) return undefined;
  if (/^(?:[0-9]{2}s|[12][0-9]{3}s?)$/.test(normalized)) return undefined;
  if (normalized.includes('seen live') || normalized.includes('favorite')) return undefined;
  return normalized;
}

function stringList(value, limit) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => typeof item === 'string')
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, limit);
}

function artistMaps(value) {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, MAX_ARTISTS)
    .filter((artist) => artist && typeof artist === 'object')
    .map((artist) => ({
      name: typeof artist.name === 'string' ? artist.name.trim() : '',
      imageUrl: typeof artist.imageUrl === 'string' ? artist.imageUrl.trim() : '',
      genres: stringList(artist.genres, 100),
      ...(typeof artist.spotifyId === 'string' && artist.spotifyId.trim()
        ? { spotifyId: artist.spotifyId.trim() }
        : {}),
    }))
    .filter((artist) => artist.name.length > 0);
}

function normalizedStoredArtistKey(value) {
  const key = String(value ?? '').trim();
  if (key.startsWith('spotify:') && key.length > 'spotify:'.length) return key;
  if (key.startsWith('name:')) {
    const name = normalizeArtistIdentityName(key.slice('name:'.length));
    return name ? `name:${name}` : undefined;
  }
  return undefined;
}

function artistKeys(artists, names, storedKeys) {
  return names.map((name, index) => {
    const artist = artists[index];
    if (
      artist &&
      normalizeArtistIdentityName(artist.name) === normalizeArtistIdentityName(name)
    ) {
      return artist.spotifyId
        ? `spotify:${artist.spotifyId}`
        : `name:${normalizeArtistIdentityName(name)}`;
    }
    return normalizedStoredArtistKey(storedKeys[index]) ??
      `name:${normalizeArtistIdentityName(name)}`;
  });
}

function topGenresFromArtists(artists) {
  const counts = new Map();
  for (const artist of artists) {
    for (const rawGenre of artist.genres) {
      const genre = normalizeGenreName(rawGenre);
      if (genre) counts.set(genre, (counts.get(genre) ?? 0) + 1);
    }
  }
  const sorted = [...counts.entries()].sort((left, right) => right[1] - left[1]);
  const total = sorted.reduce((sum, entry) => sum + entry[1], 0);
  return sorted.slice(0, MAX_GENRES).map(([name, count]) => ({
    name,
    count,
    percentage: total === 0 ? 0 : (count / total) * 100,
  }));
}

function existingGenres(data) {
  if (!Array.isArray(data?.topGenres)) return [];
  return data.topGenres.slice(0, MAX_GENRES).flatMap((genre) => {
    if (!genre || typeof genre !== 'object') return [];
    const name = normalizeGenreName(genre.name);
    if (!name) return [];
    return [{
      name,
      count: Number.isInteger(genre.count) ? genre.count : 0,
      percentage: typeof genre.percentage === 'number' ? genre.percentage : 0,
    }];
  });
}

function migrationProfile(uid, data) {
  if (!data || data.username === 'deleted_user') return undefined;
  const artists = artistMaps(data.topArtists);
  const storedNames = stringList(data.topArtistNames, MAX_ARTISTS);
  const names = artists.length > 0
    ? artists.map((artist) => artist.name)
    : storedNames;
  const keys = artistKeys(
    artists,
    names,
    stringList(data.topArtistKeys, MAX_ARTISTS),
  );
  const genres = artists.length > 0 ? topGenresFromArtists(artists) : existingGenres(data);
  const genreNames = genres.length > 0
    ? genres.map((genre) => genre.name)
    : stringList(data.topGenreNames, MAX_GENRES)
      .map(normalizeGenreName)
      .filter(Boolean);
  if (names.length === 0 && genreNames.length === 0) return undefined;

  const originalCount = Math.max(
    Array.isArray(data.topArtists) ? data.topArtists.length : 0,
    Array.isArray(data.topArtistNames) ? data.topArtistNames.length : 0,
    Array.isArray(data.topArtistKeys) ? data.topArtistKeys.length : 0,
  );
  return {
    uid,
    originalCount,
    removedCount: Math.max(0, originalCount - MAX_ARTISTS),
    artists,
    names,
    keys,
    genres,
    genreNames,
    indexData: {
      uid,
      schemaVersion: INDEX_SCHEMA_VERSION,
      artistMatchKeys: [...new Set(names.map(normalizeArtistIdentityName).filter(Boolean))],
      genreMatchKeys: [...new Set(genreNames.map((name) => name.trim().toLowerCase()))],
      topArtistNames: names,
      topArtistKeys: keys,
      topGenreNames: genreNames,
    },
  };
}

function comparableIndexData(data) {
  if (!data || typeof data !== 'object') return undefined;
  return {
    uid: data.uid,
    schemaVersion: data.schemaVersion,
    artistMatchKeys: data.artistMatchKeys,
    genreMatchKeys: data.genreMatchKeys,
    topArtistNames: data.topArtistNames,
    topArtistKeys: data.topArtistKeys,
    topGenreNames: data.topGenreNames,
  };
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

async function loadCollection(collection) {
  const documents = [];
  let lastId;
  while (true) {
    let query = collection.orderBy(FieldPath.documentId()).limit(READ_PAGE_SIZE);
    if (lastId) query = query.startAfter(lastId);
    const snapshot = await query.get();
    documents.push(...snapshot.docs);
    if (snapshot.size < READ_PAGE_SIZE) return documents;
    lastId = snapshot.docs[snapshot.docs.length - 1].id;
  }
}

function inspect(users, indexDocuments) {
  const profiles = users.flatMap((doc) => {
    const profile = migrationProfile(doc.id, doc.data());
    return profile ? [{ ...profile, ref: doc.ref, data: doc.data() }] : [];
  });
  const expectedByUid = new Map(profiles.map((profile) => [profile.uid, profile]));
  const actualByUid = new Map(indexDocuments.map((doc) => [doc.id, doc]));
  const pendingIndex = profiles.filter((profile) => {
    const actual = actualByUid.get(profile.uid);
    return !actual || !sameJson(
      comparableIndexData(actual.data()),
      profile.indexData,
    );
  });
  const staleIndex = indexDocuments.filter((doc) => !expectedByUid.has(doc.id));
  const profilesToTruncate = profiles.filter((profile) => profile.removedCount > 0);
  const refreshIncomplete = profiles.filter((profile) => {
    const requestedAt = profile.data.recommendationsRefreshRequestedAt;
    const generatedAt = profile.data.recommendationsGeneratedAt;
    return profile.data.recommendationProfileVersion !== INDEX_SCHEMA_VERSION ||
      !(requestedAt instanceof Timestamp) ||
      !(generatedAt instanceof Timestamp) ||
      generatedAt.toMillis() < requestedAt.toMillis();
  });
  return {
    profiles,
    pendingIndex,
    staleIndex,
    profilesToTruncate,
    refreshIncomplete,
  };
}

function reportFor(users, indexDocuments, inspection, mode) {
  return {
    generatedAt: new Date().toISOString(),
    projectId: EXPECTED_PROJECT_ID,
    mode,
    limits: { artists: MAX_ARTISTS, genres: MAX_GENRES },
    summary: {
      users: users.length,
      musicProfiles: inspection.profiles.length,
      existingIndexDocuments: indexDocuments.length,
      indexDocumentsPending: inspection.pendingIndex.length,
      staleIndexDocuments: inspection.staleIndex.length,
      profilesOverArtistLimit: inspection.profilesToTruncate.length,
      artistsToRemove: inspection.profilesToTruncate.reduce(
        (sum, profile) => sum + profile.removedCount,
        0,
      ),
      recommendationRefreshesPending: inspection.refreshIncomplete.length,
    },
    affectedProfiles: inspection.profilesToTruncate.map((profile) => ({
      uid: profile.uid,
      before: profile.originalCount,
      after: profile.names.length,
      removed: profile.removedCount,
    })),
  };
}

function printReport(report, reportPath) {
  const summary = report.summary;
  console.log(`\n${report.mode}`);
  console.log(`Proyecto: ${report.projectId}`);
  console.log(`Usuarios: ${summary.users}`);
  console.log(`Perfiles musicales: ${summary.musicProfiles}`);
  console.log(`Documentos de índice pendientes: ${summary.indexDocumentsPending}`);
  console.log(`Documentos de índice obsoletos: ${summary.staleIndexDocuments}`);
  console.log(`Perfiles con más de 30 artistas: ${summary.profilesOverArtistLimit}`);
  console.log(`Artistas que se descartarían: ${summary.artistsToRemove}`);
  console.log(`Recomendaciones pendientes de regenerar: ${summary.recommendationRefreshesPending}`);
  console.log(`Informe: ${reportPath}`);
}

async function writeIndex(db, inspection) {
  const operations = [
    ...inspection.pendingIndex.map((profile) => ({
      type: 'set',
      ref: db.collection(INDEX_COLLECTION).doc(profile.uid),
      data: profile.indexData,
    })),
    ...inspection.staleIndex.map((doc) => ({ type: 'delete', ref: doc.ref })),
  ];
  for (let index = 0; index < operations.length; index += WRITE_BATCH_SIZE) {
    const batch = db.batch();
    const page = operations.slice(index, index + WRITE_BATCH_SIZE);
    for (const operation of page) {
      if (operation.type === 'delete') {
        batch.delete(operation.ref);
      } else {
        batch.set(operation.ref, {
          ...operation.data,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
    console.log(`Índice actualizado: ${Math.min(index + page.length, operations.length)}/${operations.length}`);
  }
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForRefresh(ref, requestedAt) {
  const deadline = Date.now() + REFRESH_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const snapshot = await ref.get();
    const generatedAt = snapshot.data()?.recommendationsGeneratedAt;
    if (generatedAt instanceof Timestamp && generatedAt.toMillis() >= requestedAt.toMillis()) {
      return;
    }
    await sleep(2_000);
  }
  throw new Error(`Timeout esperando recomendaciones para ${ref.id}`);
}

async function migrateProfiles(inspection, concurrency) {
  if (inspection.pendingIndex.length > 0 || inspection.staleIndex.length > 0) {
    throw new Error('El índice compacto debe estar completo antes de migrar perfiles.');
  }

  for (let index = 0; index < inspection.refreshIncomplete.length; index += concurrency) {
    const page = inspection.refreshIncomplete.slice(index, index + concurrency);
    await Promise.all(page.map(async (profile) => {
      const requestedAt = Timestamp.now();
      const patch = {
        recommendationProfileVersion: INDEX_SCHEMA_VERSION,
        recommendationsRefreshRequestedAt: requestedAt,
      };
      if (profile.removedCount > 0) {
        Object.assign(patch, {
          topArtists: profile.artists,
          topArtistNames: profile.names,
          topArtistKeys: profile.keys,
          topGenres: profile.genres,
          topGenreNames: profile.genreNames,
          artistIdentityVersion: ARTIST_IDENTITY_VERSION,
          musicDataUpdatedAt: requestedAt,
        });
      }
      await profile.ref.set(patch, { merge: true });
      await waitForRefresh(profile.ref, requestedAt);
    }));
    console.log(
      `Perfiles migrados: ${Math.min(index + page.length, inspection.refreshIncomplete.length)}` +
      `/${inspection.refreshIncomplete.length}`,
    );
  }
}

async function readState(db) {
  const [users, indexDocuments] = await Promise.all([
    loadCollection(db.collection('users')),
    loadCollection(db.collection(INDEX_COLLECTION)),
  ]);
  return { users, indexDocuments, inspection: inspect(users, indexDocuments) };
}

async function main() {
  const projectId = readArgument('--project');
  const backfillIndex = hasFlag('--backfill-index');
  const migrate = hasFlag('--migrate-profiles');
  const verifyOnly = hasFlag('--verify-only');
  const selectedModes = [backfillIndex, migrate, verifyOnly].filter(Boolean).length;
  const concurrency = Number(readArgument('--concurrency') ?? DEFAULT_REFRESH_CONCURRENCY);
  const reportPath = path.resolve(readArgument('--report') ?? DEFAULT_REPORT_PATH);

  if (
    projectId !== EXPECTED_PROJECT_ID ||
    selectedModes > 1 ||
    !Number.isInteger(concurrency) ||
    concurrency < 1 ||
    concurrency > 20
  ) {
    usage();
    process.exitCode = 1;
    return;
  }

  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();
  let state = await readState(db);
  const mode = verifyOnly
    ? 'VERIFICACIÓN'
    : backfillIndex
      ? 'ANTES DE RELLENAR EL ÍNDICE'
      : migrate
        ? 'ANTES DE MIGRAR PERFILES'
        : 'DRY RUN';
  let report = reportFor(state.users, state.indexDocuments, state.inspection, mode);
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printReport(report, reportPath);

  if (!backfillIndex && !migrate && !verifyOnly) {
    console.log('\nNo se ha escrito ningún documento.');
    return;
  }

  if (backfillIndex) await writeIndex(db, state.inspection);
  if (migrate) await migrateProfiles(state.inspection, concurrency);

  state = await readState(db);
  report = reportFor(state.users, state.indexDocuments, state.inspection, 'VERIFICACIÓN FINAL');
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  printReport(report, reportPath);

  const failed = state.inspection.pendingIndex.length > 0 ||
    state.inspection.staleIndex.length > 0 ||
    (verifyOnly && (
      state.inspection.profilesToTruncate.length > 0 ||
      state.inspection.refreshIncomplete.length > 0
    ));
  if (failed) process.exitCode = 2;
}

if (require.main === module) {
  main().catch((error) => {
    console.error('\nError durante la migración:', error);
    process.exitCode = 1;
  });
}

module.exports = {
  migrationProfile,
  normalizeArtistIdentityName,
  normalizeGenreName,
  topGenresFromArtists,
};
