const assert = require("node:assert/strict");
const { playwright, chromiumExecutable, artifact, fixture } = require("./support.cjs");
const { injectExif } = require("../fixtures/jpeg-exif.cjs");

(async () => {
  const browser = await playwright.chromium.launch({ executablePath: chromiumExecutable, headless: true, args: ["--no-sandbox"] });
  let page;
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, serviceWorkers: "block" });
    await context.addInitScript(() => {
      window.photoGeoCalls = 0;
      Object.defineProperty(navigator, "geolocation", { configurable: true, value: {
        getCurrentPosition(_success, failure) { window.photoGeoCalls++; failure?.({ code: 1, message: "Test denied" }); },
        watchPosition(_success, failure) { window.photoGeoCalls++; failure?.({ code: 1, message: "Test denied" }); return 1; }, clearWatch() {},
      } });
      const read = File.prototype.arrayBuffer;
      File.prototype.arrayBuffer = function () {
        if (!this.name.startsWith("slow-")) return read.call(this);
        return new Promise((resolve, reject) => setTimeout(() => read.call(this).then(resolve, reject), 250));
      };
      const decode = window.createImageBitmap.bind(window);
      window.createImageBitmap = async (...args) => {
        if (window.delayNextPhotoDecode) {
          window.delayNextPhotoDecode = false; window.photoDecodeBlocked = true;
          await new Promise((resolve) => { window.releasePhotoDecode = resolve; });
          const image = await decode(...args); window.photoDecodeReleased = true; return image;
        }
        return decode(...args);
      };
      window.readTestLibrary = () => new Promise((resolve, reject) => {
        const open = indexedDB.open("plainwalk-web", 1);
        open.onerror = () => reject(open.error);
        open.onsuccess = () => {
          const db = open.result, read = db.transaction("data").objectStore("data").get("library");
          read.onsuccess = () => { db.close(); resolve(read.result); };
          read.onerror = () => { db.close(); reject(read.error); };
        };
      });
    });
    page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto("http://127.0.0.1:4173");
    await page.locator("#recordButton").waitFor();
    const original = Buffer.from(await page.evaluate(() => {
      const canvas = document.createElement("canvas"); canvas.width = 8; canvas.height = 6;
      const c = canvas.getContext("2d"); c.fillStyle = "#859b72"; c.fillRect(0, 0, 8, 6);
      return canvas.toDataURL("image/jpeg", 0.9).split(",")[1];
    }), "base64");
    const photo = (options = {}, name = "photo.jpg") => ({ name, mimeType: "image/jpeg", buffer: injectExif(original, options) });
    const openImport = async () => {
      if (await page.locator("#overlay").isVisible()) await page.locator("#sheetClose").click();
      await page.getByRole("button", { name: "プロフィール", exact: true }).click();
      await page.getByRole("button", { name: "写真を取り込む", exact: true }).click();
    };
    const waitPhoto = () => page.waitForFunction(() => {
      const form = document.querySelector("#spotForm"), preview = document.querySelector("#spotPreview");
      return form && form.dataset.photoBusy !== "true" && preview && !preview.hidden && preview.complete && preview.naturalWidth > 0;
    });
    const savePhoto = async (text, count) => {
      await page.locator("#spotText").fill(text);
      await page.getByRole("button", { name: "この場所に残す", exact: true }).click();
      await page.waitForFunction(async (count) => (await window.readTestLibrary())?.spots?.length === count, count);
      return page.evaluate(async () => (await window.readTestLibrary()).spots.at(-1));
    };

    // Photo metadata supplies the place without granting or requesting live GPS.
    await openImport();
    await page.locator("#spotImportPhoto").setInputFiles(photo({ lat: [0, 0, 0], lon: [0, 0, 0], date: "1970:01:01 00:00:00", offset: "+00:00", sub: "0" }));
    await waitPhoto();
    assert.match(await page.locator("#spotPhotoLocation").innerText(), /撮影場所/);
    let saved = await savePhoto("EXIF zero", 1);
    assert.equal(saved.lat, 0); assert.equal(saved.lon, 0); assert.equal(saved.t, 0);
    assert.equal(saved.photoMetadata.capturedAt, 0); assert.equal(saved.locationSource, "photo-gps");
    assert.ok(saved.photo.startsWith("data:image/jpeg;base64,"));
    assert.equal(await page.evaluate(() => window.photoGeoCalls), 0);

    // GPS can be retained even if the local camera clock has no timezone.
    await openImport();
    await page.locator("#spotImportPhoto").setInputFiles(photo({ offset: null, gpsDate: "invalid" }));
    await waitPhoto();
    assert.match(await page.locator("#spotPhotoLocation").innerText(), /追加日時/);
    saved = await savePhoto("GPS with unknown time", 2);
    assert.equal(saved.photoMetadata.capturedAt, null);
    assert.equal(saved.photoMetadata.localDateTime, "2026:10:29 12:00:00");
    assert.ok(Math.abs(saved.t - saved.addedAt) < 1000);

    // A timestamp alone places an old photo onto a saved, connected walk.
    const stamp = Date.UTC(2026, 9, 29, 3);
    await page.evaluate(async (stamp) => {
      const library = await window.readTestLibrary();
      library.walks = [{ id: "photo-walk", name: "Photo walk", start: stamp, end: stamp + 10_000,
        points: [{ lat: 35, lon: 139, t: stamp }, { lat: 35.0001, lon: 139.0001, t: stamp + 10_000 }] }];
      await new Promise((resolve, reject) => {
        const open = indexedDB.open("plainwalk-web", 1);
        open.onsuccess = () => { const db = open.result, t = db.transaction("data", "readwrite"); t.objectStore("data").put(library, "library"); t.oncomplete = () => { db.close(); resolve(); }; t.onerror = () => reject(t.error); };
      });
    }, stamp);
    await page.reload(); await page.locator("#recordButton").waitFor();
    await openImport();
    await page.locator("#spotImportPhoto").setInputFiles(photo({ gps: false, date: "2026:10:29 12:00:05", sub: "0" }));
    await waitPhoto();
    assert.match(await page.locator("#spotPhotoLocation").innerText(), /さんぽの軌跡/);
    saved = await savePhoto("Time matched old walk", 3);
    assert.equal(saved.t, stamp + 5000); assert.equal(saved.locationSource, "walk-time");
    assert.ok(Math.abs(saved.lat - 35.00005) < 1e-9);
    assert.ok(Math.abs(saved.lon - 139.00005) < 1e-9);

    // A metadata-free introductory import waits for a chosen place, retaining its file.
    await openImport();
    await page.locator("#spotImportPhoto").setInputFiles(photo({ gps: false, offset: null }, "queued.jpg"));
    await page.locator("#toast").filter({ hasText: "写真の場所が分かりません。" }).waitFor();
    assert.equal(await page.locator("#spotForm").count(), 0);
    await page.getByRole("button", { name: "地図から場所を選ぶ", exact: true }).click();
    await page.getByRole("button", { name: "マイマップ", exact: true }).click();
    await page.locator("#mapViewport").tap({ position: { x: 170, y: 240 } });
    await waitPhoto();
    saved = await savePhoto("Queued photo with chosen place", 4);
    assert.equal(saved.locationSource, "manual-location");
    assert.equal(saved.photoMetadata.capturedAt, null);
    assert.ok(saved.photo.startsWith("data:image/jpeg;base64,"));

    // Metadata-free legacy PNGs work when the person explicitly chooses a map point.
    await openImport();
    await page.getByRole("button", { name: "地図から場所を選ぶ", exact: true }).click();
    await page.getByRole("button", { name: "マイマップ", exact: true }).click();
    await page.locator("#mapViewport").tap({ position: { x: 270, y: 380 } });
    await page.locator("#spotPhoto").setInputFiles(fixture("icon.png")); await waitPhoto();
    assert.equal(await page.locator("#spotUseChosen").isVisible(), false);
    saved = await savePhoto("Explicit PNG place", 5);
    assert.equal(saved.locationSource, "manual-location");
    assert.equal(saved.photoMetadata.format, "unsupported");

    // An automatically available current point must not silently place an old photo.
    await page.evaluate(() => window.dispatchEvent(new CustomEvent("plainwalk-native", { detail: { event: "location", point: { lat: 35.6, lon: 139.7, t: Date.now(), accuracy: 5 } } })));
    await openImport();
    await page.locator("#spotPhoto").setInputFiles(photo({ gps: false, offset: null })); await waitPhoto();
    await page.locator("#spotText").fill("Requires confirmation");
    await page.getByRole("button", { name: "この場所に残す", exact: true }).click();
    await page.locator("#toast").filter({ hasText: "写真を置く場所を選択してください。" }).waitFor();
    assert.equal((await page.evaluate(() => window.readTestLibrary())).spots.length, 5);
    await page.locator("#spotUseChosen").click();
    saved = await savePhoto("Confirmed current place", 6);
    assert.equal(saved.lat, 35.6); assert.equal(saved.lon, 139.7);
    assert.equal(saved.locationSource, "manual-location");

    // A newer selected photo must win even if an older asynchronous read finishes later.
    await openImport();
    await page.locator("#spotPhoto").setInputFiles(photo({ lat: [40, 0, 0], date: "2020:01:01 00:00:00" }, "slow-old.jpg"));
    await page.locator("#spotPhoto").setInputFiles(photo({ lat: [30, 0, 0], date: "2024:01:01 00:00:00", offset: "+00:00", sub: "0" }, "new.jpg"));
    await waitPhoto(); await page.waitForTimeout(350);
    saved = await savePhoto("Newest wins", 7);
    assert.equal(saved.lat, 30); assert.equal(saved.t, Date.UTC(2024, 0, 1));

    // Closing an in-flight import cannot attach its photo or metadata to a new note.
    await openImport();
    await page.locator("#spotPhoto").setInputFiles(photo({ lat: [45, 0, 0] }, "slow-cancelled.jpg"));
    await page.locator("#sheetClose").click();
    await openImport(); await page.waitForTimeout(350);
    assert.equal(await page.locator("#spotPreview").isVisible(), false);
    saved = await savePhoto("No stale photo", 8);
    assert.equal(saved.photo, null); assert.equal(saved.photoMetadata, undefined);
    assert.equal(saved.lat, 35.6); assert.equal(saved.lon, 139.7);
    // Cancel during the separate Save decoder, then reopen a clean draft.
    await openImport();
    await page.locator("#spotPhoto").setInputFiles(photo({ lat: [45, 0, 0] }, "save-cancelled.jpg"));
    await waitPhoto(); await page.locator("#spotText").fill("Cancelled during Save");
    await page.evaluate(() => { window.delayNextPhotoDecode = true; });
    await page.getByRole("button", { name: "この場所に残す", exact: true }).click();
    await page.waitForFunction(() => window.photoDecodeBlocked === true);
    assert.equal(await page.locator("#spotPhoto").isDisabled(), true);
    await page.locator("#sheetClose").click(); await openImport();
    await page.locator("#spotText").fill("New draft survives old Save");
    await page.evaluate(() => { window.releasePhotoDecode(); });
    await page.waitForFunction(() => window.photoDecodeReleased === true); await page.waitForTimeout(80);
    assert.equal((await page.evaluate(() => window.readTestLibrary())).spots.length, 8);
    assert.equal(await page.locator("#spotText").inputValue(), "New draft survives old Save");
    assert.equal(await page.locator("#spotPreview").isVisible(), false);
    saved = await savePhoto("New draft survives old Save", 9);
    assert.equal(saved.photo, null); assert.equal(saved.photoMetadata, undefined);
    assert.equal(await page.evaluate(() => window.photoGeoCalls), 0);
    assert.deepEqual(errors, []);
    await page.screenshot({ path: artifact("photo-import-preview.png") });
    console.log("Photo imports: real JPEG EXIF GPS/time/zero, saved-walk placement, explicit PNG/current fallback, queued/manual fallback, replacement and preview/Save cancellation passed without live GPS.");
  } catch (error) {
    if (page) await page.screenshot({ path: artifact("photo-import-failed.png"), fullPage: true }).catch(() => {});
    throw error;
  } finally { await browser.close(); }
})().catch((error) => { console.error(error); process.exit(1); });
