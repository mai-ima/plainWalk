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
// 12 m cells in a local latitude-scaled metric grid; crossings are sampled every 3 m.
export function cellKeys(a, b) {
  if (!validPoint(a) || !validPoint(b)) return [];
  const d = distance(a, b),
    n = Math.max(1, Math.ceil(d / 3)),
    keys = new Set();
  // A location jump is a gap, not a road to sample millions of times.
  if (d > 50000) return [];
  for (let i = 0; i <= n; i++) {
    const t = i / n,
      p = {
        lat: a.lat + (b.lat - a.lat) * t,
        lon: a.lon + (b.lon - a.lon) * t,
      };
    const y = Math.floor((p.lat * 111195.08) / 12),
      mid = ((y + 0.5) * 12) / 111195.08;
    keys.add(
      `${y}:${Math.floor((p.lon * 111195.08 * Math.cos((mid * Math.PI) / 180)) / 12)}`,
    );
  }
  return [...keys];
}
export function exploration(walks) {
  const cells = new Set(),
    byWalk = Object.create(null);
  for (const walk of walks) {
    let n = 0;
    const ps = walk.points || [];
    for (let i = 1; i < ps.length; i++) {
      const a = ps[i - 1],
        b = ps[i];
      if (b.break) continue;
      const ks = cellKeys(a, b);
      if (!ks.length) continue;
      const fresh = ks.filter((k) => !cells.has(k)).length;
      n += (distance(a, b) * fresh) / ks.length;
      ks.forEach((k) => cells.add(k));
    }
    byWalk[walk.id] = n;
  }
  return {
    total: Object.values(byWalk).reduce((a, b) => a + b, 0),
    byWalk,
    cells,
  };
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
