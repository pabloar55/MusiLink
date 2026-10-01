const assert = require('node:assert/strict');
const { after, afterEach, before, test } = require('node:test');
const fs = require('node:fs');
const { assertFails, assertSucceeds, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc } = require('firebase/firestore');
const { getMetadata, ref, uploadBytes } = require('firebase/storage');

let env;
const storageRules = fs.readFileSync('storage.rules', 'utf8');
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'musilink-functions-test',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
    storage: { rules: storageRules },
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

function groupPhoto(uid, chatId) {
  return ref(env.authenticatedContext(uid).storage(), `group_photos/${chatId}`);
}
function uploadGroupPhoto(uid, chatId) {
  return uploadBytes(
    groupPhoto(uid, chatId),
    new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    { contentType: 'image/jpeg' },
  );
}

test('las reglas respetan el límite de dos documentos de Firestore de producción', () => {
  // The Storage emulator accepts three lookups, although production denies
  // them. With one owner UID, each referenced collection is one document.
  const collections = new Set(
    [...storageRules.matchAll(/\/documents\/([a-z_]+)\/\$\(uid\)/g)]
      .map((match) => match[1]),
  );
  assert.ok(collections.size <= 2, `Storage consultaría ${collections.size} documentos`);
});

test('permite subir la foto propia antes de publicar el borrador', async () => {
  await seed('user_private/alice', {
    friends: [],
    setupProfile: { displayName: 'Alice', username: 'alice_name', photoUrl: '' },
  });
  const result = await assertSucceeds(upload('alice'));
  assert.equal(result.metadata.size, 4);
  await assertSucceeds(upload('alice'));
  await assertSucceeds(updateDoc(
    doc(env.authenticatedContext('alice').firestore(), 'user_private/alice'),
    { 'setupProfile.photoUrl': 'https://firebasestorage.googleapis.com/v0/b/musi-link-e7759.firebasestorage.app/o/profile_photos%2Falice?alt=media&token=abc' },
  ));
  await assertFails(upload('bob', 'alice'));
});

test('permite la foto de un perfil publicado y bloquea cuentas sin alta o en eliminación', async () => {
  await assertFails(upload('alice'));
  await seed('users/alice', { username: 'alice_name' });
  await seed('user_private/alice', { friends: [] });
  await assertSucceeds(upload('alice'));
  await seed('account_deletions/alice', { status: 'pending' });
  await assertFails(upload('alice'));
});

test('un borrador no elude la eliminación de un perfil', async () => {
  await seed('users/alice', { username: 'deleted_user' });
  await seed('user_private/alice', { setupProfile: { username: 'alice_name' } });
  await seed('account_deletions/alice', { status: 'pending' });
  await assertFails(upload('alice'));
});

test('una baja durante el onboarding bloquea también la foto del borrador', async () => {
  await seed('user_private/alice', { setupProfile: { username: 'alice_name' } });
  await seed('account_deletions/alice', { status: 'requested' });
  await assertFails(upload('alice'));
});

test('un perfil anonimizado sin documento privado no puede volver a subir fotos', async () => {
  await seed('users/alice', { username: 'deleted_user' });
  await assertFails(upload('alice'));
  await assertFails(setDoc(
    doc(env.authenticatedContext('alice').firestore(), 'user_private/alice'),
    { setupProfile: { username: 'alice_name' } },
  ));
});

test('solo los miembros pueden ver y cambiar la foto de su grupo', async () => {
  const chatId = 'GroupChat00000000001';
  await seed(`chats/${chatId}`, { type: 'group', participants: ['alice', 'bob'] });

  await assertSucceeds(uploadGroupPhoto('alice', chatId));
  await assertSucceeds(uploadGroupPhoto('bob', chatId));
  await assertSucceeds(getMetadata(groupPhoto('bob', chatId)));
  await assertFails(uploadGroupPhoto('mallory', chatId));
  await assertFails(getMetadata(groupPhoto('mallory', chatId)));
  await assertFails(uploadGroupPhoto('alice', 'GroupChat00000000002'));

  await seed('account_deletions/alice', { status: 'pending' });
  await assertFails(uploadGroupPhoto('alice', chatId));
});

test('un chat individual no admite foto de grupo', async () => {
  await seed('chats/alice_bob', { participants: ['alice', 'bob'] });
  await assertFails(uploadGroupPhoto('alice', 'alice_bob'));
});
