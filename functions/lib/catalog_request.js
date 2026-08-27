"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.catalogSearchMaxQueryBytes = exports.catalogSearchMaxLimit = void 0;
exports.isRecord = isRecord;
exports.parseSpotifySearchRequest = parseSpotifySearchRequest;
exports.parseSpotifyArtistSearchRequest = parseSpotifyArtistSearchRequest;
exports.parseLastFmSearchRequest = parseLastFmSearchRequest;
const https_1 = require("firebase-functions/v2/https");
exports.catalogSearchMaxLimit = 10;
exports.catalogSearchMaxQueryBytes = 200;
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function invalidArgument(message) {
    throw new https_1.HttpsError('invalid-argument', message);
}
function parseSearchValue(data, field) {
    const rawValue = data[field];
    if (typeof rawValue !== 'string') {
        return invalidArgument(`${field} must be a string`);
    }
    const value = rawValue.trim();
    if (!value)
        return invalidArgument(`${field} must not be empty`);
    if (Buffer.byteLength(value, 'utf8') > exports.catalogSearchMaxQueryBytes) {
        return invalidArgument(`${field} is too long`);
    }
    if (/[\u0000-\u001f\u007f]/u.test(value)) {
        return invalidArgument(`${field} contains unsupported control characters`);
    }
    return value;
}
function parseLimit(data, defaultLimit) {
    const rawLimit = data.limit;
    if (rawLimit === undefined)
        return defaultLimit;
    if (typeof rawLimit !== 'number' ||
        !Number.isInteger(rawLimit) ||
        rawLimit < 1 ||
        rawLimit > exports.catalogSearchMaxLimit) {
        return invalidArgument(`limit must be an integer between 1 and ${exports.catalogSearchMaxLimit}`);
    }
    return rawLimit;
}
function parseRequest(data, field, defaultLimit) {
    if (!isRecord(data))
        return invalidArgument('Request data must be an object');
    return {
        value: parseSearchValue(data, field),
        limit: parseLimit(data, defaultLimit),
    };
}
function parseSpotifySearchRequest(data) {
    return parseRequest(data, 'query', exports.catalogSearchMaxLimit);
}
function parseSpotifyArtistSearchRequest(data) {
    const request = parseSpotifySearchRequest(data);
    const record = data;
    const rawMarket = record.market;
    if (rawMarket === undefined)
        return { ...request, market: 'ES' };
    if (typeof rawMarket !== 'string')
        return invalidArgument('market must be a string');
    const market = rawMarket.trim().toUpperCase();
    if (!/^[A-Z]{2}$/.test(market)) {
        return invalidArgument('market must be a two-letter country code');
    }
    return { ...request, market };
}
function parseLastFmSearchRequest(data) {
    return parseRequest(data, 'artistName', exports.catalogSearchMaxLimit);
}
//# sourceMappingURL=catalog_request.js.map