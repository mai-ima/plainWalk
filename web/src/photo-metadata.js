import { distance, validPoint } from "./core.js";

// Read only the small, bounded EXIF fields needed for an explicitly selected
// JPEG. Compression must happen after this call; browser canvas drops EXIF.
export function readPhotoMetadata(input) {
  const bytes = input instanceof Uint8Array ? input
    : input instanceof ArrayBuffer ? new Uint8Array(input) : null;
  const result = { format: "unsupported", capturedAt: null, localDateTime: null,
    timeSource: null, point: null, orientation: null };
  if (!bytes || bytes.length > 40_000_000 || bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216) return result;
  result.format = "jpeg";
  for (let at = 2, segments = 0; at + 1 < bytes.length && segments++ < 256;) {
    if (bytes[at++] !== 255) return result;
    while (at < bytes.length && bytes[at] === 255) at++;
    if (at >= bytes.length) return result;
    const marker = bytes[at++];
    if (marker === 218 || marker === 217) return result;
    if (marker === 1 || (marker >= 208 && marker <= 215)) continue;
    if (marker === 0 || at + 2 > bytes.length) return result;
    const length = bytes[at] * 256 + bytes[at + 1], end = at + length;
    if (length < 2 || end > bytes.length) return result;
    if (marker === 225 && length >= 16 && bytes[at + 2] === 69 && bytes[at + 3] === 120 && bytes[at + 4] === 105 && bytes[at + 5] === 102 && bytes[at + 6] === 0 && bytes[at + 7] === 0) {
      try { return { ...result, ...readTIFF(bytes.subarray(at + 8, end)) }; }
      catch { return result; } // A malformed metadata block must not break photo import.
    }
    at = end;
  }
  return result;
}

function readTIFF(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const little = bytes[0] === 73 && bytes[1] === 73;
  if (!little && !(bytes[0] === 77 && bytes[1] === 77)) throw Error("TIFF byte order");
  const range = (at, size) => {
    if (!Number.isSafeInteger(at) || !Number.isSafeInteger(size) || at < 0 || size < 0 || at + size > bytes.length) throw Error("TIFF bounds");
  };
  const u16 = (at) => { range(at, 2); return view.getUint16(at, little); };
  const u32 = (at) => { range(at, 4); return view.getUint32(at, little); };
  if (u16(2) !== 42) throw Error("TIFF marker");
  const visited = new Set();
  function directory(at) {
    if (visited.has(at) || at < 8) throw Error("TIFF cycle");
    visited.add(at);
    const count = u16(at);
    if (count > 256) throw Error("TIFF directory size");
    range(at + 2, count * 12 + 4);
    const entries = new Map();
    for (let i = 0; i < count; i++) {
      const row = at + 2 + i * 12, tag = u16(row), type = u16(row + 2), count = u32(row + 4);
      const width = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8 }[type];
      if (!width || count > 65_535) continue;
      const size = count * width, position = size <= 4 ? row + 8 : u32(row + 8);
      // Unknown malformed fields are ignored; recognized fields remain independent.
      if (position + size > bytes.length || entries.has(tag)) continue;
      entries.set(tag, { type, count, position });
    }
    return entries;
  }
  const ascii = (entry) => {
    if (!entry || entry.type !== 2 || entry.count < 1 || entry.count > 128) return null;
    let text = "";
    for (let i = 0; i < entry.count; i++) {
      const value = bytes[entry.position + i];
      if (!value) break;
      if (value < 32 || value > 126) return null;
      text += String.fromCharCode(value);
    }
    return text.trim();
  };
  const pointer = (entry) => entry?.type === 4 && entry.count === 1 ? u32(entry.position) : null;
  const rationals = (entry, count) => {
    if (entry?.type !== 5 || entry.count !== count) return null;
    const values = [];
    for (let i = 0; i < count; i++) {
      const denominator = u32(entry.position + i * 8 + 4);
      if (!denominator) return null;
      values.push(u32(entry.position + i * 8) / denominator);
    }
    return values;
  };
  const main = directory(u32(4));
  const orientation = main.get(0x112);
  let orientationValue = orientation?.type === 3 && orientation.count === 1 ? u16(orientation.position) : null;
  if (!(orientationValue >= 1 && orientationValue <= 8)) orientationValue = null;
  let capturedAt = null, localDateTime = null, timeSource = null, point = null;
  const exifOffset = pointer(main.get(0x8769));
  if (exifOffset !== null) {
    try {
      const exif = directory(exifOffset), local = ascii(exif.get(0x9003));
      const parts = local?.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/);
      if (parts) {
        const stamp = calendarTime(parts.slice(1).map(Number));
        if (stamp !== null) {
          localDateTime = local;
          const offset = ascii(exif.get(0x9011))?.match(/^([+-])(\d{2}):(\d{2})$/);
          if (offset && +offset[2] <= 14 && +offset[3] < 60 && (+offset[2] < 14 || +offset[3] === 0)) {
            const sub = ascii(exif.get(0x9291));
            const ms = sub && /^\d{1,9}$/.test(sub) ? +sub.slice(0, 3).padEnd(3, "0") : 0;
            capturedAt = stamp + ms - (offset[1] === "+" ? 1 : -1) * (+offset[2] * 60 + +offset[3]) * 60_000;
            timeSource = "exif-offset";
          }
        }
      }
    } catch { /* Preserve usable GPS even when the EXIF directory is damaged. */ }
  }
  const gpsOffset = pointer(main.get(0x8825));
  if (gpsOffset !== null) {
    try {
      const gps = directory(gpsOffset), lat = rationals(gps.get(2), 3), lon = rationals(gps.get(4), 3);
      const latRef = ascii(gps.get(1)), lonRef = ascii(gps.get(3));
      if (lat && lon && /^[NS]$/.test(latRef || "") && /^[EW]$/.test(lonRef || "") &&
          [lat, lon].every((parts) => parts[1] < 60 && parts[2] < 60)) {
        const candidate = {
          lat: (lat[0] + lat[1] / 60 + lat[2] / 3600) * (latRef === "S" ? -1 : 1),
          lon: (lon[0] + lon[1] / 60 + lon[2] / 3600) * (lonRef === "W" ? -1 : 1),
        };
        if (validPoint(candidate)) point = candidate;
      }
      if (capturedAt === null) {
        const date = ascii(gps.get(0x1d))?.match(/^(\d{4}):(\d{2}):(\d{2})$/), time = rationals(gps.get(7), 3);
        if (date && time && Number.isInteger(time[0]) && Number.isInteger(time[1]) && time[2] < 60) {
          const seconds = Math.floor(time[2]);
          const stamp = calendarTime([...date.slice(1).map(Number), time[0], time[1], seconds]);
          if (stamp !== null) { capturedAt = stamp + Math.round((time[2] - seconds) * 1000); timeSource = "gps-utc"; }
        }
      }
    } catch { /* No inferred location from broken GPS metadata. */ }
  }
  return { capturedAt, localDateTime, timeSource, point, orientation: orientationValue };
}

function calendarTime([year, month, day, hour, minute, second]) {
  if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) return null;
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day); date.setUTCHours(hour, minute, second, 0);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() + 1 !== month || date.getUTCDate() !== day) return null;
  return date.getTime();
}

// Metadata GPS is direct evidence. Route placement requires an absolute capture
// time and a short connected interval; local-only EXIF time is never guessed.
export function locatePhotoOnWalks(metadata, walks = [], options = {}) {
  const time = typeof metadata?.capturedAt === "number" && Number.isFinite(metadata.capturedAt) && Math.abs(metadata.capturedAt) <= 8.64e15 ? metadata.capturedAt : null;
  if (validPoint(metadata?.point)) return { point: { lat: metadata.point.lat, lon: metadata.point.lon }, capturedAt: time, source: "photo-gps" };
  if (time === null || !Array.isArray(walks) || walks.length > 10_000) return null;
  const all = options.activeWalk ? [...walks, options.activeWalk] : walks;
  let budget = 300_000, candidate = null, ambiguous = false;
  const maxGap = Number.isFinite(options.maxGapMs) ? Math.min(120_000, Math.max(1, options.maxGapMs)) : 120_000;
  const validTime = (p) => typeof p?.t === "number" && Number.isFinite(p.t) && Math.abs(p.t) <= 8.64e15;
  const validFix = (p) => validPoint(p) && (p.accuracy == null ||
    (typeof p.accuracy === "number" && Number.isFinite(p.accuracy) && p.accuracy >= 0 && p.accuracy <= 100));
  function accept(point, id) {
    if (!candidate) candidate = { point, capturedAt: time, source: "walk-time", ...(typeof id === "string" ? { walkID: id } : {}) };
    else {
      if (distance(candidate.point, point) > 1) ambiguous = true;
      if (candidate.walkID !== id) delete candidate.walkID;
    }
  }
  for (const walk of all) {
    if (!Array.isArray(walk?.points)) continue;
    budget -= walk.points.length;
    if (budget < 0) return null;
    // A corrupt timeline must not become a credible route by skipping/reordering points.
    if (!walk.points.every(validTime) || walk.points.some((p, i) => i > 0 && !(walk.points[i - 1].t < p.t))) continue;
    for (let i = 0; i < walk.points.length; i++) {
      const b = walk.points[i];
      if (!validFix(b)) continue;
      if (b.t === time) accept({ lat: b.lat, lon: b.lon }, walk.id);
      if (!i || b.break || b.gap) continue;
      const a = walk.points[i - 1];
      if (!validFix(a) || !(a.t < time && time < b.t)) continue;
      const interval = b.t - a.t, length = distance(a, b);
      if (interval <= 0 || interval > maxGap || length > 1000 || length / (interval / 1000) > 45) continue;
      const fraction = (time - a.t) / interval;
      const delta = ((b.lon - a.lon + 540) % 360) - 180;
      let longitude = a.lon + delta * fraction;
      if (longitude > 180) longitude -= 360;
      if (longitude < -180) longitude += 360;
      accept({ lat: a.lat + (b.lat - a.lat) * fraction, lon: longitude }, walk.id);
    }
  }
  return ambiguous ? null : candidate;
}
