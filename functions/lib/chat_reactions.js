"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.reactionEmojis = void 0;
exports.scrubUserReactions = scrubUserReactions;
// Must match the emojis allowed by firestore.rules and the client picker.
exports.reactionEmojis = ['❤️', '🔥', '👏', '😍', '💀'];
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
//# sourceMappingURL=chat_reactions.js.map