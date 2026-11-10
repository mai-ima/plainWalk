const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { createServer } = require("node:http");
const { playwright, chromiumExecutable, webkitExecutable, artifact } = require("./support.cjs");

(async () => {
  const engine = process.env.PW_ENGINE === "webkit" ? playwright.webkit : playwright.chromium;
  const browser = await engine.launch({ headless: true,
    executablePath: engine === playwright.webkit ? webkitExecutable : chromiumExecutable,
    args: engine === playwright.chromium ? ["--no-sandbox"] : [] });
  let server;
  try {
    const context = await browser.newContext({ viewport: { width: 393, height: 852 },
      isMobile: true, hasTouch: true, acceptDownloads: true, locale: "ja-JP" });
    const page = await context.newPage(), errors = [];
    page.setDefaultTimeout(12000);
    page.on("pageerror", error => errors.push(error.message));
    // UI download fixtures only. Real iPhoneOS binaries are verified by the
    // separate device-build workflow, not by these deliberately small bytes.
    const ipa = Buffer.from("download-UI-fixture-not-an-installable-app");
    const pg = Buffer.from("download-UI-project-fixture");
    const digest = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
    const valid = { available: true, filename: "PlainWalk-iPhone-unsigned.ipa",
      sourceCommit: "446d109160ef6e1c767b80dfd1949f0fededcb02", sha256: digest(ipa), bytes: ipa.length,
      platform: "iPhoneOS", architecture: "arm64", signing: "unsigned", installableAsDownloaded: false,
      minimumIOS: "17.0", playgrounds: { filename: "PlainWalk.swiftpm.zip", bytes: pg.length,
        sha256: digest(pg), sourceCommit: "931f6121917c97326ce96ca4e3eeac523e9302df" } };
    let metadata = { available: false }, offline = false;
    // Serve real HTTP responses: intercepted Playwright fulfillment is not
    // used for attachment navigation/downloads.
    const root = path.resolve(__dirname, "../../dist");
    server = createServer((req, res) => {
      const pathname = new URL(req.url, "http://localhost").pathname;
      res.setHeader("Cache-Control", "no-store");
      if (pathname === "/downloads/build.json") {
        if (offline) { req.socket.destroy(); return; }
        res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify(metadata)); return;
      }
      const bytes = pathname === `/downloads/${valid.filename}` ? ipa : pathname === `/downloads/${valid.playgrounds.filename}` ? pg : null;
      if (bytes) {
        res.setHeader("Content-Type", "application/octet-stream");
        res.setHeader("Content-Length", bytes.length); res.end(bytes); return;
      }
      const name = path.resolve(root, "." + pathname + (pathname.endsWith("/") ? "index.html" : ""));
      if (!name.startsWith(root + path.sep)) { res.writeHead(404); res.end(); return; }
      fs.readFile(name, (error, data) => {
        if (error) { res.writeHead(404); res.end(); return; }
        const type = { ".html": "text/html", ".js": "application/javascript", ".css": "text/css", ".json": "application/json", ".webmanifest": "application/manifest+json", ".svg": "image/svg+xml", ".png": "image/png", ".geojson": "application/geo+json" }[path.extname(name)] || "application/octet-stream";
        res.setHeader("Content-Type", type); res.end(data);
      });
    });
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    await page.goto(`${base}/downloads/`);
    const state = value => page.waitForFunction(value => document.querySelector("#downloadStatus").dataset.state === value, value);
    const retry = async () => { await page.locator("#downloadRetry").click(); };
    await state("pending");
    assert.equal(await page.locator("#ipaDownload").getAttribute("href"), null);
    for (const bad of [
      { ...valid, filename: "https://example.invalid/other.ipa" },
      { ...valid, platform: "iPhoneSimulator" },
      { ...valid, architecture: "x86_64" },
      { ...valid, installableAsDownloaded: true },
      { ...valid, sha256: "invalid" },
    ]) {
      metadata = bad; await retry(); await state("error");
      assert.equal(await page.locator("#ipaDownload").getAttribute("href"), null);
      assert.equal(await page.locator("#playgroundsDownload").isVisible(), false);
    }
    metadata = valid; await retry(); await state("ready");
    await page.getByText("ファイルには保存できますが、このままではインストールできません。インストールには別途有効な署名が必要です。", { exact: true }).waitFor();
    assert.equal(await page.locator("#ipaDownload").getAttribute("download"), valid.filename);
    for (const [selector, bytes, filename] of [["#ipaDownload", ipa, valid.filename], ["#playgroundsDownload", pg, valid.playgrounds.filename]]) {
      const event = page.waitForEvent("download");
      await page.locator(selector).click(); const downloaded = await event;
      assert.equal(downloaded.suggestedFilename(), filename);
      let file;
      try { file = await downloaded.path(); } catch (error) { console.error({ url: downloaded.url(), failure: await downloaded.failure() }); throw error; }
      assert.deepEqual(fs.readFileSync(file), bytes);
    }
    const bounds = await page.locator("#ipaDownload").boundingBox();
    assert.ok(bounds.height >= 44);
    await page.screenshot({ path: artifact(`downloads-${engine === playwright.webkit ? "webkit" : "chromium"}.png`), fullPage: true });
    await page.setViewportSize({ width: 320, height: 740 });
    await page.locator("#buildDetails summary").click();
    await page.locator("#playgroundsDetails summary").click();
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
    assert.equal(overflow, false, "Download metadata must fit a narrow iPhone screen");

    // With a real active SW, failed metadata must not resurrect cached old
    // release information. Distribution files must also stay out of its cache.
    await page.goto(`${base}/`);
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.reload();
    await page.waitForFunction(() => navigator.serviceWorker.controller);
    await page.goto(`${base}/downloads/`); await state("ready");
    await page.evaluate(async () => {
      const cache = await caches.open("plainwalk-v9");
      const routes = (await cache.keys()).map(request => new URL(request.url).pathname);
      if (routes.some(path => path.startsWith("/downloads/"))) throw Error("Distribution resources were stored by the app service worker");
    });
    await page.evaluate(async value => {
      const cache = await caches.open("plainwalk-v9");
      await cache.put(new Request(new URL("/downloads/build.json", location.origin)),
        new Response(JSON.stringify(value), { headers: { "Content-Type": "application/json" } }));
    }, valid);
    offline = true;
    await page.reload(); await state("error");
    assert.equal(await page.locator("#ipaDownload").getAttribute("href"), null);
    assert.deepEqual(errors, []);
    console.log(`${engine === playwright.webkit ? "WebKit" : "Chromium"}: unsigned-download wording, manifest rejection/retry, both real browser downloads, narrow layout and active-SW stale-metadata bypass passed (UI fixture bytes).`);
  } finally { await browser.close(); if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); } }
})().catch(error => { console.error(error); process.exit(1); });
