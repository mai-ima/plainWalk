// Synthetic metadata only. Browser tests insert this APP1 segment into a real
// canvas-generated JPEG; no third-party photos or GPS locations are bundled.
function jpeg(options = {}) {
  const little = options.little ?? true;
  const buffer = new Uint8Array(4096), view = new DataView(buffer.buffer);
  buffer.set(little ? [73, 73] : [77, 77]);
  const u16 = (p, n) => view.setUint16(p, n, little), u32 = (p, n) => view.setUint32(p, n, little);
  u16(2, 42); u32(4, 8);
  let cursor = 256;
  const text = (value) => Uint8Array.from([...value].map((c) => c.charCodeAt(0)).concat(0));
  const entry = (tag, type, value) => {
    let data, count;
    if (type === 2) { data = text(value); count = data.length; }
    else if (type === 3 || type === 4) {
      data = new Uint8Array(type === 3 ? 2 : 4); count = 1;
      const v = new DataView(data.buffer);
      if (type === 3) v.setUint16(0, value, little); else v.setUint32(0, value, little);
    } else {
      count = value.length; data = new Uint8Array(count * 8); const v = new DataView(data.buffer);
      value.forEach((n, i) => { const pair = Array.isArray(n) ? n : [n, 1]; v.setUint32(i * 8, pair[0], little); v.setUint32(i * 8 + 4, pair[1], little); });
    }
    return { tag, type, count, data };
  };
  function ifd(at, entries) {
    u16(at, entries.length);
    entries.forEach((e, i) => {
      const row = at + 2 + i * 12; u16(row, e.tag); u16(row + 2, e.type); u32(row + 4, e.count);
      if (e.data.length <= 4) buffer.set(e.data, row + 8);
      else { u32(row + 8, cursor); buffer.set(e.data, cursor); cursor += e.data.length; }
    });
  }
  ifd(8, [entry(0x112, 3, options.orientation ?? 6), entry(0x8769, 4, 64), entry(0x8825, 4, options.gps === false ? 0 : 128)]);
  ifd(64, [
    ...(options.date === null ? [] : [entry(0x9003, 2, options.date ?? "2026:10:29 12:00:00")]),
    ...(options.offset === null ? [] : [entry(0x9011, 2, options.offset ?? "+09:00")]),
    ...(options.sub === null ? [] : [entry(0x9291, 2, options.sub ?? "123")]),
  ]);
  ifd(128, [
    entry(1, 2, options.latRef ?? "N"), entry(2, 5, options.lat ?? [35, 40, 30]),
    entry(3, 2, options.lonRef ?? "E"), entry(4, 5, options.lon ?? [139, 45, 0]),
    entry(7, 5, options.gpsTime ?? [3, 0, 0]), entry(29, 2, options.gpsDate ?? "2026:10:29"),
  ]);
  const tiff = buffer.slice(0, cursor), length = 2 + 6 + tiff.length;
  return Uint8Array.from([255, 216, 255, 225, length >> 8, length & 255, 69, 120, 105, 102, 0, 0, ...tiff, 255, 217]);
}


function injectExif(bytes, options) {
  const data = Buffer.from(bytes);
  if (data[0] !== 255 || data[1] !== 216) throw Error("Expected a real JPEG");
  const metadata = jpeg(options);
  return Buffer.concat([data.subarray(0, 2), metadata.subarray(2, metadata.length - 2), data.subarray(2)]);
}
module.exports = { jpeg, injectExif };
