const path = require("node:path");
const fs = require("node:fs");
const root = path.resolve(__dirname, "../..");
const playwright = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const chromiumExecutable =
  process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH ||
  (fs.existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined);
const webkitExecutable = process.env.PLAYWRIGHT_WEBKIT_EXECUTABLE_PATH;
const artifact = (name) => {
  const dir = path.join(root, "artifacts/previews");
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, name);
};
const fixture = (name) =>
  name === "icon.png"
    ? path.join(root, "web/public/icon.png")
    : path.join(root, "tests/fixtures", name);
module.exports = {
  playwright,
  chromiumExecutable,
  webkitExecutable,
  artifact,
  fixture,
};
