const { playwright, chromiumExecutable, artifact } = require("./support.cjs");
const assert = require("node:assert/strict");
const fs = require("node:fs");
(async () => {
  const engine =
    process.env.PW_ENGINE === "webkit"
      ? playwright.webkit
      : playwright.chromium;
  const b = await engine.launch({
    headless: true,
    executablePath:
      engine === playwright.webkit
        ? require("./support.cjs").webkitExecutable
        : chromiumExecutable,
    args: engine === playwright.chromium ? ["--no-sandbox"] : [],
  });
  try {
    const ctx = await b.newContext({
      viewport: { width: 393, height: 852 },
      acceptDownloads: true,
    });
    await ctx.addInitScript(() => {
      window.geoRequests = 0;
      const original = navigator.geolocation.watchPosition.bind(
        navigator.geolocation,
      );
      navigator.geolocation.watchPosition = (...args) => {
        window.geoRequests++;
        return original(...args);
      };
    });
    const p = await ctx.newPage(),
      errors = [];
    p.on("pageerror", (e) => errors.push(e.message));
    await p.goto("http://127.0.0.1:4173");
    await p.getByRole("button", { name: "プロフィール", exact: true }).click();
    await p.getByRole("button", { name: "設定", exact: true }).click();
    await p
      .getByRole("checkbox", { name: "開発者モード", exact: true })
      .check();
    await p
      .getByRole("button", { name: "実機検証・診断ログ", exact: true })
      .click();
    await p.getByRole("heading", { name: "開発者向け", exact: true }).waitFor();
    assert.equal(await p.evaluate(() => geoRequests), 0);
    await p
      .getByRole("button", { name: "保存を往復テスト", exact: true })
      .click();
    await p.getByText(/保存の往復：成功/).waitFor();
    await p
      .getByRole("button", { name: "画面描画テスト", exact: true })
      .click();
    await p.getByText(/描画 .* 回/).waitFor();
    await p.locator("[data-dev-check=launch]").click();
    await p.locator("[data-dev-check=launch]").getByText("確認済み").waitFor();
    await p
      .getByRole("checkbox", { name: "タップ領域に枠を表示", exact: true })
      .check();
    await p.waitForFunction(() =>
      document.body.classList.contains("dev-outlines"),
    );
    await p
      .getByRole("checkbox", { name: "GPS 状態を小さく常時表示", exact: true })
      .check();
    await p.locator("#developerHUD").waitFor({ state: "visible" });
    const event = p.waitForEvent("download");
    await p
      .getByRole("button", { name: "診断 JSON を書き出す", exact: true })
      .click();
    const file = await event;
    const report = JSON.parse(fs.readFileSync(await file.path(), "utf8"));
    assert.equal(report.storageTest.ok, true);
    assert.ok(report.frameTest.samples > 1);
    assert.equal(report.checks.launch, "passed");
    assert.equal(report.library.walks, 0);
    assert.equal(JSON.stringify(report).includes('"lat"'), false);
    assert.equal(JSON.stringify(report).includes('"lon"'), false);
    const noProbe = await p.evaluate(
      () =>
        new Promise((resolve, reject) => {
          const r = indexedDB.open("plainwalk-web");
          r.onsuccess = () => {
            const db = r.result,
              request = db
                .transaction("data")
                .objectStore("data")
                .get("diagnostics-probe");
            request.onsuccess = () => {
              resolve(request.result === undefined);
              db.close();
            };
            request.onerror = reject;
          };
        }),
    );
    assert.equal(noProbe, true);
    await p.screenshot({ path: artifact("developer-preview.png") });
    await p.getByRole("button", { name: "戻る", exact: true }).click();
    await p
      .getByRole("checkbox", { name: "開発者モード", exact: true })
      .uncheck();
    await p.locator("#developerHUD").waitFor({ state: "hidden" });
    assert.deepEqual(errors, []);
    console.log(
      "Developer mode: no implicit GPS request, isolated storage probe, manual checklist, HUD, coordinate-free JSON and disable cleanup passed.",
    );
  } finally {
    await b.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
