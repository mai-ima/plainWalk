import { readFile, writeFile, mkdir, copyFile, rm, realpath, stat } from "node:fs/promises";
import { resolve, dirname, relative, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
function argument(name, fallback) {
  const index = args.indexOf(name);
  if (index < 0) return fallback;
  if (!args[index + 1] || args[index + 1].startsWith("--")) throw new Error(`Missing value for ${name}`);
  return resolve(root, args[index + 1]);
}
const output = argument("--out", resolve(root, "dist/screens"));
const sources = [
  { platform: "web", path: argument("--web", resolve(root, "artifacts/previews/web-all/manifest.json")) },
  { platform: "native", path: argument("--native", resolve(root, "artifacts/previews/native-all/manifest.json")) },
];
function contained(base, file) {
  const value = relative(base, file);
  return value !== "" && value !== ".." && !value.startsWith(`..${sep}`) && !value.startsWith(sep);
}
if (!contained(root, output) || output.startsWith(resolve(root, "web") + sep) || output.startsWith(resolve(root, "ios") + sep)) {
  throw new Error("Gallery output must be a generated folder within this project.");
}
const imageOutput = resolve(output, "images");
await mkdir(output, { recursive: true });
await rm(imageOutput, { recursive: true, force: true });
await mkdir(imageOutput, { recursive: true });
const result = { version: 1, generatedAt: new Date().toISOString(), screens: [], sources: [], limitations: [] };
const ids = new Set();
let failures = 0;
const allowedStatuses = new Set(["captured", "missing", "physical-only", "unsupported", "pending", "error"]);

for (const source of sources) {
  let manifest;
  try { manifest = JSON.parse(await readFile(source.path, "utf8")); }
  catch (error) {
    if (error.code !== "ENOENT") throw error;
    result.sources.push({ platform: source.platform, status: "pending", count: 0 });
    continue;
  }
  if (!Array.isArray(manifest.screens)) throw new Error(`Invalid ${source.platform} screen manifest.`);
  if (manifest.complete === false) throw new Error(`${source.platform} screen capture is still in progress.`);
  const sourceFolder = await realpath(dirname(source.path));
  let copied = 0;
  for (let index = 0; index < manifest.screens.length; index += 1) {
    const raw = manifest.screens[index];
    if (!raw || typeof raw.key !== "string" || typeof raw.title !== "string") throw new Error(`Invalid ${source.platform} screen entry ${index}.`);
    const slug = raw.key.replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 100) || `screen-${index + 1}`;
    let id = `${source.platform}-${slug}`;
    if (ids.has(id)) id += `-${index + 1}`;
    if (ids.has(id)) throw new Error(`Duplicate gallery ID ${id}.`);
    ids.add(id);
    const entry = {
      id, key: raw.key, title: raw.title, platform: source.platform,
      category: typeof raw.category === "string" ? raw.category : "その他",
      state: typeof raw.state === "string" ? raw.state : "fixture",
      part: Number.isInteger(raw.part) && raw.part > 0 ? raw.part : 1,
      sourceRoute: typeof raw.sourceRoute === "string" ? raw.sourceRoute : raw.key,
      status: allowedStatuses.has(raw.status) ? raw.status : "captured",
    };
    if (typeof raw.note === "string") entry.note = raw.note;
    const sourceImage = raw.path ?? raw.file;
    if (entry.status === "captured") {
      try {
        if (typeof sourceImage !== "string" || !sourceImage || /^(?:[a-z]+:|\/\/)/i.test(sourceImage)) throw new Error("Image path missing or invalid.");
        let candidate = resolve(sourceFolder, sourceImage);
        // Capture manifests can use project-relative artifact paths as well.
        if (!contained(sourceFolder, candidate) && sourceImage.startsWith("artifacts/")) candidate = resolve(root, sourceImage);
        if (!contained(sourceFolder, candidate)) throw new Error("Image path leaves the capture folder.");
        const image = await realpath(candidate);
        if (!contained(sourceFolder, image)) throw new Error("Image symlink leaves the capture folder.");
        const extension = extname(image).toLowerCase();
        if (![".png", ".jpg", ".jpeg", ".webp"].includes(extension)) throw new Error("Unsupported screenshot format.");
        const details = await stat(image);
        if (!details.isFile() || details.size < 1 || details.size > 30 * 1024 * 1024) throw new Error("Invalid screenshot size.");
        const filename = `${id}${extension}`;
        await copyFile(image, resolve(imageOutput, filename));
        entry.image = `images/${filename}`;
        copied += 1;
      } catch (error) {
        entry.status = "missing";
        entry.note = "撮影画像を確認できませんでした。";
        failures += 1;
        console.error(`${source.platform}/${raw.key}: ${error.message}`);
      }
    }
    result.screens.push(entry);
  }
  result.sources.push({ platform: source.platform, status: "available", count: copied, generatedAt: manifest.generatedAt ?? null, engine: manifest.engine ?? null, viewport: manifest.viewport ?? null });
  if (Array.isArray(manifest.limitations)) result.limitations.push(...manifest.limitations.filter((item) => typeof item === "string").map((note) => ({ platform: source.platform, note })));
}
await writeFile(resolve(output, "manifest.json"), JSON.stringify(result, null, 2) + "\n");
console.log(JSON.stringify({ gallery: relative(root, output), captured: result.screens.filter((entry) => entry.status === "captured").length, otherStates: result.screens.filter((entry) => entry.status !== "captured").length, platforms: result.sources, missingFiles: failures }));
if (failures) process.exitCode = 2;
