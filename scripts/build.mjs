import {
  readFile,
  readdir,
  stat,
  mkdir,
  writeFile,
  rm,
  cp,
} from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";
import { createHash } from "node:crypto";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const out = resolve(root, "dist");
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
await cp(resolve(root, "web/public"), out, { recursive: true });
await cp(resolve(root, "web/src"), out, { recursive: true });
// Distribution packages must never become nested inside the next native IPA
// or playground. The ordinary Web build retains working downloadable files.
if (process.argv.includes("--native")) {
  await rm(resolve(out, "downloads"), { recursive: true, force: true });
} else {
  let delivery;
  try { delivery = JSON.parse(await readFile(resolve(root, "web/public/downloads/build.json"), "utf8")); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  if (delivery?.available === true) {
    for (const [source, name, expected] of [
      ["distribution/ios/PlainWalk-iPhone-unsigned.ipa", "PlainWalk-iPhone-unsigned.ipa", delivery],
      ["distribution/playgrounds/PlainWalk.swiftpm.zip", "PlainWalk.swiftpm.zip", delivery.playgrounds],
    ]) {
      const bytes = await readFile(resolve(root, source));
      if (expected?.filename !== name || expected.bytes !== bytes.length || expected.sha256 !== createHash("sha256").update(bytes).digest("hex"))
        throw Error(`Download package metadata differs: ${name}`);
      await writeFile(resolve(out, "downloads", name), bytes);
    }
  }
}
await mkdir(resolve(out, "data"), { recursive: true });
await writeFile(
  resolve(out, "data/japan-municipalities.geojson"),
  gunzipSync(
    await readFile(resolve(root, "datasets/japan-municipalities.geojson.gz")),
  ),
);
const html = await readFile(resolve(out, "index.html"), "utf8");
for (const match of html.matchAll(/(?:src|href)="([^"#]+)"/g)) {
  if (!/^(https?:|data:)/.test(match[1])) await stat(resolve(out, match[1]));
}
for (const name of await readdir(resolve(root, "web/src"))) {
  if (!name.endsWith(".js")) continue;
  const source = await readFile(resolve(out, name), "utf8");
  for (const m of source.matchAll(/from\s+['"](\.\.?\/[^'"]+)['"]/g))
    await stat(resolve(out, m[1]));
}
const boundaries = JSON.parse(
  await readFile(resolve(out, "data/japan-municipalities.geojson"), "utf8"),
);
if (boundaries.features?.length !== 1905)
  throw Error("Japan boundary dataset is incomplete.");
console.log(
  "Built dist/ from web/src and web/public. Modules, entry points and 1,905 boundaries verified.",
);
