const { chromium } = require("./support.cjs").playwright;
const assert = require("node:assert/strict");
(async () => {
  const browser = await chromium.launch({
    executablePath: require("./support.cjs").chromiumExecutable,
    headless: true,
    args: ["--no-sandbox"],
  });
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
    acceptDownloads: true,
  });
  const page = await ctx.newPage();
  let errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://127.0.0.1:4173");
  await page.waitForTimeout(400);
  await page.getByRole("button", { name: "メニュー", exact: true }).click();
  await page
    .getByRole("button", { name: "GPX / TCX を取り込む", exact: true })
    .click();
  await page
    .locator("#importFile")
    .setInputFiles({
      name: "park.gpx",
      mimeType: "application/gpx+xml",
      buffer: Buffer.from(
        '<gpx><trk><trkseg><trkpt lat="35.680" lon="139.76"><time>2026-10-29T10:00:00Z</time></trkpt><trkpt lat="35.681" lon="139.76"><time>2026-10-29T10:03:00Z</time></trkpt><trkpt lat="35.681" lon="139.761"><time>2026-10-29T10:05:00Z</time></trkpt></trkseg></trk></gpx>',
      ),
    });
  await page
    .getByRole("button", { name: "この道を白地図に残す", exact: true })
    .click();
  await page.getByRole("button", { name: "プロフィール", exact: true }).click();
  await page.getByRole("button", { name: "目的地の旗", exact: true }).click();
  await page.getByRole("button", { name: "旗を立てる", exact: true }).click();
  await page.locator("#flagName").fill("公園");
  await page.locator("#flagLat").fill("35.681");
  await page.locator("#flagLon").fill("139.761");
  await page
    .getByRole("button", { name: "この場所に旗を立てる", exact: true })
    .click();
  await page.getByRole("button", { name: /公園.*35/ }).waitFor();
  await page.getByRole("button", { name: "閉じる", exact: true }).click();
  await page.getByRole("button", { name: "マイマップ", exact: true }).click();
  await page.getByRole("button", { name: "散歩を始める", exact: true }).click();
  await page
    .getByRole("button", { name: "散歩を始める", exact: true })
    .last()
    .click();
  await page.getByRole("button", { name: "ここいいな", exact: true }).click();
  await page
    .getByRole("button", { name: "地図から場所を選ぶ", exact: true })
    .click();
  await page.locator("#mapViewport").tap({ position: { x: 150, y: 220 } });
  await page.locator("#spotText").fill("小さな公園を見つけた");
  await page
    .locator("#spotPhoto")
    .setInputFiles(require("./support.cjs").fixture("icon.png"));
  await page
    .getByRole("button", { name: "この場所に残す", exact: true })
    .click();
  await page.getByRole("button", { name: "プロフィール", exact: true }).click();
  await page.getByRole("button", { name: "ノート", exact: true }).click();
  await page.locator("#dailyNote").fill("今日の道。");
  await page
    .getByRole("button", { name: "🌿 のステッカー", exact: true })
    .click();
  await page.getByRole("button", { name: "ノートを保存", exact: true }).click();
  await page.getByRole("button", { name: "閉じる", exact: true }).click();
  const downloadEvent = page.waitForEvent("download");
  await page
    .getByRole("button", { name: "データのバックアップ", exact: true })
    .click();
  const dl = await downloadEvent;
  assert.ok(dl.suggestedFilename().endsWith(".json"));
  await page.getByRole("button", { name: "マイマップ", exact: true }).click();
  await page
    .getByRole("button", { name: "記録の詳細と終了", exact: true })
    .click();
  await page.getByRole("button", { name: "記録を破棄", exact: true }).click();
  await page
    .getByRole("button", { name: "この記録を破棄", exact: true })
    .click();
  await page.screenshot({
    path: require("./support.cjs").artifact("route-preview.png"),
  });
  await page
    .getByRole("button", { name: "答え合わせマップ", exact: true })
    .click();
  await page.waitForTimeout(200);
  await page.locator("#tiles img").first().waitFor();
  await page
    .getByRole("button", { name: "答え合わせマップ", exact: true })
    .click();
  await page
    .getByRole("button", { name: "答え合わせマップ", exact: true })
    .click();
  await page.locator("#tiles img").first().waitFor();
  await page
    .getByRole("button", { name: "答え合わせマップ", exact: true })
    .click();
  await page.waitForFunction(() => navigator.serviceWorker.controller);
  await ctx.setOffline(true);
  await page.reload();
  await page.getByRole("button", { name: "記録", exact: true }).click();
  await page.getByRole("button", { name: /park/ }).waitFor();
  assert.equal(errors.length, 0, errors.join("\n"));
  console.log(
    "GPX, flags, photo pins, notes, backup, tile toggle and offline persistence passed.",
  );
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
