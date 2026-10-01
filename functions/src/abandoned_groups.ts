import { Firestore, Transaction } from 'firebase-admin/firestore';

import { chatParticipants } from './firestore_values';

/**
 * Whether nobody in `ids` can use a group any more: every account has been
 * anonymized by the deletion job, which keeps its tombstone in `participants`.
 * A missing profile is not proof of deletion and keeps the group. Reading the
 * profiles in the caller's transaction keeps the answer consistent with a
 * deletion or a departure that commits at the same time.
 */
export async function everyAccountDeleted(
  firestore: Firestore, tx: Transaction, ids: string[],
): Promise<boolean> {
  const profiles = await Promise.all(ids.map((uid) => tx.get(firestore.doc(`users/${uid}`))));
  return profiles.every((profile) => profile.data()?.username === 'deleted_user');
}

/**
 * Deletes a group whose members are all deleted accounts and returns whether
 * the group is gone, including when it had already been deleted. Its messages
 * and photo are removed by `onGroupChatDeleted`, which Firestore retries.
 */
export async function deleteGroupIfAbandoned(firestore: Firestore, chatId: string): Promise<boolean> {
  const chatRef = firestore.doc(`chats/${chatId}`);
  return firestore.runTransaction(async (tx) => {
    const chat = await tx.get(chatRef);
    if (!chat.exists) return true;
    if (chat.data()?.type !== 'group') return false;
    if (!await everyAccountDeleted(firestore, tx, chatParticipants(chat.data()))) return false;
    tx.delete(chatRef);
    return true;
  });
}
