import { distance } from "./core.js";
function rings(geometry) {
  if (geometry?.type === "Polygon") return [geometry.coordinates];
  if (geometry?.type === "MultiPolygon") return geometry.coordinates;
  return [];
}
function inRing(lon, lat, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const a = ring[i],
      b = ring[j],
      cross = (lon - a[0]) * (b[1] - a[1]) - (lat - a[1]) * (b[0] - a[0]);
    if (
      Math.abs(cross) < 1e-10 &&
      lon >= Math.min(a[0], b[0]) - 1e-10 &&
      lon <= Math.max(a[0], b[0]) + 1e-10 &&
      lat >= Math.min(a[1], b[1]) - 1e-10 &&
      lat <= Math.max(a[1], b[1]) + 1e-10
    )
      return true;
    if (
      a[1] > lat !== b[1] > lat &&
      lon < ((b[0] - a[0]) * (lat - a[1])) / (b[1] - a[1]) + a[0]
    )
      inside = !inside;
  }
  return inside;
}
export function contains(feature, point) {
  return rings(feature.geometry).some(
    (poly) =>
      poly[0]?.length >= 4 &&
      inRing(point.lon, point.lat, poly[0]) &&
      !poly.slice(1).some((hole) => inRing(point.lon, point.lat, hole)),
  );
}
export function bounds(feature) {
  let minx = Infinity,
    miny = Infinity,
    maxx = -Infinity,
    maxy = -Infinity;
  for (const poly of rings(feature.geometry))
    for (const ring of poly)
      for (const [x, y] of ring) {
        minx = Math.min(minx, x);
        miny = Math.min(miny, y);
        maxx = Math.max(maxx, x);
        maxy = Math.max(maxy, y);
      }
  return [minx, miny, maxx, maxy];
}
export function makeIndex(collection) {
  const buckets = new Map(),
    features = collection.features;
  features.forEach((f, i) => {
    f.bbox = bounds(f);
    const [a, b, c, d] = f.bbox;
    if (![a, b, c, d].every(Number.isFinite)) return;
    const x0 = Math.floor(a * 5),
      x1 = Math.floor(c * 5),
      y0 = Math.floor(b * 5),
      y1 = Math.floor(d * 5);
    if ((x1 - x0 + 1) * (y1 - y0 + 1) > 20000)
      throw Error("区域の範囲が大きすぎます。");
    for (let x = x0; x <= x1; x++)
      for (let y = y0; y <= y1; y++) {
        const key = x + ":" + y;
        if (!buckets.has(key)) buckets.set(key, []);
        buckets.get(key).push(i);
      }
  });
  return {
    collection,
    at(point) {
      const list =
        buckets.get(
          Math.floor(point.lon * 5) + ":" + Math.floor(point.lat * 5),
        ) || [];
      return list
        .map((i) => features[i])
        .filter((f) => {
          const [a, b, c, d] = f.bbox;
          return (
            point.lon >= a &&
            point.lon <= c &&
            point.lat >= b &&
            point.lat <= d &&
            contains(f, point)
          );
        });
    },
  };
}
export async function collectAreas(walks, index, onProgress = () => {}) {
  const stats = new Map();
  let operations = 0;
  for (let wi = 0; wi < walks.length; wi++) {
    const walk = walks[wi],
      walkAreas = new Set();
    function add(p, meters = 0) {
      for (const f of index.at(p)) {
        const id = f.properties.id;
        let s = stats.get(id);
        if (!s) {
          s = {
            id,
            name: f.properties.name,
            parent: f.properties.parent,
            walks: 0,
            distance: 0,
            first: walk.start,
            last: walk.start,
            cells: new Set(),
          };
          stats.set(id, s);
        }
        const centerLat = (((f.bbox[1] + f.bbox[3]) / 2) * Math.PI) / 180,
          mx = p.lon * 111195.08 * Math.cos(centerLat),
          my = p.lat * 111195.08;
        s.cells.add(Math.floor(mx / 500) + ":" + Math.floor(my / 500));
        walkAreas.add(id);
        s.distance += meters;
        s.first = Math.min(s.first, walk.start);
        s.last = Math.max(s.last, walk.start);
      }
    }
    for (let i = 0; i < walk.points.length; i++) {
      const p = walk.points[i];
      add(p);
      if (i && !p.break) {
        const before = walk.points[i - 1],
          meters = distance(before, p),
          count = Math.max(1, Math.ceil(meters / 25));
        if (count > 10000) continue;
        for (let n = 0; n < count; n++) {
          const t = (n + 0.5) / count;
          add(
            {
              lat: before.lat + (p.lat - before.lat) * t,
              lon: before.lon + (p.lon - before.lon) * t,
            },
            meters / count,
          );
        }
      }
      if (++operations % 1000 === 0) {
        onProgress(wi / walks.length);
        await new Promise((r) => setTimeout(r, 0));
      }
    }
    for (const id of walkAreas) stats.get(id).walks++;
    onProgress((wi + 1) / walks.length);
  }
  return [...stats.values()]
    .map((s) => ({ ...s, cells: [...s.cells] }))
    .sort((a, b) => b.distance - a.distance);
}
export function areaSVG(feature, size = 100, cells = null, walks = null) {
  const [a, b, c, d] = feature.bbox || bounds(feature),
    lat = (((b + d) / 2) * Math.PI) / 180,
    cos = Math.cos(lat),
    width = (c - a) * cos,
    height = d - b,
    scale = Math.max(width / (size - 14), height / (size - 14), 1e-8);
  let path = "";
  for (const poly of rings(feature.geometry))
    for (const ring of poly)
      path +=
        ring
          .map(
            ([x, y], i) =>
              `${i ? "L" : "M"}${(((x - (a + c) / 2) * cos) / scale + size / 2).toFixed(2)} ${(size / 2 - (y - (b + d) / 2) / scale).toFixed(2)}`,
          )
          .join(" ") + "Z ";
  const opening = `<svg viewBox="0 0 ${size} ${size}" aria-hidden="true">`;
  if (!cells)
    return (
      opening +
      `<path d="${path}" fill="currentColor" fill-rule="evenodd" stroke="currentColor" stroke-width=".4"/></svg>`
    );
  const clip =
      "boundary-" +
      String(feature.properties.id).replace(/[^a-zA-Z0-9_-]/g, "") +
      (walks ? "-trails" : "-cells"),
    metersScale = scale * 111195.08,
    cx = ((a + c) / 2) * 111195.08 * cos,
    cy = ((b + d) / 2) * 111195.08;
  const squares = cells
    .map((key) => {
      const [x, y] = key.split(":").map(Number);
      return `<rect x="${((x * 500 - cx) / metersScale + size / 2).toFixed(2)}" y="${(size / 2 - ((y + 1) * 500 - cy) / metersScale).toFixed(2)}" width="${(500 / metersScale + 0.1).toFixed(2)}" height="${(500 / metersScale + 0.1).toFixed(2)}"/>`;
    })
    .join("");
  const pointXY = (p) =>
    `${(((p.lon - (a + c) / 2) * cos) / scale + size / 2).toFixed(2)} ${(size / 2 - (p.lat - (b + d) / 2) / scale).toFixed(2)}`;
  let trail = "";
  if (walks)
    for (const walk of walks)
      for (let i = 1; i < walk.points.length; i++) {
        const before = walk.points[i - 1],
          point = walk.points[i];
        if (
          point.break ||
          Math.max(before.lon, point.lon) < a ||
          Math.min(before.lon, point.lon) > c ||
          Math.max(before.lat, point.lat) < b ||
          Math.min(before.lat, point.lat) > d
        )
          continue;
        trail += `M${pointXY(before)}L${pointXY(point)} `;
      }
  const routes = trail
    ? `<path data-area-trails="true" d="${trail}" clip-path="url(#${clip})" fill="none" stroke="var(--ink)" stroke-width=".7" stroke-linecap="round" stroke-linejoin="round"/>`
    : "";
  return (
    opening +
    `<defs><clipPath id="${clip}"><path d="${path}" fill-rule="evenodd" clip-rule="evenodd"/></clipPath></defs><path d="${path}" fill="none" fill-rule="evenodd" stroke="var(--muted)" stroke-opacity=".8" stroke-width=".65" stroke-dasharray=".1 1.2" stroke-linecap="round"/><g clip-path="url(#${clip})" fill="currentColor" fill-opacity=".2" stroke="none">${squares}</g>${routes}</svg>`
  );
}
