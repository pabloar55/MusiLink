const { after, afterEach, before } = require('node:test');
const test = require('node:test');
const fs = require('node:fs');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const projectId = 'musilink-rules-test';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync('firestore.rules', 'utf8'),
    },
  });
});

afterEach(async () => {
  await env.clearFirestore();
});

after(async () => {
  await env.cleanup();
});

function dbFor(uid) {
  return env.authenticatedContext(uid).firestore();
}

async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function seedActiveUser(uid, friends = []) {
  await seed(`users/${uid}`, {
    displayName: uid,
    username: `${uid}_name`,
    photoUrl: '',
  });
  await seed(`user_private/${uid}`, {
    email: `${uid}@example.com`,
    createdAt: new Date(),
    lastLogin: new Date(),
    friends,
    blockedUsers: [],
  });
}

async function seedChat({ friends = true, read = false, reactions = {} } = {}) {
  await seedActiveUser('alice', friends ? ['bob'] : []);
  await seedActiveUser('bob', friends ? ['alice'] : []);
  await seed('chats/alice_bob', {
    participants: ['alice', 'bob'],
    lastMessage: 'hola',
    lastMessageTime: new Date(),
    createdAt: new Date(),
    unreadCounts: { alice: 1, bob: 0 },
  });
  await seed('chats/alice_bob/messages/message-1', {
    senderId: 'bob',
    text: 'hola',
    timestamp: new Date(),
    read,
    type: 'text',
    reactions,
  });
}

test('el propietario no puede añadir una amistad unilateralmente', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');

  await assertFails(updateDoc(doc(dbFor('alice'), 'user_private/alice'), {
    friends: ['bob'],
  }));
});

test('un perfil privado nuevo debe comenzar sin amigos', async () => {
  await assertFails(setDoc(doc(dbFor('alice'), 'user_private/alice'), {
    email: 'alice@example.com',
    createdAt: serverTimestamp(),
    lastLogin: serverTimestamp(),
    friends: ['bob'],
  }));
});

test('solo el receptor puede aceptar una solicitud pendiente', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');
  await seed('friend_requests/alice_bob', {
    senderId: 'alice',
    receiverId: 'bob',
    status: 'pending',
    createdAt: new Date(),
    updatedAt: new Date(),
  });

  await assertFails(updateDoc(doc(dbFor('alice'), 'friend_requests/alice_bob'), {
    status: 'accepted',
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(dbFor('bob'), 'friend_requests/alice_bob'), {
    status: 'accepted',
    updatedAt: serverTimestamp(),
  }));
});

test('no se puede crear un chat sin amistad mutua', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');

  await assertFails(setDoc(doc(dbFor('alice'), 'chats/alice_bob'), {
    participants: ['alice', 'bob'],
    lastMessage: '',
    lastMessageTime: serverTimestamp(),
    createdAt: serverTimestamp(),
    unreadCounts: { alice: 0, bob: 0 },
  }));
});

test('dos amigos mutuos pueden crear el chat inicial canónico', async () => {
  await seedActiveUser('alice', ['bob']);
  await seedActiveUser('bob', ['alice']);

  await assertSucceeds(setDoc(doc(dbFor('alice'), 'chats/alice_bob'), {
    participants: ['alice', 'bob'],
    lastMessage: '',
    lastMessageTime: serverTimestamp(),
    createdAt: serverTimestamp(),
    unreadCounts: { alice: 0, bob: 0 },
  }));
});

test('solo el receptor marca read de false a true', async () => {
  await seedChat();
  const messagePath = 'chats/alice_bob/messages/message-1';

  await assertFails(updateDoc(doc(dbFor('bob'), messagePath), { read: true }));
  await assertSucceeds(updateDoc(doc(dbFor('alice'), messagePath), { read: true }));
  await assertFails(updateDoc(doc(dbFor('alice'), messagePath), { read: false }));
});

test('una reacción solo puede cambiar la pertenencia del usuario autenticado', async () => {
  await seedChat({ reactions: { '❤️': ['bob'] } });
  const messagePath = 'chats/alice_bob/messages/message-1';

  await assertSucceeds(updateDoc(doc(dbFor('alice'), messagePath), {
    reactions: { '❤️': ['bob'], '🔥': ['alice'] },
  }));
  await assertFails(updateDoc(doc(dbFor('alice'), messagePath), {
    reactions: { '🔥': ['alice'] },
  }));
});

test('un participante no puede manipular el contador del otro', async () => {
  await seedChat();

  await assertFails(updateDoc(doc(dbFor('alice'), 'chats/alice_bob'), {
    unreadCounts: { alice: 0, bob: 99 },
  }));
  await assertFails(updateDoc(doc(dbFor('alice'), 'chats/alice_bob'), {
    lastMessage: 'resumen falso',
    lastMessageTime: serverTimestamp(),
    unreadCounts: { alice: 1, bob: 1 },
  }));
  await assertSucceeds(updateDoc(doc(dbFor('alice'), 'chats/alice_bob'), {
    unreadCounts: { alice: 0, bob: 0 },
  }));
});

test('no se puede escribir en un chat después de perder la amistad mutua', async () => {
  await seedChat({ friends: false });

  await assertFails(updateDoc(
    doc(dbFor('alice'), 'chats/alice_bob/messages/message-1'),
    { read: true },
  ));
  await assertFails(updateDoc(doc(dbFor('alice'), 'chats/alice_bob'), {
    unreadCounts: { alice: 0, bob: 0 },
  }));
});

test('rechaza usernames, URLs y trackData fuera de contrato', async () => {
  await assertFails(setDoc(doc(dbFor('alice'), 'users/alice'), {
    displayName: 'Alice',
    username: 'Alice!',
    photoUrl: 'javascript:alert(1)',
  }));

  await seedActiveUser('alice');
  await assertFails(updateDoc(doc(dbFor('alice'), 'users/alice'), {
    topGenres: Array.from({ length: 11 }, (_, index) => ({
      name: `genre-${index}`,
      count: 1,
      percentage: 1,
    })),
  }));
  await assertFails(updateDoc(doc(dbFor('alice'), 'users/alice'), {
    dailySong: {
      title: 'Song',
      artist: 'Artist',
      imageUrl: 'http://insecure.example/image.jpg',
      spotifyUrl: 'https://open.spotify.com/track/id',
      injected: true,
    },
    dailySongUpdatedAt: serverTimestamp(),
  }));
});
