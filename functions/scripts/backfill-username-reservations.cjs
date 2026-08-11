'use strict';

const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

const EXPECTED_PROJECT_ID = 'musi-link-e7759';
const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;
const RESERVED_USERNAMES = new Set(['deleted_user']);
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
    `  npm run migrate:usernames -- --project ${EXPECTED_PROJECT_ID}`,
    `  npm run migrate:usernames -- --project ${EXPECTED_PROJECT_ID} --apply`,
    `  npm run migrate:usernames -- --project ${EXPECTED_PROJECT_ID} --verify-only`,
    '',
    'Sin --apply el script solo audita usuarios y reservas.',
    'La migración se cancela si encuentra duplicados, nombres inválidos o reservas conflictivas.',
  ].join('\n'));
}

function normalizeUsername(value) {
  return String(value).trim().toLowerCase();
}

function inspectState(users, reservations) {
  const invalid = [];
  const activeByUsername = new Map();

  for (const user of users) {
    const raw = typeof user.data.username === 'string' ? user.data.username.trim() : '';
    if (RESERVED_USERNAMES.has(raw)) continue;
    const normalized = normalizeUsername(raw);
    if (!USERNAME_PATTERN.test(normalized) || raw !== normalized) {
      invalid.push({ path: user.path, reason: `username inválido o no normalizado: ${raw}` });
      continue;
    }
    const owners = activeByUsername.get(normalized) ?? [];
    owners.push(user.uid);
    activeByUsername.set(normalized, owners);
  }

  const expected = new Map();
  for (const [username, owners] of activeByUsername) {
    if (owners.length > 1) {
      invalid.push({
        path: `usernames/${username}`,
        reason: `username duplicado entre UIDs: ${owners.join(', ')}`,
      });
      continue;
    }
    expected.set(username, owners[0]);
  }

  const reservationsByUsername = new Map(
    reservations.map((reservation) => [reservation.username, reservation]),
  );
  const pending = [];
  let upToDate = 0;

  for (const [username, uid] of expected) {
    const reservation = reservationsByUsername.get(username);
    if (!reservation) {
      pending.push({ username, uid });
    } else if (reservation.data.uid === uid) {
      upToDate += 1;
    } else {
      invalid.push({
        path: reservation.path,
        reason: `reservada por ${String(reservation.data.uid)}, esperaba ${uid}`,
      });
    }
  }

  for (const reservation of reservations) {
    if (!expected.has(reservation.username)) {
      invalid.push({
        path: reservation.path,
        reason: 'reserva huérfana o correspondiente a un usuario inválido',
      });
    }
  }

  return { pending, invalid, upToDate, active: expected.size };
}

async function loadState(db) {
  const [usersSnapshot, reservationsSnapshot] = await Promise.all([
    db.collection('users').get(),
    db.collection('usernames').get(),
  ]);
  return {
    users: usersSnapshot.docs.map((doc) => ({
      uid: doc.id,
      path: doc.ref.path,
      data: doc.data(),
    })),
    reservations: reservationsSnapshot.docs.map((doc) => ({
      username: doc.id,
      path: doc.ref.path,
      data: doc.data(),
    })),
  };
}

function printSummary(state, inspection, title) {
  console.log(`\n${title}`);
  console.log(`Usuarios: ${state.users.length}`);
  console.log(`Reservas: ${state.reservations.length}`);
  console.log(`Usuarios activos válidos: ${inspection.active}`);
  console.log(`Reservas correctas: ${inspection.upToDate}`);
  console.log(`Reservas pendientes: ${inspection.pending.length}`);
  console.log(`Conflictos: ${inspection.invalid.length}`);
  for (const issue of inspection.invalid) {
    console.error(`  - ${issue.path}: ${issue.reason}`);
  }
}

async function applyMigration(db, pending) {
  for (let index = 0; index < pending.length; index += WRITE_BATCH_SIZE) {
    const batch = db.batch();
    const page = pending.slice(index, index + WRITE_BATCH_SIZE);
    for (const reservation of page) {
      batch.create(db.doc(`usernames/${reservation.username}`), {
        uid: reservation.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
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
    process.exitCode = 1;
    return;
  }

  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();
  const state = await loadState(db);
  const inspection = inspectState(state.users, state.reservations);
  printSummary(state, inspection, verifyOnly ? 'VERIFICACIÓN' : apply ? 'ANTES DE MIGRAR' : 'DRY RUN');

  if (inspection.invalid.length > 0) {
    console.error('\nOperación cancelada: resuelve todos los conflictos antes de continuar.');
    process.exitCode = 2;
    return;
  }
  if (verifyOnly) {
    process.exitCode = inspection.pending.length === 0 ? 0 : 2;
    return;
  }
  if (!apply) {
    console.log('\nNo se ha escrito ningún documento. Añade --apply para ejecutar la migración.');
    return;
  }

  await applyMigration(db, inspection.pending);
  const finalState = await loadState(db);
  const finalInspection = inspectState(finalState.users, finalState.reservations);
  printSummary(finalState, finalInspection, 'VERIFICACIÓN FINAL');
  if (finalInspection.invalid.length > 0 || finalInspection.pending.length > 0) {
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

module.exports = { inspectState, normalizeUsername };
