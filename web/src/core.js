export const R = 6378137;
export function project(p) {
  return [
    (R * p.lon * Math.PI) / 180,
    R *
      Math.log(
        Math.tan(
          Math.PI / 4 + (Math.max(-85, Math.min(85, p.lat)) * Math.PI) / 360,
        ),
      ),
  ];
}
export function unproject(x, y) {
  return {
    lat: ((2 * Math.atan(Math.exp(y / R)) - Math.PI / 2) * 180) / Math.PI,
    lon: ((x / R) * 180) / Math.PI,
  };
}
export function distance(a, b) {
  const rad = Math.PI / 180,
    dl = (b.lat - a.lat) * rad,
    dn = (b.lon - a.lon) * rad;
  return (
    6371008.8 *
    2 *
    Math.asin(
      Math.min(
        1,
        Math.sqrt(
          Math.sin(dl / 2) ** 2 +
            Math.cos(a.lat * rad) *
              Math.cos(b.lat * rad) *
              Math.sin(dn / 2) ** 2,
        ),
      ),
    )
  );
}
export function validPoint(p) {
  return (
    p &&
    Number.isFinite(p.lat) &&
    Number.isFinite(p.lon) &&
    Math.abs(p.lat) <= 85 &&
    Math.abs(p.lon) <= 180
  );
}
export function trailDistance(points) {
  return points.reduce(
    (n, p, i) => n + (i && !p.break ? distance(points[i - 1], p) : 0),
    0,
  );
}
// Independent 12 m approximation: clip a trail into cells, then retain the
// largest continuous passage's 16-direction projected diameter per new cell.
// It is invariant to collinear GPS subdivision and retracing. The directional
// diameter is a lower bound within 1 - cos(pi / 32) (<0.49%) of the true diameter;
// curved paths still use a 12 m cell approximation, not the original app's formula.
const GRID_METERS_PER_DEGREE = 111195.08;
const GRID_DIRECTIONS = Array.from({ length: 16 }, (_, i) => [
  Math.cos((i * Math.PI) / 16), Math.sin((i * Math.PI) / 16),
]);
const normalizedLongitude = (lon) => ((lon + 180) % 360 + 360) % 360 - 180;
function longitudeDelta(a, b) {
  let delta = b - a;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}
function pointCell(p) {
  const row = Math.floor((p.lat * GRID_METERS_PER_DEGREE) / 12);
  const mid = ((row + 0.5) * 12) / GRID_METERS_PER_DEGREE;
  return `${row}:${Math.floor((normalizedLongitude(p.lon) * GRID_METERS_PER_DEGREE * Math.cos(mid * Math.PI / 180)) / 12)}`;
}
function gridPieces(a, b, visit) {
  if (!validPoint(a) || !validPoint(b)) return;
  const meters = distance(a, b);
  if (!(meters > 0) || meters > 50000) return;
  const dLat = b.lat - a.lat, dLon = longitudeDelta(a.lon, b.lon);
  const y0 = a.lat * GRID_METERS_PER_DEGREE, y1 = b.lat * GRID_METERS_PER_DEGREE;
  const cuts = [0, 1];
  if (y0 !== y1) {
    for (let k = Math.floor(Math.min(y0, y1) / 12) + 1; k < Math.ceil(Math.max(y0, y1) / 12); k++) {
      const t = (k * 12 - y0) / (y1 - y0);
      if (t > 0 && t < 1) cuts.push(t);
    }
  }
  for (const seam of [-180, 180]) {
    if (dLon !== 0) { const t = (seam - a.lon) / dLon; if (t > 0 && t < 1) cuts.push(t); }
  }
  cuts.sort((x, y) => x - y);
  for (let i = 1; i < cuts.length; i++) {
    const ta = cuts[i - 1], tb = cuts[i];
    if (tb - ta < 1e-12) continue;
    const midT = (ta + tb) / 2;
    const row = Math.floor(((a.lat + dLat * midT) * GRID_METERS_PER_DEGREE) / 12);
    const midLat = ((row + 0.5) * 12) / GRID_METERS_PER_DEGREE;
    const scale = GRID_METERS_PER_DEGREE * Math.cos(midLat * Math.PI / 180);
    const rawMid = a.lon + dLon * midT;
    const shift = normalizedLongitude(rawMid) - rawMid;
    const xa = (a.lon + dLon * ta + shift) * scale;
    const xb = (a.lon + dLon * tb + shift) * scale;
    const columns = [ta, tb];
    if (xa !== xb) {
      for (let k = Math.floor(Math.min(xa, xb) / 12) + 1; k < Math.ceil(Math.max(xa, xb) / 12); k++) {
        const t = ta + ((k * 12 - xa) / (xb - xa)) * (tb - ta);
        if (t > ta && t < tb) columns.push(t);
      }
    }
    columns.sort((x, y) => x - y);
    for (let j = 1; j < columns.length; j++) {
      const start = columns[j - 1], end = columns[j];
      if (end - start < 1e-12) continue;
      const column = Math.floor(((a.lon + dLon * ((start + end) / 2) + shift) * scale) / 12);
      visit(`${row}:${column}`, start, end, scale, shift, dLat, dLon);
    }
  }
}
export function cellKeys(a, b) {
  if (!validPoint(a) || !validPoint(b) || distance(a, b) > 50000) return [];
  const keys = new Set();
  gridPieces(a, b, (key) => keys.add(key));
  if (!keys.size) keys.add(pointCell(a));
  return [...keys];
}
function localDayRange(day) {
  const start = new Date(day); start.setHours(0, 0, 0, 0);
  const end = new Date(start); end.setDate(end.getDate() + 1);
  return [start.getTime(), end.getTime()];
}
export class ExplorationAccumulator {
  constructor(visitedCells = new Set(), day = Date.now()) {
    // Treat the history Set as immutable; rebuild the accumulator when history changes.
    // Sharing it avoids copying the entire explored map for every saved walk.
    this.visited = visitedCells instanceof Set ? visitedCells : new Set(visitedCells);
    this.cells = new Set(); this.best = new Map();
    this.total = 0; this.dayTotal = 0; this.walked = 0;
    [this.dayStart, this.dayEnd] = localDayRange(day);
    this.passage = null;
  }
  resetPassage() { this.passage = null; }
  append(a, b) {
    if (!validPoint(a) || !validPoint(b) || b.break || distance(a, b) > 50000) {
      this.resetPassage(); return;
    }
    this.walked += distance(a, b);
    gridPieces(a, b, (key, start, end, scale, shift, dLat, dLon) => {
      this.cells.add(key);
      if (this.visited.has(key)) { this.resetPassage(); return; }
      const cuts = [start, end], dt = b.t - a.t;
      if (Number.isFinite(a.t) && Number.isFinite(b.t) && dt > 0) {
        for (const boundary of [this.dayStart, this.dayEnd]) {
          const t = (boundary - a.t) / dt;
          if (t > start && t < end) cuts.push(t);
        }
      }
      cuts.sort((x, y) => x - y);
      for (let i = 1; i < cuts.length; i++) {
        const ta = cuts[i - 1], tb = cuts[i];
        const p = (t) => ({ lat: a.lat + dLat * t, lon: normalizedLongitude(a.lon + dLon * t) });
        const x0 = (a.lon + dLon * ta + shift) * scale, y0 = (a.lat + dLat * ta) * GRID_METERS_PER_DEGREE;
        const x1 = (a.lon + dLon * tb + shift) * scale, y1 = (a.lat + dLat * tb) * GRID_METERS_PER_DEGREE;
        if (!this.passage || this.passage.key !== key) {
          this.passage = { key, originX: x0, originY: y0, minimum: Array(16).fill(0), maximum: Array(16).fill(0) };
        }
        const passage = this.passage;
        let diameter = 0;
        for (let direction = 0; direction < 16; direction++) {
          const [dx, dy] = GRID_DIRECTIONS[direction];
          const startProjection = (x0 - passage.originX) * dx + (y0 - passage.originY) * dy;
          const endProjection = (x1 - passage.originX) * dx + (y1 - passage.originY) * dy;
          passage.minimum[direction] = Math.min(passage.minimum[direction], startProjection, endProjection);
          passage.maximum[direction] = Math.max(passage.maximum[direction], startProjection, endProjection);
          diameter = Math.max(diameter, passage.maximum[direction] - passage.minimum[direction]);
        }
        const previous = this.best.get(key) || 0;
        if (diameter > previous) {
          this.best.set(key, diameter);
          // Geodesic clipping also prevents tiny projection round-off from
          // making exploration exceed the actual new portion walked.
          const delta = Math.min(diameter - previous, distance(p(ta), p(tb)), Math.max(0, this.walked - this.total));
          this.total += delta;
          const timestamp = dt > 0 && Number.isFinite(dt) ? a.t + dt * ((ta + tb) / 2) : b.t;
          if (timestamp >= this.dayStart && timestamp < this.dayEnd) this.dayTotal += delta;
        }
      }
    });
  }
}
export function exploration(walks, day = Date.now()) {
  const cells = new Set(), byWalk = Object.create(null);
  let total = 0, dayTotal = 0;
  const chronological = [...walks].sort((a, b) => {
    const start = (w) => Number.isFinite(w.start) ? w.start : Number.isFinite(w.points?.[0]?.t) ? w.points[0].t : 0;
    return start(a) - start(b) || (String(a.id) < String(b.id) ? -1 : String(a.id) > String(b.id) ? 1 : 0);
  });
  for (const walk of chronological) {
    const accumulator = new ExplorationAccumulator(cells, day), points = walk.points || [];
    for (let i = 1; i < points.length; i++) accumulator.append(points[i - 1], points[i]);
    byWalk[walk.id] = accumulator.total;
    total += accumulator.total; dayTotal += accumulator.dayTotal;
    for (const key of accumulator.cells) cells.add(key);
  }
  return { total, byWalk, cells, dayTotal, dayKey: new Date(day).toDateString() };
}
export function parseTrack(xml) {
  const doc = new DOMParser().parseFromString(xml, "application/xml");
  if (doc.querySelector("parsererror"))
    throw Error("XML を読み取れませんでした。");
  const points = [];
  const all = (root, name) => [...root.getElementsByTagNameNS("*", name)];
  const segs = all(doc, "trkseg"),
    tracks = all(doc, "Track"),
    routes = all(doc, "rte");
  const groups = segs.length
    ? segs
    : tracks.length
      ? tracks
      : routes.length ? routes : [doc];
  for (const g of groups) {
    let first = true;
    let nodes = all(g, "trkpt");
    if (!nodes.length) nodes = all(g, "rtept");
    if (!nodes.length) nodes = all(g, "Trackpoint");
    for (const node of nodes) {
      const get = (name) => all(node, name)[0]?.textContent,
        latitude = node.getAttribute("lat") ?? get("LatitudeDegrees"),
        longitude = node.getAttribute("lon") ?? get("LongitudeDegrees"),
        timestamp = Date.parse(get("time") || get("Time") || ""),
        p = {
          lat: Number(latitude),
          lon: Number(longitude),
          t: Number.isFinite(timestamp) ? timestamp : null,
        };
      if (
        !validPoint(p) ||
        !latitude?.trim() ||
        !longitude?.trim()
      ) {
        first = true;
        continue;
      }
      if (first && points.length) p.break = true;
      points.push(p);
      if (points.length > 100000)
        throw Error("1 ファイルは 10 万点までです。分割して取り込んでください。");
      first = false;
    }
  }
  if (points.length < 2)
    throw Error("位置情報が 2 点以上ある GPX / TCX を選んでください。");
  // Interpolate missing times between known samples. Untimed files receive a
  // one-second cadence ending at import time, rather than zero-duration walks.
  const importedAt = Date.now();
  for (let i = 0; i < points.length; i++) {
    if (points[i].t !== null) continue;
    const start = i;
    while (i < points.length && points[i].t === null) i++;
    const previous = points[start - 1]?.t,
      next = points[i]?.t,
      count = i - start,
      step = previous !== undefined && next !== undefined && next >= previous
        ? (next - previous) / (count + 1)
        : 1000,
      anchor = previous ?? (next !== undefined ? next - (count + 1) * step : importedAt - count * step);
    for (let j = start; j < i; j++) points[j].t = anchor + (j - start + 1) * step;
    i--;
  }
  return points;
}
export function gpx(walk) {
  const esc = (s) =>
    String(s).replace(
      /[<>&"']/g,
      (c) =>
        ({
          "<": "&lt;",
          ">": "&gt;",
          "&": "&amp;",
          '"': "&quot;",
          "'": "&apos;",
        })[c],
    );
  return `<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="PlainWalk Web" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>${esc(walk.name)}</name><trkseg>${walk.points.map((p, i) => `${p.break && i ? "</trkseg><trkseg>" : ""}<trkpt lat="${p.lat}" lon="${p.lon}"><time>${new Date(p.t).toISOString()}</time></trkpt>`).join("")}</trkseg></trk></gpx>`;
}
export function validateBackup(v) {
  if (
    v?.version !== 1 ||
    !Array.isArray(v.walks) ||
    !Array.isArray(v.spots) ||
    !Array.isArray(v.flags)
  )
    throw Error("このアプリのバックアップではありません。");
  if (
    v.walks.length > 10000 ||
    v.spots.length > 10000 ||
    v.flags.length > 10000
  )
    throw Error("データが大きすぎます。");
  let count = 0;
  const validTime = (t) => Number.isFinite(t) && Math.abs(t) <= 8640000000000000;
  const uniqueIDs = (items) => {
    const ids = new Set();
    for (const item of items) {
      if (!item || typeof item.id !== "string" || !item.id.length || item.id.length > 200 || ids.has(item.id))
        throw Error("記録の ID が不正、または重複しています。");
      ids.add(item.id);
    }
  };
  for (const items of [v.walks, v.spots, v.flags]) uniqueIDs(items);
  for (const w of v.walks) {
    if (
      typeof w.id !== "string" ||
      !Array.isArray(w.points) ||
      !validTime(w.start) ||
      !validTime(w.end) ||
      w.end < w.start ||
      (w.duration !== undefined && (!Number.isFinite(w.duration) || w.duration < 0))
    )
      throw Error("記録の形式が不正です。");
    count += w.points.length;
    if (
      count > 300000 ||
      w.points.some((p) => !validPoint(p) || !validTime(p.t))
    )
      throw Error("位置データが不正、または大きすぎます。");
    if (
      w.points.some(
        (p, i) => i && !p.break && distance(w.points[i - 1], p) > 50000,
      )
    )
      throw Error("記録内の位置情報に大きな飛びがあります。");
  }
  for (const p of [...v.spots, ...v.flags])
    if (
      typeof p.id !== "string" ||
      !validPoint(p) ||
      (p.video &&
        (!/^data:video\/(mp4|webm|quicktime)(;codecs=[^;,]+)?;base64,/.test(
          p.video,
        ) ||
          p.video.length > 21000000)) ||
      (p.photo &&
        (!/^data:image\/(jpeg|png|webp);base64,/.test(p.photo) ||
          p.photo.length > 5000000))
    )
      throw Error("ピンの形式が不正です。");
  if (Object.keys(v.notes || {}).length + Object.keys(v.notePages || {}).length > 20000)
    throw Error("ノートのページ数が大きすぎます。");
  return {
    ...v,
    version: 1,
    walks: v.walks.map((w) => ({
      ...w,
      name: String(w.name || "さんぽ"),
      note: String(w.note || ""),
      stickers: String(w.stickers || ""),
    })),
    spots: v.spots,
    flags: v.flags,
    notes: validateNotes(v.notes),
    notePages: validateNotePages(v.notePages),
    ...validateCollections(v),
  };
}

export function validateNotes(notes) {
  if (notes == null) return {};
  if (
    typeof notes !== "object" ||
    Array.isArray(notes) ||
    Object.keys(notes).length > 20000
  )
    throw Error("ノートの形式が不正です。");
  const result = {};
  for (const [day, note] of Object.entries(notes)) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) ||
      new Date(`${day}T00:00:00Z`).toJSON()?.slice(0, 10) !== day ||
      !note || typeof note !== "object" || Array.isArray(note))
      throw Error("ノートの日付が不正です。");
    if (note.pageDeleted !== undefined && typeof note.pageDeleted !== "boolean")
      throw Error("ノートの削除状態が不正です。");
    if (note._plainwalkImportSourceID !== undefined && (typeof note._plainwalkImportSourceID !== "string" || !note._plainwalkImportSourceID.length || note._plainwalkImportSourceID.length > 200))
      throw Error("ノートの取込元 ID が不正です。");
    const text = String(note.text || ""),
      stickers = String(note.stickers || "");
    if (text.length > 5000 || stickers.length > 1000)
      throw Error("ノートの文字数が大きすぎます。");
    const layout = note.layout || [];
    if (!Array.isArray(layout) || layout.length > 20)
      throw Error("ノートの素材が多すぎます。");
    for (const item of layout) {
      if (
        !item ||
        typeof item.id !== "string" ||
        !["photo", "sticker", "route", "emoji"].includes(item.type) ||
        !Number.isFinite(item.x) ||
        !Number.isFinite(item.y) ||
        !Number.isFinite(item.width) ||
        item.width < 10 ||
        item.width > 1000 ||
        !Number.isFinite(item.ratio) ||
        item.ratio < 0.01 ||
        item.ratio > 100 ||
        (item.rotation !== undefined && !Number.isFinite(item.rotation))
      )
        throw Error("ノートの配置が不正です。");
      if (
        item.type !== "emoji" &&
        (typeof item.src !== "string" ||
          !/^data:image\/(jpeg|png|webp);base64,/.test(item.src) ||
          item.src.length > 5000000)
      )
        throw Error("ノートの画像が不正です。");
    }
    result[day] = {
      ...note,
      day,
      text,
      stickers,
      layout,
      paper: ["plain", "grid", "lined", "kraft"].includes(note.paper)
        ? note.paper
        : "plain",
      font: ["serif", "sans", "mono"].includes(note.font) ? note.font : "serif",
    };
    if (note.steps !== undefined) {
      if (
        !Number.isInteger(note.steps) ||
        note.steps < 0 ||
        note.steps > 100000
      )
        throw Error("歩数の形式が不正です。");
      result[day].steps = note.steps;
    }
  }
  return result;
}

export function validateNotePages(pages) {
  if (pages == null) return {};
  if (typeof pages !== "object" || Array.isArray(pages) || Object.keys(pages).length > 20000)
    throw Error("ノートのページ形式が不正です。");
  const result = {};
  for (const [id, page] of Object.entries(pages)) {
    if (!id.length || id.length > 200 || id.startsWith("legacy:") || ["__proto__", "prototype", "constructor"].includes(id) || !page || typeof page !== "object" || Array.isArray(page) || page.id !== id || typeof page.day !== "string" || page.pageDeleted !== undefined || page.steps !== undefined)
      throw Error("ノートのページ ID または形式が不正です。");
    const value = validateNotes({ [page.day]: page })[page.day];
    if (page.created !== undefined && (!Number.isFinite(page.created) || Math.abs(page.created) > 8640000000000000))
      throw Error("ノートの作成日時が不正です。");
    result[id] = { ...value, id };
  }
  return result;
}

export function validateCollections(v) {
  const list = (key) => {
    const items = v[key] ?? [];
    if (!Array.isArray(items) || items.length > 1000)
      throw Error("コレクションが大きすぎます。");
    const ids = new Set();
    for (const item of items) {
      if (!item || typeof item.id !== "string" || !item.id.length || ids.has(item.id))
        throw Error("コレクションの ID が不正、または重複しています。");
      ids.add(item.id);
    }
    return items;
  };
  const points = (ps) => {
    if (
      !Array.isArray(ps) ||
      ps.length > 300000 ||
      ps.some((p) => !validPoint(p))
    )
      throw Error("コレクションの位置情報が不正です。");
    return ps.map((p) => ({
      lat: p.lat,
      lon: p.lon,
      ...(p.break ? { break: true } : {}),
      ...(p.done ? { done: true } : {}),
    }));
  };
  const entry = (x) => {
    if (
      !x ||
      typeof x.id !== "string" ||
      x.id.length > 200 ||
      typeof x.name !== "string" ||
      x.name.length > 200
    )
      throw Error("コレクションの形式が不正です。");
    return { id: x.id, name: x.name };
  };
  let totalPoints = 0;
  const boundedPoints = (ps) => {
    const clean = points(ps);
    totalPoints += clean.length;
    if (totalPoints > 300000)
      throw Error("コレクションの位置情報が多すぎます。");
    return clean;
  };
  return {
    bookmarks: list("bookmarks").map((p) => {
      const clean = entry(p);
      if (!validPoint(p)) throw Error("しおりの位置が不正です。");
      return { ...clean, lat: p.lat, lon: p.lon };
    }),
    doodles: list("doodles").map((d) => {
      const clean = entry(d);
      if (!Number.isFinite(d.created))
        throw Error("らくがきの日付が不正です。");
      return { ...clean, created: d.created, points: boundedPoints(d.points) };
    }),
    sharedMaps: list("sharedMaps").map((m) => {
      const clean = entry(m);
      if (!Array.isArray(m.walks) || m.walks.length > 10000)
        throw Error("共有の道が多すぎます。");
      return {
        ...clean,
        walks: m.walks.map((w) => {
          if (typeof w.id !== "string") throw Error("共有の道が不正です。");
          return {
            id: w.id,
            points: boundedPoints(w.points).map(({ lat, lon, break: gap }) => ({
              lat,
              lon,
              ...(gap ? { break: true } : {}),
            })),
          };
        }),
      };
    }),
  };
}
