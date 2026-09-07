const assert = require('node:assert/strict');
const { after, afterEach, before, test } = require('node:test');
const fs = require('node:fs');
const { assertFails, assertSucceeds, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc } = require('firebase/firestore');
const { ref, uploadBytes } = require('firebase/storage');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'musilink-functions-test',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
    storage: { rules: fs.readFileSync('storage.rules', 'utf8') },
  });
});
afterEach(async () => {
  await env.clearStorage();
  await env.clearFirestore();
});
after(async () => { await env?.cleanup(); });

async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}
function upload(uid, owner = uid) {
  return uploadBytes(
    ref(env.authenticatedContext(uid).storage(), `profile_photos/${owner}`),
    new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    { contentType: 'image/jpeg' },
  );
}

test('permite subir la foto propia antes de publicar el borrador', async () => {
  await seed('user_private/alice', { setupProfile: { username: 'alice_name' } });
  const result = await assertSucceeds(upload('alice'));
  assert.equal(result.metadata.size, 4);
  await assertFails(upload('bob', 'alice'));
});

test('permite la foto de un perfil publicado y bloquea cuentas sin alta o en eliminación', async () => {
  await assertFails(upload('alice'));
  await seed('users/alice', { username: 'alice_name' });
  await assertSucceeds(upload('alice'));
  await seed('account_deletions/alice', { status: 'pending' });
  await assertFails(upload('alice'));
});

test('un borrador no elude la eliminación de un perfil', async () => {
  await seed('users/alice', { username: 'deleted_user' });
  await seed('user_private/alice', { setupProfile: { username: 'alice_name' } });
  await assertFails(upload('alice'));
});
