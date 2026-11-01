import test from "node:test";
import assert from "node:assert/strict";
import { R, project, validPoint } from "../../web/src/core.js";
import {
  WORLD_WIDTH,
  nearestWorldX,
  projectTrail,
  unprojectWrapped,
} from "../../web/src/map-geometry.js";

function near(actual, expected, tolerance = 1e-6) {
  assert.ok(
    Math.abs(actual - expected) <= tolerance,
    `${actual} should be within ${tolerance} of ${expected}`,
  );
}

test("a short equatorial date-line crossing stays about22 projected meters", () => {
  const points = [
    { lat: 0, lon: 179.9999 },
    { lat: 0, lon: -179.9999 },
    { lat: 0, lon: -179.9998 },
  ];
  const xy = projectTrail(points);
  near(xy[1][0] - xy[0][0], (2 * Math.PI * R * 0.0002) / 360);
  near(xy[2][0] - xy[1][0], (2 * Math.PI * R * 0.0001) / 360);
  assert.ok(xy[1][0] > xy[0][0]);
  const reversed = projectTrail([...points].reverse());
  near(reversed[1][0] - reversed[2][0], xy[1][0] - xy[0][0]);
  assert.ok(Math.max(...xy.map(([x]) => x)) - Math.min(...xy.map(([x]) => x)) < 34);
});

test("ordinary Japanese paths retain their projected positions and source metadata", () => {
  const points = [
    { lat: 35.68, lon: 139.76, t: 123, mode: "walking" },
    { lat: 35.6808, lon: 139.7602, edited: true },
    { lat: 35.681, lon: 139.761, break: true },
  ];
  const original = structuredClone(points);
  const xy = projectTrail(points);
  assert.equal(xy.length, points.length);
  points.forEach((point, index) => {
    const expected = project(point);
    near(xy[index][0], expected[0]);
    near(xy[index][1], expected[1]);
  });
  assert.deepEqual(points, original);
});

test("breaks and invalid slots reset drift to the first valid point's branch", () => {
  // Each step follows the nearest copy. Two complete revolutions make a reset
  // observable; a one-off date-line crossing would not expose stale streak state.
  const turns = [0, 120, -120, 0, 120, -120, 0].map((lon) => ({ lat: 0, lon }));
  const points = [
    ...turns,
    { lat: 0, lon: 120, break: true },
    { lat: 0, lon: -120 },
    null,
    { lat: 0, lon: 0 },
    { lat: 0, lon: 181 },
    { lat: NaN, lon: 1 },
    { lat: 0, lon: 120 },
  ];
  const xy = projectTrail(points);
  near(xy[6][0], 2 * WORLD_WIDTH);
  near(xy[7][0], WORLD_WIDTH / 3);
  near(xy[8][0], (2 * WORLD_WIDTH) / 3);
  assert.equal(xy[9], null);
  near(xy[10][0], 0);
  assert.equal(xy[11], null);
  assert.equal(xy[12], null);
  near(xy[13][0], WORLD_WIDTH / 3);
  assert.deepEqual(projectTrail([undefined, null, { lat: 86, lon: 0 }]), [null, null, null]);
});

test("an explicit world reference anchors every disconnected streak near that world", () => {
  const points = [
    null,
    { lat: 0, lon: 179.9999 },
    { lat: 0, lon: -179.9999 },
    { lat: 0, lon: 170, break: true },
    undefined,
    { lat: 0, lon: -175 },
  ];
  const reference = -4 * WORLD_WIDTH;
  const xy = projectTrail(points, reference);
  assert.equal(xy[0], null);
  near(xy[1][0], nearestWorldX(project(points[1])[0], reference));
  near(xy[2][0] - xy[1][0], (WORLD_WIDTH * 0.0002) / 360);
  assert.equal(xy[4], null);
  for (const index of [1, 3, 5]) {
    assert.ok(Math.abs(xy[index][0] - xy[1][0]) <= WORLD_WIDTH / 2);
  }
});

test("world selection uses bounded arithmetic even after millions of repeated worlds", () => {
  const original = project({ lat: 35.68, lon: 139.76 })[0];
  for (const worlds of [-10_000_000, -24, 0, 24, 10_000_000]) {
    const far = original + worlds * WORLD_WIDTH;
    near(nearestWorldX(far, original), original, 0.1);
    const anchor = far + 1234;
    const nearest = nearestWorldX(original, anchor);
    assert.ok(Number.isFinite(nearest));
    assert.ok(Math.abs(nearest - anchor) <= WORLD_WIDTH / 2);
    near(nearest, far, 0.1);
  }
  assert.ok(Number.isFinite(nearestWorldX(Number.MAX_VALUE, -Number.MAX_VALUE)));
  assert.ok(Number.isFinite(nearestWorldX(-Number.MAX_VALUE, Number.MAX_VALUE)));
});

test("screen-to-world inverse wraps longitude while preserving projected input position", () => {
  for (const originPoint of [
    { lat: 35.68, lon: 139.76 },
    { lat: 0, lon: 179.9999 },
  ]) {
    const rawOrigin = project(originPoint);
    const origin = [rawOrigin[0] + 7 * WORLD_WIDTH, rawOrigin[1]];
    const viewport = [393, 852], screen = [310, 270], mpp = 3.25;
    const x = origin[0] + (screen[0] - viewport[0] / 2) * mpp;
    const y = origin[1] - (screen[1] - viewport[1] / 2) * mpp;
    const point = unprojectWrapped(x, y);
    assert.ok(point.lon >= -180 && point.lon < 180);
    assert.ok(validPoint(point));
    const [wrapped] = projectTrail([point], origin[0]);
    near((wrapped[0] - origin[0]) / mpp + viewport[0] / 2, screen[0]);
    near(viewport[1] / 2 - (wrapped[1] - origin[1]) / mpp, screen[1]);
  }
  for (const x of [Math.PI * R, -Math.PI * R]) {
    const edge = unprojectWrapped(x, 0);
    assert.ok(edge.lon >= -180 && edge.lon < 180);
    // The projected boundary can round infinitesimally to either side.
    near(Math.abs(edge.lon), 180);
  }
  near(unprojectWrapped((R * 1000 * Math.PI) / 180, 0).lon, -80);
  const latitude = 88;
  const y = R * Math.log(Math.tan(Math.PI / 4 + (latitude * Math.PI) / 360));
  const outside = unprojectWrapped(0, y);
  near(outside.lat, latitude);
  assert.equal(validPoint(outside), false);
});
