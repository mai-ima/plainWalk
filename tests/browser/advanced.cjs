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
  const page = await ctx.newPage(),
    errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://127.0.0.1:4173");
  await page.waitForTimeout(200);
  await page.getByRole("button", { name: "メニュー", exact: true }).click();
  await page
    .getByRole("button", { name: "GPX / TCX を取り込む", exact: true })
    .click();
  await page
    .locator("#importFile")
    .setInputFiles({
      name: "edit-test.gpx",
      mimeType: "application/gpx+xml",
      buffer: Buffer.from(
        '<gpx><trk><trkseg><trkpt lat="35.680" lon="139.76"/><trkpt lat="35.681" lon="139.76"/><trkpt lat="35.681" lon="139.761"/></trkseg></trk></gpx>',
      ),
    });
  await page
    .getByRole("button", { name: "この道を白地図に残す", exact: true })
    .click();
  await page.getByRole("button", { name: /edit-test.*km/ }).click();
  await page
    .getByRole("button", { name: "軌跡を手で修正", exact: true })
    .click();
  const dot = page.locator('[data-edit-point="1"]');
  await dot.waitFor();
  const box = await dot.boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(
    box.x + box.width / 2 + 20,
    box.y + box.height / 2 + 10,
    { steps: 5 },
  );
  await page.mouse.up();
  await page.locator('#editorToolbar [data-action="editSave"]').click();
  await page.getByRole("button", { name: "閉じる", exact: true }).click();
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
  await page
    .locator("#spotVideo")
    .setInputFiles(require("./support.cjs").fixture("clip.mp4"));
  await page.locator("#spotVideoPreview").waitFor({ state: "visible" });
  await page.locator("#spotText").fill("2 秒の景色");
  await page
    .getByRole("button", { name: "この場所に残す", exact: true })
    .click();
  await page.getByRole("button", { name: "プロフィール", exact: true }).click();
  await page.getByRole("button", { name: "ここいいな", exact: true }).click();
  await page.getByRole("button", { name: /2 秒の景色/ }).click();
  assert.ok(
    (await page.locator("#sheetBody video").getAttribute("src")).startsWith(
      "data:video/mp4",
    ),
  );
  await page.getByRole("button", { name: "閉じる", exact: true }).click();
  await page.getByRole("button", { name: "マイマップ", exact: true }).click();
  await page.getByRole("button", { name: "メニュー", exact: true }).click();
  await page
    .getByRole("button", { name: "地図の成長を再生", exact: true })
    .click();
  const downloading = page.waitForEvent("download", { timeout: 20000 });
  await page
    .getByRole("button", { name: "動画にして保存", exact: true })
    .click();
  const download = await downloading;
  await download.saveAs(
    "/workspace/scratch/timelapse." +
      download.suggestedFilename().split(".").at(-1),
  );
  assert.equal(errors.length, 0, errors.join("\n"));
  console.log(
    "Route editing, two-second video pin and recorded timelapse export passed.",
  );
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
