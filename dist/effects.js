export function parseCube(text) {
  let size = 0,
    min = [0, 0, 0],
    max = [1, 1, 1];
  const colors = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.split("#")[0].trim();
    if (!line || line.startsWith("TITLE")) continue;
    const p = line.split(/\s+/);
    if (p[0] === "LUT_3D_SIZE") {
      size = Number(p[1]);
      if (!Number.isInteger(size) || size < 2 || size > 33)
        throw Error("LUT のサイズは 2〜33 に対応しています。");
    } else if (p[0] === "DOMAIN_MIN") min = p.slice(1).map(Number);
    else if (p[0] === "DOMAIN_MAX") max = p.slice(1).map(Number);
    else if (p.length === 3 && p.every((v) => Number.isFinite(Number(v))))
      colors.push(p.map(Number));
    else throw Error("3D .cube 形式の LUT を選んでください。");
  }
  if (
    !size ||
    colors.length !== size ** 3 ||
    min.length !== 3 ||
    max.length !== 3 ||
    min.some(
      (v, i) => !Number.isFinite(v) || !Number.isFinite(max[i]) || max[i] <= v,
    )
  )
    throw Error("LUT のデータが不正です。");
  return { size, min, max, colors };
}
export function applyEffect(image, filter, lut) {
  const bytes = image.data;
  for (let i = 0; i < bytes.length; i += 4) {
    let r = bytes[i],
      g = bytes[i + 1],
      b = bytes[i + 2];
    if (filter === "custom" && lut) {
      const s = lut.size,
        coords = [r, g, b].map(
          (v, k) =>
            Math.max(
              0,
              Math.min(1, (v / 255 - lut.min[k]) / (lut.max[k] - lut.min[k])),
            ) *
            (s - 1),
        ),
        lo = coords.map(Math.floor),
        hi = coords.map((v) => Math.min(s - 1, Math.ceil(v))),
        frac = coords.map((v, k) => v - lo[k]),
        out = [0, 0, 0];
      for (let z = 0; z < 2; z++)
        for (let y = 0; y < 2; y++)
          for (let x = 0; x < 2; x++) {
            const index =
                (x ? hi[0] : lo[0]) +
                s * (y ? hi[1] : lo[1]) +
                s * s * (z ? hi[2] : lo[2]),
              weight =
                (x ? frac[0] : 1 - frac[0]) *
                (y ? frac[1] : 1 - frac[1]) *
                (z ? frac[2] : 1 - frac[2]);
            for (let k = 0; k < 3; k++) out[k] += lut.colors[index][k] * weight;
          }
      [r, g, b] = out.map((v) => Math.round(Math.max(0, Math.min(1, v)) * 255));
    } else if (filter === "grayscale(1)") {
      const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      r = g = b = y;
    } else if (filter === "sepia(.65) saturate(.7)") {
      const sr = 0.393 * r + 0.769 * g + 0.189 * b,
        sg = 0.349 * r + 0.686 * g + 0.168 * b,
        sb = 0.272 * r + 0.534 * g + 0.131 * b;
      r = r * 0.35 + sr * 0.65;
      g = g * 0.35 + sg * 0.65;
      b = b * 0.35 + sb * 0.65;
      const gray = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      r = gray + (r - gray) * 0.7;
      g = gray + (g - gray) * 0.7;
      b = gray + (b - gray) * 0.7;
    } else if (filter === "saturate(.65) contrast(.9)") {
      const gray = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      r = (gray + (r - gray) * 0.65 - 128) * 0.9 + 128;
      g = (gray + (g - gray) * 0.65 - 128) * 0.9 + 128;
      b = (gray + (b - gray) * 0.65 - 128) * 0.9 + 128;
    }
    bytes[i] = r;
    bytes[i + 1] = g;
    bytes[i + 2] = b;
  }
  return image;
}
