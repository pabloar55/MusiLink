#!/usr/bin/env node

const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const verbose = args.includes('--verbose');

function argumentValue(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

const projectId = argumentValue('--project');
const confirmedProject = argumentValue('--confirm-project');
if (apply && (!projectId || confirmedProject !== projectId)) {
  throw new Error(
    'Apply mode requires matching --project and --confirm-project values.',
  );
}

function hasOnlyKeys(value, allowed) {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isArtist(value) {
  if (!isRecord(value)
      || !hasOnlyKeys(value, ['genres', 'imageUrl', 'name', 'spotifyId'])
      || typeof value.name !== 'string'
      || value.name.trim().length === 0
      || (value.imageUrl !== undefined && typeof value.imageUrl !== 'string')
      || (value.spotifyId !== undefined && typeof value.spotifyId !== 'string')
      || (value.genres !== undefined && !Array.isArray(value.genres))) {
    return false;
  }
  return value.genres === undefined
    || value.genres.every((genre) => typeof genre === 'string');
}

function isGenre(value) {
  return isRecord(value)
    && hasOnlyKeys(value, ['count', 'name', 'percentage'])
    && typeof value.name === 'string'
    && value.name.trim().length > 0
    && (value.count === undefined || typeof value.count === 'number')
    && (value.percentage === undefined
      || (typeof value.percentage === 'number' && Number.isFinite(value.percentage)));
}

function sanitizedStrings(value, limit, maxBytes) {
  if (!Array.isArray(value)) return undefined;
  return value
    .filter((item) => typeof item === 'string')
    .map((item) => item.trim())
    .filter((item) => item.length > 0 && Buffer.byteLength(item, 'utf8') <= maxBytes)
    .slice(0, limit);
}

function sameArray(left, right) {
  return Array.isArray(left)
    && left.length === right.length
    && left.every((value, index) => value === right[index]);
}

function cleanupFor(data) {
  const patch = {};
  if ('topArtists' in data
      && (!Array.isArray(data.topArtists)
        || data.topArtists.length > 30
        || !data.topArtists.every(isArtist))) {
    patch.topArtists = FieldValue.delete();
  }
  if ('topGenres' in data
      && (!Array.isArray(data.topGenres)
        || data.topGenres.length > 10
        || !data.topGenres.every(isGenre))) {
    patch.topGenres = FieldValue.delete();
  }

  for (const [field, limit, maxBytes] of [
    ['topArtistNames', 30, 300],
    ['topArtistKeys', 30, 400],
    ['topGenreNames', 10, 200],
  ]) {
    if (!(field in data)) continue;
    const sanitized = sanitizedStrings(data[field], limit, maxBytes);
    if (sanitized === undefined) {
      patch[field] = FieldValue.delete();
    } else if (!sameArray(data[field], sanitized)) {
      patch[field] = sanitized;
    }
  }
  return patch;
}

async function main() {
  initializeApp({
    credential: applicationDefault(),
    ...(projectId ? { projectId } : {}),
  });
  const firestore = getFirestore();
  const writer = apply ? firestore.bulkWriter() : undefined;
  let scanned = 0;
  let affected = 0;

  for await (const snapshot of firestore.collection('users').stream()) {
    scanned++;
    const patch = cleanupFor(snapshot.data());
    if (Object.keys(patch).length === 0) continue;
    affected++;
    if (verbose) console.log(`${apply ? 'sanitizing' : 'would sanitize'} ${snapshot.id}`);
    if (writer) writer.update(snapshot.ref, patch);
  }

  if (writer) await writer.close();
  console.log(JSON.stringify({ mode: apply ? 'apply' : 'dry-run', scanned, affected }));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}

module.exports = { cleanupFor };
