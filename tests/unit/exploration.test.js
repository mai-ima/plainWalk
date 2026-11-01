import test from "node:test";
import assert from "node:assert/strict";
import { ExplorationAccumulator, exploration, trailDistance, distance, cellKeys } from "../../web/src/core.js";
const METERS = 111195.08;
function line(intervals, angle = 0, start = 0, end = 100000, length = 1000) {
  const radians = angle * Math.PI / 180;
  const deltaLat = length * Math.sin(radians) / METERS;
  const deltaLon = length * Math.cos(radians) / (METERS * Math.cos(35 * Math.PI / 180));
  return Array.from({ length: intervals + 1 }, (_, i) => ({
    lat: 35 + deltaLat * i / intervals, lon: 139 + deltaLon * i / intervals,
    t: start + (end - start) * i / intervals,
  }));
}
function run(points, visited = new Set(), day = Date.now()) {
  const accumulator = new ExplorationAccumulator(visited, day);
  for (let i = 1; i < points.length; i++) accumulator.append(points[i - 1], points[i]);
  return accumulator;
}
const near = (actual, expected, tolerance = 0.001) => assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} != ${expected} ±${tolerance}`);

test("first kilometre is invariant to GPS density and does not exceed walked distance", () => {
  for (const angle of [0, 5.625, 22.5, 45, 78, 90]) {
    const sparse = line(1, angle), expected = run(sparse).total;
    assert.ok(expected >= trailDistance(sparse) * Math.cos(Math.PI / 32) - 0.01);
    for (const intervals of [1, 100, 200, 300]) {
      const points = line(intervals, angle), result = run(points);
      near(result.total, expected);
      assert.ok(result.total <= trailDistance(points) + 1e-8);
    }
  }
  near(run(line(1)).total, 1000);
});
test("retracing a road, within one walk and in later walks, does not add exploration", () => {
  const points = line(200), outward = run(points);
  const loop = [...points, ...points.slice(0, -1).reverse()];
  near(run(loop).total, outward.total);
  assert.equal(run(points, outward.cells).total, 0);
  const older = { id: "old", start: 0, points }, newer = { id: "new", start: 200000, points: [...points].reverse() };
  const one = exploration([older, newer]), reversed = exploration([newer, older]);
  near(one.byWalk.old, outward.total);
  assert.equal(one.byWalk.new, 0);
  assert.deepEqual(reversed.byWalk, one.byWalk);
});
test("break-separated short passages in one cell cannot invent a long diagonal", () => {
  const points = [
    { lat: .00001, lon: .00001, t: 0 }, { lat: .00001, lon: .000019, t: 1000 },
    { lat: .00009, lon: .00008, t: 2000, break: true }, { lat: .00009, lon: .000089, t: 3000 },
  ];
  const result = run(points);
  near(result.total, distance(points[0], points[1]), 0.00001);
  assert.ok(result.total < 1.01 && result.total <= trailDistance(points));
  const repeated = [...points, { ...points[0], break: true }, ...points.slice(1)];
  near(run(repeated).total, result.total);
  assert.equal(run([{ ...points[0] }, { ...points[1], break: true }]).total, 0);
});
test("short routes are measured as a passage, not twelve metres per cell", () => {
  const points = line(1, 0, 0, 1000, 1);
  near(run(points).total, 1, 0.00001);
  assert.ok(run(points).total <= trailDistance(points));
});
test("midnight allocation is density invariant and sums to the whole walk", () => {
  const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
  const yesterday = new Date(midnight); yesterday.setDate(yesterday.getDate() - 1);
  for (const intervals of [1, 100, 300]) {
    const points = line(intervals, 0, midnight.getTime() - 60000, midnight.getTime() + 60000);
    const prior = run(points, new Set(), yesterday), today = run(points, new Set(), midnight);
    near(prior.dayTotal, 500); near(today.dayTotal, 500);
    near(prior.dayTotal + today.dayTotal, today.total);
    const saved = exploration([{ id: "overnight", start: points[0].t, points }], midnight);
    near(saved.dayTotal, today.dayTotal); near(saved.byWalk.overnight, today.total);
  }
});
test("the antimeridian visits local cells, not distant cells around Greenwich", () => {
  const a = { lat: 0, lon: 179.9999, t: 0 }, b = { lat: 0, lon: -179.9999, t: 10000 };
  const keys = cellKeys(a, b);
  assert.ok(keys.length <= 10 && keys.every((key) => Math.abs(Number(key.split(":")[1])) > 1000000));
  near(run([a, b]).total, distance(a, b), 0.00001);
  const reverse = run([a, b, a]); near(reverse.total, run([a, b]).total);
});
test("invalid jumps reset a passage and extreme times do not loop through days", () => {
  const points = line(1), accumulator = run(points);
  accumulator.append(points[1], { lat: -35, lon: -139, t: 100001 });
  near(accumulator.total, run(points).total);
  const ancient = line(1, 0, -8640000000000000, 8640000000000000, 1);
  const result = run(ancient);
  assert.ok(Number.isFinite(result.total) && result.total <= trailDistance(ancient));
});
test("Web numeric fixtures are shared with the native math self test", () => {
  // NativeTrackMath.selfTest checks these values with the same coordinates.
  near(run(line(1)).total, 1000.0000015969747, 0.00001);
  near(run(line(1, 5.625)).total, 995.1794604570179, 0.00001);
  near(run(line(1, 45)).total, 999.9805162985023, 0.00001);
});
test("calendar-day boundaries follow the local calendar including DST", () => {
  const start = new Date(2026, 10, 1, 0, 0, 0), end = new Date(start);
  end.setDate(end.getDate() + 1);
  const prior = new Date(start); prior.setDate(prior.getDate() - 1);
  const points = line(1, 0, start.getTime(), end.getTime());
  const result = run(points, new Set(), start);
  near(result.dayTotal, result.total);
  near(run(points, new Set(), prior).dayTotal, 0);
  assert.equal(result.dayEnd - result.dayStart, end.getTime() - start.getTime());
});
