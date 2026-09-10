"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.acknowledgeChatDelivery = void 0;
exports.deliveryTokenHash = deliveryTokenHash;
exports.createDeliveryToken = createDeliveryToken;
exports.confirmPushDelivery = confirmPushDelivery;
const node_crypto_1 = require("node:crypto");
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const firebase_1 = require("./firebase");
function deliveryTokenHash(token) {
    return (0, node_crypto_1.createHash)('sha256').update(token).digest('hex');
}
/// Solo el hash queda en el documento legible por los participantes.
async function createDeliveryToken(messageRef) {
    const token = (0, node_crypto_1.randomBytes)(32).toString('hex');
    await messageRef.update({
        deliveryTokenHashes: firestore_1.FieldValue.arrayUnion(deliveryTokenHash(token)),
    });
    return token;
}
async function confirmPushDelivery(body) {
    if (!body || typeof body !== 'object')
        return false;
    const { chatId, messageId, deliveryToken } = body;
    if (typeof chatId !== 'string' || !chatId || chatId.length > 300 || chatId.includes('/') ||
        typeof messageId !== 'string' || !messageId || messageId.length > 128 || messageId.includes('/') ||
        typeof deliveryToken !== 'string' || !/^[a-f0-9]{64}$/.test(deliveryToken))
        return false;
    const ref = firebase_1.db.doc(`chats/${chatId}/messages/${messageId}`);
    return firebase_1.db.runTransaction(async (tx) => {
        const message = (await tx.get(ref)).data();
        if (!Array.isArray(message?.deliveryTokenHashes) ||
            !message.deliveryTokenHashes.includes(deliveryTokenHash(deliveryToken)))
            return false;
        if (message.delivered !== true)
            tx.update(ref, { delivered: true });
        return true;
    });
}
// La capacidad aleatoria autoriza únicamente la entrega de ese mensaje.
// No concede lectura, envío ni acceso a la cuenta. App Check/reCAPTCHA no
// puede ejecutarse en un service worker sin una ventana abierta.
exports.acknowledgeChatDelivery = (0, https_1.onRequest)({ region: 'europe-southwest1', maxInstances: 10 }, async (request, response) => {
    if (request.method !== 'POST') {
        response.status(405).end();
        return;
    }
    const accepted = await confirmPushDelivery(request.body);
    response.status(accepted ? 204 : 403).end();
});
//# sourceMappingURL=chat_delivery.js.map