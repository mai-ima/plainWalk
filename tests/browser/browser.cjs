const { chromium } = require("./support.cjs").playwright;
const assert = require("node:assert/strict");
(async () => {
  const browser = await chromium.launch({
    executablePath: require("./support.cjs").chromiumExecutable,
    headless: true,
    args: ["--no-sandbox"],
  });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    geolocation: { latitude: 35.68, longitude: 139.76, accuracy: 5 },
    permissions: ["geolocation"],
  });
  const page = await context.newPage();
  let errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://127.0.0.1:4173");
  await page.waitForTimeout(500);
  await page.screenshot({
    path: require("./support.cjs").artifact("map-preview.png"),
  });
  await page.getByRole("button", { name: "メニュー", exact: true }).click();
  await page.getByRole("button", { name: "設定", exact: true }).click();
  await page.getByRole("checkbox", { name: "beta 機能", exact: true }).check();
  await page.getByRole("button", { name: "GPS の診断", exact: true }).waitFor();
  await page.getByRole("button", { name: "戻る", exact: true }).click();
  await page.getByRole("button", { name: "散歩を始める", exact: true }).click();
  await page
    .getByRole("button", { name: "散歩を始める", exact: true })
    .last()
    .click();
  await page.waitForTimeout(600);
  for (let i = 1; i <= 5; i++) {
    await context.setGeolocation({
      latitude: 35.68 + i * 0.0001,
      longitude: 139.76 + i * 0.00005,
      accuracy: 5,
    });
    await page.waitForTimeout(1200);
  }
  await page
    .getByRole("button", { name: "記録の詳細と終了", exact: true })
    .click();
  await page
    .getByRole("button", { name: "さんぽを保存して終了", exact: true })
    .click();
  await page.waitForTimeout(600);
  await page.locator("#walkName").fill("朝の寄り道");
  await page.locator("#walkNote").fill("公園の緑がきれい。");
  await page.getByRole("button", { name: "変更を保存", exact: true }).click();
  await page
    .getByRole("heading", { name: "朝の寄り道", exact: true })
    .waitFor();
  await page.getByRole("button", { name: "閉じる", exact: true }).click();
  await page.screenshot({
    path: require("./support.cjs").artifact("records-preview.png"),
  });
  await page.reload();
  await page.waitForTimeout(300);
  await page.getByRole("button", { name: "記録", exact: true }).click();
  await page.getByRole("button", { name: /朝の寄り道/ }).waitFor();
  await page.getByRole("button", { name: "プロフィール", exact: true }).click();
  await page.screenshot({
    path: require("./support.cjs").artifact("profile-preview.png"),
  });
  assert.equal(errors.length, 0, errors.join("\n"));
  console.log("Mobile flows passed; no runtime errors.");
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
