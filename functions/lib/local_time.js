"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.utcOffsetsAtLocalTime = utcOffsetsAtLocalTime;
exports.localDay = localDay;
const dayMs = 24 * 60 * 60 * 1000;
/**
 * UTC offsets, in minutes, where the local time is [localMinutes] during the
 * [slotMinutes]-long scheduled slot that contains [scheduledAt].
 */
function utcOffsetsAtLocalTime(scheduledAt, localMinutes, slotMinutes) {
    const utcMinutes = scheduledAt.getUTCHours() * 60
        + Math.floor(scheduledAt.getUTCMinutes() / slotMinutes) * slotMinutes;
    const offset = localMinutes - utcMinutes;
    // Offsets span UTC-12:00 to UTC+14:00, so a slot can match two zones on
    // opposite sides of the date line.
    return [offset, offset - 24 * 60, offset + 24 * 60]
        .filter((value) => value >= -720 && value <= 840);
}
function localDay(millis, utcOffsetMinutes) {
    return Math.floor((millis + utcOffsetMinutes * 60 * 1000) / dayMs);
}
//# sourceMappingURL=local_time.js.map