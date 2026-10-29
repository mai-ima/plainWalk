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
  });
  await ctx.addInitScript(() => {
    window.mockSession = null;
    window.nativeCalls = [];
    window.PlainWalkNative = {
      request: async (action, p = {}) => {
        window.nativeCalls.push({ action, p });
        if (action === "storageRead")
          return JSON.parse(localStorage.getItem("native-" + p.key) || "null");
        if (action === "storageWrite") {
          localStorage.setItem("native-" + p.key, JSON.stringify(p.value));
          return null;
        }
        if (action === "status") return { session: window.mockSession };
        if (action === "locationStart") {
          if (p.recording) {
            window.mockSession = {
              id: p.sessionID,
              start: p.start,
              points: window.mockSession?.points || [],
              recording: true,
            };
          }
          return null;
        }
        if (action === "locationStop") {
          if (p.end) window.mockSession = null;
          else if (window.mockSession) window.mockSession.recording = false;
          return null;
        }
        if (action === "healthSteps" || action === "pedometerSteps")
          return { steps: 4321 };
        if (action === "healthWorkouts") return [];
        if (
          action === "ready" ||
          action === "haptic" ||
          action === "showMap" ||
          action === "shareFile"
        )
          return null;
        throw Error(action);
      },
    };
  });
  const page = await ctx.newPage(),
    errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://127.0.0.1:4173");
  await page.getByRole("button", { name: "散歩を始める", exact: true }).click();
  await page
    .getByRole("button", { name: "散歩を始める", exact: true })
    .last()
    .click();
  await page.waitForTimeout(200);
  await page.evaluate(() => {
    for (let i = 0; i < 4; i++) {
      const point = {
        lat: 35.68 + i * 0.0001,
        lon: 139.76,
        t: Date.now() + i * 2000,
        seq: i + 1,
        accuracy: 5,
        gap: false,
      };
      window.mockSession.points.push(point);
      window.dispatchEvent(
        new CustomEvent("plainwalk-native", {
          detail: {
            event: "location",
            point,
            sessionID: window.mockSession.id,
          },
        }),
      );
    }
  });
  await page
    .getByRole("button", { name: "記録を一時停止する", exact: true })
    .click();
  await page
    .getByRole("button", { name: "記録を再開する", exact: true })
    .waitFor();
  const holdBox = await page
    .getByRole("button", { name: "記録を再開する", exact: true })
    .boundingBox();
  await page.mouse.move(
    holdBox.x + holdBox.width / 2,
    holdBox.y + holdBox.height / 2,
  );
  await page.mouse.down();
  await page.waitForTimeout(1100);
  await page.mouse.up();
  await page.getByRole("button", { name: "閉じる", exact: true }).click();
  await page.getByRole("button", { name: "プロフィール", exact: true }).click();
  await page.getByRole("button", { name: "設定", exact: true }).click();
  await page
    .getByRole("button", { name: "1 日の歩数の目標", exact: true })
    .click();
  await page
    .getByRole("button", { name: "今日の歩数を更新", exact: true })
    .click();
  assert.equal(await page.locator("#manualSteps").inputValue(), "4321");
  assert.equal(
    await page.evaluate(
      () => JSON.parse(localStorage.getItem("native-library")).walks.length,
    ),
    1,
  );
  assert.ok(
    await page.evaluate(() =>
      nativeCalls.some((c) => c.action === "locationStop" && c.p.end),
    ),
  );
  assert.equal(errors.length, 0, errors.join("\n"));
  console.log(
    "Native bridge contract: recording, pause, durable save, HealthKit response and end passed (mock adapter; not an iOS runtime test).",
  );
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
