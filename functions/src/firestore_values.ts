import { DocumentData, Timestamp } from 'firebase-admin/firestore';

export function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

export function timestampMillis(value: unknown): number | undefined {
  return value instanceof Timestamp ? value.toMillis() : undefined;
}

export function timestampValue(value: unknown): Timestamp | undefined {
  return value instanceof Timestamp ? value : undefined;
}

export function chatParticipants(data: DocumentData | undefined): string[] {
  if (!Array.isArray(data?.participants)) return [];
  return data.participants.filter(
    (value: unknown): value is string => typeof value === 'string',
  );
}
