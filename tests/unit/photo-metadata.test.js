import test from "node:test";
import assert from "node:assert/strict";
import { readPhotoMetadata, locatePhotoOnWalks } from "../../web/src/photo-metadata.js";

import exifFixture from "../fixtures/jpeg-exif.cjs";
const { jpeg } = exifFixture;

test("JPEG EXIF preserves absolute capture time, orientation and GPS in either TIFF byte order", () => {
  for (const little of [true, false]) {
    const result = readPhotoMetadata(jpeg({ little }));
    assert.equal(result.format, "jpeg");
    assert.equal(result.capturedAt, Date.UTC(2026, 9, 29, 3, 0, 0, 123));
    assert.equal(result.localDateTime, "2026:10:29 12:00:00");
    assert.equal(result.timeSource, "exif-offset");
    assert.equal(result.orientation, 6);
    assert.equal(result.point.lat, 35 + 40 / 60 + 30 / 3600);
    assert.equal(result.point.lon, 139.75);
  }
});

test("JPEG EXIF accepts explicit west/south and zero; subarray input retains correct offsets", () => {
  const source = jpeg({ lat: [0, 0, 0], lon: [0, 0, 0], latRef: "N", lonRef: "E" });
  const padded = new Uint8Array(source.length + 13); padded.set(source, 7);
  assert.deepEqual(readPhotoMetadata(padded.subarray(7, 7 + source.length)).point, { lat: 0, lon: 0 });
  assert.deepEqual(readPhotoMetadata(jpeg({ latRef: "S", lonRef: "W" }).buffer).point,
    { lat: -(35 + 40 / 60 + 30 / 3600), lon: -139.75 });
});

test("timezone-free local EXIF is retained without inventing an absolute capture date", () => {
  const local = readPhotoMetadata(jpeg({ offset: null, gps: false }));
  assert.equal(local.localDateTime, "2026:10:29 12:00:00");
  assert.equal(local.capturedAt, null); assert.equal(local.timeSource, null);
  const utc = readPhotoMetadata(jpeg({ offset: null, gpsTime: [3, 0, [125, 100]] }));
  assert.equal(utc.capturedAt, Date.UTC(2026, 9, 29, 3, 0, 1, 250));
  assert.equal(utc.timeSource, "gps-utc");
  assert.equal(readPhotoMetadata(jpeg({ date: "1970:01:01 00:00:00", offset: "+00:00", sub: "0", gps: false })).capturedAt, 0);
});

test("invalid dates, offsets, GPS refs and rationals cannot create plausible-looking positions", () => {
  for (const date of ["2026:02:30 12:00:00", "2026:13:01 12:00:00", "2026:10:29 25:00:00", "0000:01:01 00:00:00"]) {
    const result = readPhotoMetadata(jpeg({ date, gps: false }));
    assert.equal(result.capturedAt, null); assert.equal(result.localDateTime, null);
  }
  for (const offset of ["+24:00", "+14:01", "09:00", "+09:99"]) assert.equal(readPhotoMetadata(jpeg({ offset, gps: false })).capturedAt, null);
  for (const options of [{ latRef: "?" }, { lonRef: "east" }, { lat: [35, 60, 0] }, { lon: [181, 0, 0] }, { lat: [[35, 1], [0, 0], [0, 1]] }]) {
    assert.equal(readPhotoMetadata(jpeg(options)).point, null);
  }
  assert.equal(readPhotoMetadata(jpeg({ offset: null, gpsDate: "2026:02:30" })).capturedAt, null);
  assert.equal(readPhotoMetadata(jpeg({ orientation: 9 })).orientation, null);
});

test("corrupt TIFF offsets, cycles and truncated JPEG data never throw or allocate unbounded fields", () => {
  const source = jpeg(), view = new DataView(source.buffer);
  view.setUint32(12 + 42, 0xffffffff, true);
  const damagedGPS = readPhotoMetadata(source);
  assert.equal(damagedGPS.point, null); assert.equal(damagedGPS.timeSource, "exif-offset");
  const cycle = jpeg(); new DataView(cycle.buffer).setUint32(12 + 30, 8, true);
  assert.equal(readPhotoMetadata(cycle).timeSource, "gps-utc");
  for (let length = 0; length < source.length; length++) assert.doesNotThrow(() => readPhotoMetadata(source.slice(0, length)));
  assert.equal(readPhotoMetadata(new Uint8Array([137, 80, 78, 71])).format, "unsupported");
  assert.equal(readPhotoMetadata(new Uint8Array([255, 216, 255, 217])).format, "jpeg");
  const withAPP0 = Uint8Array.from([255, 216, 255, 224, 0, 4, 1, 2, ...jpeg().slice(2)]);
  assert.equal(readPhotoMetadata(withAPP0).point.lon, 139.75);
});

const origin = Date.UTC(2026, 9, 29);
const walk = { id: "walk", points: [{ lat: 35, lon: 139, t: origin }, { lat: 35.0001, lon: 139.0001, t: origin + 10_000 }] };
const metadata = { capturedAt: origin + 5000, point: null };

test("photo location prefers actual photo GPS and otherwise interpolates a short connected saved or active walk", () => {
  assert.deepEqual(locatePhotoOnWalks({ capturedAt: null, point: { lat: 0, lon: 0 } }, [walk]), { point: { lat: 0, lon: 0 }, capturedAt: null, source: "photo-gps" });
  const found = locatePhotoOnWalks(metadata, [walk]);
  assert.equal(found.source, "walk-time"); assert.equal(found.walkID, "walk");
  assert.ok(Math.abs(found.point.lat - 35.00005) < 1e-9);
  assert.ok(Math.abs(found.point.lon - 139.00005) < 1e-9);
  assert.deepEqual(locatePhotoOnWalks(metadata, [], { activeWalk: walk }), found);
  assert.equal(locatePhotoOnWalks({ ...metadata, capturedAt: null, localDateTime: "2026:10:29 00:00:05" }, [walk]), null);
});

test("photo placement never bridges a pause, stale interval, missing timestamp or implausible move", () => {
  for (const change of [{ break: true }, { gap: true }, { t: origin + 600_000 }, { t: undefined }, { lat: 36 }, { t: origin - 10_000 }]) {
    const modified = { ...walk, points: [walk.points[0], { ...walk.points[1], ...change }] };
    assert.equal(locatePhotoOnWalks(metadata, [modified]), null);
  }
  const exact = locatePhotoOnWalks({ capturedAt: origin + 10_000 }, [{ ...walk, points: [walk.points[0], { ...walk.points[1], break: true }] }]);
  assert.deepEqual(exact.point, { lat: 35.0001, lon: 139.0001 });
  assert.equal(locatePhotoOnWalks({ capturedAt: origin - 1 }, [walk]), null);
  assert.equal(locatePhotoOnWalks({ capturedAt: true }, [walk]), null);
});

test("overlapping walks with conflicting locations are ambiguous; antimeridian uses the short path", () => {
  const elsewhere = { id: "other", points: walk.points.map((p) => ({ ...p, lat: 34 })) };
  assert.equal(locatePhotoOnWalks(metadata, [walk, elsewhere]), null);
  const same = { ...walk, id: "also" };
  assert.equal(locatePhotoOnWalks(metadata, [walk, same]).walkID, undefined);
  const crossing = { id: "cross", points: [{ lat: 0, lon: 179.9999, t: origin }, { lat: 0, lon: -179.9999, t: origin + 10_000 }] };
  assert.ok(Math.abs(locatePhotoOnWalks(metadata, [crossing]).point.lon) === 180);
});


test("parallel walks 20 m apart are ambiguous; poor GPS accuracy is not used for photo placement", () => {
  const parallel = { id: "parallel", points: walk.points.map((p) => ({ ...p, lat: p.lat + 0.00018 })) };
  assert.equal(locatePhotoOnWalks(metadata, [walk, parallel]), null);
  for (const accuracy of [-1, 101, NaN, Infinity, true, "5"]) {
    const inaccurate = { ...walk, points: walk.points.map((p) => ({ ...p, accuracy })) };
    assert.equal(locatePhotoOnWalks(metadata, [inaccurate]), null);
    assert.equal(locatePhotoOnWalks({ capturedAt: origin }, [inaccurate]), null);
  }
  for (const accuracy of [0, 100, null, undefined]) {
    const usable = { ...walk, points: walk.points.map((p) => ({ ...p, accuracy })) };
    assert.equal(locatePhotoOnWalks(metadata, [usable]).source, "walk-time");
  }
  const corrupt = { ...walk, points: [...walk.points, { lat: 35, lon: 139, t: origin + 1 }] };
  assert.equal(locatePhotoOnWalks(metadata, [corrupt]), null);
});
