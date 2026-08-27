import { HttpsError } from 'firebase-functions/v2/https';

export const catalogSearchMaxLimit = 10;
export const catalogSearchMaxQueryBytes = 200;

export interface CatalogSearchRequest {
  value: string;
  limit: number;
}

export interface SpotifyArtistSearchRequest extends CatalogSearchRequest {
  market: string;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function invalidArgument(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

function parseSearchValue(data: Record<string, unknown>, field: string): string {
  const rawValue = data[field];
  if (typeof rawValue !== 'string') {
    return invalidArgument(`${field} must be a string`);
  }

  const value = rawValue.trim();
  if (!value) return invalidArgument(`${field} must not be empty`);
  if (Buffer.byteLength(value, 'utf8') > catalogSearchMaxQueryBytes) {
    return invalidArgument(`${field} is too long`);
  }
  if (/[\u0000-\u001f\u007f]/u.test(value)) {
    return invalidArgument(`${field} contains unsupported control characters`);
  }
  return value;
}

function parseLimit(data: Record<string, unknown>, defaultLimit: number): number {
  const rawLimit = data.limit;
  if (rawLimit === undefined) return defaultLimit;
  if (
    typeof rawLimit !== 'number' ||
    !Number.isInteger(rawLimit) ||
    rawLimit < 1 ||
    rawLimit > catalogSearchMaxLimit
  ) {
    return invalidArgument(`limit must be an integer between 1 and ${catalogSearchMaxLimit}`);
  }
  return rawLimit;
}

function parseRequest(
  data: unknown,
  field: string,
  defaultLimit: number,
): CatalogSearchRequest {
  if (!isRecord(data)) return invalidArgument('Request data must be an object');
  return {
    value: parseSearchValue(data, field),
    limit: parseLimit(data, defaultLimit),
  };
}

export function parseSpotifySearchRequest(data: unknown): CatalogSearchRequest {
  return parseRequest(data, 'query', catalogSearchMaxLimit);
}

export function parseSpotifyArtistSearchRequest(data: unknown): SpotifyArtistSearchRequest {
  const request = parseSpotifySearchRequest(data);
  const record = data as Record<string, unknown>;
  const rawMarket = record.market;
  if (rawMarket === undefined) return { ...request, market: 'ES' };
  if (typeof rawMarket !== 'string') return invalidArgument('market must be a string');

  const market = rawMarket.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(market)) {
    return invalidArgument('market must be a two-letter country code');
  }
  return { ...request, market };
}

export function parseLastFmSearchRequest(data: unknown): CatalogSearchRequest {
  return parseRequest(data, 'artistName', catalogSearchMaxLimit);
}
