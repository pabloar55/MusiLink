'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { inspectState, normalizeUsername } = require('./backfill-username-reservations.cjs');

function user(uid, username) {
  return { uid, path: `users/${uid}`, data: { username } };
}

function reservation(username, uid) {
  return { username, path: `usernames/${username}`, data: { uid } };
}

test('normaliza espacios y mayúsculas', () => {
  assert.equal(normalizeUsername(' TestUser '), 'testuser');
});

test('detecta usernames duplicados antes de escribir', () => {
  const result = inspectState([
    user('alice', 'same_name'),
    user('bob', 'same_name'),
  ], []);

  assert.equal(result.pending.length, 0);
  assert.equal(result.invalid.length, 1);
  assert.match(result.invalid[0].reason, /duplicado/);
});

test('prepara reservas faltantes e ignora perfiles anonimizados', () => {
  const result = inspectState([
    user('alice', 'alice_name'),
    user('deleted', 'deleted_user'),
  ], []);

  assert.deepEqual(result.pending, [{ username: 'alice_name', uid: 'alice' }]);
  assert.equal(result.invalid.length, 0);
});

test('rechaza una reserva que pertenece a otro UID', () => {
  const result = inspectState(
    [user('alice', 'alice_name')],
    [reservation('alice_name', 'bob')],
  );

  assert.equal(result.pending.length, 0);
  assert.equal(result.invalid.length, 1);
  assert.match(result.invalid[0].reason, /reservada por bob/);
});
