import test from "node:test";
import assert from "node:assert/strict";
import { validateBackup, validateNotePages } from "../../web/src/core.js";
import { legacyNoteID, notebookPage, notebookPages, notebookContent, sameNotebookContent, putNotebookPage, removeNotebookPage, mergeNotebookLibraries } from "../../web/src/notebook-pages.js";
const day = "2026-11-10";
const backup = notes => ({ version: 1, walks: [], spots: [], flags: [], notes });
const extra = (id, text, more = {}) => ({ id, day, text, ...more });
test("legacy backups retain daily steps and unknown fields with a stable first page", () => {
  const library = validateBackup(backup({ [day]: { text: "First", steps: 42, future: { keep: true } } }));
  assert.equal(notebookPages(library)[0].id, legacyNoteID(day));
  assert.deepEqual(library.notePages, {});
  const saved = putNotebookPage(library, { ...notebookPages(library)[0], text: "Edited" });
  assert.equal(saved.notes[day].text, "Edited");
  assert.equal(saved.notes[day].steps, 42);
  assert.deepEqual(saved.notes[day].future, { keep: true });
  assert.equal(library.notes[day].text, "First");
});
test("multiple same-day pages save independently and remain stable after JSON round trip", () => {
  let library = validateBackup(backup({ [day]: { text: "One", steps: 12 } }));
  library = putNotebookPage(library, extra("p2", "Two", { created: 2, future: 9 }));
  library = putNotebookPage(library, extra("p3", "Three", { created: 3 }));
  library = validateBackup(JSON.parse(JSON.stringify(library)));
  assert.deepEqual(notebookPages(library, day).map(page => page.id), [legacyNoteID(day), "p2", "p3"]);
  library = putNotebookPage(library, { ...notebookPage(library, day, "p2"), text: "Second changed" });
  assert.equal(library.notes[day].text, "One");
  assert.equal(library.notePages.p3.text, "Three");
  assert.equal(library.notePages.p2.future, 9);
  assert.equal(library.notePages.p2.steps, undefined);
});
test("deleting legacy and extra pages keeps siblings and daily metadata", () => {
  const source = { notes: { [day]: { text: "One", steps: 0, future: "retain", layout: [] } }, notePages: { p2: extra("p2", "Two") } };
  const removed = removeNotebookPage(source, day, legacyNoteID(day));
  assert.equal(removed.notes[day].pageDeleted, true);
  assert.equal(removed.notes[day].steps, 0);
  assert.equal(removed.notes[day].future, "retain");
  assert.equal(removed.notes[day].text, undefined);
  assert.deepEqual(notebookPages(removed).map(page => page.id), ["p2"]);
  const empty = removeNotebookPage(removed, day, "p2");
  assert.equal(notebookPages(empty).length, 0);
  assert.equal(empty.notes[day].steps, 0);
  const restored = putNotebookPage(empty, { id: legacyNoteID(day), day, text: "Again" });
  assert.equal(restored.notes[day].pageDeleted, undefined);
  assert.equal(restored.notes[day].steps, 0);
  assert.equal(source.notes[day].text, "One");
});
test("divergent same-day and same-ID imports preserve both versions and repeat idempotently", () => {
  const local = validateBackup({ ...backup({ [day]: { text: "Local", steps: 123, native: { n: 1 } } }), notePages: { x: extra("x", "Local extra") } });
  const incoming = validateBackup({ ...backup({ [day]: { text: "Incoming", steps: 999, foreign: [1, 2] } }), notePages: { x: extra("x", "Incoming extra"), y: extra("y", "Distinct") } });
  const merged = mergeNotebookLibraries(local, incoming);
  assert.equal(merged.notes[day].steps, 123);
  assert.equal(merged.notes[day].text, "Local");
  assert.equal(merged.notes[day].foreign, undefined);
  assert.deepEqual(notebookPages(merged, day).map(page => page.text).sort(), ["Distinct", "Incoming", "Incoming extra", "Local", "Local extra"]);
  assert.deepEqual(merged.notePages[`import:${day}:1`].foreign, [1, 2]);
  assert.equal(merged.notePages[`import:${day}:1`].steps, undefined);
  assert.deepEqual(mergeNotebookLibraries(merged, incoming), merged);
  assert.deepEqual(local.notePages.x.text, "Local extra");
  assert.equal(Object.keys(validateBackup(merged).notePages).length, 4);
});
test("normalized equality ignores identity/daily metadata but keeps unknown fields", () => {
  assert.equal(sameNotebookContent({ text: "same", steps: 1, id: "a", day }, { text: "same", steps: 9, id: "b", day, layout: [], font: "serif", paper: "plain", stickers: "" }), true);
  assert.equal(sameNotebookContent({ text: "same", future: { b: 2, a: 1 } }, { text: "same", future: { a: 1, b: 2 } }), true);
  assert.equal(sameNotebookContent({ text: "same", future: 1 }, { text: "same", future: 2 }), false);
  assert.equal(notebookContent({ steps: 99 }).steps, undefined);
});
test("incoming live page never revives local tombstone or overwrites local steps", () => {
  const local = { notes: { [day]: { pageDeleted: true, steps: 7, future: "local" } } };
  const incoming = { notes: { [day]: { text: "Imported", steps: 8 } } };
  const merged = mergeNotebookLibraries(local, incoming);
  assert.equal(merged.notes[day].pageDeleted, true);
  assert.equal(merged.notes[day].steps, 7);
  assert.equal(notebookPages(merged).length, 1);
  assert.equal(notebookPages(merged)[0].text, "Imported");
  assert.deepEqual(mergeNotebookLibraries(merged, incoming), merged);
});
test("notes on a day without a walk and collision-safe deterministic imports", () => {
  const local = { notes: { [day]: { text: "One" } }, notePages: { [`import:${day}:1`]: extra(`import:${day}:1`, "Occupied") } };
  const incoming = { notes: { [day]: { text: "Two" } } };
  const merged = mergeNotebookLibraries(local, incoming);
  assert.equal(merged.notePages[`import:${day}:2`].text, "Two");
  const newDay = "2026-11-09";
  const added = putNotebookPage(merged, { id: "nonwalking", day: newDay, text: "A quiet day" });
  assert.equal(notebookPages(added, newDay)[0].text, "A quiet day");
  assert.equal(added.notes[newDay], undefined);
});
test("additional page validation rejects malformed IDs, dates and page data", () => {
  assert.equal(validateNotePages({ good: extra("good", "ok", { nativeValue: true }) }).good.nativeValue, true);
  for (const page of [extra("wrong", "x"), extra("good", "x", { day: "2026-02-30" }), extra("good", "x", { pageDeleted: true }), extra("good", "x", { steps: 1 }), extra("good", "x", { layout: Array(21).fill({}) }), extra("good", "x", { created: Infinity })])
    assert.throws(() => validateNotePages({ good: page }));
  assert.throws(() => validateNotePages({ [legacyNoteID(day)]: extra(legacyNoteID(day), "x") }));
  assert.throws(() => validateNotePages(JSON.parse('{"__proto__":{"id":"__proto__","day":"2026-11-10"}}')));
  assert.throws(() => validateBackup(backup({ [day]: { pageDeleted: "yes" } })));
});
test("distinct identical blank pages are preserved by ID on first and repeated imports", () => {
  const incoming = { notes: {}, notePages: { a: extra("a", ""), b: extra("b", "") } };
  const merged = mergeNotebookLibraries({ notes: {} }, incoming);
  assert.deepEqual(notebookPages(merged).map(page => page.id), ["a", "b"]);
  assert.deepEqual(mergeNotebookLibraries(merged, incoming), merged);
});
test("identical conflicting content from different source IDs creates independent idempotent copies", () => {
  const local = { notes: { [day]: { text: "Local legacy" } }, notePages: { a: extra("a", "Local A"), b: extra("b", "Local B") } };
  const incoming = { notes: { [day]: { text: "" } }, notePages: { a: extra("a", ""), b: extra("b", "") } };
  const merged = mergeNotebookLibraries(local, incoming);
  assert.equal(notebookPages(merged).length, 6);
  assert.deepEqual(Object.values(merged.notePages).filter(page => page._plainwalkImportSourceID).map(page => page._plainwalkImportSourceID).sort(), ["a", "b", legacyNoteID(day)].sort());
  assert.deepEqual(mergeNotebookLibraries(merged, incoming), merged);
  const edited = putNotebookPage(merged, { ...notebookPage(merged, day, `import:${day}:2`), text: "Edited copy" });
  assert.equal(edited.notePages[`import:${day}:2`]._plainwalkImportSourceID, "a");
  assert.equal(sameNotebookContent({ text: "same", _plainwalkImportSourceID: "a" }, { text: "same", _plainwalkImportSourceID: "b" }), true);
});
test("independent conflict-ID collisions retain root origin through repeated nested imports", () => {
  const conflictID = `import:${day}:1`;
  const local = { notes: {}, notePages: { [conflictID]: extra(conflictID, "Same", { _plainwalkImportSourceID: "root-a" }) } };
  const incoming = { notes: {}, notePages: { [conflictID]: extra(conflictID, "Same", { _plainwalkImportSourceID: "root-b" }) } };
  const merged = mergeNotebookLibraries(local, incoming);
  assert.equal(notebookPages(merged).length, 2);
  assert.equal(merged.notePages[`import:${day}:2`]._plainwalkImportSourceID, "root-b");
  assert.deepEqual(mergeNotebookLibraries(merged, incoming), merged);
  const third = { notes: {}, notePages: { [conflictID]: extra(conflictID, "Same", { _plainwalkImportSourceID: "root-c" }) } };
  const nested = mergeNotebookLibraries(third, merged);
  assert.equal(notebookPages(nested).length, 3);
  assert.deepEqual(new Set(notebookPages(nested).map(page => page._plainwalkImportSourceID)), new Set(["root-a", "root-b", "root-c"]));
  assert.deepEqual(mergeNotebookLibraries(nested, merged), nested);
});
test("legacy slots with identical content retain different imported root identities", () => {
  const local = { notes: { [day]: { text: "Same", _plainwalkImportSourceID: "root-a" } } };
  const incoming = { notes: { [day]: { text: "Same", _plainwalkImportSourceID: "root-b" } } };
  const merged = mergeNotebookLibraries(local, incoming);
  assert.equal(notebookPages(merged).length, 2);
  assert.equal(merged.notePages[`import:${day}:1`]._plainwalkImportSourceID, "root-b");
  assert.deepEqual(mergeNotebookLibraries(merged, incoming), merged);
});
