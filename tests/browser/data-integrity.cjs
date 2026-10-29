const assert = require("node:assert/strict");
const { playwright, chromiumExecutable } = require("./support.cjs");

(async () => {
  const browser = await playwright.chromium.launch({
    executablePath: chromiumExecutable,
    headless: true,
    args: ["--no-sandbox"],
  });
  try {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true,
    });
    await context.addInitScript(() => {
      window.mockFault = "";
      window.nativeCalls = [];
      window.mockSession = null;
      window.PlainWalkNative = {
        request: async (action, p = {}) => {
          window.nativeCalls.push({ action, p });
          if (action === "storageRead")
            return JSON.parse(localStorage.getItem("native-" + p.key) || "null");
          if (action === "storageWrite") {
            if (window.mockFault === p.key ||
              (window.mockFault === "clear" && p.key === "active" && p.value === null))
              throw Error("Simulated storage failure");
            localStorage.setItem("native-" + p.key, JSON.stringify(p.value));
          } else if (action === "status") return { session: window.mockSession };
          else if (action === "locationStart" && p.recording) {
            window.mockSession = {
              id: p.sessionID, start: p.start, recording: true,
              points: window.mockSession?.points || [],
            };
          } else if (action === "locationStop") {
            if (p.end) window.mockSession = null;
            else if (window.mockSession) window.mockSession.recording = false;
          }
          return null;
        },
      };
    });
    const page = await context.newPage(), errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("http://127.0.0.1:4173");
    await page.locator("#recordButton").waitFor();

    // Exercise the browser's XML parser, including namespaced TCX and GPX.
    const parsed = await page.evaluate(async () => {
      const { parseTrack, gpx, trailDistance } = await import("/core.js");
      const points = parseTrack(`<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
        <trkpt lat="0" lon="0"><time>1970-01-01T00:00:00Z</time></trkpt>
        <trkpt lat="0.00001" lon="0"/>
        <trkpt lat="0.00002" lon="0"><time>1970-01-01T00:00:02Z</time></trkpt>
        <trkpt lat="0.00003" lon=""/>
        <trkpt lat="0.00004" lon="0"><time>1970-01-01T00:00:04Z</time></trkpt>
      </trkseg></trk></gpx>`);
      const tcx = parseTrack(`<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities><Activity><Lap><Track>
        <Trackpoint><Time>2026-01-01T01:00:00Z</Time><Position><LatitudeDegrees>35</LatitudeDegrees><LongitudeDegrees>139</LongitudeDegrees></Position></Trackpoint>
        <Trackpoint><Position><LatitudeDegrees>35.0001</LatitudeDegrees><LongitudeDegrees> </LongitudeDegrees></Position></Trackpoint>
        <Trackpoint><Time>2026-01-01T01:00:02Z</Time><Position><LatitudeDegrees>35.0002</LatitudeDegrees><LongitudeDegrees>139</LongitudeDegrees></Position></Trackpoint>
      </Track></Lap></Activity></Activities></TrainingCenterDatabase>`);
      const routes = parseTrack(`<gpx><rte><rtept lat="35" lon="139"/></rte><rte><rtept lat="36" lon="140"/></rte></gpx>`);
      return { points, tcx, routes, tcxDistance: trailDistance(tcx), roundTrip: parseTrack(gpx({ name: "Epoch", points })) };
    });
    assert.equal(parsed.points.length, 4);
    assert.deepEqual(parsed.points.map((p) => p.t), [0, 1000, 2000, 4000]);
    assert.equal(parsed.points[3].break, true);
    assert.equal(parsed.tcx.length, 2);
    assert.equal(parsed.tcx[1].break, true);
    assert.equal(parsed.tcxDistance, 0);
    assert.equal(parsed.routes[1].break, true);
    assert.equal(parsed.routes[1].t - parsed.routes[0].t, 1000);
    assert.deepEqual(parsed.roundTrip, parsed.points);

    const action = (name) => page.evaluate((name) =>
      window.dispatchEvent(new CustomEvent("plainwalk-native", {
        detail: { event: "uiAction", action: name },
      })), name);
    const saved = () => page.evaluate(() =>
      JSON.parse(localStorage.getItem("native-library") || "null"));

    // A failed initial checkpoint must not start location recording.
    await page.evaluate(() => { window.mockFault = "active"; });
    await action("begin");
    await page.getByText("記録の自動保存に失敗しました。バックアップを確認してください。", { exact: true }).waitFor();
    assert.equal(await page.evaluate(() => nativeCalls.filter((c) => c.action === "locationStart").length), 0);
    await page.getByRole("button", { name: "散歩を始める", exact: true }).waitFor();

    await page.evaluate(() => { window.mockFault = ""; });
    await action("begin");
    await page.getByRole("button", { name: "記録を一時停止する", exact: true }).waitFor();
    await page.evaluate(() => {
      for (let i = 0; i < 3; i++) {
        const point = {
          lat: 35 + i * 0.0001, lon: 139,
          t: Date.now() + i * 2000, seq: i + 1, accuracy: 5,
        };
        window.mockSession.points.push(point);
        window.dispatchEvent(new CustomEvent("plainwalk-native", {
          detail: { event: "location", point, sessionID: window.mockSession.id },
        }));
      }
      window.mockFault = "active";
    });
    await action("pause");
    await page.getByText("記録の自動保存に失敗しました。バックアップを確認してください。", { exact: true }).waitFor();
    assert.equal(await page.evaluate(() => mockSession.recording), true);
    await page.getByRole("button", { name: "記録を一時停止する", exact: true }).waitFor();
    await page.evaluate(() => { window.mockFault = ""; });
    await action("pause");
    await page.getByRole("button", { name: "記録を再開する", exact: true }).waitFor();
    assert.equal(await page.evaluate(() => mockSession.recording), false);

    // Simulate a crash after the library commit but before checkpoint removal.
    await page.evaluate(() => { window.mockFault = "clear"; });
    await action("finish");
    await page.getByText("今日の道を、白地図に残しました。", { exact: true }).waitFor();
    assert.equal((await saved()).walks.length, 1);
    assert.notEqual(await page.evaluate(() => localStorage.getItem("native-active")), "null");
    await page.reload();
    await page.getByRole("button", { name: "散歩を始める", exact: true }).waitFor();
    assert.equal(await page.getByText("中断したさんぽがあります", { exact: true }).count(), 0);
    assert.equal((await saved()).walks.length, 1);
    assert.equal(await page.evaluate(() => localStorage.getItem("native-active")), "null");

    // Zero is recorded data, and metadata from native clients must survive merge.
    await action("steps");
    await page.locator("#manualSteps").fill("0");
    await page.getByRole("button", { name: "保存", exact: true }).click();
    await page.waitForFunction(() => document.querySelector("#steps").textContent === "0");
    const incoming = {
      version: 1, walks: [], spots: [], flags: [],
      nativeMetadata: { schema: 2 },
      notes: { "2000-01-01": { text: "Native", nativeStyle: { size: 17 } } },
    };
    await page.locator("#importFile").setInputFiles({
      name: "native.json", mimeType: "application/json", buffer: Buffer.from(JSON.stringify(incoming)),
    });
    await page.getByRole("button", { name: "確認して取り込む", exact: true }).click();
    await page.getByText("バックアップを取り込みました。", { exact: true }).waitFor();
    assert.deepEqual((await saved()).nativeMetadata, { schema: 2 });
    assert.deepEqual((await saved()).notes["2000-01-01"].nativeStyle, { size: 17 });

    // A quota failure leaves the pending import retryable without duplicate IDs.
    await page.locator("#importFile").setInputFiles({
      name: "retry.gpx", mimeType: "application/gpx+xml",
      buffer: Buffer.from('<gpx><trk><trkseg><trkpt lat="35" lon="139"/><trkpt lat="35.0001" lon="139"/></trkseg></trk></gpx>'),
    });
    await page.evaluate(() => { window.mockFault = "library"; });
    await page.getByRole("button", { name: "この道を白地図に残す", exact: true }).click();
    await page.locator("#toast").filter({ hasText: "Simulated storage failure" }).waitFor();
    assert.equal((await saved()).walks.length, 1);
    await page.evaluate(() => { window.mockFault = ""; });
    await page.getByRole("button", { name: "この道を白地図に残す", exact: true }).click();
    await page.getByText("歩いた道を取り込みました。", { exact: true }).waitFor();
    assert.equal((await saved()).walks.length, 2);
    assert.equal(errors.length, 0, errors.join("\n"));
    console.log("Data integrity: GPX/TCX gaps and time round trips, failed start/pause, post-commit recovery, zero steps, native metadata and quota retry passed (mock bridge).");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
