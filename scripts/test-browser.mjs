import { spawnSync } from "node:child_process";
// Start npm start in another terminal first. PW_ENGINE=webkit selects WebKit.
let ready = false;
for (let attempt = 0; attempt < 30; attempt++) {
  try {
    if ((await fetch("http://127.0.0.1:4173")).ok) {
      ready = true;
      break;
    }
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 100));
}
if (!ready)
  throw Error("Start npm start in another terminal before browser tests.");
const suites = process.argv.slice(2);
for (const name of suites.length
  ? suites
  : ["browser", "reference", "collections", "features"]) {
  if (!/^[a-z-]+$/.test(name)) throw Error("Invalid suite name.");
  const result = spawnSync(process.execPath, [`tests/browser/${name}.cjs`], {
    stdio: "inherit",
    env: process.env,
  });
  if (result.status !== 0) process.exit(result.status || 1);
}
