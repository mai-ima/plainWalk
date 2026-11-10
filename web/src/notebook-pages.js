// Additive notebook storage: the original day envelope remains the first page.
// Further pages have stable IDs; daily metadata is never copied into them.
const fields = ["text", "stickers", "paper", "font", "layout"];
export const legacyNoteID = day => `legacy:${day}`;
export const notebookSourceID = page => typeof page._plainwalkImportSourceID === "string" && page._plainwalkImportSourceID.length > 0 && page._plainwalkImportSourceID.length <= 200 ? page._plainwalkImportSourceID : page.id;
const clone = value => structuredClone(value);
export function notebookContent(page = {}) {
  const result = { text: "", stickers: "", paper: "plain", font: "serif", layout: [], ...clone(page) };
  for (const [key, value] of Object.entries({ text: "", stickers: "", paper: "plain", font: "serif", layout: [] }))
    if (result[key] == null) result[key] = value;
  for (const key of ["id", "day", "steps", "pageDeleted", "_plainwalkImportSourceID"]) delete result[key];
  return result;
}
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
export const sameNotebookContent = (a, b) => JSON.stringify(canonical(notebookContent(a))) === JSON.stringify(canonical(notebookContent(b)));
export function notebookPages(library, day) {
  const groups = new Map();
  const add = page => { if (!groups.has(page.day)) groups.set(page.day, []); groups.get(page.day).push(page); };
  for (const [date, value] of Object.entries(library.notes || {}))
    if ((!day || date === day) && value && !value.pageDeleted) add({ ...value, day: date, id: legacyNoteID(date) });
  const extra = Object.entries(library.notePages || {}).filter(([, value]) => value && (!day || value.day === day)).map(([id, value]) => ({ ...value, id })).sort((a, b) => (Number(a.created) || 0) - (Number(b.created) || 0) || a.id.localeCompare(b.id));
  for (const page of extra) add(page);
  return [...groups.keys()].sort().reverse().flatMap(date => groups.get(date));
}
export function notebookPage(library, day, id = legacyNoteID(day)) {
  if (id === legacyNoteID(day)) {
    const note = library.notes?.[day];
    return note && !note.pageDeleted ? { ...clone(note), day, id } : null;
  }
  const page = library.notePages?.[id];
  return page?.day === day ? { ...clone(page), day, id } : null;
}
export function putNotebookPage(library, page) {
  const notes = { ...(library.notes || {}) }, notePages = { ...(library.notePages || {}) };
  const content = notebookContent(page);
  if (page._plainwalkImportSourceID !== undefined) content._plainwalkImportSourceID = page._plainwalkImportSourceID;
  if (page.id === legacyNoteID(page.day)) {
    const value = { ...notes[page.day], ...content, day: page.day };
    delete value.pageDeleted;
    notes[page.day] = value;
  } else notePages[page.id] = { ...notePages[page.id], ...content, id: page.id, day: page.day };
  return { ...library, notes, notePages };
}
export function removeNotebookPage(library, day, id) {
  const notes = { ...(library.notes || {}) }, notePages = { ...(library.notePages || {}) };
  if (id === legacyNoteID(day)) {
    const value = { ...notes[day], day, pageDeleted: true };
    for (const key of fields) delete value[key];
    notes[day] = value;
  } else if (notePages[id]?.day === day) delete notePages[id];
  return { ...library, notes, notePages };
}
export function mergeNotebookLibraries(local, incoming) {
  let result = { ...local, notes: clone(local.notes || {}), notePages: clone(local.notePages || {}) };
  const copies = new Map();
  const contentKey = page => JSON.stringify(canonical(notebookContent(page)));
  const sourceKey = (day, sourceID) => `${day}|${sourceID}`;
  const rememberCopy = page => {
    const key = sourceKey(page.day, notebookSourceID(page));
    if (!copies.has(key)) copies.set(key, new Set());
    copies.get(key).add(contentKey(page));
  };
  for (const page of notebookPages(result)) rememberCopy(page);
  const nextImport = new Map();
  const addCopy = page => {
    // Equal contents are not page identity: two intentionally blank pages must
    // remain two pages. Only suppress a previous copy of this exact source ID.
    if (copies.get(sourceKey(page.day, notebookSourceID(page)))?.has(contentKey(page))) return;
    let n = nextImport.get(page.day) || 1, id;
    do { id = `import:${page.day}:${n++}`; } while (Object.hasOwn(result.notePages, id));
    nextImport.set(page.day, n);
    const copy = { ...notebookContent(page), day: page.day, id, _plainwalkImportSourceID: notebookSourceID(page) };
    result.notePages[id] = copy;
    rememberCopy(copy);
  };
  for (const day of Object.keys(incoming.notes || {}).sort()) {
    const value = incoming.notes[day], existing = result.notes[day];
    if (!existing) { result.notes[day] = clone(value); if (!value.pageDeleted) rememberCopy({ ...value, day, id: legacyNoteID(day) }); continue; }
    if (existing.steps === undefined && value.steps !== undefined) result.notes[day] = { ...existing, steps: value.steps };
    if (!value.pageDeleted && (existing.pageDeleted || notebookSourceID({ ...existing, id: legacyNoteID(day) }) !== notebookSourceID({ ...value, id: legacyNoteID(day) }) || !sameNotebookContent(existing, value))) addCopy({ ...value, day, id: legacyNoteID(day) });
  }
  for (const id of Object.keys(incoming.notePages || {}).sort()) {
    const page = { ...incoming.notePages[id], id }, existing = result.notePages[id];
    if (!existing) {
      result.notePages[id] = clone(page);
      rememberCopy(page);
    } else if (existing.day !== page.day || notebookSourceID(existing) !== notebookSourceID(page) || !sameNotebookContent(existing, page)) addCopy(page);
  }
  return result;
}
