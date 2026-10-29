import test from "node:test";
import assert from "node:assert/strict";
import {
  createDiagnostics,
  sanitizeEvent,
  sanitizeNativeReport,
} from "../../web/src/diagnostics.js";
test("diagnostic events exclude raw coordinates, messages and user data", () => {
  assert.deepEqual(
    sanitizeEvent({
      source: "native",
      accuracy: 7.234,
      points: 20,
      lat: 35.123,
      lon: 139.456,
      message: "private address",
      photo: "data:image",
      sessionID: "private",
    }),
    { source: "native", accuracy: 7.2, points: 20 },
  );
  assert.deepEqual(sanitizeEvent(null), {});
  assert.deepEqual(
    sanitizeEvent({ source: "https://example.com/?token=private" }),
    {},
  );
});
test("diagnostic log is opt in, bounded and returns independent entries", () => {
  const persisted = [];
  const log = createDiagnostics({
    limit: 3,
    now: () => 0,
    persist: (events) => persisted.push(events),
  });
  log.record("gps", { accuracy: 5 });
  assert.equal(log.entries().length, 0);
  log.enable(true);
  for (let i = 0; i < 5; i++) log.record("gps", { points: i, lat: i });
  assert.deepEqual(
    log.entries().map((e) => e.points),
    [2, 3, 4],
  );
  const copy = log.entries();
  copy[0].points = 99;
  assert.equal(log.entries()[0].points, 2);
  log.enable(false);
  assert.deepEqual(log.entries(), []);
  assert.deepEqual(persisted.at(-1), []);
});
test("restored logs and native snapshots keep only diagnostic metadata", () => {
  const log = createDiagnostics();
  log.enable(true);
  log.restore([
    {
      type: "gps",
      time: new Date(0).toISOString(),
      source: "web",
      lat: 1,
      photo: "secret",
    },
  ]);
  assert.equal(log.entries()[0].lat, undefined);
  assert.deepEqual(
    sanitizeNativeReport({
      flavor: "xcode",
      nativePoints: 30,
      points: [{ lat: 1 }],
      sessionID: "secret",
      lat: 35,
    }),
    { flavor: "xcode", nativePoints: 30 },
  );
});
