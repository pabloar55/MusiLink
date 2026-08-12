const { after, afterEach, before } = require('node:test');
const test = require('node:test');
const fs = require('node:fs');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
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
  await seed(`usernames/${uid}_name`, {
    uid,
    createdAt: new Date(),
  });
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

test('el cliente puede consultar reservas pero no crearlas', async () => {
  await seedActiveUser('alice');

  await assertSucceeds(getDoc(doc(dbFor('alice'), 'usernames/alice_name')));
  await assertFails(setDoc(doc(dbFor('alice'), 'usernames/new_name'), {
    uid: 'alice',
    createdAt: serverTimestamp(),
  }));
});

test('el cliente no puede saltarse la callable al crear el perfil', async () => {
  await assertFails(setDoc(doc(dbFor('alice'), 'users/alice'), {
    displayName: 'Alice',
    username: 'alice_name',
    photoUrl: '',
  }));
  await assertFails(setDoc(doc(dbFor('alice'), 'user_private/alice'), {
    email: 'alice@example.com',
    createdAt: serverTimestamp(),
    lastLogin: serverTimestamp(),
    friends: [],
  }));
});

test('un usuario no puede cambiar su username activo', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');

  await assertFails(updateDoc(doc(dbFor('alice'), 'users/alice'), {
    username: 'bob_name',
  }));
});

test('la anonimización libera la reserva en el mismo batch', async () => {
  await seedActiveUser('alice');
  const db = dbFor('alice');
  const batch = writeBatch(db);
  batch.update(doc(db, 'users/alice'), {
    displayName: 'Deleted user',
    username: 'deleted_user',
    photoUrl: '',
  });
  batch.delete(doc(db, 'usernames/alice_name'));

  await assertSucceeds(batch.commit());
});

test('una reserva no se puede liberar sin anonimizar el perfil', async () => {
  await seedActiveUser('alice');
  const db = dbFor('alice');
  const batch = writeBatch(db);
  batch.delete(doc(db, 'usernames/alice_name'));

  await assertFails(batch.commit());
});

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

test('cada usuario solo puede gestionar sus propios tokens push válidos', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');
  const tokenPath =
    'user_private/alice/push_tokens/abcdefghijklmnopqrstuvwx';
  const validToken = {
    token: 'fcm-token',
    platform: 'web',
    preferredLocale: 'es',
    updatedAt: serverTimestamp(),
  };

  await assertSucceeds(setDoc(doc(dbFor('alice'), tokenPath), validToken));
  await assertFails(setDoc(doc(dbFor('bob'), tokenPath), validToken));
  await assertFails(setDoc(
    doc(
      dbFor('alice'),
      'user_private/alice/push_tokens/zyxwvutsrqponmlkjihgfedc',
    ),
    {
      ...validToken,
      platform: 'unknown',
    },
  ));
});

test('las solicitudes solo se aceptan mediante la callable', async () => {
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
  await assertFails(updateDoc(doc(dbFor('bob'), 'friend_requests/alice_bob'), {
    status: 'accepted',
    updatedAt: serverTimestamp(),
  }));
});

test('un usuario puede consultar sus solicitudes en bloque', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');
  await seedActiveUser('carol');
  await seed('friend_requests/alice_bob', {
    senderId: 'alice',
    receiverId: 'bob',
    status: 'pending',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await seed('friend_requests/carol_alice', {
    senderId: 'carol',
    receiverId: 'alice',
    status: 'pending',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  const db = dbFor('alice');
  const requests = collection(db, 'friend_requests');

  await assertSucceeds(getDocs(query(
    requests,
    where('senderId', '==', 'alice'),
    where('receiverId', 'in', ['bob', 'carol']),
    where('status', '==', 'pending'),
  )));
  await assertSucceeds(getDocs(query(
    requests,
    where('receiverId', '==', 'alice'),
    where('senderId', 'in', ['bob', 'carol']),
    where('status', '==', 'pending'),
  )));
});

test('un usuario activo puede crear su primera solicitud y su rate limit atómicamente', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');
  const db = dbFor('alice');

  await assertSucceeds(runTransaction(db, async (tx) => {
    const limiterRef = doc(db, 'rate_limits/alice');
    await tx.get(limiterRef);
    tx.set(doc(db, 'friend_requests/alice_bob'), {
      senderId: 'alice',
      receiverId: 'bob',
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    tx.set(limiterRef, {
      lastFriendRequestAt: serverTimestamp(),
      friendRequestWindowStart: serverTimestamp(),
      friendRequestCount: 1,
    }, { merge: true });
  }));
});

test('una solicitud reinicia una ventana de rate limit caducada', async () => {
  await seedActiveUser('alice');
  await seedActiveUser('bob');
  await seed('rate_limits/alice', {
    lastFriendRequestAt: new Date('2026-01-01T00:00:00Z'),
    friendRequestWindowStart: new Date('2026-01-01T00:00:00Z'),
    friendRequestCount: 8,
    lastMessageAt: new Date('2026-01-01T00:00:00Z'),
    messageWindowStart: new Date('2026-01-01T00:00:00Z'),
    messageCount: 3,
  });
  const db = dbFor('alice');

  await assertSucceeds(runTransaction(db, async (tx) => {
    const limiterRef = doc(db, 'rate_limits/alice');
    await tx.get(limiterRef);
    tx.set(doc(db, 'friend_requests/alice_bob'), {
      senderId: 'alice',
      receiverId: 'bob',
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    tx.set(limiterRef, {
      lastFriendRequestAt: serverTimestamp(),
      friendRequestWindowStart: serverTimestamp(),
      friendRequestCount: 1,
    }, { merge: true });
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
