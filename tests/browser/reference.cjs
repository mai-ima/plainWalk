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
    isMobile: true,
    hasTouch: true,
    deviceScaleFactor: 2,
  });
  const page = await ctx.newPage(),
    errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://127.0.0.1:4173");
  await page.waitForTimeout(700);
  assert.equal(
    await page
      .getByRole("button", { name: "ここいいな", exact: true })
      .isVisible(),
    false,
  );
  await page.screenshot({
    path: require("./support.cjs").artifact("map-reference-preview.png"),
    animations: "disabled",
  });
  await page.getByRole("button", { name: "地図レイヤー", exact: true }).click();
  await page
    .getByRole("heading", { name: "地図レイヤー", exact: true })
    .waitFor();
  assert.equal(await page.locator('[data-layer-key="pin"]').count(), 5);
  await page.screenshot({
    path: require("./support.cjs").artifact("layers-reference-preview.png"),
    animations: "disabled",
  });
  await page.getByRole("button", { name: "ミント", exact: true }).click();
  await page
    .getByRole("checkbox", { name: "方眼グリッドを表示", exact: true })
    .check();
  await page.getByRole("button", { name: "閉じる", exact: true }).click();
  await page.waitForTimeout(100);
  assert.ok((await page.locator("#mapGrid path").count()) > 0);
  await page.getByRole("button", { name: "プロフィール", exact: true }).click();
  await page.getByRole("button", { name: "ここいいな", exact: true }).click();
  await page
    .getByRole("heading", {
      name: "まだ「ここいいな」がありません",
      exact: true,
    })
    .waitFor();
  await page.screenshot({
    path: require("./support.cjs").artifact("spots-reference-preview.png"),
    animations: "disabled",
  });
  await page.getByRole("button", { name: "戻る", exact: true }).click();
  await page.getByRole("button", { name: "設定", exact: true }).click();
  await page.getByRole("heading", { name: "設定", exact: true }).waitFor();
  await page.screenshot({
    path: require("./support.cjs").artifact("settings-reference-preview.png"),
    animations: "disabled",
  });
  await page.getByRole("checkbox", { name: "beta 機能", exact: true }).check();
  await page.getByRole("button", { name: "体験モード", exact: true }).waitFor();
  assert.equal(errors.length, 0, errors.join("\n"));
  console.log(
    (engine === webkit ? "WebKit" : "Chromium") +
      ": reference map, five pin styles, grouped layers, grid, full-page empty state and grouped settings passed.",
  );
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
