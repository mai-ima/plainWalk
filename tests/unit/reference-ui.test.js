import test from "node:test";
import assert from "node:assert/strict";
import { settingsHTML } from "../../web/src/reference-ui.js";

const settings = (morningTime) =>
  settingsHTML({ morningTime }, { native: false, icon: () => "" });

test("imported reminder times cannot insert settings markup", () => {
  const injection = '\"><img src=x onerror="globalThis.compromised=true">';
  const html = settings(injection);
  assert.equal(html.includes("onerror"), false);
  assert.equal(html.includes("<img"), false);
  assert.match(html, /id="morningTime" type="time" value="07:45"/);
});

test("settings retain valid midnight times and replace out-of-range imports", () => {
  for (const valid of ["00:00", "07:45", "23:59"])
    assert.ok(settings(valid).includes(`type="time" value="${valid}"`));
  for (const invalid of ["24:00", "07:60", "7:45", null, 745])
    assert.ok(settings(invalid).includes('type="time" value="07:45"'));
});
