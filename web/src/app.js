import { createDiagnostics } from "./diagnostics.js";
import { createDeveloperUI } from "./developer-ui.js";
import { createCollections } from "./collections.js";
import { formatDistance, distanceUnit as getDistanceUnit } from "./units.js";
import { layersHTML, settingsHTML } from "./reference-ui.js";
import { companionSVG } from "./companion.js";
import { drawNotebook, hitItem, loadImage, lassoCutout } from "./notebook.js";
import { makeIndex, collectAreas, areaSVG } from "./areas.js";
import { readVideo, openCamera, captureTwoSeconds } from "./media.js";
import { parseCube, applyEffect } from "./effects.js";
import { native, nativeCall, nativeDownload, onNative } from "./native.js";
import {
  project,
  unproject,
  distance,
  validPoint,
  trailDistance,
  exploration,
  parseTrack,
  gpx,
  validateBackup,
  cellKeys,
} from "./core.js";
const $ = (s) => document.querySelector(s),
  $$ = (s) => [...document.querySelectorAll(s)],
  esc = (s) =>
    String(s ?? "").replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
const icons = {
  home: '<path d="m3 11 9-8 9 8M5 10v11h14V10M9 21v-7h6v7"/>',
  building: '<path d="M4 3h12v18H4zM16 9h5v12M8 7h4M8 11h4M8 15h4"/>',
  exchange: '<path d="M4 7h15m-5-5 5 5-5 5M20 17H5m5-5-5 5 5 5"/>',
  plus: '<circle cx="12" cy="12" r="10"/><path d="M12 7v10M7 12h10"/>',
  target:
    '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
  back: '<path d="m15 4-8 8 8 8" stroke-width="2"/>',
  pen: '<path d="m4 20 2-6L17 3l4 4L10 18zM15 5l4 4M4 20l6-2"/>',
  sparkles:
    '<path d="m12 4 2.2 6.2L20 12l-5.8 2.2L12 21l-2.2-6.8L4 12l5.8-1.8zM5 2v4M3 4h4M20 3v5M17.5 5.5h5"/>',
  menu: '<path d="M5 7h14M5 12h14M5 17h14"/>',
  map: '<path d="m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2zM9 3v16M15 5v16"/>',
  records:
    '<rect x="5" y="4" width="14" height="17" rx="3"/><path d="M9 3h6v4H9zM9 12h6M9 16h4"/>',
  profile:
    '<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
  camera:
    '<path d="M3 8h4l2-3h6l2 3h3a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-9a2 2 0 0 1 1-2z"/><circle cx="12" cy="13" r="4"/>',
  locate:
    '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v5M12 17v5M2 12h5M17 12h5"/>',
  layers: '<path d="m12 3 9 5-9 5-9-5zM3 12l9 5 9-5M3 16l9 5 9-5"/>',
  foot: '<g fill="currentColor" stroke="none"><path d="M7.2 10c-2.2 1-2.5 5.5-.8 7.5 1.5 1.8 4 1.4 4.1-.8.1-2.2-1.1-7.8-3.3-6.7zm9-3c-2.2-1-3.4 4.5-3.3 6.7.1 2.2 2.6 2.6 4.1.8 1.7-2 1.4-6.5-.8-7.5z"/><ellipse cx="5.9" cy="6.5" rx="2.1" ry="3.3" transform="rotate(-14 5.9 6.5)"/><ellipse cx="18" cy="18" rx="2.1" ry="3.3" transform="rotate(14 18 18)"/></g>',
  legacyfoot:
    '<ellipse cx="8" cy="15" rx="3" ry="5" transform="rotate(-20 8 15)"/><ellipse cx="17" cy="9" rx="3" ry="5" transform="rotate(20 17 9)"/><circle cx="5" cy="7" r="1"/><circle cx="19" cy="17" r="1"/>',
  flag: '<path d="M5 22V3c5-4 9 5 14 1v10c-5 4-9-5-14-1"/>',
  play: '<path d="m8 4 12 8-12 8z"/>',
  settings:
    '<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3"/><circle cx="15" cy="17" r="3"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
  upload: '<path d="M12 17V4m-5 5 5-5 5 5M4 17v4h16v-4"/>',
  chart: '<path d="M4 21V11h4v10M10 21V3h4v18M16 21V7h4v14"/>',
  badge: '<path d="m12 2 3 5 6 1-3 5 1 7-7-3-7 3 1-7-3-5 6-1z"/>',
  note: '<path d="M5 3h14v18H5zM9 8h6M9 12h6M9 16h4"/>',
  pause: '<path d="M8 5v14M16 5v14" stroke-width="3"/>',
  stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  moon: '<path d="M21 14A9 9 0 0 1 10 3a9 9 0 1 0 11 11"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
  cat: '<path d="m6 9-2-6 7 4h3l6-4-1 7a7 7 0 1 1-13-1M8 13h.1M16 13h.1m-5 3 1 1 1-1M2 13l5 1m10 0 5-1"/>',
  trash: '<path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7M14 10v7"/>',
};
const icon = (name) =>
  `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.map}</svg>`;
for (const [id, name] of Object.entries({
  menuButton: "menu",
  answerButton: "map",
  spotButton: "camera",
  locateButton: "locate",
  layerButton: "layers",
  recordButton: "foot",
  tabMap: "sparkles",
  tabRecords: "chart",
  tabProfile: "profile",
}))
  $("#" + id).innerHTML = icon(name);
let pageStack = [];
let sheetStack = [],
  sheetGesture = null;
let holdTimer = null,
  suppressRecordClick = false;
let db;
try {
  if (native) {
    db = { native: true };
  } else
    db = await new Promise((resolve, reject) => {
      const req = indexedDB.open("plainwalk-web", 1);
      req.onupgradeneeded = () => req.result.createObjectStore("data");
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
} catch {
  toast("端末内ストレージを利用できません。記録は保存されません。", 10000);
}
async function read(key) {
  if (native) return nativeCall("storageRead", { key });
  if (!db) return null;
  return new Promise((resolve) => {
    const r = db.transaction("data").objectStore("data").get(key);
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => resolve(null);
  });
}
async function write(key, value) {
  if (native) return nativeCall("storageWrite", { key, value });
  if (!db) throw Error("端末内ストレージが利用できません。");
  return new Promise((resolve, reject) => {
    const t = db.transaction("data", "readwrite");
    t.objectStore("data").put(value, key);
    t.oncomplete = () => resolve();
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}
let data = (await read("library")) || {
    version: 1,
    walks: [],
    spots: [],
    flags: [],
    notes: {},
  },
  config = {
    theme: 0,
    line: "solid",
    pin: "card",
    cat: "black",
    dark: "auto",
    beta: false,
    accuracy: true,
    wake: true,
    reduce: false,
    goal: 5000,
    ...(await read("config")),
  },
  active = await read("active"),
  watch = null,
  tab = "map",
  month = new Date(),
  selectedWalk = null,
  answer = false,
  follow = true,
  current = null,
  accuracy = 0,
  paused = false,
  wakeLock = null,
  toastTimer,
  renderFrame,
  geoError = "",
  mapMode = "normal",
  replayTimer = null,
  modalFocus = null;
const trace = createDiagnostics({
  persist: (events) => {
    try {
      sessionStorage.setItem("plainwalk-diagnostics", JSON.stringify(events));
    } catch {}
  },
});
trace.enable(config.developerMode === true);
try {
  trace.restore(
    JSON.parse(sessionStorage.getItem("plainwalk-diagnostics") || "[]"),
  );
} catch {}
trace.record("app", { status: "started", source: native ? "native" : "web" });
window.addEventListener("error", (e) =>
  trace.record("error", {
    source: "javascript",
    code: e.error?.name || "Error",
  }),
);
window.addEventListener("unhandledrejection", (e) =>
  trace.record("error", { source: "promise", code: e.reason?.name || "Error" }),
);
let editing = null,
  editorDrag = null;
let view = {
  x: project({ lat: 35.6762, lon: 139.6503 })[0],
  y: project({ lat: 35.6762, lon: 139.6503 })[1],
  zoom: 16,
};
let noteDraft = null,
  noteSelected = null,
  noteDrag = null,
  notePaint = 0,
  lassoState = null;
let areaState = { index: null, stats: [], revision: -1 },
  areaRevision = 0;
let exp = exploration(data.walks);
let visits = new Map();
function countVisits() {
  visits = new Map();
  for (const w of data.walks) {
    const cells = new Set();
    for (let i = 1; i < w.points.length; i++) {
      if (w.points[i].break) continue;
      for (const k of cellKeys(w.points[i - 1], w.points[i])) cells.add(k);
    }
    for (const k of cells) visits.set(k, (visits.get(k) || 0) + 1);
  }
}
countVisits();
if (active) {
  active.paused = true;
  paused = true;
}
const themes = [
  ["白地図", "#fafbf9", "#1d211e"],
  ["ミント", "#eff7f2", "#143028"],
  ["さくら", "#fcf1f3", "#35171f"],
  ["ラベンダー", "#f3f1fa", "#221b3a"],
  ["スカイ", "#eef4fb", "#12253a"],
  ["セピア", "#f8f2e6", "#33270f"],
  ["フォレスト", "#f0f4ec", "#172913"],
  ["ピーチ", "#fcf1ea", "#3b2015"],
  ["レモン", "#fbf7e3", "#332b0d"],
  ["ティール", "#eaf5f4", "#0f2c2d"],
  ["ストーン", "#f2f2ef", "#1f1f1d"],
  ["マスタード", "#e9be4f", "#2a1f04"],
  ["テラコッタ", "#e0956f", "#33150b"],
  ["オリーブ", "#bdbb74", "#1f2008"],
  ["デニム", "#93b1d8", "#0b1b30"],
];
const fmt = (m) => formatDistance(m, config.units),
  distanceUnit = () => getDistanceUnit(config.units),
  dateKey = (t) => {
    const d = new Date(t);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  },
  today = () => dateKey(Date.now()),
  time = (t) =>
    new Date(t).toLocaleTimeString("ja-JP", {
      hour: "2-digit",
      minute: "2-digit",
    }),
  duration = (ms) =>
    `${Math.floor(ms / 60000)}:${String(Math.floor(ms / 1000) % 60).padStart(2, "0")}`,
  id = () =>
    crypto.randomUUID?.() ||
    "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = crypto.getRandomValues(new Uint8Array(1))[0] & 15;
      return (c === "x" ? r : (r & 3) | 8).toString(16);
    });
function toast(msg, ms = 5000) {
  clearTimeout(toastTimer);
  $("#toast").textContent = msg;
  $("#toast").hidden = false;
  toastTimer = setTimeout(() => ($("#toast").hidden = true), ms);
}
async function save() {
  try {
    await write("library", data);
    trace.record("storage", {
      source: "library",
      status: "saved",
      count: data.walks.length,
    });
    areaRevision++;
    exp = exploration(data.walks);
    countVisits();
    updateStats();
  } catch (e) {
    toast(
      "保存できませんでした。空き容量を確認し、バックアップしてください。",
      10000,
    );
    trace.record("storage", { source: "library", status: "failed" });
    throw e;
  }
}
async function saveConfig() {
  await write("config", config).catch(() =>
    toast("設定を保存できませんでした。"),
  );
  applyTheme();
  draw();
}
function applyTheme() {
  if (native) nativeCall("appearance", { mode: config.dark }).catch(() => {});
  const theme = themes[config.theme] || themes[0],
    dark =
      config.dark === "dark" ||
      (config.dark === "auto" &&
        matchMedia("(prefers-color-scheme:dark)").matches);
  const root = document.documentElement.style;
  root.setProperty("--map-paper", dark ? "#191e1b" : theme[1]);
  root.setProperty("--map-ink", dark ? "#e4e7df" : theme[2]);
  root.setProperty("--paper", dark ? "#191b19" : "#fafafa");
  root.setProperty("--ink", dark ? "#e4e7df" : "#080808");
  document.body.classList.toggle("dark", dark);
  document.body.classList.toggle("reduce-motion", config.reduce);
  $('meta[name="theme-color"]').content = dark ? "#191b19" : "#fafafa";
}

if (!config.paletteVersion) {
  config.theme =
    [0, 6, 2, 5, 3, 4, 1, 8, 12, 9, 3, 13, 10, 0][config.theme] ?? 0;
  config.paletteVersion = 1;
}
matchMedia("(prefers-color-scheme:dark)").addEventListener("change", () => {
  applyTheme();
  draw();
});
applyTheme();
function metersPerPixel() {
  return (2 * Math.PI * 6378137) / (256 * 2 ** view.zoom);
}
function pointToScreen(p) {
  const [x, y] = project(p),
    el = $("#mapViewport");
  return [
    (x - view.x) / metersPerPixel() + el.clientWidth / 2,
    (view.y - y) / metersPerPixel() + el.clientHeight / 2,
  ];
}
function screenToPoint(x, y) {
  const el = $("#mapViewport");
  return unproject(
    view.x + (x - el.clientWidth / 2) * metersPerPixel(),
    view.y - (y - el.clientHeight / 2) * metersPerPixel(),
  );
}
function paths(points, limit = points.length) {
  const groups = [];
  for (const p of points.slice(0, limit)) {
    if (!groups.length || p.break) groups.push([]);
    groups.at(-1).push(pointToScreen(p));
  }
  return groups
    .map((ps) => {
      if (!ps.length) return "";
      let d = `M${ps[0][0].toFixed(1)},${ps[0][1].toFixed(1)} `;
      if (config.smooth === false || ps.length < 3)
        return (
          d +
          ps
            .slice(1)
            .map(([x, y]) => `L${x.toFixed(1)},${y.toFixed(1)}`)
            .join(" ")
        );
      for (let i = 1; i < ps.length - 1; i++) {
        const [x, y] = ps[i],
          next = ps[i + 1];
        d += `Q${x.toFixed(1)},${y.toFixed(1)} ${((x + next[0]) / 2).toFixed(1)},${((y + next[1]) / 2).toFixed(1)} `;
      }
      return d + `L${ps.at(-1)[0].toFixed(1)},${ps.at(-1)[1].toFixed(1)}`;
    })
    .join(" ");
}
function trailMarkup(w, color) {
  const groups = [];
  let group = null;
  for (let i = 1; i < w.points.length; i++) {
    const a = w.points[i - 1],
      b = w.points[i],
      mode = b.mode || w.mode || "walking";
    if (b.break || config.transportVisible?.[mode] === false) {
      group = null;
      continue;
    }
    const key = cellKeys(b, b)[0],
      visitsCount = visits.get(key) || 1,
      level =
        w === active || config.thicken === false
          ? 0
          : Math.min(4, Math.floor(Math.log2(visitsCount)));
    if (!group || group.level !== level) {
      group = { level, points: [a, b] };
      groups.push(group);
    } else group.points.push(b);
  }
  const fade = active && w !== active && config.fadeOther !== false ? 0.22 : 1;
  return groups
    .map(
      (g) =>
        `<path d="${paths(g.points)}" stroke="${color}" stroke-width="${1.3 + g.level * 0.65}" opacity="${fade * (w === active ? 1 : 0.68 + g.level * 0.08)}" ${config.line === "dashed" ? 'stroke-dasharray="1 5"' : ""}/>`,
    )
    .join("");
}
function draw() {
  cancelAnimationFrame(renderFrame);
  renderFrame = requestAnimationFrame(() => {
    const el = $("#mapViewport"),
      w = el.clientWidth,
      h = el.clientHeight;
    if (!w || !h) return;
    const color =
      getComputedStyle(document.body).getPropertyValue("--map-ink").trim() ||
      "#1d211e";
    const walks = (
      selectedWalk
        ? data.walks.filter((w) => w.id === selectedWalk)
        : data.walks
    ).map((w) => (editing?.id === w.id ? { ...w, points: editing.points } : w));
    const list =
      mapMode === "demo"
        ? [{ points: demoPoints }]
        : active
          ? [...walks, active]
          : walks;
    $("#trails").innerHTML = list.map((w) => trailMarkup(w, color)).join("");
    $("#emptyMap").hidden =
      list.some((w) => w.points.length > 1) || data.spots.length > 0;
    drawMapContext(w, h);
    collections.render();
    let pins = "";
    for (const p of data.flags) {
      const [x, y] = pointToScreen(p);
      if (x < -50 || x > w + 50 || y < -50 || y > h + 50) continue;
      pins += `<g transform="translate(${x},${y})" data-flag="${esc(p.id)}" role="button" tabindex="0" aria-label="${esc(p.name)}"><circle r="17" fill="var(--panel)" stroke="none"/><path d="M-4 10V-10c5-4 9 5 14 0V0c-5 5-9-4-14 0" stroke="${color}"/><text y="29" text-anchor="middle" fill="${color}" stroke="none" font-size="9">${esc(p.name).slice(0, 30)}</text></g>`;
    }
    for (const p of data.spots) {
      if (
        (p.photo && config.showPhotos === false) ||
        (!p.photo && !config.showTweets)
      )
        continue;
      const [x, y] = pointToScreen(p);
      if (x < -80 || x > w + 80 || y < -80 || y > h + 80) continue;
      pins += `<g transform="translate(${x},${y})" data-spot="${esc(p.id)}" role="button" tabindex="0" aria-label="${esc(p.text || "ここいいな")}">${spotMarker(p, color)}</g>`;
    }
    if (editing) {
      const step = Math.max(1, Math.ceil(editing.points.length / 500));
      editing.points.forEach((p, i) => {
        if (i % step && i !== editing.points.length - 1) return;
        const [x, y] = pointToScreen(p);
        if (x < 0 || x > w || y < 0 || y > h) return;
        pins += `<circle data-edit-point="${i}" cx="${x}" cy="${y}" r="5" fill="var(--panel)" stroke="var(--ink)" stroke-width="1.5"/>`;
      });
    }
    $("#pins").innerHTML = pins;
    if (current) {
      const [x, y] = pointToScreen(current),
        radius = Math.min(
          100,
          Math.max(
            35,
            accuracy /
              (metersPerPixel() * Math.cos((current.lat * Math.PI) / 180)),
          ),
        );
      $("#location").innerHTML =
        `${config.highlight !== false ? `<circle cx="${x}" cy="${y}" r="${radius}" fill="#8ab7ee" fill-opacity=".15" stroke="none"/>` : ""}<circle cx="${x}" cy="${y}" r="5" fill="${answer ? "#208ac4" : color}" stroke="var(--paper)" stroke-width="2"/>${config.locationMark && config.locationMark !== "dot" && view.zoom >= 14 && !answer ? `<foreignObject x="${x - 13}" y="${y - 30}" width="26" height="42"><div xmlns="http://www.w3.org/1999/xhtml">${companionSVG(config.locationMark, !!active && !paused && Date.now() - current.t < 10000, current.heading || 0)}</div></foreignObject>` : ""}`;
    } else $("#location").innerHTML = "";
    $("#mapPage").classList.toggle("answer-map", answer);
    if ($("#answerButton").dataset.mode !== String(answer)) {
      $("#answerButton").dataset.mode = String(answer);
      $("#answerButton").innerHTML = answer ? "閉じる" : icon("map");
      $(".map-caption").innerHTML = answer
        ? "<strong>答え合わせマップ</strong>"
        : "<strong>歩いた道が、地図になる。</strong><span>まだ誰も描いていない場所を、あなたの一歩で。</span>";
    }
    drawTiles();
    const scale =
      metersPerPixel() *
      45 *
      Math.cos(((current?.lat || 35.6) * Math.PI) / 180);
    $("#scaleText").textContent =
      scale >= 1000
        ? `${fmt(scale)} ${distanceUnit()}`
        : `${Math.round(scale)} m`;
    updateFlag();
  });
}
function drawTiles() {
  const el = $("#tiles");
  if (!answer) {
    el.innerHTML = "";
    delete el.dataset.key;
    return;
  }
  const z = Math.round(view.zoom),
    size = 256 * 2 ** (view.zoom - z),
    world = 256 * 2 ** view.zoom,
    cx = (view.x / (2 * Math.PI * 6378137) + 0.5) * world,
    cy = (0.5 - view.y / (2 * Math.PI * 6378137)) * world,
    w = $("#mapViewport").clientWidth,
    h = $("#mapViewport").clientHeight;
  let html = "";
  for (
    let x = Math.floor((cx - w / 2) / size);
    x <= Math.floor((cx + w / 2) / size);
    x++
  )
    for (
      let y = Math.floor((cy - h / 2) / size);
      y <= Math.floor((cy + h / 2) / size);
      y++
    ) {
      if (y < 0 || y >= 2 ** z) continue;
      const tx = ((x % 2 ** z) + 2 ** z) % 2 ** z;
      html += `<img alt="" src="https://tile.openstreetmap.org/${z}/${tx}/${y}.png" style="left:${x * size - cx + w / 2}px;top:${y * size - cy + h / 2}px;width:${size}px;height:${size}px" loading="lazy">`;
    }
  if (el.dataset.key === html) return;
  el.dataset.key = html;
  el.innerHTML = html;
}
function fit(points) {
  if (!points?.length) return;
  const ps = points.map(project);
  let minx = Infinity,
    maxx = -Infinity,
    miny = Infinity,
    maxy = -Infinity;
  for (const [x, y] of ps) {
    minx = Math.min(minx, x);
    maxx = Math.max(maxx, x);
    miny = Math.min(miny, y);
    maxy = Math.max(maxy, y);
  }
  view.x = (minx + maxx) / 2;
  view.y = (miny + maxy) / 2;
  const mpp = Math.max(
    (maxx - minx) / Math.max(150, $("#mapViewport").clientWidth - 100),
    (maxy - miny) / Math.max(200, $("#mapViewport").clientHeight - 240),
    0.7,
  );
  view.zoom = Math.max(
    3,
    Math.min(19, Math.log2((2 * Math.PI * 6378137) / (256 * mpp))),
  );
  follow = false;
  draw();
}
let expCache = { length: -1, value: 0 };
function updateStats() {
  $$(".map-stats em")
    .slice(1)
    .forEach((el) => (el.textContent = distanceUnit()));
  const todayWalks = data.walks.filter((w) => dateKey(w.start) === today());
  if (active && expCache.length !== active.points.length) {
    expCache = {
      length: active.points.length,
      value: exploration([...data.walks, active]).byWalk[active.id] || 0,
    };
  }
  const activeExp = active ? expCache.value : 0;
  $("#todayNew").textContent = fmt(
    todayWalks.reduce((n, w) => n + (exp.byWalk[w.id] || 0), 0) + activeExp,
  );
  $("#totalNew").textContent = fmt(exp.total + activeExp);
  const manual = Number(data.notes?.[today()]?.steps);
  $("#steps").textContent = manual ? manual.toLocaleString("ja-JP") : "—";
  $(".map-scale").hidden = !config.beta;
  $("#recordButton").classList.toggle("active", !!active);
  $("#recordButton").innerHTML = icon(
    active ? (paused ? "foot" : "pause") : "foot",
  );
  $("#recordLabel").textContent = active
    ? paused
      ? "タップで再開・長押しで終了"
      : "タップで一時停止"
    : "軌跡を残す";
  $("#spotButton").hidden = !active;
  $("#spotToolLabel").hidden = !active;
  $("#recordButton").setAttribute(
    "aria-label",
    active
      ? paused
        ? "記録を再開する"
        : "記録を一時停止する"
      : "散歩を始める",
  );
  $("#recordStatus").hidden = !active;
  if (active)
    $("#recordStatus").innerHTML =
      `<span class="status-dot"></span>${paused ? "一時停止" : geoError ? "GPS 待機" : "記録中"} ${duration(Math.max(0, Date.now() - active.start - (active.pausedMs || 0) - (active.pauseAt ? Date.now() - active.pauseAt : 0)))}`;
  if (tab === "map") draw();
}
let lastPersist = 0;
async function persistActive() {
  try {
    await write("active", active);
  } catch {
    toast(
      "記録の自動保存に失敗しました。バックアップを確認してください。",
      9000,
    );
  }
}
function acceptPosition(pos) {
  current = {
    lat: pos.coords.latitude,
    lon: pos.coords.longitude,
    t: pos.timestamp || Date.now(),
  };
  accuracy = pos.coords.accuracy;
  geoError = "";
  if (!validPoint(current)) return;
  if (follow) {
    [view.x, view.y] = project(current);
  }
  if (active && !paused) {
    const last = active.points.at(-1);
    let ok = accuracy <= 60;
    if (last) {
      const dt = (current.t - last.t) / 1000,
        d = distance(last, current);
      if (dt <= 0 || d < 3) ok = false;
      else if (dt > 120) current.break = true;
      else if (d / dt > 45) ok = false;
    }
    if (ok) {
      if (active.nextBreak) {
        current.break = true;
        delete active.nextBreak;
      }
      active.points.push({ ...current, accuracy });
      trace.record("gps", {
        source: "web",
        status: "accepted",
        accuracy,
        points: active.points.length,
      });
      collections.progress({ ...current, accuracy });
      if (Date.now() - lastPersist > 4000) {
        persistActive();
        lastPersist = Date.now();
      }
    }
  }
  updateStats();
  draw();
}
function startWatch() {
  if (native) {
    geoError = "位置情報を取得中";
    nativeCall("locationStart", {
      sessionID: active?.id,
      start: active?.start,
      recording: !!active && !paused,
    }).catch((e) => {
      geoError = e.message;
      toast(e.message);
      updateStats();
    });
    return;
  }
  if (watch !== null) navigator.geolocation.clearWatch(watch);
  if (!navigator.geolocation) {
    toast("このブラウザは位置情報に対応していません。");
    return;
  }
  geoError = "位置情報を取得中";
  watch = navigator.geolocation.watchPosition(
    acceptPosition,
    (e) => {
      geoError =
        e.code === 1
          ? "位置情報が許可されていません"
          : e.code === 2
            ? "位置情報を取得できません"
            : "位置情報がタイムアウトしました";
      toast(geoError + "。Safari の位置情報設定を確認してください。", 8000);
      updateStats();
    },
    { enableHighAccuracy: true, maximumAge: 3000, timeout: 25000 },
  );
}
async function requestWake() {
  if (
    config.beta &&
    config.wake &&
    active &&
    !paused &&
    "wakeLock" in navigator &&
    document.visibilityState === "visible"
  ) {
    try {
      wakeLock = await navigator.wakeLock.request("screen");
    } catch {}
  }
}
async function begin() {
  if (!db) {
    toast("端末に保存できないため、記録を開始できません。");
    return;
  }
  active = {
    id: id(),
    name: "さんぽ",
    start: Date.now(),
    end: Date.now(),
    points: [],
    note: "",
    stickers: "",
    pausedMs: 0,
  };
  paused = false;
  trace.record("recording", {
    status: "started",
    source: native ? "native" : "web",
  });
  expCache = { length: -1, value: 0 };
  follow = true;
  await persistActive();
  startWatch();
  requestWake();
  closeSheet();
  updateStats();
  toast(
    native
      ? "記録を始めました。画面を閉じても記録します。"
      : "記録を始めました。Web 版では画面を開いたままお使いください。",
    7000,
  );
}
async function stopWalk() {
  if (!active) return;
  if (native) await syncNative();
  const walk = { ...active, end: Date.now() };
  walk.duration = Math.max(
    0,
    walk.end -
      walk.start -
      (walk.pausedMs || 0) -
      (walk.pauseAt ? walk.end - walk.pauseAt : 0),
  );
  if (walk.points.length < 2) {
    sheet(
      "まだ道が記録されていません",
      `<p>位置情報を取得して少し歩くと、白地図に道が描かれます。</p><button class="primary" data-action="close">記録を続ける</button><button class="secondary" data-action="discard">この記録を破棄</button>`,
    );
    return;
  }
  data.walks.push(walk);
  try {
    await save();
  } catch {
    data.walks.pop();
    return;
  }
  active = null;
  paused = false;
  await persistActive();
  clearWatch();
  closeSheet();
  switchTab("records");
  detail(walk.id);
  toast("今日の道を、白地図に残しました。");
}
function clearWatch() {
  if (native)
    nativeCall("locationStop", { end: !active }).catch((e) => toast(e.message));
  if (watch !== null) {
    navigator.geolocation.clearWatch(watch);
    watch = null;
  }
  wakeLock?.release().catch(() => {});
  wakeLock = null;
}
function recordMenu() {
  if (editing) {
    toast("軌跡の修正を保存するか、キャンセルしてください。");
    return;
  }
  if (!active) {
    sheet(
      "今日の一歩を、白地図に。",
      `<div class="center" style="margin:25px">${icon("foot")}</div><p>歩いた道だけを記録します。位置情報はこの端末内に保存されます。</p><p class="subtle">iPhone では Safari の位置情報を許可してください。${native ? "iOS アプリでは記録中だけ、画面を閉じても位置情報を保存します。権限が必要です。" : "Web 版は画面ロック・他のアプリへの切り替え中の記録を保証できません。歩数は設定から手動入力できます。"}</p><button class="primary" data-action="begin">散歩を始める</button><button class="secondary" data-action="demo">まずは体験してみる</button>`,
    );
    return;
  }
  sheet(
    "さんぽの記録",
    `<div class="stats-row"><div><b>${fmt(trailDistance(active.points))}<span class="unit"> ${distanceUnit()}</span></b><small>歩いた距離</small></div><div><b>${duration(Date.now() - active.start - (active.pausedMs || 0) - (active.pauseAt ? Date.now() - active.pauseAt : 0))}</b><small>記録時間</small></div></div><p class="subtle">${paused ? "一時停止しています。" : esc(geoError || `GPS 精度 ±${Math.round(accuracy)} m`)} · ${active.points.length} 点</p><button class="primary" data-action="finish">さんぽを保存して終了</button><button class="secondary" data-action="pause">${paused ? "記録を再開" : "一時停止"}</button><button class="secondary" data-action="tweet">今のひとことを残す</button><button class="secondary danger-button" data-action="discardConfirm">記録を破棄</button>`,
  );
}
async function pauseToggle() {
  paused = !paused;
  if (paused) {
    active.paused = true;
    active.pauseAt = Date.now();
    clearWatch();
  } else {
    active.pausedMs =
      (active.pausedMs || 0) +
      (active.pauseAt ? Date.now() - active.pauseAt : 0);
    delete active.pauseAt;
    active.paused = false;
    active.nextBreak = true;
    startWatch();
    requestWake();
  }
  await persistActive();
  closeSheet();
  updateStats();
}
function snapshotSheet() {
  const root = $("#sheetBody"),
    clone = root.cloneNode(true),
    actual = root.querySelectorAll("input,textarea,select"),
    copies = clone.querySelectorAll("input,textarea,select");
  actual.forEach((el, i) => {
    const copy = copies[i];
    if (el.tagName === "TEXTAREA") copy.textContent = el.value;
    else if (el.tagName === "SELECT") {
      [...copy.options].forEach((o, j) =>
        o.toggleAttribute("selected", el.options[j].selected),
      );
    } else if (el.type === "checkbox") {
      copy.toggleAttribute("checked", el.checked);
    } else if (el.type !== "file") copy.setAttribute("value", el.value);
  });
  return {
    title: $("#sheetTitle").textContent,
    html: clone.innerHTML,
    scroll: $("#sheet").scrollTop,
  };
}
function sheet(title, html) {
  $("#sheet").classList.toggle("reference-sheet", title === "地図レイヤー");
  const opening = $("#overlay").hidden;
  if (opening) {
    modalFocus = document.activeElement;
    sheetStack = [];
  } else if ($("#sheetTitle").textContent !== title) {
    sheetStack.push(snapshotSheet());
    if (sheetStack.length > 20) sheetStack.shift();
    stopCamera();
  }
  $("#sheetTitle").textContent = title;
  $("#sheetBody").innerHTML = html;
  $("#overlay").hidden = false;
  $("#sheetBack").hidden = !sheetStack.length;
  $("#sheet").scrollTop = 0;
  $("#sheet").style.transform = "";
  $("#app").inert = true;
  $("#sheetClose").focus({ preventScroll: true });
}
function sheetBack() {
  const previous = sheetStack.pop();
  if (!previous) {
    closeSheet();
    return;
  }
  stopCamera();
  clearInterval(replayTimer);
  replayTimer = null;
  $("#sheet").classList.toggle(
    "reference-sheet",
    previous.title === "地図レイヤー",
  );
  $("#sheetTitle").textContent = previous.title;
  $("#sheetBody").innerHTML = previous.html;
  $("#sheetBack").hidden = !sheetStack.length;
  $("#sheet").scrollTop = previous.scroll;
  if ($("#noteCanvas")) {
    paintNote();
    updateNoteControls();
  }
  if ($("#lassoCanvas")) paintLasso();
  $("#sheetBack").hidden
    ? $("#sheetClose").focus({ preventScroll: true })
    : $("#sheetBack").focus({ preventScroll: true });
}
function closeSheet() {
  stopCamera();
  clearInterval(replayTimer);
  replayTimer = null;
  $("#overlay").hidden = true;
  $("#app").inert = false;
  sheetStack = [];
  $("#sheet").style.transform = "";
  if (modalFocus?.isConnected) modalFocus.focus({ preventScroll: true });
  else $(".tabbar .selected")?.focus({ preventScroll: true });
}

function row(action, label, name = "map", sub = "") {
  return `<button class="row" data-action="${action}" aria-label="${esc(label)}">${icon(name)}<span class="grow stack"><strong>${esc(label)}</strong>${sub ? `<small>${esc(sub)}</small>` : ""}</span><span class="chevron">›</span></button>`;
}
function toggle(key, label, sub = "") {
  return `<label class="row"><span class="grow stack"><strong>${esc(label)}</strong>${sub ? `<small>${esc(sub)}</small>` : ""}</span><input class="switch" type="checkbox" data-config="${key}" ${config[key] ? "checked" : ""} aria-label="${esc(label)}"></label>`;
}
function menu() {
  sheet(
    "PlainWalk",
    `<div class="subtle" style="margin-bottom:16px">歩いた道が、あなたの地図になる。</div>${row("allMap", "すべての道を見る")}${row("flags", "目的地の旗", "flag")}${row("spots", "ここいいな", "camera")}${row("replay", "地図の成長を再生", "play")}${row("notes", "今日のノート", "note")}${row("stats", "歩行の統計", "chart")}${row("import", "GPX / TCX を取り込む", "upload")}${row("settings", "設定", "settings")}<p class="caption-note">非公式 Web 移植版 · 課金・広告なし</p>`,
  );
}
function switchTab(next) {
  pageStack = [];
  $("#contentPage").className = "";
  delete $("#contentPage").dataset.route;
  tab = next;
  $("#mapPage").hidden = tab !== "map";
  $("#contentPage").hidden = tab === "map";
  $$("[data-tab]").forEach((b) =>
    b.classList.toggle("selected", b.dataset.tab === tab),
  );
  if (tab === "records") renderRecords();
  if (tab === "profile" && !$("#contentPage").dataset.route) renderProfile();
  if (tab === "map") draw();
}
function miniSvg(points, cls = "") {
  if (!points.length) return `<svg viewBox="0 0 100 80" class="${cls}"></svg>`;
  const ps = points.map(project);
  let minx = Infinity,
    miny = Infinity,
    maxx = -Infinity,
    maxy = -Infinity;
  for (const [x, y] of ps) {
    minx = Math.min(minx, x);
    maxx = Math.max(maxx, x);
    miny = Math.min(miny, y);
    maxy = Math.max(maxy, y);
  }
  const scale = Math.max((maxx - minx) / 80, (maxy - miny) / 60, 1);
  const d = ps
    .map(
      ([x, y], i) =>
        `${!i || points[i].break ? "M" : "L"}${((x - (minx + maxx) / 2) / scale + 50).toFixed(2)} ${(40 - (y - (miny + maxy) / 2) / scale).toFixed(2)}`,
    )
    .join(" ");
  return `<svg viewBox="0 0 100 80" class="${cls}"><path class="mini-trail" d="${d}" vector-effect="non-scaling-stroke"/></svg>`;
}
function renderRecords() {
  const now = new Date(),
    weekStart = new Date(now);
  weekStart.setDate(now.getDate() - now.getDay());
  weekStart.setHours(0, 0, 0, 0);
  const nextWeek = new Date(weekStart),
    previousWeek = new Date(weekStart),
    weekEnd = new Date(weekStart);
  nextWeek.setDate(nextWeek.getDate() + 7);
  previousWeek.setDate(previousWeek.getDate() - 7);
  weekEnd.setDate(weekEnd.getDate() + 6);
  const week = data.walks.filter(
    (w) => w.start >= +weekStart && w.start < +nextWeek,
  );
  const previous = data.walks.filter(
    (w) => w.start >= +previousWeek && w.start < +weekStart,
  );
  const previousDistance = previous.reduce(
    (n, w) => n + trailDistance(w.points),
    0,
  );
  const previousNew = previous.reduce((n, w) => n + (exp.byWalk[w.id] || 0), 0);
  const daysInMonth = new Date(
      month.getFullYear(),
      month.getMonth() + 1,
      0,
    ).getDate(),
    offset = new Date(month.getFullYear(), month.getMonth(), 1).getDay();
  let calendar = ["日", "月", "火", "水", "木", "金", "土"]
    .map((s) => `<span class="weekday">${s}</span>`)
    .join("");
  calendar += "<span></span>".repeat(offset);
  for (let i = 1; i <= daysInMonth; i++) {
    const d = dateKey(new Date(month.getFullYear(), month.getMonth(), i)),
      n = data.walks.filter((w) => dateKey(w.start) === d).length;
    calendar += `<button class="day ${n ? "walked" : ""} ${d === today() ? "today" : ""}" data-day="${d}" aria-label="${d}、${n}回の記録" title="${i}日"><span class="day-dot" aria-hidden="true"></span></button>`;
  }
  const walks = data.walks
    .filter((w) => {
      const d = new Date(w.start);
      return (
        d.getFullYear() === month.getFullYear() &&
        d.getMonth() === month.getMonth()
      );
    })
    .sort((a, b) => b.start - a.start);
  $("#contentPage").innerHTML =
    `<h1 class="page-title">記録</h1><section class="card"><div class="card-heading"><strong>今週</strong><small>${weekStart.getMonth() + 1}/${weekStart.getDate()} — ${weekEnd.getMonth() + 1}/${weekEnd.getDate()}</small></div><div class="stats-row"><div><b>${week.length}</b><small>さんぽ</small><small class="week-comparison">先週 ${previous.length}</small></div><div><b>${fmt(week.reduce((n, w) => n + trailDistance(w.points), 0))}<span class="unit"> ${distanceUnit()}</span></b><small>歩いた距離</small><small class="week-comparison">先週 ${fmt(previousDistance)} ${distanceUnit()}</small></div><div><b>${fmt(week.reduce((n, w) => n + (exp.byWalk[w.id] || 0), 0))}<span class="unit"> ${distanceUnit()}</span></b><small>開拓した道</small><small class="week-comparison">先週 ${fmt(previousNew)} ${distanceUnit()}</small></div></div><div class="card-heading" style="margin-bottom:10px"><button data-action="prevMonth" aria-label="前月">‹</button><small>${month.getFullYear()}年 ${month.getMonth() + 1}月</small><button data-action="nextMonth" aria-label="翌月">›</button></div><div class="calendar">${calendar}</div><div style="margin-top:15px">${row("weeklyReview", "今週のふりかえり", "records")}</div></section><div class="two-buttons"><button data-action="replay">${icon("play")}地図の成長を<br>再生</button><button data-action="stats">${icon("chart")}歩行の記録</button></div><div class="month-label"><span>${month.getFullYear()}年 ${month.getMonth() + 1}月</span><span>距離 ${fmt(walks.reduce((n, w) => n + trailDistance(w.points), 0))} ${distanceUnit()}</span></div>${walks.length ? walks.map((w) => `<button class="walk-card" data-walk="${esc(w.id)}">${miniSvg(w.points)}<span class="stack"><strong>${esc(w.name)}</strong><small>${new Date(w.start).getMonth() + 1}月${new Date(w.start).getDate()}日 ${time(w.start)} – ${time(w.end)}</small><b>開拓 ${fmt(exp.byWalk[w.id])} ${distanceUnit()} <small>· ${fmt(trailDistance(w.points))} ${distanceUnit()}</small></b><span class="walk-exploration-bar" role="meter" aria-label="開拓した道の割合" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(Math.min(100, (100 * (exp.byWalk[w.id] || 0)) / Math.max(1, trailDistance(w.points))))}" style="--pioneer:${Math.min(100, (100 * (exp.byWalk[w.id] || 0)) / Math.max(1, trailDistance(w.points)))}%"></span></span><span class="subtle">›</span></button>`).join("") : `<div class="empty-state">${icon("foot")}<br>まだ、さんぽの記録がありません。<br>白地図で、最初の一歩を。</div>`}`;
}
function renderProfile() {
  $("#contentPage").innerHTML =
    `<h1 class="page-title">プロフィール</h1><div class="profile-avatar">${companionSVG(config.locationMark === "dot" ? "black" : config.locationMark || "black")}</div><h2 class="profile-name">あなたの白地図</h2><p class="center subtle">いつもの一歩が、ちいさな冒険に。</p><div class="center"><span class="pill">${levelName()} · 開拓 ${fmt(exp.total)} ${distanceUnit()}</span></div><div class="stats-row" style="margin:28px 0"><div><b>${data.walks.length}</b><small>さんぽ</small></div><div><b>${new Set(data.walks.map((w) => dateKey(w.start))).size}</b><small>歩いた日</small></div><div><b>${fmt(exp.total)}</b><small>総開拓距離 ${distanceUnit()}</small></div></div><section class="card">${row("stats", "歩行の統計", "chart")}${row("badges", "エリアと開拓のバッジ", "badge")}${row("spots", "ここいいな", "camera")}${row("stickers", "ステッカー", "badge")}${row("doodles", "らくがき", "pen")}${row("sharedMaps", "共有の白地図", "map")}${row("bookmarks", "気になる場所", "flag")}${row("flags", "目的地の旗", "flag")}${row("notes", "ノート", "note")}</section><section class="card">${row("layers", "地図の見た目", "layers", "配色・線・写真ピン・相棒を、自由に。")}${row("settings", "設定", "settings")}${row("backup", "データのバックアップ", "download")}${row("about", "この Web 版について", "info")}</section><p class="center caption-note">PlainWalk Web · 非公式・無料<br>記録はこのブラウザの中に。</p>`;
}
function levelName() {
  const levels = [
    [0, "はじめの一歩"],
    [42195, "フルマラソン"],
    [100000, "街の探検家"],
    [300000, "道の旅人"],
    [1000000, "千の道"],
    [3000000, "大陸の旅"],
    [10000000, "地球の旅人"],
    [40075000, "地球一周"],
    [100000000, "星への道"],
    [384400000, "月までの旅"],
  ];
  return levels.filter(([m]) => exp.total >= m).at(-1)[1];
}
function detail(walkId) {
  const w = data.walks.find((w) => w.id === walkId);
  if (!w) return;
  sheet(
    w.name,
    `${miniSvg(w.points, "walk-thumbnail")}<p class="center subtle">${new Date(w.start).toLocaleDateString("ja-JP")} ${time(w.start)} — ${time(w.end)}</p><div class="stats-row"><div><b>${fmt(trailDistance(w.points))}</b><small>歩いた距離 ${distanceUnit()}</small></div><div><b>${fmt(exp.byWalk[w.id])}</b><small>開拓した道 ${distanceUnit()}</small></div><div><b>${duration(w.duration ?? w.end - w.start)}</b><small>記録時間</small></div></div><label class="form-label">さんぽの名前</label><input id="walkName" maxlength="60" value="${esc(w.name)}"><label class="form-label">ひとこと</label><textarea id="walkNote" maxlength="3000">${esc(w.note || "")}</textarea><button class="primary" data-save-walk="${esc(w.id)}">変更を保存</button><div class="two-buttons" style="margin-top:15px"><button data-map-walk="${esc(w.id)}">${icon("map")}地図で見る</button><button data-replay-walk="${esc(w.id)}">${icon("play")}再生</button><button data-share-walk="${esc(w.id)}">${icon("download")}カードを保存</button><button data-gpx-walk="${esc(w.id)}">${icon("download")}GPX 書き出し</button></div><button class="secondary" data-edit-walk="${esc(w.id)}">軌跡を手で修正</button><button class="secondary danger-button" data-delete-walk="${esc(w.id)}">この記録を削除</button>`,
  );
}
function settings(forceWeb = false) {
  if (native && !forceWeb) {
    closeSheet();
    nativeCall("showSettings", { config }).catch((e) => toast(e.message));
    return;
  }
  const html = settingsHTML(config, { native, icon });
  if ($("#contentPage").dataset.route === "設定") {
    $("#pageBody").innerHTML = html;
  } else openPage("設定", html, { grouped: true });
}

function layers() {
  sheet("地図レイヤー", layersHTML(config, themes));
  $("#sheet").classList.add("reference-sheet");
}

function flags() {
  sheet(
    "目的地の旗",
    `<p class="subtle">行き先は決めて、道は決めない。旗を複数立てて、訪れる順に並べられます。</p>${data.flags.length ? data.flags.map((f, i) => `<div class="row"><span>${i + 1}. ⚑</span><button class="grow stack" data-flag-detail="${esc(f.id)}"><strong>${esc(f.name)}</strong><small>${f.lat.toFixed(5)}, ${f.lon.toFixed(5)}${current ? " · " + fmt(distance(current, f)) + " " + distanceUnit() : ""}</small></button><button data-flag-up="${esc(f.id)}" aria-label="上に移動" ${i === 0 ? "disabled" : ""}>↑</button><button data-flag-remove="${esc(f.id)}" aria-label="旗を削除">×</button></div>`).join("") : '<div class="empty-state">まだ旗がありません。</div>'}<button class="primary" data-action="flagAdd">旗を立てる</button><p class="caption-note">座標を入力するか、地図上の場所を選べます。住所検索や自動の経路案内はありません。</p>`,
  );
}
function flagAdd(p) {
  sheet(
    "旗を立てる",
    `<label class="form-label">目的地の名前</label><input id="flagName" maxlength="60" placeholder="気になっていた喫茶店"><div style="display:flex;gap:10px"><label class="grow form-label">緯度<input id="flagLat" type="number" step="any" min="-85" max="85" value="${p?.lat ?? current?.lat ?? ""}"></label><label class="grow form-label">経度<input id="flagLon" type="number" step="any" min="-180" max="180" value="${p?.lon ?? current?.lon ?? ""}"></label></div><button class="primary" data-action="flagSave">この場所に旗を立てる</button><button class="secondary" data-action="flagPick">白地図から選ぶ</button>`,
  );
}
function updateFlag() {
  const f = data.flags[0];
  $("#flagDirection").hidden = !f || !current;
  if (!f || !current) return;
  const a = (current.lat * Math.PI) / 180,
    b = (f.lat * Math.PI) / 180,
    dl = ((f.lon - current.lon) * Math.PI) / 180,
    deg =
      (Math.atan2(
        Math.sin(dl) * Math.cos(b),
        Math.cos(a) * Math.sin(b) - Math.sin(a) * Math.cos(b) * Math.cos(dl),
      ) *
        180) /
      Math.PI;
  const d = distance(current, f);
  $("#flagDirection").innerHTML =
    `${d < 1000 ? Math.round(d) + " m" : fmt(d) + " " + distanceUnit()}<span style="transform:rotate(${deg}deg)">↑</span>`;
  $("#flagDirection").title = f.name + " · 北を上にした方角";
  $("#flagDirection").onclick = () => flagDetail(f.id);
}
function flagDetail(flagId) {
  const f = data.flags.find((f) => f.id === flagId);
  if (!f) return;
  sheet(
    f.name,
    `<p>⚑ ${f.lat.toFixed(6)}, ${f.lon.toFixed(6)}</p>${current ? `<p>現在地から ${fmt(distance(current, f))} ${distanceUnit()}</p>` : ""}<button class="primary" data-flag-view="${esc(f.id)}">地図で見る</button><button class="secondary" data-flag-share="${esc(f.id)}">旗の座標を共有</button><button class="secondary danger-button" data-flag-remove="${esc(f.id)}">この旗を削除</button>`,
  );
}
function spots() {
  openPage(
    "ここいいな",
    `${
      data.spots.length
        ? `<div class="photo-grid">${[...data.spots]
            .reverse()
            .map(
              (p) =>
                `<button class="photo-card" data-spot="${esc(p.id)}">${p.photo ? `<img src="${esc(p.photo)}" alt="${esc(p.text)}">` : `<div style="height:100px;display:grid;place-items:center;font-size:35px">${esc(p.emoji || "♡")}</div>`}<p>${esc(p.text || "ここいいな")}</p><small>${new Date(p.t).toLocaleDateString("ja-JP")} ${time(p.t)}</small></button>`,
            )
            .join("")}</div>`
        : `<div class="full-page-empty">${icon("camera")}<h2>まだ「ここいいな」がありません</h2><p>さんぽ中に「ここいいな」を残すと、ここに並びます。</p></div>`
    }${data.spots.length ? '<button class="primary" data-action="spot">ここいいなを残す</button>' : ""}`,
  );
}
let pendingPhoto = null,
  pendingVideo = null,
  cameraStream = null;
function addSpot(p = current) {
  pendingPhoto = null;
  pendingVideo = null;
  if (!p) {
    sheet(
      "ここいいな",
      `<div class="empty-state">${icon("camera")}<p>道で見つけた「ここいいな」を、<br>写真とひとことで。</p></div><button class="primary" data-action="spotPick">地図から場所を選ぶ</button><button class="secondary" data-action="spotLocate">現在地に残す</button>`,
    );
    return;
  }
  sheet(
    "ここいいな",
    `<form id="spotForm" data-lat="${p.lat}" data-lon="${p.lon}"><div class="segmented capture-tabs"><button type="button" class="chosen" data-spot-mode="photo">写真</button><button type="button" data-spot-mode="video">1〜2 秒の動画</button></div><div id="spotPhotoPanel"><input type="file" id="spotPhoto" accept="image/*" hidden><label for="spotPhoto" class="photo-stage"><span id="photoStageHint">${icon("camera")}<strong>今日の「ここいいな」を撮る</strong><small>カメラ・写真ライブラリから</small></span><img id="spotPreview" alt="選んだ写真" hidden></label></div><div id="spotVideoPanel" hidden><input type="file" id="spotVideo" accept="video/mp4,video/webm,video/quicktime" hidden><label for="spotVideo" class="video-picker">${icon("play")}<span>短い動画を選ぶ</span></label><video id="spotVideoPreview" class="spot-preview" playsinline controls hidden></video><video id="spotLive" class="spot-preview" playsinline muted hidden></video><label class="row"><span class="grow">音も残す</span><input id="spotAudio" class="switch" type="checkbox" aria-label="撮影時の音声"></label><div class="two-buttons"><button type="button" data-action="videoCamera">${icon("camera")}カメラを開く</button><button type="button" id="videoRecordButton" data-action="videoRecord" disabled>${icon("play")}2 秒を残す</button></div></div><label class="form-label">フィルム</label><select id="spotFilm" hidden><option value="none">そのまま</option><option value="sepia(.65) saturate(.7)">あたたかなフィルム</option><option value="grayscale(1)">モノクローム</option><option value="saturate(.65) contrast(.9)">やわらかな色</option>${config.lut ? '<option value="custom">自分の LUT</option>' : ""}</select><div class="film-options">${[["none", "そのまま", "#e7e9de"], ["sepia(.65) saturate(.7)", "あたたか", "#dbc9a5"], ["grayscale(1)", "モノクロ", "#a5aaa5"], ["saturate(.65) contrast(.9)", "やわらか", "#c9d6cf"], ...(config.lut ? [["custom", "自分の LUT", "#bfb4d1"]] : [])].map(([value, label, color]) => `<button type="button" data-spot-filter="${value}" class="${value === "none" ? "chosen" : ""}" aria-label="${label}"><span style="background:${color}"></span><small>${label}</small></button>`).join("")}</div><details class="film-advanced"><summary>自分のフィルムを読み込む</summary><label class="form-label">3D LUT（.cube）</label><input type="file" id="spotLut" accept=".cube,text/plain"><p class="caption-note">サイズ 2〜33 の 3D LUT に対応しています。</p></details><label class="form-label">ひとこと</label><textarea id="spotText" class="spot-caption" maxlength="500" placeholder="路地裏の喫茶店。プリンがかため。"></textarea><label class="form-label">どんな「ここいいな」？</label><select id="spotEmoji" hidden><option>♡</option><option>☕</option><option>🌿</option><option>🐈</option><option>🍰</option><option>📷</option><option>✦</option></select><div class="spot-categories">${[
      ["♡", "好き"],
      ["☕", "お店"],
      ["🌿", "景色"],
      ["🐈", "出会い"],
      ["🍰", "美味しい"],
      ["📷", "写真"],
      ["✦", "発見"],
    ]
      .map(
        ([emoji, label]) =>
          `<button type="button" data-spot-category="${emoji}" class="${emoji === "♡" ? "chosen" : ""}">${emoji}<small>${label}</small></button>`,
      )
      .join(
        "",
      )}</div><button type="submit" class="primary">この場所に残す</button><p class="center caption-note">写真と位置は、この端末の中に。</p></form>`,
  );
}

async function resizePhoto(file, filter = "none") {
  if (!file || !file.type.startsWith("image/"))
    throw Error("写真ファイルを選んでください。");
  if (file.size > 30 * 1024 * 1024)
    throw Error("写真は 30 MB 以下で選んでください。");
  const bitmap = await createImageBitmap(file).catch(() => null);
  let img = bitmap;
  if (!img) {
    const url = URL.createObjectURL(file);
    try {
      img = await new Promise((res, rej) => {
        const i = new Image();
        i.onload = () => res(i);
        i.onerror = () =>
          rej(
            Error(
              "この写真形式は読み込めません。JPEG または PNG をお試しください。",
            ),
          );
        i.src = url;
      });
    } finally {
      URL.revokeObjectURL(url);
    }
  }
  const scale = Math.min(1, 1000 / Math.max(img.width, img.height)),
    c = document.createElement("canvas");
  c.width = Math.round(img.width * scale);
  c.height = Math.round(img.height * scale);
  const ctx = c.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, c.width, c.height);
  if (filter !== "none") {
    const image = ctx.getImageData(0, 0, c.width, c.height);
    ctx.putImageData(applyEffect(image, filter, config.lut), 0, 0);
  }
  bitmap?.close();
  return c.toDataURL("image/jpeg", 0.8);
}
function spotDetail(spotId) {
  const p = data.spots.find((p) => p.id === spotId);
  if (!p) return;
  sheet(
    "ここいいな",
    `${p.video ? `<video class="spot-preview" src="${esc(p.video)}" poster="${esc(p.photo)}" playsinline controls></video>` : p.photo ? `<img class="spot-preview" src="${esc(p.photo)}" alt="${esc(p.text)}">` : ""}<p>${esc(p.emoji || "♡")} ${esc(p.text)}</p><p class="subtle">${new Date(p.t).toLocaleString("ja-JP")}<br>${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}</p><button class="primary" data-spot-view="${esc(p.id)}">地図で見る</button>${p.photo ? `<button class="secondary" data-spot-download="${esc(p.id)}">写真を保存</button>` : ""}${p.video ? `<button class="secondary" data-video-download="${esc(p.id)}">動画を保存</button>` : ""}<button class="secondary danger-button" data-spot-delete="${esc(p.id)}">このピンを削除</button>`,
  );
}
function notes(day = today()) {
  noteDraft = {
    day,
    paper: "plain",
    font: "serif",
    layout: [],
    ...structuredClone(data.notes[day] || {}),
  };
  noteSelected = null;
  showNote();
}
function showNote() {
  if (!noteDraft) return;
  const day = noteDraft.day;
  sheet(
    `${day} のノート`,
    `<label class="form-label">今日のひとこと</label><textarea id="dailyNote" maxlength="5000" placeholder="今日、どんな道を歩きましたか？">${esc(noteDraft.text || "")}</textarea><div class="segmented">${["🌿", "☕", "🐈", "✦", "🌼", "☁"].map((e) => `<button data-sticker="${e}" aria-label="${e} のステッカー">${e}</button>`).join("")}</div><div id="noteStickers" hidden>${esc(noteDraft.stickers || "")}</div><div class="two-buttons"><button data-action="notePhoto">${icon("camera")}写真を貼る</button><button data-action="noteRoute">${icon("map")}道を貼る</button><button data-action="noteCutout">${icon("badge")}ステッカーを作る</button><button data-save-note="${day}">${icon("note")}保存</button></div><canvas id="noteCanvas" width="720" height="960" aria-label="ノート。写真やステッカーをドラッグして配置できます。"></canvas><p class="caption-note">写真やステッカーをタップして選択し、ドラッグで配置できます。</p><div id="noteItemControls" hidden><label class="form-label">大きさ<input id="noteItemSize" type="range" min="40" max="600" value="180"></label><label class="form-label">回転<input id="noteItemRotation" type="range" min="-180" max="180" value="0"></label><label class="form-label">仕上げ<select id="noteItemFinish"><option value="plain">そのまま</option><option value="foil">箔</option><option value="holo">ホログラム</option></select></label><div class="two-buttons"><button data-action="noteItemFront">手前へ</button><button data-action="noteItemDelete">取り除く</button></div></div><div style="display:flex;gap:10px"><label class="form-label" style="flex:1">紙<select id="notePaper">${[
      ["plain", "白い紙"],
      ["grid", "方眼"],
      ["lined", "罫線"],
      ["kraft", "クラフト"],
    ]
      .map(
        ([v, l]) =>
          `<option value="${v}" ${noteDraft.paper === v ? "selected" : ""}>${l}</option>`,
      )
      .join(
        "",
      )}</select></label><label class="form-label" style="flex:1">書体<select id="noteFont">${[
      ["serif", "セリフ"],
      ["sans", "サンセリフ"],
      ["mono", "等幅"],
    ]
      .map(
        ([v, l]) =>
          `<option value="${v}" ${noteDraft.font === v ? "selected" : ""}>${l}</option>`,
      )
      .join(
        "",
      )}</select></label></div><button class="primary" data-save-note="${day}">ノートを保存</button><button class="secondary" data-share-note="${day}">画像にして保存</button><button class="secondary" data-action="clearStickers">絵文字のステッカーを外す</button>`,
  );
  paintNote();
  updateNoteControls();
}
function captureNoteDraft() {
  if (!noteDraft) return;
  if ($("#dailyNote")) noteDraft.text = $("#dailyNote").value;
  if ($("#noteStickers")) noteDraft.stickers = $("#noteStickers").textContent;
}
async function paintNote() {
  const canvas = $("#noteCanvas");
  if (!canvas || !noteDraft) return;
  const serial = ++notePaint,
    copy = structuredClone(noteDraft),
    offscreen = document.createElement("canvas");
  await drawNotebook(offscreen, copy, { selection: noteSelected });
  if (serial === notePaint && canvas.isConnected) {
    canvas.width = 720;
    canvas.height = 960;
    canvas.getContext("2d").drawImage(offscreen, 0, 0);
  }
}
function updateNoteControls() {
  const controls = $("#noteItemControls"),
    item = noteDraft?.layout?.find((i) => i.id === noteSelected);
  if (!controls) return;
  controls.hidden = !item;
  if (item) {
    $("#noteItemSize").value = item.width;
    $("#noteItemRotation").value = item.rotation || 0;
    $("#noteItemFinish").value = item.finish || "plain";
  }
}
async function addNoteImage(src, type = "photo") {
  if (!noteDraft) return;
  if (noteDraft.layout.length >= 20) {
    toast("1 ページには 20 点まで貼れます。");
    return;
  }
  const image = await loadImage(src),
    item = {
      id: id(),
      type,
      src,
      ratio: image.width / image.height,
      x: 360,
      y: 500,
      width: 240,
      rotation: -5,
      finish: "plain",
    };
  noteDraft.layout.push(item);
  noteSelected = item.id;
  showNote();
}
function notePhotoPicker(cutout = false) {
  captureNoteDraft();
  const photos = data.spots.filter((p) => p.photo);
  sheet(
    cutout ? "写真からステッカー" : "ノートに写真を貼る",
    `<label class="form-label">写真を選ぶ</label><input type="file" id="notePhotoFile" data-cutout="${cutout ? "yes" : "no"}" accept="image/*"><div class="photo-grid" style="margin-top:20px">${photos.map((p) => `<button class="photo-card" data-note-photo="${esc(p.id)}" data-cutout="${cutout ? "yes" : "no"}"><img src="${esc(p.photo)}" alt="${esc(p.text || "ここいいな")}"><p>${esc(p.text || "ここいいな")}</p></button>`).join("")}</div><button class="secondary" data-action="noteBack">ノートに戻る</button>`,
  );
}
async function cutoutPhoto(src) {
  if (native) {
    sheet(
      "ステッカーを作っています",
      '<p class="center subtle">この iPhone で写真の被写体を探しています。</p>',
    );
    const result = await nativeCall("photoCutout", {
      base64: src.split(",")[1],
    });
    await addNoteImage(result, "sticker");
    return;
  }
  const image = await loadImage(src);
  lassoState = { src, points: [], image };
  sheet(
    "被写体を囲んで切り抜く",
    '<p class="subtle">残したい部分のまわりを順にタップしてください。3 点以上で囲み、「切り抜く」を押します。</p><canvas id="lassoCanvas" width="720" height="720" aria-label="写真の切り抜き範囲"></canvas><button class="primary" data-action="lassoFinish">切り抜く</button><button class="secondary" data-action="lassoUndo">ひとつ戻す</button><button class="secondary" data-action="noteBack">ノートに戻る</button>',
  );
  paintLasso();
}
function paintLasso() {
  const c = $("#lassoCanvas");
  if (!c || !lassoState) return;
  const { image, points } = lassoState;
  c.width = 720;
  c.height = Math.round((720 * image.height) / image.width);
  const ctx = c.getContext("2d");
  ctx.drawImage(image, 0, 0, c.width, c.height);
  ctx.strokeStyle = "#fff";
  ctx.fillStyle = "#ffffff30";
  ctx.lineWidth = 3;
  ctx.beginPath();
  points.forEach(([x, y], i) => {
    i
      ? ctx.lineTo(x * c.width, y * c.height)
      : ctx.moveTo(x * c.width, y * c.height);
  });
  if (points.length > 2) ctx.closePath();
  ctx.fill();
  ctx.stroke();
  for (const [x, y] of points) {
    ctx.beginPath();
    ctx.arc(x * c.width, y * c.height, 6, 0, Math.PI * 2);
    ctx.fillStyle = "#fff";
    ctx.fill();
  }
}

function stats() {
  const total = data.walks.reduce((n, w) => n + trailDistance(w.points), 0),
    days = new Set(data.walks.map((w) => dateKey(w.start))).size;
  const seven = Array.from({ length: 7 }, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - 6 + i);
    const key = dateKey(d);
    return {
      label: ["日", "月", "火", "水", "木", "金", "土"][d.getDay()],
      m: data.walks
        .filter((w) => dateKey(w.start) === key)
        .reduce((n, w) => n + trailDistance(w.points), 0),
    };
  });
  const max = Math.max(...seven.map((d) => d.m), 100);
  const best = [...data.walks].sort(
    (a, b) => trailDistance(b.points) - trailDistance(a.points),
  )[0];
  sheet(
    "歩行の統計",
    `<div class="stats-row"><div><b>${data.walks.length}</b><small>さんぽ</small></div><div><b>${fmt(total)}</b><small>歩いた距離 ${distanceUnit()}</small></div><div><b>${days}</b><small>歩いた日</small></div></div><section class="card"><h3>最近 7 日間 · 歩いた距離</h3><div class="bars">${seven.map((d) => `<button class="bar" style="height:${Math.max(2, (d.m / max) * 100)}%" data-bar="${fmt(d.m)} ${distanceUnit()}" aria-label="${d.label}曜日 ${fmt(d.m)} ${distanceUnit()}"><small>${d.label}</small></button>`).join("")}</div><div style="height:15px"></div></section><section class="card"><h3>開拓レベル</h3><p>${levelName()}</p><p class="subtle">総開拓 ${fmt(exp.total)} ${distanceUnit()} · 通った 12 m セルの重複を除いて算出する Web 版の近似値です。</p><progress value="${Math.min(exp.total / 42195, 1)}" max="1"></progress><small class="subtle">最初の目標：${fmt(42195)} ${distanceUnit()}</small></section>${best ? `<h3>いちばん長いさんぽ</h3><button class="walk-card" data-walk="${esc(best.id)}">${miniSvg(best.points)}<span class="stack">${esc(best.name)}<b>${fmt(trailDistance(best.points))} ${distanceUnit()}</b></span></button>` : ""}${row("steps", "歩数の記録と目標", "foot")}`,
  );
}
async function badges() {
  openPage(
    "エリアバッジ",
    '<p class="center subtle">歩いた街を調べています。</p><progress id="areaProgress" max="1" value="0"></progress>',
  );
  try {
    if (!areaState.index) {
      const response = await fetch("./data/japan-municipalities.geojson");
      if (!response.ok) throw Error("境界データを読み取れませんでした。");
      areaState.index = makeIndex(await response.json());
    }
    if (areaState.revision !== areaRevision) {
      areaState.stats = await collectAreas(data.walks, areaState.index, (p) => {
        const el = $("#areaProgress");
        if (el) el.value = p;
      });
      areaState.revision = areaRevision;
    }
    if ($("#contentPage").dataset.route !== "エリアバッジ") return;
    if (!areaState.stats.length) {
      $("#pageBody").innerHTML =
        `<div class="full-page-empty">${icon("map")}<h2>まだバッジがありません</h2><p>どこかを歩くと、最初のバッジがここに出ます。</p></div>`;
      return;
    }
    $("#pageBody").innerHTML =
      `<div class="stats-row"><div><b>${areaState.stats.length}</b><small>訪れた街</small></div><div><b>${new Set(areaState.stats.map((s) => s.parent)).size}</b><small>都道府県</small></div></div><label class="form-label" for="areaSearch">街・都道府県で絞り込む</label><input id="areaSearch" type="search" placeholder="街の名前"><div class="segmented">${[
        ["glass", "クリスタル"],
        ["ink", "インク"],
        ["foil", "箔"],
      ]
        .map(
          ([v, l]) =>
            `<button data-area-finish="${v}" class="${(config.areaFinish || "ink") === v ? "chosen" : ""}">${l}</button>`,
        )
        .join(
          "",
        )}</div><div id="areaGrid" class="area-grid"></div><p class="caption-note">日本の市区町村・行政区 1,905 区域に対応。記録した位置と境界ポリゴンから判定します。境界付近や GPS の誤差で判定が変わる場合があります。</p><details><summary>境界データの出典</summary><p class="caption-note">「国土数値情報（行政区域データ）」（国土交通省）を加工して作成。<a href="https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-2026.html" target="_blank" rel="noopener">原典</a> / <a href="https://geo.maderaojen.me/" target="_blank" rel="noopener">配布元の加工データ</a>（2026-08-04.1）。CC BY 4.0。属性を整理して使用。</p></details>`;
    renderAreaGrid();
  } catch (e) {
    if ($("#contentPage").dataset.route === "エリアバッジ")
      $("#pageBody").innerHTML = '<p class="subtle">' + esc(e.message) + "</p>";
  }
}
function renderAreaGrid() {
  const el = $("#areaGrid");
  if (!el) return;
  const q = $("#areaSearch")?.value.trim() || "",
    stats = areaState.stats.filter((s) => (s.name + s.parent).includes(q));
  el.innerHTML = stats.length
    ? stats
        .map((s) => {
          const feature = areaState.index.collection.features.find(
            (f) => f.properties.id === s.id,
          );
          return `<button class="area-card ${config.areaFinish || "ink"}" data-area="${esc(s.id)}"><span class="area-shape">${areaSVG(feature, 100, s.cells)}</span><strong>${esc(s.name)}</strong><small>${esc(s.parent)}</small><small>${s.walks} さんぽ · ${fmt(s.distance)} ${distanceUnit()}</small></button>`;
        })
        .join("")
    : `<div class="empty-state" style="grid-column:1/-1">${q ? "一致する街はありません。" : "まだ街のバッジがありません。<br>日本の街を歩くと、その輪郭が集まります。"}</div>`;
}
function areaDetail(areaID) {
  const stat = areaState.stats.find((s) => s.id === areaID),
    feature = areaState.index?.collection.features.find(
      (f) => f.properties.id === areaID,
    );
  if (!stat || !feature) return;
  sheet(
    stat.name,
    `<div class="area-detail ${config.areaFinish || "ink"}"><span class="area-shape">${areaSVG(feature, 100, stat.cells, data.walks)}</span></div><p class="center subtle">${esc(stat.parent)}</p><div class="stats-row"><div><b>${stat.walks}</b><small>さんぽ</small></div><div><b>${fmt(stat.distance)}</b><small>街の中の道 ${distanceUnit()}</small></div></div><p class="center subtle">はじめて歩いた日 ${new Date(stat.first).toLocaleDateString("ja-JP")}<br>最近歩いた日 ${new Date(stat.last).toLocaleDateString("ja-JP")}</p><button class="primary" data-area-map="${esc(areaID)}">この街を白地図で見る</button><p class="caption-note">${stat.cells.length} 区画（500 m 四方）を歩いています。距離は軌跡を 25 m ごとに区切り、区間の中点で境界と照合した近似値です。バッジの質感は独自実装です。</p>`,
  );
}

function steps() {
  const d = data.notes[today()] || {};
  sheet(
    "歩数と目標",
    `${native ? '<button class="primary" data-action="healthSteps">今日の歩数を更新</button><p class="subtle">「取得」を押すと読み取りを許可した歩数をこの端末に保存します。データがない場合と読み取り未許可は区別できません。</p>' : '<p class="subtle">Web アプリから Apple ヘルスケアの歩数は取得できません。iPhone のヘルスケアなどを見て、今日の歩数を入力できます。</p>'}<label class="form-label">今日の歩数</label><input id="manualSteps" type="number" min="0" max="100000" value="${Number(d.steps) || 0}" inputmode="numeric"><label class="form-label">1 日の目標</label><input id="stepGoal" type="number" min="100" max="100000" value="${Number(config.goal) || 5000}" inputmode="numeric"><button class="primary" data-action="stepsSave">保存</button><p class="subtle">${d.steps ? `現在 ${Math.min(100, Math.round((d.steps / config.goal) * 100))}% 達成` : "未入力の歩数は「—」と表示します。"}</p>`,
  );
}
let replayPoints = [],
  replayIndex = 0;
function replay(walkId) {
  const walks = walkId ? data.walks.filter((w) => w.id === walkId) : data.walks;
  replayPoints = [];
  for (const w of walks)
    w.points.forEach((p, i) =>
      replayPoints.push({ ...p, break: p.break || i === 0 }),
    );
  if (!replayPoints.length) {
    toast("再生するさんぽの記録がありません。");
    return;
  }
  sheet(
    "地図の成長",
    `<div id="replayCanvas">${miniSvg(replayPoints, "replay-map")}</div><input type="range" id="replayRange" min="0" max="${replayPoints.length}" value="0" style="width:100%" aria-label="再生位置"><p class="center subtle" id="replayLabel">0 / ${replayPoints.length}</p><button class="primary" data-action="replayToggle">▶ 再生</button><button class="secondary" data-action="exportReplayVideo">動画にして保存</button><p class="caption-note">動画の書き出しは対応するブラウザで利用できます。共有前に道や位置情報をご確認ください。</p>`,
  );
  replayIndex = 0;
  const original = $("#replayCanvas path");
  if (original) {
    const len = original.getTotalLength();
    original.style.strokeDasharray = len;
    original.style.strokeDashoffset = len;
  }
}
function updateReplay() {
  const path = $("#replayCanvas path");
  if (!path) return;
  const total = path.getTotalLength();
  path.style.strokeDashoffset = total * (1 - replayIndex / replayPoints.length);
  $("#replayRange").value = replayIndex;
  $("#replayLabel").textContent = `${replayIndex} / ${replayPoints.length}`;
}
function replayToggle() {
  if (replayTimer) {
    clearInterval(replayTimer);
    replayTimer = null;
    return;
  }
  if (replayIndex >= replayPoints.length) replayIndex = 0;
  replayTimer = setInterval(() => {
    replayIndex = Math.min(
      replayPoints.length,
      replayIndex + Math.max(1, Math.ceil(replayPoints.length / 150)),
    );
    updateReplay();
    if (replayIndex >= replayPoints.length) {
      clearInterval(replayTimer);
      replayTimer = null;
    }
  }, 40);
}
function download(blob, name) {
  if (native) {
    nativeDownload(blob, name).catch((e) => toast(e.message));
    return;
  }
  const url = URL.createObjectURL(blob),
    a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}
function backup() {
  const blob = new Blob(
    [JSON.stringify({ ...data, exportedAt: new Date().toISOString() })],
    { type: "application/json" },
  );
  download(blob, `plainwalk-backup-${today()}.json`);
  toast(
    "バックアップを書き出しました。iPhone では「ファイル」に保存してください。",
  );
}
async function handleImport(file) {
  if (!file) return;
  if (file.size > 45 * 1024 * 1024)
    throw Error("45 MB 以下のファイルを選んでください。");
  const text = await file.text();
  if (/\.json$/i.test(file.name) || text.trim().startsWith("{")) {
    const value = JSON.parse(text);
    if (value.type === "plainwalk-white-map" && value.version === 1) {
      await collections.importWhiteMap(value);
      return;
    }
    const incoming = validateBackup(value);
    const newWalks = incoming.walks.filter(
      (w) => !data.walks.some((p) => p.id === w.id),
    );
    pendingImport = incoming;
    sheet(
      "バックアップを取り込む",
      `<p>${incoming.walks.length} 回のさんぽ、${incoming.spots.length} 件のピン、${incoming.flags.length} 本の旗を確認しました。</p><p class="subtle">今あるデータに追加します。同じ ID の記録は重複させません。新しく加わるさんぽは ${newWalks.length} 回です。ノートは未登録の日付だけ追加します。</p><button class="primary" data-action="restore">確認して取り込む</button>`,
    );
    return;
  }
  const points = parseTrack(text);
  for (let i = 1; i < points.length; i++)
    if (!points[i].break && distance(points[i - 1], points[i]) > 10000)
      points[i].break = true;
  pendingImport = {
    id: id(),
    name: file.name.replace(/\.[^.]+$/, ""),
    start: points.reduce((n, p) => Math.min(n, p.t), Infinity),
    end: points.reduce((n, p) => Math.max(n, p.t), 0),
    points,
    note: "",
    stickers: "",
  };
  sheet(
    "歩行の記録を取り込む",
    `${miniSvg(points, "walk-thumbnail")}<p>${esc(file.name)}</p><div class="stats-row"><div><b>${fmt(trailDistance(points))}</b><small>距離 ${distanceUnit()}</small></div><div><b>${points.length.toLocaleString()}</b><small>記録点</small></div></div><button class="primary" data-action="importTrack">この道を白地図に残す</button>`,
  );
}
let pendingImport = null;
async function restore() {
  if (!pendingImport?.walks) return;
  const incoming = pendingImport;
  const prev = structuredClone(data);
  for (const key of [
    "walks",
    "spots",
    "flags",
    "bookmarks",
    "doodles",
    "sharedMaps",
  ])
    (data[key] ||= []).push(
      ...(incoming[key] || []).filter(
        (w) => !data[key].some((p) => p.id === w.id),
      ),
    );
  data.walks.sort((a, b) => a.start - b.start);
  data.notes = { ...incoming.notes, ...data.notes };
  try {
    await save();
    pendingImport = null;
    closeSheet();
    switchTab("records");
    toast("バックアップを取り込みました。");
  } catch {
    data = prev;
  }
}
async function shareCard(walkId) {
  const w = data.walks.find((w) => w.id === walkId);
  if (!w) return;
  sheet(
    "さんぽのカード",
    `<div id="sharePreview">${miniSvg(w.points, "walk-thumbnail")}</div><p class="center">${esc(w.name)} · ${fmt(trailDistance(w.points))} ${distanceUnit()}</p><label class="form-label">サイズ</label><select id="shareSize"><option value="square">正方形</option><option value="story">ストーリー</option></select><button class="primary" data-card-download="${esc(w.id)}">画像を保存</button>`,
  );
}
async function exportCard(walkId) {
  const w = data.walks.find((w) => w.id === walkId);
  if (!w) return;
  const story = $("#shareSize")?.value === "story",
    c = document.createElement("canvas");
  c.width = 1080;
  c.height = story ? 1920 : 1080;
  const ctx = c.getContext("2d"),
    theme = themes[config.theme] || themes[0];
  ctx.fillStyle = theme[1];
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = theme[2];
  ctx.font = "20px -apple-system, sans-serif";
  ctx.textAlign = "center";
  ctx.fillText("P L A I N W A L K", 540, 105);
  const ps = w.points.map(project);
  let minx = Infinity,
    maxx = -Infinity,
    miny = Infinity,
    maxy = -Infinity;
  for (const [x, y] of ps) {
    minx = Math.min(minx, x);
    maxx = Math.max(maxx, x);
    miny = Math.min(miny, y);
    maxy = Math.max(maxy, y);
  }
  const mapH = c.height - 440,
    scale = Math.max((maxx - minx) / 790, (maxy - miny) / mapH, 1);
  ctx.strokeStyle = theme[2];
  ctx.lineWidth = config.line === "bold" ? 5 : 3;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  if (config.line === "dashed") ctx.setLineDash([8, 10]);
  ctx.beginPath();
  ps.forEach(([x, y], i) => {
    const sx = (x - (minx + maxx) / 2) / scale + 540,
      sy = (c.height - 100) / 2 - (y - (miny + maxy) / 2) / scale;
    !i || w.points[i].break ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy);
  });
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.font = "bold 49px -apple-system,sans-serif";
  ctx.fillText(w.name.slice(0, 20), 540, c.height - 190);
  ctx.font = "25px -apple-system,sans-serif";
  ctx.fillText(
    `${new Date(w.start).toLocaleDateString("ja-JP")}   ·   ${fmt(trailDistance(w.points))} ${distanceUnit()}   ·   開拓 ${fmt(exp.byWalk[w.id])} ${distanceUnit()}`,
    540,
    c.height - 125,
  );
  ctx.font = "16px -apple-system,sans-serif";
  ctx.fillText("歩いた道が、あなたの地図になる。", 540, c.height - 65);
  c.toBlob((blob) => {
    if (blob) download(blob, `plainwalk-${dateKey(w.start)}.png`);
  }, "image/png");
}
async function exportNote(day) {
  captureNoteDraft();
  const note = noteDraft?.day === day ? noteDraft : { day, ...data.notes[day] },
    canvas = document.createElement("canvas");
  await drawNotebook(canvas, note);
  canvas.toBlob(
    (blob) => blob && download(blob, `plainwalk-note-${day}.png`),
    "image/png",
  );
}

function limitations() {
  sheet(
    "iOS と Web 版の対応範囲",
    `<p>このアプリは、公式アプリの公開情報を参考に制作した非公式 Web 移植版です。寸分違わない完全再現には至っていません。</p><h3>利用できる機能</h3><p>前面での GPS 記録、白地図、履歴、開拓距離の近似計算、答え合わせ、写真・短い動画のピン、複数の旗、ノート、軌跡の手動修正、軌跡再生、対応ブラウザでの再生動画出力、画像・GPX の書き出し、GPX / TCX の取り込み、バックアップ、配色・線・カスタム LUT。</p><h3>Web ではネイティブ版と同じにできない機能</h3><p>画面ロック中の継続的な GPS、Live Activities、Apple Watch、ウィジェット、HealthKit と iCloud の直接連携、自宅からの自動記録、バックグラウンドの移動検知。</p><h3>追加した iOS プロジェクト</h3><p>Core Location のバックグラウンド記録、端末内ファイル保存、HealthKit の歩数・ワークアウト取り込み、ActivityKit、MapKit の立体・航空写真表示、ファイル共有のコードを同梱しています。GitHub で Xcode ビルド、iPhone シミュレーターの起動と記録の復元テストを通過しました。実機動作は未検証です。この Web サイトだけでネイティブ機能が使えるわけではありません。</p><h3>この実装で未対応の機能</h3><p>日本以外の市区町村バッジ、公式と同じ立体造形、道路への自動補正、共有の白地図の自動同期、近接によるステッカー交換、Apple Watch アプリ、通常のウィジェット、自宅からの自動記録。Web の傾斜表示は建物の 3D 表示ではありません。動画ピンのフィルム加工は未対応です。</p><p class="subtle">iPhone では Safari の共有メニューから「ホーム画面に追加」でアプリとして開けます。初回読み込み後の白地図と保存済み記録はオフラインで利用できます。答え合わせには通信が必要です。</p>`,
  );
}
function about() {
  sheet(
    "PlainWalk Web について",
    `<p>歩いた道だけが描かれる、白地図の Web アプリ。公式 PlainWalk とは別の非公式実装です。</p><p>この Web 版には有料プラン、購入ボタン、広告はありません。実装済みのカスタマイズと複数の旗は無料で利用できます。設定で beta 機能を有効にできます。</p><h3>調査した一次資料</h3><p><a href="https://plainwalk.app/" target="_blank" rel="noopener">PlainWalk 公式サイト</a><br><a href="https://apps.apple.com/jp/app/id6800746478" target="_blank" rel="noopener">App Store の説明とスクリーンショット</a><br><a href="https://note.com/plainwalk/n/nab36140b7cf1" target="_blank" rel="noopener">公式 note：PlainWalk でできること</a><br><a href="https://note.com/plainwalk/n/nf160cabe8248" target="_blank" rel="noopener">公式 note：旅行で使うコツ</a></p><p class="subtle">調査日：2026年10月29日。公式のコードや非公開の内部仕様は使用していません。映像検索も実施しましたが、操作を網羅した動画は確認できていません。</p>${row("limitations", "対応範囲と未実装機能", "info")}<h3>プライバシー</h3><p class="subtle">Web は IndexedDB、同梱の iOS アプリは端末内の保護されたファイルに記録・写真を保存する実装です。答え合わせを開いたときだけ、表示範囲の地図タイルを OpenStreetMap から取得します。位置の経路・写真をアプリのサーバーへ送信する処理はありません。</p>`,
  );
}
function demo() {
  if (active) {
    toast("記録中は体験モードに入れません。先に記録を終了してください。");
    return;
  }
  closeSheet();
  switchTab("map");
  mapMode = "demo";
  selectedWalk = null;
  current = { lat: 35.6762, lon: 139.6503, t: Date.now() };
  accuracy = 0;
  [view.x, view.y] = project(current);
  view.zoom = 16;
  demoPoints = [{ ...current }];
  $("#mapBanner").hidden = false;
  $("#mapBanner").textContent =
    "体験モード · 地図をタップして歩く · ここを押すと終了";
  $("#mapBanner").onclick = endDemo;
  draw();
}
let demoPoints = [];
function endDemo() {
  mapMode = "normal";
  demoPoints = [];
  current = null;
  $("#mapBanner").hidden = true;
  $("#mapBanner").onclick = null;
  draw();
  toast("体験モードを終了しました。体験の道は保存しません。");
}
const collections = createCollections({
  $,
  esc,
  icon,
  row,
  miniSvg,
  save,
  sheet,
  openPage,
  switchTab,
  draw,
  fit,
  id,
  toast,
  download,
  project,
  screenToPoint,
  paths,
  closeSheet,
  pickMode,
  state: () => ({ data, active, answer, editing }),
  setFollow: (value) => {
    follow = value;
  },
  setAnswer: (value) => {
    answer = value;
    $("#attribution").hidden = !value;
    $("#answerButton").style.background = value ? "var(--wash)" : "";
    draw();
  },
});
const developer = createDeveloperUI({
  $,
  esc,
  openPage,
  trace,
  native,
  nativeCall,
  saveConfig,
  download,
  toast,
  state: () => ({
    config,
    recording: !!active && !paused,
    paused: !!active && paused,
    activePoints: active?.points.length || 0,
    accuracy,
    fixAgeMs: current ? Math.max(0, Date.now() - current.t) : null,
    walks: data.walks.length,
    points: data.walks.reduce((n, w) => n + w.points.length, 0),
  }),
  storageProbe: async () => {
    if (!db) throw Error("No storage");
    const key = "diagnostics-probe",
      value = { id: crypto.randomUUID(), time: Date.now() };
    try {
      await write(key, value);
      const result = await read(key);
      if (result?.id !== value.id) throw Error("Round trip failed");
    } finally {
      await new Promise((resolve, reject) => {
        const tx = db.transaction("data", "readwrite");
        tx.objectStore("data").delete(key);
        tx.oncomplete = resolve;
        tx.onerror = () => reject(tx.error);
      });
    }
  },
});
developer.apply();
const actions = {
  ...developer.actions,
  ...collections.actions,
  pageBack: pageBack,
  back: sheetBack,
  healthSteps: async () => {
    const result = await nativeCall(
      config.healthEnabled ? "healthSteps" : "pedometerSteps",
    );
    if (result.steps === null) {
      toast(
        "読み取れる歩数がありません。ヘルスケアの共有設定を確認してください。",
      );
      return;
    }
    data.notes[today()] = {
      ...data.notes[today()],
      steps: Math.round(result.steps),
    };
    await save();
    steps();
  },
  healthImport: healthImport,
  nativeRestore: async () => {
    const text = await nativeCall("restoreFile");
    if (text)
      await handleImport(
        new File([text], "backup.json", { type: "application/json" }),
      );
  },
  nativeMap: () => showNativeMap(false),
  nativeSatellite: () => showNativeMap(true),
  close: closeSheet,
  menu,
  record: async () => {
    if (active) await pauseToggle();
    else recordMenu();
  },
  recordOptions: recordMenu,
  begin,
  finish: stopWalk,
  pause: pauseToggle,
  settings,
  notificationSettings: () => settings(true),
  nativeDeveloper: () => nativeCall("showNativeDeveloper"),
  nativeImport: async () => {
    const file = await nativeCall("importFile");
    if (file?.text)
      await handleImport(
        new File([file.text], file.name || "track.gpx", {
          type: "application/xml",
        }),
      );
  },
  layers,
  flags,
  spots,
  notes: () => notes(),
  weeklyReview: () => {
    const start = new Date();
    start.setDate(start.getDate() - start.getDay());
    start.setHours(0, 0, 0, 0);
    const end = new Date(start);
    end.setDate(end.getDate() + 7);
    const walks = data.walks.filter((w) => w.start >= +start && w.start < +end);
    sheet(
      "今週のふりかえり",
      `<p class="center subtle">${start.toLocaleDateString("ja-JP")} からの一週間</p><div class="stats-row"><div><b>${walks.length}</b><small>さんぽ</small></div><div><b>${fmt(walks.reduce((n, w) => n + trailDistance(w.points), 0))}</b><small>歩いた距離 ${distanceUnit()}</small></div><div><b>${fmt(walks.reduce((n, w) => n + (exp.byWalk[w.id] || 0), 0))}</b><small>開拓した道 ${distanceUnit()}</small></div></div>${walks.length ? walks.map((w) => `<button class="walk-card" data-walk="${esc(w.id)}">${miniSvg(w.points)}<span class="stack"><strong>${esc(w.name)}</strong><small>${new Date(w.start).toLocaleDateString("ja-JP")}</small></span></button>`).join("") : '<p class="center subtle">今週の最初の一歩を、白地図に。</p>'}<button class="secondary" data-action="notes">今日のノートを書く</button>`,
    );
  },
  stats,
  badges,
  steps,
  replay: () => replay(),
  replayToggle,
  about,
  limitations,
  demo,
  backup,
  zoomIn: () => {
    view.zoom = Math.min(19, view.zoom + 1);
    draw();
  },
  zoomOut: () => {
    view.zoom = Math.max(3, view.zoom - 1);
    draw();
  },
  locate: () => {
    if (mapMode === "demo") endDemo();
    follow = true;
    startWatch();
    if (current) {
      [view.x, view.y] = project(current);
      draw();
    }
  },
  answer: () => {
    answer = !answer;
    $("#attribution").hidden = !answer;
    $("#answerButton").style.background = answer ? "var(--wash)" : "";
    closeSheet();
    draw();
    if (answer) toast("答え合わせ · 地図タイルの取得に通信を使います。");
  },
  tilt: () => {
    $("#mapViewport").classList.toggle("tilt");
    closeSheet();
  },
  allMap: () => {
    selectedWalk = null;
    closeSheet();
    switchTab("map");
    const ps = data.walks.flatMap((w) => w.points);
    if (ps.length) fit(ps);
  },
  flagAdd: () => flagAdd(),
  flagPick: () => pickMode("flag"),
  spotPick: () => pickMode("spot"),
  spot: () => addSpot(),
  spotLocate: () => {
    closeSheet();
    actions.locate();
    toast("現在地を取得したら、もう一度「ここいいな」を押してください。");
  },
  flagSave: async () => {
    const latText = $("#flagLat").value,
      lonText = $("#flagLon").value,
      p = { lat: Number(latText), lon: Number(lonText) };
    if (!latText || !lonText || !validPoint(p)) {
      toast("有効な緯度・経度を入力してください。");
      return;
    }
    data.flags.push({
      id: id(),
      name: $("#flagName").value.trim() || "行きたい場所",
      ...p,
    });
    await save();
    flags();
    draw();
  },
  stepsSave: async () => {
    const n = Number($("#manualSteps").value),
      goal = Number($("#stepGoal").value);
    if (
      !Number.isInteger(n) ||
      n < 0 ||
      n > 100000 ||
      !Number.isInteger(goal) ||
      goal < 100 ||
      goal > 100000
    ) {
      toast("歩数は 0〜100000、目標は 100〜100000 で入力してください。");
      return;
    }
    data.notes[today()] = { ...data.notes[today()], steps: n };
    config.goal = goal;
    await save();
    await saveConfig();
    closeSheet();
    toast("歩数を保存しました。");
  },
  prevMonth: () => {
    month = new Date(month.getFullYear(), month.getMonth() - 1, 1);
    renderRecords();
  },
  nextMonth: () => {
    month = new Date(month.getFullYear(), month.getMonth() + 1, 1);
    renderRecords();
  },
  import: () => $("#importFile").click(),
  restore,
  importTrack: async () => {
    if (!pendingImport?.points) return;
    data.walks.push(pendingImport);
    data.walks.sort((a, b) => a.start - b.start);
    await save();
    fit(pendingImport.points);
    pendingImport = null;
    closeSheet();
    switchTab("records");
    toast("歩いた道を取り込みました。");
  },
  discardConfirm: () =>
    sheet(
      "記録を破棄しますか？",
      '<p>記録中の道は保存されません。</p><button class="primary danger-button" data-action="discard">この記録を破棄</button><button class="secondary" data-action="close">戻る</button>',
    ),
  discard: async () => {
    active = null;
    paused = false;
    clearWatch();
    await persistActive();
    closeSheet();
    updateStats();
  },
  tweet: () => addSpot(current),
  clearStickers: () => {
    $("#noteStickers").textContent = "";
  },
  gpxExportAll: () => {
    if (!data.walks.length) {
      toast("書き出す記録がありません。");
      return;
    }
    const merged = {
      name: "すべてのさんぽ",
      points: data.walks.flatMap((w) =>
        w.points.map((p, i) => ({ ...p, break: p.break || i === 0 })),
      ),
    };
    download(
      new Blob([gpx(merged)], { type: "application/gpx+xml" }),
      "plainwalk-all.gpx",
    );
  },
  diagnostics: () =>
    sheet(
      "記録の診断",
      `<p>保存先：${native ? "iOS 端末内ファイル" : "IndexedDB"} ${db ? "利用可能" : "利用不可"}<br>位置情報：${navigator.geolocation ? "対応" : "未対応"}<br>画面スリープ防止：${"wakeLock" in navigator ? "対応" : "未対応"}<br>記録：${data.walks.length} 回<br>記録点：${data.walks.reduce((n, w) => n + w.points.length, 0).toLocaleString()} 点<br>GPS 精度：${accuracy ? "±" + Math.round(accuracy) + " m" : "未取得"}<br>状態：${esc(geoError || "通常")}</p><p class="subtle">GPS 精度が 60 m より悪い点、3 m 未満の揺れ、秒速 45 m を超える飛びは記録しません。2 分以上空いた位置は線をつなぎません。</p>`,
    ),
  storage: async () => {
    const e = await navigator.storage?.estimate?.();
    sheet(
      "保存領域",
      `<p>使用量：${e?.usage ? (e.usage / 1024 / 1024).toFixed(1) + " MB" : "不明"}<br>利用上限：${e?.quota ? (e.quota / 1024 / 1024).toFixed(0) + " MB" : "不明"}</p><p class="subtle">容量の表示はブラウザ全体の推定値です。端末の空き容量によって変わります。</p><button class="primary" data-action="persistStorage">保存データの保持をリクエスト</button><button class="secondary" data-action="backup">バックアップを書き出す</button>`,
    );
  },
  persistStorage: async () =>
    toast(
      (await navigator.storage?.persist?.())
        ? "保存データの保持が許可されました。"
        : "ブラウザから保持の許可が得られませんでした。バックアップをご利用ください。",
    ),
};
function pickMode(type) {
  closeSheet();
  switchTab("map");
  mapMode = type;
  $("#mapBanner").textContent =
    type === "flag"
      ? "旗を立てる場所をタップ"
      : type === "bookmark"
        ? "しおりを挟む場所をタップ"
        : "ここいいなを残す場所をタップ";
  $("#mapBanner").hidden = false;
}
async function handleClick(e) {
  const tabEl = e.target.closest("[data-tab]");
  if (tabEl) {
    switchTab(tabEl.dataset.tab);
    return;
  }
  const b = e.target.closest("button,[data-spot],[data-flag]");
  if (!b) return;
  const d = b.dataset;
  if (await developer.click(d)) return;
  if (await collections.click(d)) return;
  if (d.action) {
    if (d.action === "record" && suppressRecordClick) {
      suppressRecordClick = false;
      return;
    }
    await actions[d.action]?.();
    return;
  }
  if (d.movementPolicy) {
    await movementPolicy(d.movementPolicy);
    return;
  }
  if (d.layerKey) {
    const key = d.layerKey;
    config[key] = key === "theme" ? Number(d.layerValue) : d.layerValue;
    await saveConfig();
    $$("[data-layer-key]")
      .filter((el) => el.dataset.layerKey === key)
      .forEach((el) => {
        const chosen = el.dataset.layerValue === d.layerValue;
        el.classList.toggle("chosen", chosen);
        el.setAttribute("aria-pressed", String(chosen));
      });
    return;
  }
  if (d.spotMode) {
    $("#spotPhotoPanel").hidden = d.spotMode !== "photo";
    $("#spotVideoPanel").hidden = d.spotMode !== "video";
    $$("[data-spot-mode]").forEach((el) =>
      el.classList.toggle("chosen", el.dataset.spotMode === d.spotMode),
    );
    return;
  }
  if (d.spotFilter) {
    $("#spotFilm").value = d.spotFilter;
    $$("[data-spot-filter]").forEach((el) =>
      el.classList.toggle("chosen", el.dataset.spotFilter === d.spotFilter),
    );
    if (pendingPhoto)
      $("#spotPreview").src = await resizePhoto(pendingPhoto, d.spotFilter);
    return;
  }
  if (d.spotCategory) {
    $("#spotEmoji").value = d.spotCategory;
    $$("[data-spot-category]").forEach((el) =>
      el.classList.toggle("chosen", el.dataset.spotCategory === d.spotCategory),
    );
    return;
  }
  if (d.notePhoto) {
    const p = data.spots.find((p) => p.id === d.notePhoto);
    if (p?.photo) {
      if (d.cutout === "yes") await cutoutPhoto(p.photo);
      else await addNoteImage(p.photo);
    }
    return;
  }
  if (d.area) {
    areaDetail(d.area);
    return;
  }
  if (d.areaMap) {
    const f = areaState.index.collection.features.find(
      (f) => f.properties.id === d.areaMap,
    );
    const [a, b, c, d1] = f.bbox;
    closeSheet();
    switchTab("map");
    fit([
      { lat: b, lon: a },
      { lat: d1, lon: c },
    ]);
    return;
  }
  if (d.areaFinish) {
    config.areaFinish = d.areaFinish;
    await saveConfig();
    $$("[data-area-finish]").forEach((el) =>
      el.classList.toggle("chosen", el.dataset.areaFinish === d.areaFinish),
    );
    renderAreaGrid();
    return;
  }
  if (d.theme !== undefined) {
    config.theme = Number(d.theme);
    await saveConfig();
    layers();
    return;
  }
  for (const key of ["line", "pin", "cat"])
    if (d[key]) {
      config[key] = d[key];
      await saveConfig();
      layers();
      if (tab === "profile" && !$("#contentPage").dataset.route)
        renderProfile();
      return;
    }
  if (d.editWalk) {
    beginEdit(d.editWalk);
    return;
  }
  if (d.walk) {
    detail(d.walk);
    return;
  }
  if (d.day) {
    const walks = data.walks.filter((w) => dateKey(w.start) === d.day);
    sheet(
      d.day,
      `${walks.length ? walks.map((w) => `<button class="walk-card" data-walk="${esc(w.id)}">${miniSvg(w.points)}<span class="stack">${esc(w.name)}<b>${fmt(trailDistance(w.points))} ${distanceUnit()}</b></span></button>`).join("") : '<p class="subtle">この日の記録はありません。</p>'}<button class="secondary" data-day-note="${d.day}">この日のノート</button>`,
    );
    return;
  }
  if (d.dayNote) {
    notes(d.dayNote);
    return;
  }
  if (d.saveWalk) {
    const w = data.walks.find((w) => w.id === d.saveWalk);
    if (w) {
      w.name = $("#walkName").value.trim() || "さんぽ";
      w.note = $("#walkNote").value;
      await save();
      detail(w.id);
      if (tab === "records") renderRecords();
      toast("変更を保存しました。");
    }
    return;
  }
  if (d.mapWalk) {
    const w = data.walks.find((w) => w.id === d.mapWalk);
    closeSheet();
    selectedWalk = w.id;
    switchTab("map");
    fit(w.points);
    $("#mapBanner").hidden = false;
    $("#mapBanner").textContent = w.name + " · タップですべて表示";
    $("#mapBanner").onclick = () => {
      selectedWalk = null;
      $("#mapBanner").hidden = true;
      draw();
    };
    return;
  }
  if (d.replayWalk) {
    replay(d.replayWalk);
    return;
  }
  if (d.shareWalk) {
    shareCard(d.shareWalk);
    return;
  }
  if (d.cardDownload) {
    exportCard(d.cardDownload);
    return;
  }
  if (d.gpxWalk) {
    const w = data.walks.find((w) => w.id === d.gpxWalk);
    if (w)
      download(
        new Blob([gpx(w)], { type: "application/gpx+xml" }),
        `plainwalk-${dateKey(w.start)}.gpx`,
      );
    return;
  }
  if (d.deleteWalk) {
    sheet(
      "この記録を削除しますか？",
      '<p>このさんぽの道が白地図からなくなります。写真ピンは残ります。</p><button class="primary danger-button" data-confirm-delete="' +
        esc(d.deleteWalk) +
        '">削除する</button><button class="secondary" data-action="close">キャンセル</button>',
    );
    return;
  }
  if (d.confirmDelete) {
    data.walks = data.walks.filter((w) => w.id !== d.confirmDelete);
    if (selectedWalk === d.confirmDelete) selectedWalk = null;
    await save();
    closeSheet();
    if (tab === "records") renderRecords();
    if (tab === "profile" && !$("#contentPage").dataset.route) renderProfile();
    draw();
    return;
  }
  if (d.flagDetail || d.flag) {
    flagDetail(d.flagDetail || d.flag);
    return;
  }
  if (d.flagRemove) {
    data.flags = data.flags.filter((f) => f.id !== d.flagRemove);
    await save();
    flags();
    draw();
    return;
  }
  if (d.flagUp) {
    const i = data.flags.findIndex((f) => f.id === d.flagUp);
    if (i > 0)
      [data.flags[i - 1], data.flags[i]] = [data.flags[i], data.flags[i - 1]];
    await save();
    flags();
    draw();
    return;
  }
  if (d.flagView || d.spotView) {
    const p = (d.flagView ? data.flags : data.spots).find(
      (p) => p.id === (d.flagView || d.spotView),
    );
    if (p) {
      closeSheet();
      switchTab("map");
      [view.x, view.y] = project(p);
      view.zoom = 17;
      follow = false;
      draw();
    }
    return;
  }
  if (d.flagShare) {
    const p = data.flags.find((p) => p.id === d.flagShare),
      text = `${p.name}\n${p.lat}, ${p.lon}\nhttps://www.openstreetmap.org/?mlat=${p.lat}&mlon=${p.lon}#map=17/${p.lat}/${p.lon}`;
    if (navigator.share)
      await navigator.share({ title: p.name, text }).catch((err) => {
        if (err.name !== "AbortError") toast("共有できませんでした。");
      });
    else {
      await navigator.clipboard.writeText(text);
      toast("旗の座標をコピーしました。");
    }
    return;
  }
  if (d.spot) {
    spotDetail(d.spot);
    return;
  }
  if (d.spotDelete) {
    sheet(
      "このピンを削除しますか？",
      `<p>写真とひとことを端末から削除します。</p><button class="primary danger-button" data-spot-confirm-delete="${esc(d.spotDelete)}">削除する</button><button class="secondary" data-action="close">キャンセル</button>`,
    );
    return;
  }
  if (d.spotConfirmDelete) {
    data.spots = data.spots.filter((p) => p.id !== d.spotConfirmDelete);
    await save();
    spots();
    draw();
    return;
  }
  if (d.videoDownload) {
    const p = data.spots.find((p) => p.id === d.videoDownload);
    if (p?.video) {
      const r = await fetch(p.video);
      download(
        await r.blob(),
        `plainwalk-spot-${dateKey(p.t)}.${p.video.startsWith("data:video/mp4") ? "mp4" : "webm"}`,
      );
    }
    return;
  }
  if (d.spotDownload) {
    const p = data.spots.find((p) => p.id === d.spotDownload);
    if (p?.photo) {
      const r = await fetch(p.photo);
      download(await r.blob(), `plainwalk-spot-${dateKey(p.t)}.jpg`);
    }
    return;
  }
  if (d.sticker) {
    const el = $("#noteStickers");
    if ([...el.textContent].length < 60) el.textContent += d.sticker;
    captureNoteDraft();
    paintNote();
    return;
  }
  if (d.saveNote) {
    captureNoteDraft();
    data.notes[d.saveNote] = {
      ...data.notes[d.saveNote],
      ...structuredClone(noteDraft),
    };
    await save();
    toast("ノートを保存しました。");
    return;
  }
  if (d.shareNote) {
    exportNote(d.shareNote);
    return;
  }
  if (d.bar) toast(d.bar);
}
document.addEventListener("click", (e) => {
  handleClick(e).catch((err) => {
    trace.record("error", { source: "ui", code: err.name || "Error" });
    console.error(err);
    toast(
      "操作を完了できませんでした。" +
        (err.message || "もう一度お試しください。"),
    );
  });
});
document.addEventListener("change", async (e) => {
  try {
    const el = e.target;
    if (await developer.change(el)) return;
    if (el.dataset.mapConfig) {
      const key = el.dataset.mapConfig;
      if (
        [
          "registeredPlaces",
          "stayDeparture",
          "morningNotification",
          "weeklyNotification",
          "interruptionNotification",
          "healthEnabled",
          "healthAutoSync",
          "healthSave",
        ].includes(key)
      ) {
        await configureNativeSetting(key, el);
        return;
      }
      if (key === "developerMode") {
        config.developerMode = el.checked;
        trace.enable(el.checked);
        trace.record("app", { status: "developerEnabled" });
        await saveConfig();
        developer.apply();
        settings();
        return;
      }
      if (key === "beta") {
        config.beta = el.checked;
        await saveConfig();
        settings();
        return;
      }
      if (key.startsWith("transport:")) {
        config.transportVisible = {
          ...config.transportVisible,
          [key.split(":")[1]]: el.checked,
        };
      } else config[key] = el.checked;
      if (key === "outline" && el.checked) await loadAreaIndex();
      await saveConfig();
      return;
    }
    if (el.dataset.config) {
      config[el.dataset.config] =
        el.type === "checkbox" ? el.checked : el.value;
      await saveConfig();
      if (el.dataset.config === "beta") settings();
      if (el.dataset.config === "wake") requestWake();
      if (tab === "profile" && !$("#contentPage").dataset.route)
        renderProfile();
    }
    if (el.id === "morningTime") {
      config.morningTime = el.value;
      await saveConfig();
      if (native && config.morningNotification)
        await nativeCall("notificationsConfigure", config);
    }
    if (el.id === "notePhotoFile" && el.files[0]) {
      const src = await resizePhoto(el.files[0]);
      if (el.dataset.cutout === "yes") await cutoutPhoto(src);
      else await addNoteImage(src);
    }
    if (["notePaper", "noteFont", "noteItemFinish"].includes(el.id)) {
      captureNoteDraft();
      if (el.id === "notePaper") noteDraft.paper = el.value;
      else if (el.id === "noteFont") noteDraft.font = el.value;
      else {
        const item = noteDraft.layout.find((i) => i.id === noteSelected);
        if (item) item.finish = el.value;
      }
      paintNote();
    }
    if (el.id === "importFile") {
      await handleImport(el.files[0]);
      el.value = "";
    }
    if (el.id === "spotVideo" && el.files[0]) {
      pendingVideo = await readVideo(el.files[0]);
      $("#spotVideoPreview").src = pendingVideo.data;
      $("#spotVideoPreview").hidden = false;
      if ($("#spotVideoPanel")) {
        $("#spotVideoPanel").hidden = false;
        $("#spotPhotoPanel").hidden = true;
        $$("[data-spot-mode]").forEach((b) =>
          b.classList.toggle("chosen", b.dataset.spotMode === "video"),
        );
      }
    }
    if (el.id === "spotPhoto") {
      const file = el.files[0];
      if (file) {
        pendingPhoto = file;
        $("#spotPreview").src = await resizePhoto(file);
        $("#spotPreview").hidden = false;
        if ($("#photoStageHint")) $("#photoStageHint").hidden = true;
      }
    }
    if (el.id === "spotFilm" && pendingPhoto) {
      $("#spotPreview").src = await resizePhoto(pendingPhoto, el.value);
      $("#spotPreview").style.filter = "none";
    }
    if (el.id === "spotLut" && el.files[0]) {
      if (el.files[0].size > 5000000)
        throw Error("LUT は 5 MB 以下で選んでください。");
      config.lut = parseCube(await el.files[0].text());
      await saveConfig();
      const option = document.createElement("option");
      option.value = "custom";
      option.textContent = "自分の LUT";
      $("#spotFilm").append(option);
      $("#spotFilm").value = "custom";
      if (pendingPhoto)
        $("#spotPreview").src = await resizePhoto(pendingPhoto, "custom");
      toast("自分の LUT を読み込みました。");
    }
  } catch (err) {
    toast(err.message || "読み込みに失敗しました。");
    if (e.target.id === "importFile") e.target.value = "";
  }
});
document.addEventListener("submit", async (e) => {
  if (e.target.id !== "spotForm") return;
  e.preventDefault();
  const form = e.target,
    button = form.querySelector("button[type=submit]");
  button.disabled = true;
  try {
    const text = $("#spotText").value.trim();
    if (!text && !pendingPhoto && !pendingVideo) {
      toast("写真かひとことを残してください。");
      button.disabled = false;
      return;
    }
    const photo = pendingPhoto
        ? await resizePhoto(pendingPhoto, $("#spotFilm").value)
        : null,
      p = {
        id: id(),
        lat: Number(form.dataset.lat),
        lon: Number(form.dataset.lon),
        t: Date.now(),
        text,
        photo: photo || pendingVideo?.poster || null,
        video: pendingVideo?.data || null,
        videoDuration: pendingVideo?.duration || null,
        emoji: $("#spotEmoji").value,
      };
    data.spots.push(p);
    try {
      await save();
    } catch (err) {
      data.spots.pop();
      throw err;
    }
    pendingPhoto = null;
    closeSheet();
    draw();
    toast("「ここいいな」を残しました。");
  } catch (err) {
    toast(err.message || "写真を保存できませんでした。");
    button.disabled = false;
  }
});
document.addEventListener("input", (e) => {
  if (e.target.id === "dailyNote") {
    captureNoteDraft();
    paintNote();
  }
  if (["noteItemSize", "noteItemRotation"].includes(e.target.id)) {
    const item = noteDraft?.layout.find((i) => i.id === noteSelected);
    if (item) {
      if (e.target.id === "noteItemSize") item.width = Number(e.target.value);
      else item.rotation = Number(e.target.value);
      paintNote();
    }
  }
  if (e.target.id === "areaSearch") renderAreaGrid();
  if (e.target.id === "replayRange") {
    clearInterval(replayTimer);
    replayTimer = null;
    replayIndex = Number(e.target.value);
    updateReplay();
  }
});
$("#overlay").addEventListener("pointerdown", (e) => {
  if (e.target === $("#overlay")) closeSheet();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeSheet();
  if (e.key === "Tab" && !$("#overlay").hidden) {
    const els = $$(
      "#sheet button:not(:disabled),#sheet input,#sheet textarea,#sheet select,#sheet a",
    );
    const first = els[0],
      last = els.at(-1);
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last?.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first?.focus();
    }
  }
  if (
    ["Enter", " "].includes(e.key) &&
    e.target.matches("[data-spot],[data-flag]")
  ) {
    e.preventDefault();
    handleClick({ target: e.target }).catch(() => {});
  }
});
// Panning and pinch zoom use projected coordinates, never alter saved GPS tracks.
const pointers = new Map();
let dragStart = null,
  dragged = false,
  pinchDist = 0,
  pinchZoom = 0;
const viewport = $("#mapViewport");
collections.attach(viewport);
viewport.addEventListener("pointerdown", (e) => {
  if (e.target.closest("[data-spot],[data-flag]")) return;
  viewport.setPointerCapture(e.pointerId);
  pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
  dragged = false;
  if (pointers.size === 1)
    dragStart = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y };
  if (pointers.size === 2) {
    const p = [...pointers.values()];
    pinchDist = Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y);
    pinchZoom = view.zoom;
    dragged = true;
  }
});
viewport.addEventListener("pointermove", (e) => {
  if (!pointers.has(e.pointerId)) return;
  pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (pointers.size === 2) {
    const p = [...pointers.values()],
      dist = Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y);
    view.zoom = Math.max(
      3,
      Math.min(19, pinchZoom + Math.log2(dist / Math.max(pinchDist, 1))),
    );
    dragged = true;
    follow = false;
    draw();
    return;
  }
  if (dragStart) {
    const dx = e.clientX - dragStart.x,
      dy = e.clientY - dragStart.y;
    if (Math.hypot(dx, dy) > 5) dragged = true;
    if (dragged) {
      follow = false;
      view.x = dragStart.vx - dx * metersPerPixel();
      view.y = Math.max(
        -20037508,
        Math.min(20037508, dragStart.vy + dy * metersPerPixel()),
      );
      draw();
    }
  }
});
viewport.addEventListener("pointerup", (e) => {
  const hadPointer = pointers.has(e.pointerId),
    wasMulti = pointers.size > 1;
  pointers.delete(e.pointerId);
  if (!hadPointer) return;
  if (!dragged && !wasMulti && !e.target.closest("[data-spot],[data-flag]")) {
    const r = viewport.getBoundingClientRect(),
      p = screenToPoint(e.clientX - r.left, e.clientY - r.top);
    if (["flag", "spot", "bookmark"].includes(mapMode)) {
      const type = mapMode;
      mapMode = "normal";
      $("#mapBanner").hidden = true;
      type === "flag"
        ? flagAdd(p)
        : type === "bookmark"
          ? collections.bookmarkAdd(p)
          : addSpot(p);
    } else if (mapMode === "demo") {
      current = { ...p, t: Date.now() };
      demoPoints.push(current);
      draw();
      requestAnimationFrame(() => {
        $("#trails").innerHTML =
          `<path d="${paths(demoPoints)}" stroke="var(--ink)" stroke-width="2"/>`;
        $("#emptyMap").hidden = true;
      });
      updateFlag();
    }
  }
  if (!pointers.size) dragStart = null;
  else {
    dragged = true;
    const p = [...pointers.values()][0];
    dragStart = { x: p.x, y: p.y, vx: view.x, vy: view.y };
  }
});
viewport.addEventListener("pointercancel", (e) => {
  pointers.delete(e.pointerId);
  dragStart = null;
  dragged = true;
});
viewport.addEventListener(
  "wheel",
  (e) => {
    e.preventDefault();
    view.zoom = Math.max(3, Math.min(19, view.zoom - e.deltaY * 0.003));
    follow = false;
    draw();
  },
  { passive: false },
);
window.addEventListener("resize", draw);
document.addEventListener("visibilitychange", () => {
  trace.record("visibility", {
    status: document.visibilityState,
    points: active?.points.length || 0,
  });
  if (document.visibilityState === "hidden") {
    if (active) persistActive();
    if (!active) clearWatch();
  } else {
    if (native) {
      syncNative().catch((e) => toast(e.message));
    } else if (active && !paused) {
      startWatch();
      requestWake();
      toast(
        "記録を再開しました。画面を閉じていた間の位置は取得できていない場合があります。",
        7000,
      );
    }
    updateStats();
  }
});
window.addEventListener("pagehide", () => {
  if (active) persistActive();
});
let statsDate = today();
setInterval(() => {
  if (active || statsDate !== today()) {
    statsDate = today();
    updateStats();
  }
}, 1000);
if ("serviceWorker" in navigator)
  navigator.serviceWorker.register("./sw.js").catch(() => {});
if (data.walks.length) fit(data.walks.flatMap((w) => w.points));
updateStats();
draw();
if (native) await syncNative(true);
if (active && paused) {
  active.pauseAt = active.pauseAt || active.points.at(-1)?.t || active.start;
  active.paused = true;
  persistActive();
  sheet(
    "中断したさんぽがあります",
    `<p>端末に保存された ${active.points.length} 点の記録が見つかりました。記録は一時停止しています。</p><button class="primary" data-action="pause">位置情報を許可して再開</button><button class="secondary" data-action="finish">ここまでを保存</button><button class="secondary danger-button" data-action="discardConfirm">記録を破棄</button>`,
  );
}

async function showNativeMap(satellite) {
  const points = (
    selectedWalk ? data.walks.filter((w) => w.id === selectedWalk) : data.walks
  ).flatMap((w) =>
    w.points.map((p, i) => ({ ...p, break: p.break || i === 0 })),
  );
  closeSheet();
  await nativeCall("showMap", { points, satellite });
}
async function healthImport() {
  sheet(
    "ヘルスケアのワークアウト",
    '<p class="subtle">ヘルスケアの読み取りを許可すると、最近の屋外ワークアウトからルートを選べます。</p><button class="primary" data-action="healthLoad">許可して読み込む</button>',
  );
}
let healthWorkouts = [];
actions.healthLoad = async () => {
  healthWorkouts = await nativeCall("healthWorkouts");
  sheet(
    "ワークアウトを白地図に",
    healthWorkouts.length
      ? healthWorkouts
          .map(
            (w) =>
              `<button class="row" data-health-route="${esc(w.id)}"><span class="grow stack"><strong>${new Date(w.start).toLocaleDateString("ja-JP")} ${time(w.start)}</strong><small>${fmt(w.distance)} ${distanceUnit()} · ${w.kind === "running" ? "ランニング" : w.kind === "cycling" ? "サイクリング" : "ウォーキング"}</small></span><span>›</span></button>`,
          )
          .join("")
      : "<p>読み取れるワークアウトがありません。共有の許可、ルートの有無を確認してください。</p>",
  );
};
document.addEventListener("click", async (e) => {
  const b = e.target.closest("[data-health-route]");
  if (!b) return;
  try {
    const w = healthWorkouts.find((w) => w.id === b.dataset.healthRoute);
    if (!w) return;
    if (data.walks.some((p) => p.healthID === w.id)) {
      toast("このワークアウトは取り込み済みです。");
      return;
    }
    b.disabled = true;
    const points = await nativeCall("healthRoute", { id: w.id });
    if (points.length < 2) {
      toast("共有された位置のルートがありません。");
      b.disabled = false;
      return;
    }
    pendingImport = {
      id: id(),
      healthID: w.id,
      name: "ヘルスケアのさんぽ",
      start: w.start,
      end: w.end,
      duration: w.duration * 1000,
      mode: w.kind,
      points: points.filter(validPoint),
      note: "",
      stickers: "",
    };
    sheet(
      "ワークアウトを取り込む",
      `${miniSvg(pendingImport.points, "walk-thumbnail")}<p>${fmt(trailDistance(pendingImport.points))} ${distanceUnit()}</p><button class="primary" data-action="importTrack">この道を白地図に残す</button>`,
    );
  } catch (e) {
    toast(e.message);
    b.disabled = false;
  }
});
async function syncNative(initial = false) {
  if (!native || syncNative.busy) return;
  syncNative.busy = true;
  try {
    const result = await nativeCall("status"),
      session = result.session;
    if (session) {
      if (!active && !data.walks.some((w) => w.id === session.id)) {
        active = {
          id: session.id,
          start: session.start,
          end: Date.now(),
          name: "さんぽ",
          points: [],
          note: "",
          pausedMs: 0,
          nativeSeq: 0,
        };
      }
      if (active?.id === session.id) {
        if (initial) {
          paused = !session.recording;
          active.paused = paused;
          if (!paused) delete active.pauseAt;
        }
        for (const point of session.points || [])
          consumeNativePoint(point, session.id);
        await persistActive();
      }
    }
    updateStats();
  } finally {
    syncNative.busy = false;
  }
}
function consumeNativePoint(point, sessionID) {
  if (!validPoint(point)) return;
  if (sessionID && active?.id !== sessionID) return;
  if (active && sessionID && point.seq <= (active.nativeSeq || 0)) return;
  current = {
    lat: point.lat,
    lon: point.lon,
    t: point.t,
    heading: point.heading || 0,
    mode: point.mode || "walking",
  };
  accuracy = point.accuracy || 0;
  geoError = "";
  if (follow) [view.x, view.y] = project(current);
  if (active && sessionID) {
    const last = active.points.at(-1);
    if (!last || point.t > last.t) {
      active.points.push({
        ...current,
        accuracy,
        break: point.gap || active.nextBreak || false,
      });
      delete active.nextBreak;
      trace.record("gps", {
        source: "native",
        status: "accepted",
        accuracy,
        points: active.points.length,
      });
      collections.progress({ ...current, accuracy });
    }
    active.nativeSeq = point.seq;
  }
  draw();
}
onNative((message) => {
  if (message.event === "configChanged") {
    config = { ...config, ...message.config };
    trace.enable(config.developerMode === true);
    saveConfig()
      .then(() => developer.apply())
      .catch((e) => toast(e.message));
    return;
  }
  if (message.event === "uiAction") {
    if (message.action.startsWith("tab:")) {
      switchTab(message.action.slice(4));
      return;
    }
    actions[message.action]?.();
    return;
  }
  if (message.event === "location") {
    consumeNativePoint(message.point, message.sessionID);
    if (active && Date.now() - lastPersist > 5000) {
      persistActive();
      lastPersist = Date.now();
    }
    updateStats();
  } else if (message.event === "foreground") {
    syncNative().catch((e) => toast(e.message));
  } else if (message.event === "error") {
    trace.record("error", { source: "native", code: "recorder" });
    geoError = message.message;
    toast(message.message);
  }
});

$("#recordButton").addEventListener("pointerdown", (e) => {
  if (!active) return;
  const button = e.currentTarget;
  button.setPointerCapture(e.pointerId);
  button.classList.add("holding");
  holdTimer = setTimeout(() => {
    suppressRecordClick = true;
    setTimeout(() => (suppressRecordClick = false), 1200);
    button.classList.remove("holding");
    if (native) nativeCall("haptic").catch(() => {});
    stopWalk().catch((e) => toast(e.message));
  }, 900);
});
for (const event of ["pointerup", "pointercancel", "lostpointercapture"])
  $("#recordButton").addEventListener(event, () => {
    clearTimeout(holdTimer);
    $("#recordButton").classList.remove("holding");
  });

function beginEdit(walkID) {
  if (active) {
    toast("記録を終了してから軌跡を修正してください。");
    return;
  }
  const w = data.walks.find((w) => w.id === walkID);
  if (!w) return;
  $("#mapViewport").classList.remove("tilt");
  editing = { id: walkID, points: structuredClone(w.points), history: [] };
  selectedWalk = walkID;
  closeSheet();
  switchTab("map");
  fit(editing.points);
  $("#editorToolbar").hidden = false;
  $("#mapBanner").hidden = false;
  $("#mapBanner").textContent =
    "点をドラッグして位置を修正。タップで削除・区切り。";
  $("#mapBanner").onclick = null;
  draw();
}
function editSnapshot() {
  if (!editing) return;
  editing.history.push(structuredClone(editing.points));
  if (editing.history.length > 20) editing.history.shift();
}
function exitEdit() {
  editing = null;
  editorDrag = null;
  selectedWalk = null;
  $("#editorToolbar").hidden = true;
  $("#mapBanner").hidden = true;
  draw();
}
actions.editCancel = () => {
  exitEdit();
  closeSheet();
};
actions.editUndo = () => {
  if (!editing?.history.length) return;
  editing.points = editing.history.pop();
  draw();
};
actions.editSave = async () => {
  if (!editing || editing.points.length < 2) return;
  const w = data.walks.find((w) => w.id === editing.id);
  if (!w) return;
  const previous = w.points;
  w.points = editing.points;
  try {
    await save();
  } catch (e) {
    w.points = previous;
    throw e;
  }
  const walkID = w.id;
  exitEdit();
  toast("修正した道を保存しました。");
  detail(walkID);
};
actions.editPointDelete = () => {
  if (!editing || editing.points.length <= 2) {
    toast("記録点は 2 点以上残してください。");
    return;
  }
  editSnapshot();
  const i = editing.selected;
  const wasGap = editing.points[i].break;
  editing.points.splice(i, 1);
  if (wasGap && editing.points[i]) editing.points[i].break = true;
  closeSheet();
  draw();
};
actions.editPointSplit = () => {
  if (!editing || editing.selected === 0) return;
  editSnapshot();
  editing.points[editing.selected].break =
    !editing.points[editing.selected].break;
  closeSheet();
  draw();
};
viewport.addEventListener(
  "pointerdown",
  (e) => {
    const dot = e.target.closest("[data-edit-point]");
    if (!editing || !dot) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    viewport.setPointerCapture(e.pointerId);
    editorDrag = {
      index: Number(dot.dataset.editPoint),
      x: e.clientX,
      y: e.clientY,
      moved: false,
    };
    editSnapshot();
  },
  { capture: true },
);
viewport.addEventListener(
  "pointermove",
  (e) => {
    if (!editorDrag || !editing) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (Math.hypot(e.clientX - editorDrag.x, e.clientY - editorDrag.y) > 3)
      editorDrag.moved = true;
    if (editorDrag.moved) {
      const r = viewport.getBoundingClientRect(),
        p = screenToPoint(e.clientX - r.left, e.clientY - r.top);
      Object.assign(editing.points[editorDrag.index], p);
      draw();
    }
  },
  { capture: true },
);
viewport.addEventListener(
  "pointerup",
  (e) => {
    if (!editorDrag || !editing) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    const drag = editorDrag;
    editorDrag = null;
    if (!drag.moved) {
      editing.history.pop();
      editing.selected = drag.index;
      sheet(
        "記録点を修正",
        `<p class="subtle">${drag.index + 1} / ${editing.points.length} 点目。位置を動かすときは、地図の点をドラッグしてください。</p><button class="primary" data-action="editPointSplit">${editing.points[drag.index].break ? "前の点とつなぐ" : "ここで軌跡を区切る"}</button><button class="secondary danger-button" data-action="editPointDelete">この点を削除</button>`,
      );
    }
  },
  { capture: true },
);
viewport.addEventListener(
  "pointercancel",
  () => {
    editorDrag = null;
  },
  { capture: true },
);

function stopCamera() {
  cameraStream?.getTracks().forEach((t) => t.stop());
  cameraStream = null;
  const video = $("#spotLive");
  if (video) {
    video.srcObject = null;
    video.hidden = true;
  }
}
actions.videoCamera = async () => {
  stopCamera();
  cameraStream = await openCamera($("#spotLive"), $("#spotAudio").checked);
  $("#videoRecordButton").disabled = false;
};
actions.videoRecord = async () => {
  if (!cameraStream) return;
  const button = $("#videoRecordButton");
  button.disabled = true;
  button.textContent = "録画中…";
  try {
    const blob = await captureTwoSeconds(cameraStream);
    pendingVideo = await readVideo(blob, 2);
    if ($("#spotVideoPreview")) {
      $("#spotVideoPreview").src = pendingVideo.data;
      $("#spotVideoPreview").hidden = false;
      if ($("#spotVideoPanel")) {
        $("#spotVideoPanel").hidden = false;
        $("#spotPhotoPanel").hidden = true;
        $$("[data-spot-mode]").forEach((b) =>
          b.classList.toggle("chosen", b.dataset.spotMode === "video"),
        );
      }
    }
    toast("2 秒の動画を撮りました。");
  } finally {
    stopCamera();
    if (button.isConnected) button.textContent = "2 秒の動画を撮る";
  }
};

actions.exportReplayVideo = async () => {
  if (!replayPoints.length) return;
  if (!HTMLCanvasElement.prototype.captureStream || !window.MediaRecorder) {
    toast(
      "このブラウザでは動画の書き出しに対応していません。画像カードをお使いください。",
    );
    return;
  }
  const points = structuredClone(replayPoints),
    canvas = document.createElement("canvas");
  canvas.width = 720;
  canvas.height = 960;
  const ctx = canvas.getContext("2d"),
    ps = points.map(project);
  let minx = Infinity,
    maxx = -Infinity,
    miny = Infinity,
    maxy = -Infinity;
  for (const [x, y] of ps) {
    minx = Math.min(minx, x);
    maxx = Math.max(maxx, x);
    miny = Math.min(miny, y);
    maxy = Math.max(maxy, y);
  }
  const scale = Math.max((maxx - minx) / 560, (maxy - miny) / 620, 1),
    coords = ps.map(([x, y]) => [
      (x - (minx + maxx) / 2) / scale + 360,
      470 - (y - (miny + maxy) / 2) / scale,
    ]),
    theme = themes[config.theme] || themes[0];
  const mime = ["video/mp4", "video/webm;codecs=vp9", "video/webm"].find((m) =>
    MediaRecorder.isTypeSupported(m),
  );
  if (!mime) {
    toast("利用できる動画形式がありません。");
    return;
  }
  sheet(
    "動画にしています",
    '<p class="center">白地図に、あなたの道を描いています。</p><progress id="videoExportProgress" max="1" value="0"></progress><p class="caption-note">画面を開いたままお待ちください。閉じると書き出しを中止します。</p>',
  );
  const stream = canvas.captureStream(30),
    recorder = new MediaRecorder(stream, {
      mimeType: mime,
      videoBitsPerSecond: 2500000,
    }),
    chunks = [];
  let raf,
    aborted = false,
    recorderFailure = null;
  const drawFrame = (progress) => {
    ctx.fillStyle = theme[1];
    ctx.fillRect(0, 0, 720, 960);
    ctx.fillStyle = theme[2];
    ctx.font = "17px -apple-system,sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("P L A I N W A L K", 360, 80);
    ctx.strokeStyle = theme[2];
    ctx.lineWidth = 2.5;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    if (config.line === "dashed") ctx.setLineDash([5, 7]);
    ctx.beginPath();
    const n = Math.max(1, Math.ceil(coords.length * progress));
    coords.slice(0, n).forEach(([x, y], i) => {
      !i || points[i].break ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
    ctx.stroke();
    ctx.setLineDash([]);
    if (n) {
      const [x, y] = coords[n - 1];
      ctx.beginPath();
      ctx.arc(x, y, 5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.font = "bold 32px -apple-system,sans-serif";
    ctx.fillText("歩いた道が、あなたの地図になる。", 360, 845);
    ctx.font = "19px -apple-system,sans-serif";
    ctx.fillText(
      fmt(trailDistance(points.slice(0, n))) + " " + distanceUnit(),
      360,
      890,
    );
  };
  drawFrame(0);
  try {
    const result = new Promise((resolve, reject) => {
      recorder.ondataavailable = (e) => {
        if (e.data.size) chunks.push(e.data);
      };
      recorder.onstop = () => resolve(new Blob(chunks, { type: mime }));
      recorder.onerror = (e) => {
        recorderFailure = e.error || Error("動画を書き出せませんでした。");
        reject(recorderFailure);
      };
    });
    recorder.start();
    const start = performance.now();
    await new Promise((resolve) => {
      const tick = () => {
        if ($("#overlay").hidden || !$("#videoExportProgress")) {
          aborted = true;
          resolve();
          return;
        }
        const progress = Math.min(1, (performance.now() - start) / 6000);
        drawFrame(progress);
        $("#videoExportProgress").value = progress;
        if (progress === 1 || recorderFailure) resolve();
        else raf = requestAnimationFrame(tick);
      };
      tick();
    });
    if (recorder.state !== "inactive") recorder.stop();
    const blob = await result;
    if (aborted) return;
    if (!blob.size) throw Error("空の動画が生成されました。");
    download(
      blob,
      "plainwalk-timelapse." + (mime.startsWith("video/mp4") ? "mp4" : "webm"),
    );
    closeSheet();
    toast("動画を書き出しました。");
  } finally {
    cancelAnimationFrame(raf);
    stream.getTracks().forEach((t) => t.stop());
    if (recorder.state !== "inactive") recorder.stop();
  }
};

actions.notePhoto = () => notePhotoPicker(false);
actions.noteCutout = () => notePhotoPicker(true);
actions.noteBack = showNote;
actions.noteRoute = async () => {
  captureNoteDraft();
  const points = data.walks
    .filter((w) => dateKey(w.start) === noteDraft.day)
    .flatMap((w) =>
      w.points.map((p, i) => ({ ...p, break: p.break || i === 0 })),
    );
  if (!points.length) {
    toast("この日に歩いた道はありません。");
    return;
  }
  const svg = miniSvg(points)
      .replace(
        'class="mini-trail"',
        'stroke="#293126" stroke-width="1.2" fill="none"',
      )
      .replace("<svg ", '<svg xmlns="http://www.w3.org/2000/svg" '),
    src =
      "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svg))),
    image = await loadImage(src),
    canvas = document.createElement("canvas");
  canvas.width = 600;
  canvas.height = 480;
  canvas.getContext("2d").drawImage(image, 0, 0, 600, 480);
  await addNoteImage(canvas.toDataURL("image/png"), "route");
};
actions.noteItemDelete = () => {
  noteDraft.layout = noteDraft.layout.filter((i) => i.id !== noteSelected);
  noteSelected = null;
  paintNote();
  updateNoteControls();
};
actions.noteItemFront = () => {
  const i = noteDraft.layout.findIndex((i) => i.id === noteSelected);
  if (i >= 0) {
    const [item] = noteDraft.layout.splice(i, 1);
    noteDraft.layout.push(item);
    paintNote();
  }
};
actions.lassoUndo = () => {
  lassoState?.points.pop();
  paintLasso();
};
actions.lassoFinish = async () => {
  const result = await lassoCutout(lassoState.src, lassoState.points);
  await addNoteImage(result.src, "sticker");
};
const oldClearStickers = actions.clearStickers;
actions.clearStickers = () => {
  oldClearStickers();
  captureNoteDraft();
  paintNote();
};
document.addEventListener("pointerdown", (e) => {
  if (e.target.id !== "noteCanvas" || !noteDraft) return;
  e.preventDefault();
  const canvas = e.target,
    rect = canvas.getBoundingClientRect(),
    x = ((e.clientX - rect.left) / rect.width) * 720,
    y = ((e.clientY - rect.top) / rect.height) * 960,
    item = hitItem(noteDraft.layout, x, y);
  noteSelected = item?.id || null;
  if (item) {
    canvas.setPointerCapture(e.pointerId);
    noteDrag = { id: item.id, dx: x - item.x, dy: y - item.y };
  }
  paintNote();
  updateNoteControls();
});
document.addEventListener("pointermove", (e) => {
  if (!noteDrag || e.target.id !== "noteCanvas") return;
  e.preventDefault();
  const rect = e.target.getBoundingClientRect(),
    item = noteDraft.layout.find((i) => i.id === noteDrag.id);
  if (item) {
    item.x = Math.max(
      0,
      Math.min(720, ((e.clientX - rect.left) / rect.width) * 720 - noteDrag.dx),
    );
    item.y = Math.max(
      0,
      Math.min(960, ((e.clientY - rect.top) / rect.height) * 960 - noteDrag.dy),
    );
    paintNote();
  }
});
for (const event of ["pointerup", "pointercancel"])
  document.addEventListener(event, () => (noteDrag = null));
document.addEventListener("click", (e) => {
  if (e.target.id !== "lassoCanvas" || !lassoState) return;
  const rect = e.target.getBoundingClientRect();
  lassoState.points.push([
    (e.clientX - rect.left) / rect.width,
    (e.clientY - rect.top) / rect.height,
  ]);
  paintLasso();
});

$("#sheet").addEventListener("pointerdown", (e) => {
  if (
    e.target.closest("button,input,textarea,select") ||
    !e.target.closest("#sheet>header,.sheet-handle")
  )
    return;
  sheetGesture = {
    id: e.pointerId,
    y: e.clientY,
    start: performance.now(),
    distance: 0,
  };
  $("#sheet").setPointerCapture(e.pointerId);
});
$("#sheet").addEventListener("pointermove", (e) => {
  if (!sheetGesture || sheetGesture.id !== e.pointerId) return;
  const dy = Math.max(0, e.clientY - sheetGesture.y);
  sheetGesture.distance = dy;
  $("#sheet").style.transform = `translateY(${dy * 0.85}px)`;
  e.preventDefault();
});
for (const event of ["pointerup", "pointercancel"])
  $("#sheet").addEventListener(event, () => {
    if (!sheetGesture) return;
    const g = sheetGesture;
    sheetGesture = null;
    const velocity = g.distance / Math.max(1, performance.now() - g.start);
    if (g.distance > 110 || (g.distance > 35 && velocity > 0.65)) {
      closeSheet();
    } else {
      $("#sheet").style.transition = "transform .2s cubic-bezier(.2,.8,.2,1)";
      $("#sheet").style.transform = "";
      setTimeout(() => ($("#sheet").style.transition = ""), 220);
    }
  });

async function loadAreaIndex() {
  if (areaState.index) return areaState.index;
  if (!loadAreaIndex.pending)
    loadAreaIndex.pending = fetch("./data/japan-municipalities.geojson")
      .then((r) => {
        if (!r.ok) throw Error("境界データを読み込めません。");
        return r.json();
      })
      .then((geo) => (areaState.index = makeIndex(geo)))
      .finally(() => (loadAreaIndex.pending = null));
  return loadAreaIndex.pending;
}
function drawMapContext(w, h) {
  let grid = "";
  if (config.grid) {
    const meter = metersPerPixel(),
      step = Math.max(30, Math.min(120, 100 / meter)),
      x = (((w / 2 - view.x / meter) % step) + step) % step,
      y = (((h / 2 + view.y / meter) % step) + step) % step;
    for (let gx = x; gx < w; gx += step) grid += `M${gx.toFixed(1)} 0V${h} `;
    for (let gy = y; gy < h; gy += step) grid += `M0 ${gy.toFixed(1)}H${w} `;
  }
  $("#mapGrid").innerHTML = grid
    ? `<path d="${grid}" stroke="var(--muted)" stroke-opacity=".13" stroke-width=".5"/>`
    : "";
  let outlines = "";
  if (config.outline && areaState.index) {
    const a = screenToPoint(0, 0),
      b = screenToPoint(w, h),
      step = view.zoom < 10 ? 5 : view.zoom < 13 ? 2 : 1;
    for (const f of areaState.index.collection.features) {
      const [x1, y1, x2, y2] = f.bbox;
      if (x2 < a.lon || x1 > b.lon || y2 < b.lat || y1 > a.lat) continue;
      const polygons =
        f.geometry.type === "Polygon"
          ? [f.geometry.coordinates]
          : f.geometry.coordinates;
      for (const poly of polygons)
        for (const ring of poly) {
          const points = ring
            .filter((p, i) => i % step === 0 || i === ring.length - 1)
            .map(([lon, lat]) => ({ lon, lat }));
          let d = "";
          points.forEach((p, i) => {
            const [x, y] = pointToScreen(p);
            d += `${i ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)} `;
          });
          outlines += d + "Z ";
        }
    }
  }
  $("#mapOutlines").innerHTML = outlines
    ? `<path d="${outlines}" fill="none" stroke="var(--muted)" stroke-opacity=".24" stroke-width=".7"/>`
    : "";
}
if (config.outline)
  loadAreaIndex()
    .then(draw)
    .catch((e) => toast(e.message));

function openPage(title, html, { grouped = false, right = "" } = {}) {
  const content = $("#contentPage");
  pageStack.push({
    tab,
    html: content.innerHTML,
    scroll: content.scrollTop,
    route: content.dataset.route || "",
    className: content.className,
  });
  if (pageStack.length > 20) pageStack.shift();
  closeSheet();
  tab = "profile";
  $("#mapPage").hidden = true;
  content.hidden = false;
  content.dataset.route = title;
  content.className = "native-page" + (grouped ? " grouped-page" : "");
  content.innerHTML = `<header class="native-page-header"><button class="circle" data-action="pageBack" aria-label="戻る">${icon("back")}</button><h1>${esc(title)}</h1>${right || "<span></span>"}</header><div id="pageBody">${html}</div>`;
  content.scrollTop = 0;
  $$("[data-tab]").forEach((el) =>
    el.classList.toggle("selected", el.dataset.tab === "profile"),
  );
}
function pageBack() {
  const state = pageStack.pop();
  if (!state) {
    switchTab("profile");
    return;
  }
  const content = $("#contentPage");
  tab = state.tab;
  content.innerHTML = state.html;
  content.className = state.className;
  content.dataset.route = state.route;
  content.scrollTop = state.scroll;
  content.hidden = tab === "map";
  $("#mapPage").hidden = tab !== "map";
  $$("[data-tab]").forEach((el) =>
    el.classList.toggle("selected", el.dataset.tab === tab),
  );
  if (tab === "map") draw();
}

$$(".map-stats .stat-icon").forEach(
  (el, i) => (el.innerHTML = icon(["foot", "pen", "flag"][i])),
);

function unavailableNative(
  title,
  text = "この機能は iOS アプリで利用する機能です。Web ブラウザでは同じ動作を実行できません。",
) {
  sheet(
    title,
    `<p class="subtle">${esc(text)}</p><button class="primary" data-action="close">わかりました</button>`,
  );
}
async function configureNativeSetting(key, element) {
  const desired = element.checked;
  if (!native) {
    element.checked = !!config[key];
    unavailableNative("iOS アプリの機能");
    return;
  }
  if (
    [
      "morningNotification",
      "weeklyNotification",
      "interruptionNotification",
    ].includes(key)
  ) {
    const next = { ...config, [key]: desired };
    try {
      await nativeCall("notificationsConfigure", next);
      config[key] = desired;
      await saveConfig();
    } catch (e) {
      element.checked = !!config[key];
      toast(e.message);
    }
    return;
  }
  if (key === "healthEnabled") {
    if (desired) {
      const result = await nativeCall("healthSteps");
      if (result.steps != null) {
        data.notes[today()] = {
          ...data.notes[today()],
          steps: Math.round(result.steps),
        };
        await save();
      }
    }
    config[key] = desired;
    await saveConfig();
    return;
  }
  element.checked = !!config[key];
  unavailableNative(
    "実装状況",
    "この機能の iOS 接続はまだ完了していません。設定だけを有効にした状態にはしません。",
  );
}
async function movementPolicy(policy) {
  if (policy === "none") {
    config.movementPolicy = "none";
    await saveConfig();
    settings();
    return;
  }
  unavailableNative(
    "動き出したとき",
    native
      ? "移動の自動検知は、現在の iOS プロジェクトではまだ接続されていません。"
      : "Web ブラウザでは画面を閉じた間の移動検知を実行できません。手動で「軌跡を残す」を使えます。",
  );
}
actions.homePlace = () => unavailableNative("自宅");
actions.workPlace = () => unavailableNative("職場");
actions.addPlace = () => unavailableNative("よく行く場所");
actions.systemSettings = () => nativeCall("openSettings");
actions.resetData = () =>
  sheet(
    "データをリセットしますか？",
    '<p>この端末のさんぽ、ここいいな、旗、ノートをすべて削除します。先にバックアップを書き出してください。</p><button class="secondary" data-action="backup">バックアップを書き出す</button><button class="primary danger-button" data-action="resetConfirm">すべてのデータを削除</button>',
  );
actions.resetConfirm = async () => {
  if (active) {
    toast("記録を終了してからリセットしてください。");
    return;
  }
  data = { version: 1, walks: [], spots: [], flags: [], notes: {} };
  selectedWalk = null;
  await save();
  closeSheet();
  switchTab("profile");
  draw();
  toast("この端末のデータをリセットしました。");
};
actions.lutSettings = () =>
  sheet(
    "LUT",
    `<p class="subtle">カメラの「自分のフィルムを読み込む」から 3D .cube を読み込めます。</p><p>${config.lut ? "カスタム LUT を保存しています。" : "まだ LUT がありません。"}</p>`,
  );

function spotMarker(p, color) {
  if (p.photo && $("#mapViewport").classList.contains("tilt"))
    return `<rect x="-19" y="-43" width="38" height="43" fill="var(--panel)" stroke="var(--line)" transform="rotate(-6)"/><image href="${esc(p.photo)}" x="-16" y="-40" width="32" height="32" preserveAspectRatio="xMidYMid slice" transform="rotate(-6)"/><circle cy="4" r="2" fill="${color}"/>`;
  if (!p.photo) {
    const text = p.text.slice(0, 18),
      width = Math.min(150, Math.max(30, [...text].length * 8 + 16));
    return `<rect x="${-width / 2}" y="-30" width="${width}" height="26" rx="10" fill="var(--panel)" stroke="var(--line)"/><text x="0" y="-13" fill="${color}" stroke="none" text-anchor="middle" font-size="10">${esc(text)}</text><circle r="2" fill="${color}"/>`;
  }
  const type = config.pin === "card" ? "badge" : config.pin || "badge",
    symbol = p.emoji === "♡" ? "♥" : p.emoji || "♥";
  if (type === "dot")
    return `<circle r="4" fill="${color}" stroke="var(--paper)" stroke-width="1"/>`;
  const shape =
    type === "square"
      ? '<rect x="-13" y="-27" width="26" height="26" rx="2"/>'
      : type === "circle" || type === "outline"
        ? `<circle cx="0" cy="-14" r="13" ${type === "outline" ? 'stroke-width="2.4"' : ""}/>`
        : '<rect x="-13" y="-28" width="26" height="27" rx="9"/><path d="m-3-1 3 4 3-4"/>';
  return `<g fill="var(--panel)" stroke="${type === "outline" ? color : "var(--line)"}">${shape}</g><text x="0" y="-9" text-anchor="middle" fill="${color}" stroke="none" font-size="16">${esc(symbol)}</text>`;
}

if (native)
  nativeCall("ready", { version: "0.3.0" }).catch((e) => toast(e.message));
