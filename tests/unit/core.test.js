import test from "node:test";
import assert from "node:assert/strict";
import {
  distance,
  project,
  unproject,
  trailDistance,
  exploration,
  validPoint,
  gpx,
  validateBackup,
} from "../../web/src/core.js";
const a = { lat: 35.68, lon: 139.76, t: 1 },
  b = { lat: 35.681, lon: 139.76, t: 2 };
test("geographic projection round trip", () => {
  for (const p of [a, { lat: -33.8, lon: 151.2 }, { lat: 0, lon: 0 }]) {
    const q = unproject(...project(p));
    assert.ok(Math.abs(q.lat - p.lat) < 1e-8);
    assert.ok(Math.abs(q.lon - p.lon) < 1e-8);
  }
});
test("distance in meters and disconnected segments", () => {
  assert.ok(Math.abs(distance(a, b) - 111.2) < 0.1);
  assert.equal(trailDistance([a, { ...b, break: true }]), 0);
  assert.equal(distance(a, a), 0);
});
test("returning along an explored road does not add exploration", () => {
  const x = exploration([
    { id: "one", points: [a, b] },
    { id: "two", points: [b, a] },
  ]);
  assert.ok(x.byWalk.one > 100);
  assert.equal(x.byWalk.two, 0);
  assert.equal(x.total, x.byWalk.one);
});
test("gaps do not pioneer imaginary roads", () => {
  assert.equal(
    exploration([{ id: "x", points: [a, { ...b, break: true }] }]).total,
    0,
  );
});
test("export escapes names and keeps gaps", () => {
  const s = gpx({ name: "A < B & C", points: [a, { ...b, break: true }] });
  assert.ok(s.includes("A &lt; B &amp; C"));
  assert.ok(s.includes("</trkseg><trkseg>"));
});
test("invalid backup rejected and numeric zero coordinates accepted", () => {
  assert.equal(validPoint({ lat: 0, lon: 0 }), true);
  assert.equal(validPoint({ lat: 91, lon: 0 }), false);
  assert.throws(() =>
    validateBackup({
      version: 1,
      walks: [
        { id: "1", start: 0, end: 1, points: [{ lat: NaN, lon: 1, t: 0 }] },
      ],
      spots: [],
      flags: [],
    }),
  );
  assert.throws(() =>
    validateBackup({
      version: 1,
      walks: [],
      spots: [{ id: "x", lat: 1, lon: 1, photo: "javascript:alert(1)" }],
      flags: [],
    }),
  );
  assert.equal(
    validateBackup({ version: 1, walks: [], spots: [], flags: [] }).version,
    1,
  );
});
test("collections survive backup without sharing timestamps or private photo data", () => {
  const v = validateBackup({
    version: 1,
    walks: [],
    spots: [],
    flags: [],
    bookmarks: [{ id: "b", name: "Cafe", lat: 35, lon: 139 }],
    doodles: [
      { id: "d", name: "Draw", created: 1, points: [{ ...a, done: true }, b] },
    ],
    sharedMaps: [
      {
        id: "s",
        name: "Paper",
        walks: [{ id: "w", points: [{ ...a, photo: "private" }, b] }],
      },
    ],
  });
  assert.equal(v.bookmarks[0].name, "Cafe");
  assert.equal(v.doodles[0].points[0].done, true);
  assert.equal(v.sharedMaps[0].walks[0].points[0].t, undefined);
  assert.equal(v.sharedMaps[0].walks[0].points[0].photo, undefined);
  assert.throws(() =>
    validateBackup({
      ...v,
      doodles: [
        { id: "d", name: "x", created: 1, points: [{ lat: 999, lon: 0 }] },
      ],
    }),
  );
});
