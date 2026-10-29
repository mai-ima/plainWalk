// A bounded, opt-in log. Raw positions, filenames, messages and application data never enter it.
const FIELDS = new Set([
  "source",
  "status",
  "code",
  "accuracy",
  "ageMs",
  "points",
  "durationMs",
  "mode",
  "count",
]);
export function sanitizeEvent(detail = {}) {
  const clean = {};
  if (!detail || typeof detail !== "object") return clean;
  for (const [key, value] of Object.entries(detail)) {
    if (!FIELDS.has(key)) continue;
    if (typeof value === "number" && Number.isFinite(value))
      clean[key] = Math.round(value * 10) / 10;
    else if (typeof value === "boolean") clean[key] = value;
    else if (typeof value === "string" && /^[a-zA-Z0-9_.:-]{1,48}$/.test(value))
      clean[key] = value;
  }
  return clean;
}
export function createDiagnostics({
  limit = 250,
  now = Date.now,
  persist = () => {},
} = {}) {
  let enabled = false,
    events = [];
  return {
    enable(value) {
      enabled = !!value;
      if (!enabled) {
        events = [];
        persist([]);
      }
    },
    record(type, detail) {
      if (!enabled || !/^[a-zA-Z0-9_.:-]{1,48}$/.test(type)) return;
      events.push({
        time: new Date(now()).toISOString(),
        type,
        ...sanitizeEvent(detail),
      });
      if (events.length > limit) events.splice(0, events.length - limit);
      persist(events.map((e) => ({ ...e })));
    },
    restore(list) {
      if (!enabled || !Array.isArray(list)) return;
      events = list
        .slice(-limit)
        .filter(
          (e) =>
            e &&
            typeof e.time === "string" &&
            Number.isFinite(Date.parse(e.time)) &&
            /^[a-zA-Z0-9_.:-]{1,48}$/.test(e.type),
        )
        .map((e) => ({
          time: new Date(e.time).toISOString(),
          type: e.type,
          ...sanitizeEvent(e),
        }));
    },
    entries() {
      return events.map((e) => ({ ...e }));
    },
    clear() {
      events = [];
      persist([]);
    },
  };
}
export const DEVICE_CHECKS = [
  ["launch", "起動・初回の表示"],
  ["location", "位置情報の許可と拒否"],
  ["record", "前面での記録・一時停止・再開"],
  ["background", "画面ロック中の記録（Xcode 版）"],
  ["recovery", "終了・再起動後の復元"],
  ["media", "写真・短い動画・共有"],
  ["backup", "バックアップの書き出しと取り込み"],
  ["offline", "オフラインで保存済みの道を開く"],
  ["accessibility", "VoiceOver・文字サイズ・タップ領域"],
];
export function sanitizeNativeReport(value) {
  const keys = [
    "flavor",
    "systemVersion",
    "deviceFamily",
    "appVersion",
    "locationAuthorization",
    "accuracyAuthorization",
    "motionAuthorization",
    "cameraAuthorization",
    "microphoneAuthorization",
    "notificationAuthorization",
    "lowPowerMode",
    "thermalState",
    "backgroundRefresh",
    "backgroundLocation",
    "nativeRecording",
    "nativePoints",
    "lastAccuracy",
    "lastFixAgeMs",
    "storedBytes",
    "freeBytes",
  ];
  if (!value || typeof value !== "object") return null;
  return Object.fromEntries(
    keys
      .filter(
        (k) =>
          Object.hasOwn(value, k) &&
          (["string", "number", "boolean"].includes(typeof value[k]) ||
            value[k] === null),
      )
      .map((k) => [
        k,
        typeof value[k] === "string" ? value[k].slice(0, 100) : value[k],
      ]),
  );
}
