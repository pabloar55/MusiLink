// Must match the emojis allowed by firestore.rules and the client picker.
export const reactionEmojis = ['❤️', '🔥', '👏', '😍', '💀'] as const;

export function scrubUserReactions(
  reactions: unknown,
  uid: string,
): Record<string, string[]> {
  if (!reactions || typeof reactions !== 'object' || Array.isArray(reactions)) return {};
  const scrubbed: Record<string, string[]> = {};
  for (const [emoji, users] of Object.entries(reactions)) {
    if (!Array.isArray(users)) continue;
    const remaining = users.filter(
      (value): value is string => typeof value === 'string' && value !== uid,
    );
    if (remaining.length > 0) scrubbed[emoji] = remaining;
  }
  return scrubbed;
}
