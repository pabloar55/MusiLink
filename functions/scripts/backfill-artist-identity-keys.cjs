'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const EXPECTED_PROJECT_ID = 'musi-link-e7759';
const ARTIST_IDENTITY_VERSION = 1;
const WRITE_BATCH_SIZE = 400;
const DEFAULT_REPORT_PATH = 'artist-key-migration-report.json';

const latinDiacriticGroups = {
  a: 'áàäâãåāăąæ',
  c: 'çćčĉċ',
  d: 'ďđð',
  e: 'éèëêēĕėęě',
  g: 'ğĝġģ',
  h: 'ĥħ',
  i: 'íìïîīĭįı',
  j: 'ĵ',
  k: 'ķ',
  l: 'ĺļľŀł',
  n: 'ñńņňŉŋ',
  o: 'óòöôõōŏőøœ',
  r: 'ŕŗř',
  s: 'śşšŝșß',
  t: 'ťţŧț',
  u: 'úùüûūŭůűų',
  w: 'ŵ',
  y: 'ýÿŷ',
  z: 'źżž',
};

const latinDiacriticReplacements = new Map(
  Object.entries(latinDiacriticGroups)
    .flatMap(([replacement, characters]) =>
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
    `  npm run migrate:artist-keys -- --project ${EXPECTED_PROJECT_ID}`,
    `  npm run migrate:artist-keys -- --project ${EXPECTED_PROJECT_ID} --apply`,
    `  npm run migrate:artist-keys -- --project ${EXPECTED_PROJECT_ID} --verify-only`,
    '',
    'Opciones:',
    `  --report <ruta>   Informe JSON (por defecto: ${DEFAULT_REPORT_PATH})`,
    '  --print-artists   Imprime también todos los artistas en consola',
    '',
    'Sin --apply el script solo lee Firestore y genera el informe.',
    'No consulta Spotify, Last.fm ni ningún otro servicio externo.',
  ].join('\n'));
}

function normalizeArtistIdentityName(value) {
  const folded = [...String(value).trim().toLowerCase()]
    .map((character) => latinDiacriticReplacements.get(character) ?? character)
    .join('');
  return folded
    .replace(/['’]/g, '')
    .replace(/&/g, ' and ')
    .replace(/[-_/.,:;!?()[\]{}"“”+*=|\\]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function stringList(value) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => typeof item === 'string')
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 50);
}

function rawArtists(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 50).map((artist) => {
    if (!artist || typeof artist !== 'object') return { name: '', spotifyId: '' };
    return {
      name: typeof artist.name === 'string' ? artist.name.trim() : '',
      spotifyId: typeof artist.spotifyId === 'string' ? artist.spotifyId.trim() : '',
    };
  });
}

function artistRecords(data) {
  const artists = rawArtists(data?.topArtists);
  const storedNames = stringList(data?.topArtistNames);
  const names = storedNames.length > 0
    ? storedNames
    : artists.map((artist) => artist.name).filter(Boolean);
  const usedArtistIndexes = new Set();

  return names.map((name, nameIndex) => {
    const normalizedName = normalizeArtistIdentityName(name);
    let artistIndex = -1;
    const direct = artists[nameIndex];
    if (
      direct &&
      normalizeArtistIdentityName(direct.name) === normalizedName
    ) {
      artistIndex = nameIndex;
    } else {
      artistIndex = artists.findIndex((artist, index) =>
        !usedArtistIndexes.has(index) &&
        normalizeArtistIdentityName(artist.name) === normalizedName);
    }
    if (artistIndex >= 0) usedArtistIndexes.add(artistIndex);

    const spotifyId = artistIndex >= 0 ? artists[artistIndex].spotifyId : '';
    return {
      name,
      normalizedName,
      spotifyId,
      key: spotifyId ? `spotify:${spotifyId}` : `name:${normalizedName}`,
    };
  });
}

function sameStringList(left, right) {
  return Array.isArray(left) &&
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function addReportOccurrence(collection, identity, uid) {
  const aggregateKey = identity.spotifyId || identity.normalizedName;
  let aggregate = collection.get(aggregateKey);
  if (!aggregate) {
    aggregate = {
      spotifyId: identity.spotifyId || undefined,
      normalizedName: identity.normalizedName,
      names: new Set(),
      users: new Set(),
      occurrences: 0,
    };
    collection.set(aggregateKey, aggregate);
  }
  aggregate.names.add(identity.name);
  aggregate.users.add(uid);
  aggregate.occurrences += 1;
}

function inspectUsers(snapshot) {
  const pending = [];
  const resolved = new Map();
  const unresolved = new Map();
  let artistProfiles = 0;
  let profilesWithoutArtists = 0;
  let upToDate = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const records = artistRecords(data);
    if (records.length === 0) {
      profilesWithoutArtists += 1;
      continue;
    }
    artistProfiles += 1;

    for (const record of records) {
      addReportOccurrence(record.spotifyId ? resolved : unresolved, record, doc.id);
    }

    const expectedKeys = records.map((record) => record.key);
    if (
      data.artistIdentityVersion === ARTIST_IDENTITY_VERSION &&
      sameStringList(data.topArtistKeys, expectedKeys)
    ) {
      upToDate += 1;
      continue;
    }
    pending.push({ ref: doc.ref, uid: doc.id, expectedKeys });
  }

  return {
    pending,
    resolved,
    unresolved,
    artistProfiles,
    profilesWithoutArtists,
    upToDate,
  };
}

function serializeAggregates(collection) {
  return [...collection.values()]
    .map((aggregate) => ({
      ...(aggregate.spotifyId ? { spotifyId: aggregate.spotifyId } : {}),
      normalizedName: aggregate.normalizedName,
      names: [...aggregate.names].sort((left, right) => left.localeCompare(right)),
      occurrences: aggregate.occurrences,
      userCount: aggregate.users.size,
    }))
    .sort((left, right) =>
      right.userCount - left.userCount ||
      left.normalizedName.localeCompare(right.normalizedName));
}

function buildReport(snapshot, inspection, mode) {
  const resolvedArtists = serializeAggregates(inspection.resolved);
  const unresolvedArtists = serializeAggregates(inspection.unresolved);
  const resolvedOccurrences = resolvedArtists.reduce(
    (sum, artist) => sum + artist.occurrences,
    0,
  );
  const unresolvedOccurrences = unresolvedArtists.reduce(
    (sum, artist) => sum + artist.occurrences,
    0,
  );

  return {
    generatedAt: new Date().toISOString(),
    projectId: EXPECTED_PROJECT_ID,
    mode,
    artistIdentityVersion: ARTIST_IDENTITY_VERSION,
    summary: {
      users: snapshot.size,
      artistProfiles: inspection.artistProfiles,
      profilesWithoutArtists: inspection.profilesWithoutArtists,
      profilesUpToDate: inspection.upToDate,
      profilesPending: inspection.pending.length,
      uniqueArtistsWithSpotifyId: resolvedArtists.length,
      uniqueArtistsWithoutSpotifyId: unresolvedArtists.length,
      artistOccurrencesWithSpotifyId: resolvedOccurrences,
      artistOccurrencesWithoutSpotifyId: unresolvedOccurrences,
    },
    artistsWithSpotifyId: resolvedArtists,
    artistsWithoutSpotifyId: unresolvedArtists,
  };
}

function writeReport(reportPath, report) {
  const absolutePath = path.resolve(reportPath);
  fs.writeFileSync(absolutePath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  return absolutePath;
}

function printSummary(report, reportPath) {
  const summary = report.summary;
  console.log(`\n${report.mode}`);
  console.log(`Proyecto: ${report.projectId}`);
  console.log(`Usuarios: ${summary.users}`);
  console.log(`Perfiles con artistas: ${summary.artistProfiles}`);
  console.log(`Perfiles ya actualizados: ${summary.profilesUpToDate}`);
  console.log(`Perfiles pendientes: ${summary.profilesPending}`);
  console.log(
    `Artistas únicos con spotifyId: ${summary.uniqueArtistsWithSpotifyId} ` +
    `(${summary.artistOccurrencesWithSpotifyId} selecciones)`,
  );
  console.log(
    `Artistas únicos sin spotifyId: ${summary.uniqueArtistsWithoutSpotifyId} ` +
    `(${summary.artistOccurrencesWithoutSpotifyId} selecciones)`,
  );
  console.log(`Informe completo: ${reportPath}`);
}

function printArtists(report) {
  console.log('\nARTISTAS CON SPOTIFY ID');
  for (const artist of report.artistsWithSpotifyId) {
    console.log(
      `  - ${artist.names.join(' / ')} | ${artist.spotifyId} | ` +
      `${artist.userCount} usuarios`,
    );
  }

  console.log('\nARTISTAS SIN SPOTIFY ID');
  for (const artist of report.artistsWithoutSpotifyId) {
    console.log(
      `  - ${artist.names.join(' / ')} | ${artist.normalizedName} | ` +
      `${artist.userCount} usuarios`,
    );
  }
}

async function applyMigration(db, pending) {
  for (let index = 0; index < pending.length; index += WRITE_BATCH_SIZE) {
    const page = pending.slice(index, index + WRITE_BATCH_SIZE);
    const batch = db.batch();
    for (const profile of page) {
      batch.set(profile.ref, {
        topArtistKeys: profile.expectedKeys,
        artistIdentityVersion: ARTIST_IDENTITY_VERSION,
      }, { merge: true });
    }
    await batch.commit();
    console.log(`Escritos ${Math.min(index + page.length, pending.length)}/${pending.length}`);
  }
}

async function main() {
  const projectId = readArgument('--project');
  const apply = hasFlag('--apply');
  const verifyOnly = hasFlag('--verify-only');
  const printAllArtists = hasFlag('--print-artists');
  const reportPath = readArgument('--report') || DEFAULT_REPORT_PATH;

  if (!projectId || projectId !== EXPECTED_PROJECT_ID || (apply && verifyOnly)) {
    usage();
    if (projectId && projectId !== EXPECTED_PROJECT_ID) {
      console.error(`\nProyecto rechazado: ${projectId}`);
    }
    process.exitCode = 1;
    return;
  }

  initializeApp({
    credential: applicationDefault(),
    projectId,
  });
  const db = getFirestore();

  const initialSnapshot = await db.collection('users').get();
  const initialInspection = inspectUsers(initialSnapshot);
  const initialMode = verifyOnly ? 'VERIFICACIÓN' : apply ? 'ANTES DE MIGRAR' : 'DRY RUN';
  const initialReport = buildReport(initialSnapshot, initialInspection, initialMode);
  const absoluteReportPath = writeReport(reportPath, initialReport);
  printSummary(initialReport, absoluteReportPath);
  if (printAllArtists) printArtists(initialReport);

  if (verifyOnly) {
    process.exitCode = initialInspection.pending.length === 0 ? 0 : 2;
    return;
  }

  if (!apply) {
    console.log('\nNo se ha escrito ningún documento. Añade --apply para ejecutar la migración.');
    return;
  }

  await applyMigration(db, initialInspection.pending);

  const finalSnapshot = await db.collection('users').get();
  const finalInspection = inspectUsers(finalSnapshot);
  const finalReport = buildReport(finalSnapshot, finalInspection, 'VERIFICACIÓN FINAL');
  writeReport(reportPath, finalReport);
  printSummary(finalReport, absoluteReportPath);
  if (finalInspection.pending.length > 0) {
    process.exitCode = 2;
    return;
  }

  console.log('\nMigración completada y verificada.');
}

if (require.main === module) {
  main().catch((error) => {
    console.error('\nError durante la migración:', error);
    process.exitCode = 1;
  });
}

module.exports = {
  artistRecords,
  inspectUsers,
  normalizeArtistIdentityName,
};
