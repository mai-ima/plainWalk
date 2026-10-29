const { chromium, webkit } = require("./support.cjs").playwright;
const assert = require("node:assert/strict");
(async () => {
  const engine = process.env.PW_ENGINE === "webkit" ? webkit : chromium;
  const browser = await engine.launch({
    headless: true,
    executablePath:
      engine === webkit
        ? require("./support.cjs").webkitExecutable
        : require("./support.cjs").chromiumExecutable,
    args: engine === chromium ? ["--no-sandbox"] : [],
  });
  const ctx = await browser.newContext({
    viewport: { width: 393, height: 852 },
    hasTouch: true,
    isMobile: true,
    acceptDownloads: true,
  });
  const page = await ctx.newPage(),
    errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://127.0.0.1:4173");
  const button = (name) => page.getByRole("button", { name, exact: true });
  await button("プロフィール").click();
  await button("ステッカー").click();
  await page
    .getByText("ここいいなの写真から切り抜いたステッカーが、ここに集まります。")
    .waitFor();
  await page.screenshot({
    path: require("./support.cjs").artifact("stickers-reference-preview.png"),
  });
  await button("戻る").click();
  await button("気になる場所").click();
  await page
    .getByRole("heading", { name: "気になる場所はまだありません" })
    .waitFor();
  await page.screenshot({
    path: require("./support.cjs").artifact("bookmarks-reference-preview.png"),
  });
  await button("マイマップ").click();
  await button("答え合わせマップ").click();
  await button("しおりを挟む").click();
  await page.locator("#mapViewport").tap({ position: { x: 160, y: 250 } });
  await page.locator("#bookmarkName").fill("路地の喫茶店");
  await page.locator("[data-bookmark-save]").click();
  await button("路地の喫茶店 ›").click();
  await button("ここへ向かう").click();
  await page.locator("#pins [data-flag]").waitFor();
  assert.equal(await page.locator("#pins [data-flag]").count(), 1);
  await button("プロフィール").click();
  await button("らくがき").click();
  await page.screenshot({
    path: require("./support.cjs").artifact("doodles-reference-preview.png"),
  });
  await button("らくがきを描く").last().click();
  await page.mouse.move(100, 300);
  await page.mouse.down();
  await page.mouse.move(200, 350, { steps: 15 });
  await page.mouse.move(240, 430, { steps: 15 });
  await page.mouse.up();
  await button("完了").click();
  await page.locator("[data-doodle]").waitFor();
  await page.reload();
  await button("プロフィール").click();
  await button("らくがき").click();
  await page.locator("[data-doodle]").click();
  await button("地図で見る").click();
  assert.ok(
    (await page.locator("#doodles path").getAttribute("d")).includes("L") ||
      (await page.locator("#doodles path").getAttribute("d")).includes("Q"),
  );
  await page.locator("#importFile").setInputFiles({
    name: "shared.gpx",
    mimeType: "application/gpx+xml",
    buffer: Buffer.from(
      '<gpx><trk><trkseg><trkpt lat="35.68" lon="139.76"><time>2026-10-29T10:00:00Z</time></trkpt><trkpt lat="35.681" lon="139.76"><time>2026-10-29T10:02:00Z</time></trkpt></trkseg></trk></gpx>',
    ),
  });
  await button("この道を白地図に残す").click();
  await button("プロフィール").click();
  await button("共有の白地図").click();
  await page.screenshot({
    path: require("./support.cjs").artifact("shared-reference-preview.png"),
  });
  await button("紙を作る").click();
  await page.locator("#sharedName").fill("週末の白地図");
  await page.locator("[data-shared-walk]").check();
  await page.locator("[data-action=sharedSave]").click();
  await page.locator("[data-shared-map]").click();
  const event = page.waitForEvent("download");
  await button("白地図ファイルを渡す").click();
  const file = await event;
  const fs = require("node:fs");
  const content = JSON.parse(fs.readFileSync(await file.path(), "utf8"));
  assert.equal(content.type, "plainwalk-white-map");
  assert.equal(content.name, "週末の白地図");
  assert.equal(content.photo, undefined);
  assert.equal(content.walks.length, 1);
  assert.equal(content.walks[0].points.length, 2);
  assert.equal(content.walks[0].points[0].t, undefined);
  await button("閉じる").click();
  await button("マイマップ").click();
  await button("メニュー").click();
  await button("GPX / TCX を取り込む").click();
  await page.locator("#importFile").setInputFiles({
    name: "white-map.json",
    mimeType: "application/json",
    buffer: Buffer.from(JSON.stringify(content)),
  });
  await page
    .getByRole("heading", { name: "共有の白地図", exact: true })
    .waitFor();
  assert.equal(await page.locator("[data-shared-map]").count(), 1);
  assert.deepEqual(errors, []);
  console.log(
    `${engine === webkit ? "WebKit" : "Chromium"}: profile routes, bookmark-to-flag, doodle drawing/reload, private white map export and deduplicated import passed.`,
  );
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
