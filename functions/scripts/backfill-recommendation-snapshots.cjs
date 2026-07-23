'use strict';

const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

const EXPECTED_PROJECT_ID = 'musi-link-e7759';
const SNAPSHOT_VERSION = 1;
const WRITE_BATCH_SIZE = 400;

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
    `  npm run migrate:recommendation-snapshots -- --project ${EXPECTED_PROJECT_ID}`,
    `  npm run migrate:recommendation-snapshots -- --project ${EXPECTED_PROJECT_ID} --apply`,
    `  npm run migrate:recommendation-snapshots -- --project ${EXPECTED_PROJECT_ID} --verify-only`,
    '',
    'Sin --apply el script solo muestra los cambios que realizaría.',
  ].join('\n'));
}

function stringList(value, limit) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => typeof item === 'string')
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
    .slice(0, limit);
}

function profileSnapshot(data) {
  const displayName = typeof data?.displayName === 'string' ? data.displayName.trim() : '';
  const username = typeof data?.username === 'string' ? data.username.trim() : '';
  const photoUrl = typeof data?.photoUrl === 'string' ? data.photoUrl.trim() : '';
  if (!displayName || !username) return undefined;

  return {
    displayName,
    username,
    photoUrl,
    topArtistNames: stringList(data.topArtistNames, 15),
    topGenreNames: stringList(data.topGenreNames, 10),
  };
}

function snapshotsEqual(left, right) {
  if (!left || typeof left !== 'object') return false;
  return left.displayName === right.displayName &&
    left.username === right.username &&
    left.photoUrl === right.photoUrl &&
    JSON.stringify(left.topArtistNames) === JSON.stringify(right.topArtistNames) &&
    JSON.stringify(left.topGenreNames) === JSON.stringify(right.topGenreNames);
}

function validStoredSnapshot(data, expected) {
  return data?.snapshotVersion === SNAPSHOT_VERSION &&
    data.profileSnapshot &&
    typeof data.profileSnapshot === 'object' &&
    snapshotsEqual(data.profileSnapshot, expected);
}

async function loadState(db) {
  const usersSnapshot = await db.collection('users').get();
  const users = new Map(usersSnapshot.docs.map((doc) => [doc.id, doc.data()]));
  const recommendations = [];

  for (const owner of usersSnapshot.docs) {
    const ownerRecommendations = await owner.ref.collection('recommendations').get();
    for (const recommendation of ownerRecommendations.docs) {
      recommendations.push({
        ownerUid: owner.id,
        ref: recommendation.ref,
        data: recommendation.data(),
      });
    }
  }

  return { users, recommendations };
}

function inspectState(state) {
  const pending = [];
  const invalid = [];
  let upToDate = 0;

  for (const recommendation of state.recommendations) {
    const candidateUid = String(
      recommendation.data.userId ?? recommendation.ref.id,
    ).trim();
    const candidateData = state.users.get(candidateUid);
    const snapshot = profileSnapshot(candidateData);

    if (!candidateUid || !snapshot) {
      invalid.push({
        path: recommendation.ref.path,
        candidateUid,
        reason: candidateData ? 'perfil público inválido' : 'usuario inexistente',
      });
      continue;
    }

    if (validStoredSnapshot(recommendation.data, snapshot)) {
      upToDate += 1;
      continue;
    }

    pending.push({ ...recommendation, candidateUid, snapshot });
  }

  return { pending, invalid, upToDate };
}

function printSummary(state, inspection, title) {
  console.log(`\n${title}`);
  console.log(`Proyecto: ${EXPECTED_PROJECT_ID}`);
  console.log(`Usuarios: ${state.users.size}`);
  console.log(`Recomendaciones: ${state.recommendations.length}`);
  console.log(`Actualizadas: ${inspection.upToDate}`);
  console.log(`Pendientes: ${inspection.pending.length}`);
  console.log(`Inválidas: ${inspection.invalid.length}`);

  for (const item of inspection.invalid) {
    console.error(`  - ${item.path}: ${item.reason} (${item.candidateUid || 'sin uid'})`);
  }
}

async function applyMigration(db, pending) {
  for (let index = 0; index < pending.length; index += WRITE_BATCH_SIZE) {
    const batch = db.batch();
    const page = pending.slice(index, index + WRITE_BATCH_SIZE);

    for (const recommendation of page) {
      batch.set(recommendation.ref, {
        userId: recommendation.candidateUid,
        snapshotVersion: SNAPSHOT_VERSION,
        profileSnapshot: recommendation.snapshot,
        snapshotGeneratedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    await batch.commit();
    console.log(`Escritas ${Math.min(index + page.length, pending.length)}/${pending.length}`);
  }
}

async function main() {
  const projectId = readArgument('--project');
  const apply = hasFlag('--apply');
  const verifyOnly = hasFlag('--verify-only');

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

  const initialState = await loadState(db);
  const initialInspection = inspectState(initialState);
  printSummary(
    initialState,
    initialInspection,
    verifyOnly ? 'VERIFICACIÓN' : apply ? 'ANTES DE MIGRAR' : 'DRY RUN',
  );

  if (verifyOnly) {
    process.exitCode =
      initialInspection.pending.length === 0 && initialInspection.invalid.length === 0 ? 0 : 2;
    return;
  }

  if (!apply) {
    console.log('\nNo se ha escrito ningún documento. Añade --apply para ejecutar la migración.');
    return;
  }

  if (initialInspection.invalid.length > 0) {
    console.error('\nMigración cancelada: resuelve las recomendaciones inválidas antes de continuar.');
    process.exitCode = 2;
    return;
  }

  await applyMigration(db, initialInspection.pending);

  const finalState = await loadState(db);
  const finalInspection = inspectState(finalState);
  printSummary(finalState, finalInspection, 'VERIFICACIÓN FINAL');
  if (finalInspection.pending.length > 0 || finalInspection.invalid.length > 0) {
    process.exitCode = 2;
    return;
  }

  console.log('\nMigración completada y verificada.');
}

main().catch((error) => {
  console.error('\nError durante la migración:', error);
  process.exitCode = 1;
});
