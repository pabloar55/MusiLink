"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processAccountDeletion = exports.requestAccountDeletion = void 0;
exports.scrubUserReactions = scrubUserReactions;
const node_crypto_1 = require("node:crypto");
const auth_1 = require("firebase-admin/auth");
const functions_1 = require("firebase-admin/functions");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const v2_1 = require("firebase-functions/v2");
const https_1 = require("firebase-functions/v2/https");
const tasks_1 = require("firebase-functions/v2/tasks");
const callableRegion = 'europe-southwest1';
// Cloud Tasks is not available in Madrid. Keep the client-facing callable
// close to Firestore and run only the durable queue worker in Belgium.
const taskRegion = 'europe-west1';
const deletionJobsCollection = 'account_deletions';
const deletionWorkerName = 'processAccountDeletion';
const batchSize = 300;
const chatsPerSlice = 40;
const recentAuthenticationSeconds = 5 * 60;
const deletedProfile = {
    displayName: 'Deleted user',
    username: 'deleted_user',
    photoUrl: '',
};
const reactionEmojis = ['❤️', '🔥', '👏', '😍', '💀'];
const phases = [
    'freeze',
    'push_tokens',
    'friend_references',
    'blocked_references',
    'sent_friend_requests',
    'received_friend_requests',
    'sent_notification_limits',
    'received_notification_limits',
    'sent_messages',
    'reactions_heart',
    'reactions_fire',
    'reactions_clap',
    'reactions_love',
    'reactions_skull',
    'chats',
    'owned_recommendations',
    'referencing_recommendations',
    'recommendation_index',
    'recommendation_profile',
    'username_reservations',
    'rate_limits',
    'storage',
    'private_profile',
    'public_profile',
    'verify',
    'auth',
];
function deletionJobRef(uid) {
    return (0, firestore_1.getFirestore)().collection(deletionJobsCollection).doc(uid);
}
function isDeletionPhase(value) {
    return typeof value === 'string' && phases.includes(value);
}
function readJob(data) {
    if (!data || !isDeletionPhase(data.phase))
        return undefined;
    const status = data.status;
    const version = data.version;
    if (status !== 'requested' &&
        status !== 'running' &&
        status !== 'retry_wait' &&
        status !== 'completed') {
        return undefined;
    }
    if (typeof version !== 'number' || !Number.isInteger(version) || version < 1) {
        return undefined;
    }
    return {
        status,
        phase: data.phase,
        version,
        ...(typeof data.cursor === 'string' ? { cursor: data.cursor } : {}),
    };
}
function publicJobData(data) {
    return {
        status: data.status,
        phase: data.phase,
        progress: data.progress ?? {},
    };
}
function taskId(uid, version) {
    const digest = (0, node_crypto_1.createHash)('sha256').update(uid).digest('hex').slice(0, 32);
    return `delete-${digest}-${version}`;
}
function taskAlreadyExists(error) {
    if (!error || typeof error !== 'object')
        return false;
    const code = 'code' in error ? String(error.code) : '';
    return code === 'functions/task-already-exists' || code === '6' || code === 'ALREADY_EXISTS';
}
async function enqueueDeletionTask(uid, version) {
    const queue = (0, functions_1.getFunctions)().taskQueue(`locations/${taskRegion}/functions/${deletionWorkerName}`);
    try {
        await queue.enqueue({ uid, version }, { id: taskId(uid, version), dispatchDeadlineSeconds: 600 });
    }
    catch (error) {
        if (taskAlreadyExists(error))
            return;
        throw error;
    }
}
function recentAuthentication(authTime) {
    if (typeof authTime !== 'number')
        return false;
    return Math.floor(Date.now() / 1000) - authTime <= recentAuthenticationSeconds;
}
exports.requestAccountDeletion = (0, https_1.onCall)({ region: callableRegion }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    }
    const ref = deletionJobRef(uid);
    const authIsRecent = recentAuthentication(request.auth?.token.auth_time);
    const result = await (0, firestore_1.getFirestore)().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        const existing = readJob(snapshot.data());
        if (existing?.status === 'completed') {
            return { job: existing, data: snapshot.data() };
        }
        if (!snapshot.exists) {
            if (!authIsRecent) {
                throw new https_1.HttpsError('failed-precondition', 'Recent authentication is required before deleting the account.');
            }
            const job = {
                status: 'requested',
                phase: 'freeze',
                version: 1,
            };
            const data = {
                ...job,
                requestedAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                progress: {},
            };
            transaction.create(ref, data);
            return { job, data };
        }
        if (!existing) {
            throw new https_1.HttpsError('internal', 'The deletion job is invalid.');
        }
        // A manual retry gets a fresh task id. Any older automatic retry becomes
        // harmless because workers only process the exact stored version.
        if (existing.status === 'retry_wait') {
            const job = { ...existing, status: 'requested', version: existing.version + 1 };
            transaction.update(ref, {
                status: job.status,
                version: job.version,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                lastErrorCode: firestore_1.FieldValue.delete(),
            });
            return { job, data: { ...snapshot.data(), ...job } };
        }
        return { job: existing, data: snapshot.data() };
    });
    if (result.job.status !== 'completed') {
        await enqueueDeletionTask(uid, result.job.version);
    }
    return publicJobData(result.data);
});
async function commitDeletes(query) {
    const snapshot = await query.limit(batchSize).get();
    if (snapshot.empty)
        return 0;
    const batch = (0, firestore_1.getFirestore)().batch();
    snapshot.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();
    return snapshot.size;
}
async function removeArrayReference(collection, field, uid) {
    const snapshot = await (0, firestore_1.getFirestore)()
        .collection(collection)
        .where(field, 'array-contains', uid)
        .limit(batchSize)
        .get();
    if (snapshot.empty)
        return 0;
    const batch = (0, firestore_1.getFirestore)().batch();
    snapshot.docs.forEach((document) => {
        batch.update(document.ref, { [field]: firestore_1.FieldValue.arrayRemove(uid) });
    });
    await batch.commit();
    return snapshot.size;
}
function messageSummary(data) {
    if (data.type === 'track') {
        const title = data.trackData?.title;
        if (typeof title === 'string' && title.length > 0)
            return `🎵 ${title}`;
    }
    return typeof data.text === 'string' ? data.text : '';
}
function scrubUserReactions(reactions, uid) {
    if (!reactions || typeof reactions !== 'object' || Array.isArray(reactions))
        return {};
    const scrubbed = {};
    for (const [emoji, users] of Object.entries(reactions)) {
        if (!Array.isArray(users))
            continue;
        const remaining = users.filter((value) => typeof value === 'string' && value !== uid);
        if (remaining.length > 0)
            scrubbed[emoji] = remaining;
    }
    return scrubbed;
}
async function scrubReactionBatch(uid, emoji) {
    const snapshot = await (0, firestore_1.getFirestore)()
        .collectionGroup('messages')
        .where(new firestore_1.FieldPath('reactions', emoji), 'array-contains', uid)
        .limit(batchSize)
        .get();
    if (snapshot.empty)
        return 0;
    const batch = (0, firestore_1.getFirestore)().batch();
    snapshot.docs.forEach((document) => {
        batch.update(document.ref, {
            reactions: scrubUserReactions(document.data().reactions, uid),
        });
    });
    await batch.commit();
    return snapshot.size;
}
async function freezeAccount(uid) {
    const db = (0, firestore_1.getFirestore)();
    const publicRef = db.doc(`users/${uid}`);
    const privateRef = db.doc(`user_private/${uid}`);
    await db.runTransaction(async (transaction) => {
        const [publicProfile, privateProfile] = await Promise.all([
            transaction.get(publicRef),
            transaction.get(privateRef),
        ]);
        const username = publicProfile.data()?.username;
        let reservation;
        let reservationRef;
        if (typeof username === 'string' && username !== '' && username !== 'deleted_user') {
            reservationRef = db.doc(`usernames/${username.trim().toLowerCase()}`);
            reservation = await transaction.get(reservationRef);
        }
        // Replace, rather than merge, so future or legacy personal fields cannot
        // survive because they were missing from a hard-coded deletion list.
        transaction.set(publicRef, deletedProfile);
        if (privateProfile.exists) {
            transaction.update(privateRef, { friends: [], blockedUsers: [] });
        }
        if (reservationRef && reservation?.data()?.uid === uid) {
            transaction.delete(reservationRef);
        }
    });
}
async function processChats(uid, cursor) {
    let query = (0, firestore_1.getFirestore)()
        .collection('chats')
        .where('participants', 'array-contains', uid)
        .orderBy(firestore_1.FieldPath.documentId())
        .limit(chatsPerSlice);
    if (cursor)
        query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty)
        return { nextPhase: 'owned_recommendations' };
    const latestMessages = await Promise.all(snapshot.docs.map(async (chat) => {
        const latest = await chat.ref
            .collection('messages')
            .orderBy('timestamp', 'desc')
            .limit(1)
            .get();
        return { chat, latest: latest.docs[0] };
    }));
    const batch = (0, firestore_1.getFirestore)().batch();
    for (const { chat, latest } of latestMessages) {
        if (!latest) {
            batch.delete(chat.ref);
            continue;
        }
        batch.update(chat.ref, 'lastMessage', messageSummary(latest.data()), 'lastMessageTime', latest.data().timestamp ?? firestore_1.FieldValue.serverTimestamp(), new firestore_1.FieldPath('unreadCounts', uid), firestore_1.FieldValue.delete(), new firestore_1.FieldPath('deletedAt', uid), firestore_1.FieldValue.delete());
    }
    await batch.commit();
    return {
        nextPhase: snapshot.size < chatsPerSlice ? 'owned_recommendations' : 'chats',
        processed: snapshot.size,
        ...(snapshot.size < chatsPerSlice ? {} : { cursor: snapshot.docs.at(-1).id }),
    };
}
async function verifyCleanup(uid) {
    const db = (0, firestore_1.getFirestore)();
    const checks = [
        {
            phase: 'push_tokens',
            query: db.collection(`user_private/${uid}/push_tokens`),
        },
        {
            phase: 'friend_references',
            query: db.collection('user_private').where('friends', 'array-contains', uid),
        },
        {
            phase: 'blocked_references',
            query: db.collection('user_private').where('blockedUsers', 'array-contains', uid),
        },
        {
            phase: 'sent_friend_requests',
            query: db.collection('friend_requests').where('senderId', '==', uid),
        },
        {
            phase: 'received_friend_requests',
            query: db.collection('friend_requests').where('receiverId', '==', uid),
        },
        {
            phase: 'sent_notification_limits',
            query: db.collection('friend_request_notification_limits').where('senderId', '==', uid),
        },
        {
            phase: 'received_notification_limits',
            query: db.collection('friend_request_notification_limits').where('receiverId', '==', uid),
        },
        {
            phase: 'sent_messages',
            query: db.collectionGroup('messages').where('senderId', '==', uid),
        },
        {
            phase: 'owned_recommendations',
            query: db.collection(`users/${uid}/recommendations`),
        },
        {
            phase: 'referencing_recommendations',
            query: db.collectionGroup('recommendations').where('userId', '==', uid),
        },
        {
            phase: 'recommendation_index',
            query: db.collectionGroup('users').where('uid', '==', uid),
        },
        {
            phase: 'username_reservations',
            query: db.collection('usernames').where('uid', '==', uid),
        },
    ];
    for (const check of checks) {
        if (!(await check.query.limit(1).get()).empty)
            return check.phase;
    }
    if ((await db.doc(`music_recommendation_profiles/${uid}`).get()).exists) {
        return 'recommendation_profile';
    }
    for (let index = 0; index < reactionEmojis.length; index += 1) {
        const emoji = reactionEmojis[index];
        const snapshot = await db
            .collectionGroup('messages')
            .where(new firestore_1.FieldPath('reactions', emoji), 'array-contains', uid)
            .limit(1)
            .get();
        if (!snapshot.empty)
            return phases[9 + index];
    }
    if ((await db.doc(`rate_limits/${uid}`).get()).exists)
        return 'rate_limits';
    if ((await db.doc(`user_private/${uid}`).get()).exists)
        return 'private_profile';
    const publicProfile = await db.doc(`users/${uid}`).get();
    const publicData = publicProfile.data();
    if (!publicProfile.exists ||
        !publicData ||
        Object.keys(publicData).length !== Object.keys(deletedProfile).length ||
        publicData.displayName !== deletedProfile.displayName ||
        publicData.username !== deletedProfile.username ||
        publicData.photoUrl !== deletedProfile.photoUrl) {
        return 'public_profile';
    }
    const [fileExists] = await (0, storage_1.getStorage)().bucket().file(`profile_photos/${uid}`).exists();
    if (fileExists)
        return 'storage';
    return undefined;
}
async function processPhase(uid, job) {
    const db = (0, firestore_1.getFirestore)();
    switch (job.phase) {
        case 'freeze':
            await freezeAccount(uid);
            return { nextPhase: 'push_tokens' };
        case 'push_tokens': {
            const count = await commitDeletes(db.collection(`user_private/${uid}/push_tokens`));
            return { nextPhase: count === batchSize ? 'push_tokens' : 'friend_references', processed: count };
        }
        case 'friend_references': {
            const count = await removeArrayReference('user_private', 'friends', uid);
            return { nextPhase: count === batchSize ? 'friend_references' : 'blocked_references', processed: count };
        }
        case 'blocked_references': {
            const count = await removeArrayReference('user_private', 'blockedUsers', uid);
            return { nextPhase: count === batchSize ? 'blocked_references' : 'sent_friend_requests', processed: count };
        }
        case 'sent_friend_requests': {
            const count = await commitDeletes(db.collection('friend_requests').where('senderId', '==', uid));
            return { nextPhase: count === batchSize ? 'sent_friend_requests' : 'received_friend_requests', processed: count };
        }
        case 'received_friend_requests': {
            const count = await commitDeletes(db.collection('friend_requests').where('receiverId', '==', uid));
            return { nextPhase: count === batchSize ? 'received_friend_requests' : 'sent_notification_limits', processed: count };
        }
        case 'sent_notification_limits': {
            const count = await commitDeletes(db.collection('friend_request_notification_limits').where('senderId', '==', uid));
            return { nextPhase: count === batchSize ? 'sent_notification_limits' : 'received_notification_limits', processed: count };
        }
        case 'received_notification_limits': {
            const count = await commitDeletes(db.collection('friend_request_notification_limits').where('receiverId', '==', uid));
            return { nextPhase: count === batchSize ? 'received_notification_limits' : 'sent_messages', processed: count };
        }
        case 'sent_messages': {
            const count = await commitDeletes(db.collectionGroup('messages').where('senderId', '==', uid));
            return { nextPhase: count === batchSize ? 'sent_messages' : 'reactions_heart', processed: count };
        }
        case 'reactions_heart':
        case 'reactions_fire':
        case 'reactions_clap':
        case 'reactions_love':
        case 'reactions_skull': {
            const reactionIndex = phases.indexOf(job.phase) - phases.indexOf('reactions_heart');
            const count = await scrubReactionBatch(uid, reactionEmojis[reactionIndex]);
            const nextPhase = count === batchSize
                ? job.phase
                : phases[phases.indexOf(job.phase) + 1];
            return { nextPhase, processed: count };
        }
        case 'chats':
            return processChats(uid, job.cursor);
        case 'owned_recommendations': {
            const count = await commitDeletes(db.collection(`users/${uid}/recommendations`));
            return { nextPhase: count === batchSize ? 'owned_recommendations' : 'referencing_recommendations', processed: count };
        }
        case 'referencing_recommendations': {
            const count = await commitDeletes(db.collectionGroup('recommendations').where('userId', '==', uid));
            return { nextPhase: count === batchSize ? 'referencing_recommendations' : 'recommendation_index', processed: count };
        }
        case 'recommendation_index': {
            const count = await commitDeletes(db.collectionGroup('users').where('uid', '==', uid));
            return { nextPhase: count === batchSize ? 'recommendation_index' : 'recommendation_profile', processed: count };
        }
        case 'recommendation_profile':
            await db.doc(`music_recommendation_profiles/${uid}`).delete();
            return { nextPhase: 'username_reservations', processed: 1 };
        case 'username_reservations': {
            const count = await commitDeletes(db.collection('usernames').where('uid', '==', uid));
            return { nextPhase: count === batchSize ? 'username_reservations' : 'rate_limits', processed: count };
        }
        case 'rate_limits':
            await db.doc(`rate_limits/${uid}`).delete();
            return { nextPhase: 'storage' };
        case 'storage':
            await (0, storage_1.getStorage)().bucket().file(`profile_photos/${uid}`).delete({ ignoreNotFound: true });
            return { nextPhase: 'private_profile' };
        case 'private_profile':
            // Firestore does not cascade subcollections when deleting a parent.
            // recursiveDelete also covers future private subcollections unknown to
            // this version of the worker.
            await db.recursiveDelete(db.doc(`user_private/${uid}`));
            return { nextPhase: 'public_profile' };
        case 'public_profile':
            // Recommendation triggers spawned by the initial anonymization may have
            // written generatedAt/count metadata. Replace the document once more
            // after recommendation cleanup so the retained tombstone is minimal.
            {
                const publicRef = db.doc(`users/${uid}`);
                const subcollections = await publicRef.listCollections();
                await Promise.all(subcollections.map((collection) => db.recursiveDelete(collection)));
                await publicRef.set(deletedProfile);
            }
            return { nextPhase: 'verify' };
        case 'verify': {
            const residualPhase = await verifyCleanup(uid);
            return { nextPhase: residualPhase ?? 'auth' };
        }
        case 'auth':
            try {
                await (0, auth_1.getAuth)().deleteUser(uid);
            }
            catch (error) {
                const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
                if (code !== 'auth/user-not-found')
                    throw error;
            }
            return { nextPhase: 'auth', completed: true };
    }
}
async function advanceJob(uid, expectedVersion, currentPhase, result) {
    const ref = deletionJobRef(uid);
    return (0, firestore_1.getFirestore)().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        const job = readJob(snapshot.data());
        if (!job || job.version !== expectedVersion || job.status === 'completed')
            return undefined;
        if (result.completed) {
            transaction.update(ref, {
                status: 'completed',
                phase: 'auth',
                completedAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                cursor: firestore_1.FieldValue.delete(),
                lastErrorCode: firestore_1.FieldValue.delete(),
            });
            return undefined;
        }
        const nextVersion = expectedVersion + 1;
        transaction.update(ref, {
            status: 'running',
            phase: result.nextPhase,
            version: nextVersion,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            lastErrorCode: firestore_1.FieldValue.delete(),
            cursor: result.cursor ?? firestore_1.FieldValue.delete(),
            ...(result.processed === undefined
                ? {}
                : { [`progress.${currentPhase}`]: firestore_1.FieldValue.increment(result.processed) }),
        });
        return nextVersion;
    });
}
async function recordRetryableError(uid, version, error) {
    const ref = deletionJobRef(uid);
    await (0, firestore_1.getFirestore)().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        const job = readJob(snapshot.data());
        if (!job || job.version !== version || job.status === 'completed')
            return;
        const rawCode = error && typeof error === 'object' && 'code' in error
            ? String(error.code)
            : 'internal';
        transaction.update(ref, {
            status: 'retry_wait',
            lastErrorCode: rawCode.slice(0, 100),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            attempts: firestore_1.FieldValue.increment(1),
        });
    });
}
exports.processAccountDeletion = (0, tasks_1.onTaskDispatched)({
    region: taskRegion,
    timeoutSeconds: 600,
    memory: '512MiB',
    retryConfig: {
        maxAttempts: 30,
        maxRetrySeconds: 7 * 24 * 60 * 60,
        minBackoffSeconds: 10,
        maxBackoffSeconds: 60 * 60,
        maxDoublings: 8,
    },
    rateLimits: {
        maxConcurrentDispatches: 10,
        maxDispatchesPerSecond: 10,
    },
}, async (request) => {
    const uid = request.data?.uid;
    const version = request.data?.version;
    if (typeof uid !== 'string' || uid === '' || typeof version !== 'number') {
        v2_1.logger.error('processAccountDeletion: invalid task payload');
        return;
    }
    const snapshot = await deletionJobRef(uid).get();
    const job = readJob(snapshot.data());
    if (!job || job.status === 'completed')
        return;
    if (job.version !== version) {
        // Recovers the narrow case where state advanced but enqueueing the next
        // continuation failed before the previous task returned.
        await enqueueDeletionTask(uid, job.version);
        return;
    }
    await deletionJobRef(uid).update({
        status: 'running',
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    try {
        const result = await processPhase(uid, job);
        const nextVersion = await advanceJob(uid, version, job.phase, result);
        if (nextVersion !== undefined)
            await enqueueDeletionTask(uid, nextVersion);
    }
    catch (error) {
        v2_1.logger.error('processAccountDeletion: retryable phase failure', {
            uid,
            phase: job.phase,
            version,
            error,
        });
        await recordRetryableError(uid, version, error);
        throw error;
    }
});
//# sourceMappingURL=account_deletion.js.map