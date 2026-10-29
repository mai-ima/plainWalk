import test from "node:test";
import assert from "node:assert/strict";
import { gunzipSync } from "node:zlib";
import { readFile } from "node:fs/promises";
import {
  contains,
  makeIndex,
  collectAreas,
  areaSVG,
} from "../../web/src/areas.js";
const f = {
  type: "Feature",
  properties: { id: "square", name: "Square", parent: "Test" },
  geometry: {
    type: "Polygon",
    coordinates: [
      [
        [0, 0],
        [2, 0],
        [2, 2],
        [0, 2],
        [0, 0],
      ],
      [
        [0.7, 0.7],
        [1.3, 0.7],
        [1.3, 1.3],
        [0.7, 1.3],
        [0.7, 0.7],
      ],
    ],
  },
};
test("polygon holes, exterior and boundary", () => {
  assert.equal(contains(f, { lat: 0.3, lon: 0.3 }), true);
  assert.equal(contains(f, { lat: 1, lon: 1 }), false);
  assert.equal(contains(f, { lat: 3, lon: 3 }), false);
  assert.equal(contains(f, { lat: 0, lon: 1 }), true);
});
test("multi-polygons test every island", () => {
  const multi = {
    geometry: {
      type: "MultiPolygon",
      coordinates: [
        f.geometry.coordinates,
        [
          [
            [3, 3],
            [4, 3],
            [4, 4],
            [3, 4],
            [3, 3],
          ],
        ],
      ],
    },
  };
  assert.equal(contains(multi, { lat: 3.5, lon: 3.5 }), true);
  assert.equal(contains(multi, { lat: 2.5, lon: 2.5 }), false);
});
test("real Tokyo station point collects Chiyoda badge without sending coordinates", async () => {
  const geo = JSON.parse(
      gunzipSync(
        await readFile(
          new URL(
            "../../datasets/japan-municipalities.geojson.gz",
            import.meta.url,
          ),
        ),
      ).toString("utf8"),
    ),
    index = makeIndex(geo);
  const hits = index.at({ lat: 35.681236, lon: 139.767125 });
  assert.ok(hits.some((f) => f.properties.name === "千代田区"));
  assert.equal(index.at({ lat: 0, lon: 0 }).length, 0);
  const stats = await collectAreas(
    [
      {
        id: "w",
        start: 100,
        points: [
          { lat: 35.681236, lon: 139.767125 },
          { lat: 35.681336, lon: 139.767225 },
        ],
      },
    ],
    index,
  );
  assert.ok(
    stats.some(
      (s) =>
        s.name === "千代田区" &&
        s.walks === 1 &&
        s.distance > 10 &&
        s.cells.length > 0,
    ),
  );
  assert.ok(areaSVG(hits[0]).includes('fill-rule="evenodd"'));
});
test("gaps do not count invented cross-town distance", async () => {
  const index = makeIndex({ features: [structuredClone(f)] }),
    stats = await collectAreas(
      [
        {
          id: "w",
          start: 1,
          points: [
            { lat: 0.2, lon: 0.2 },
            { lat: 0.3, lon: 0.3, break: true },
          ],
        },
      ],
      index,
    );
  assert.equal(stats[0].distance, 0);
  assert.equal(stats[0].walks, 1);
});
