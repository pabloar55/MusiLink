"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.stringList = stringList;
exports.timestampMillis = timestampMillis;
exports.timestampValue = timestampValue;
exports.chatParticipants = chatParticipants;
const firestore_1 = require("firebase-admin/firestore");
function stringList(value) {
    if (!Array.isArray(value))
        return [];
    return value
        .filter((item) => typeof item === 'string')
        .map((item) => item.trim())
        .filter((item) => item.length > 0);
}
function timestampMillis(value) {
    return value instanceof firestore_1.Timestamp ? value.toMillis() : undefined;
}
function timestampValue(value) {
    return value instanceof firestore_1.Timestamp ? value : undefined;
}
function chatParticipants(data) {
    if (!Array.isArray(data?.participants))
        return [];
    return data.participants.filter((value) => typeof value === 'string');
}
//# sourceMappingURL=firestore_values.js.map