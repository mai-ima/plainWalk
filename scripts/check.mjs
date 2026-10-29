import { readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
for (const folder of ["web/src", "web/public", "scripts"]) {
  for (const name of readdirSync(folder).filter((name) =>
    /\.(m?js)$/.test(name),
  )) {
    const result = spawnSync(
      process.execPath,
      ["--check", `${folder}/${name}`],
      { stdio: "inherit" },
    );
    if (result.status !== 0) process.exit(result.status || 1);
  }
}
console.log("All source modules and scripts passed syntax checks.");
