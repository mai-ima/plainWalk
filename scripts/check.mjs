import { readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
for (const name of readdirSync("dist").filter((name) => name.endsWith(".js"))) {
  const result = spawnSync(process.execPath, ["--check", `dist/${name}`], {
    stdio: "inherit",
  });
  if (result.status !== 0) process.exit(result.status || 1);
}
console.log("All application modules passed syntax checks.");
