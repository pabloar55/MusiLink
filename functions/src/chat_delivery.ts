import { createHash, randomBytes } from 'node:crypto';
import { DocumentReference, FieldValue } from 'firebase-admin/firestore';
import { onRequest } from 'firebase-functions/v2/https';

import { db } from './firebase';

export function deliveryTokenHash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/// Solo el hash queda en el documento legible por los participantes.
export async function createDeliveryToken(messageRef: DocumentReference): Promise<string> {
  const token = randomBytes(32).toString('hex');
  await messageRef.update({
    deliveryTokenHashes: FieldValue.arrayUnion(deliveryTokenHash(token)),
  });
  return token;
}

export async function confirmPushDelivery(body: unknown): Promise<boolean> {
  if (!body || typeof body !== 'object') return false;
  const { chatId, messageId, deliveryToken } = body as Record<string, unknown>;
  if (typeof chatId !== 'string' || !chatId || chatId.length > 300 || chatId.includes('/') ||
      typeof messageId !== 'string' || !messageId || messageId.length > 128 || messageId.includes('/') ||
      typeof deliveryToken !== 'string' || !/^[a-f0-9]{64}$/.test(deliveryToken)) return false;
  const ref = db.doc(`chats/${chatId}/messages/${messageId}`);
  return db.runTransaction(async (tx) => {
    const message = (await tx.get(ref)).data();
    if (!Array.isArray(message?.deliveryTokenHashes) ||
        !message.deliveryTokenHashes.includes(deliveryTokenHash(deliveryToken))) return false;
    if (message.delivered !== true) tx.update(ref, { delivered: true });
    return true;
  });
}

// La capacidad aleatoria autoriza únicamente la entrega de ese mensaje.
// No concede lectura, envío ni acceso a la cuenta. App Check/reCAPTCHA no
// puede ejecutarse en un service worker sin una ventana abierta.
export const acknowledgeChatDelivery = onRequest(
  { region: 'europe-southwest1', maxInstances: 10 },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).end();
      return;
    }
    const accepted = await confirmPushDelivery(request.body);
    response.status(accepted ? 204 : 403).end();
  },
);
