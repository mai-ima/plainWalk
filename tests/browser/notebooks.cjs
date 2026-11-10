const assert = require("node:assert/strict");
const { playwright, chromiumExecutable, webkitExecutable, artifact } = require("./support.cjs");

(async () => {
  const engine = process.env.PW_ENGINE === "webkit" ? playwright.webkit : playwright.chromium;
  const browser = await engine.launch({ headless: true,
    executablePath: engine === playwright.webkit ? webkitExecutable : chromiumExecutable,
    args: engine === playwright.chromium ? ["--no-sandbox"] : [] });
  try {
    const context = await browser.newContext({ viewport: { width: 393, height: 852 },
      isMobile: true, hasTouch: true, acceptDownloads: true, timezoneId: "UTC" });
    await context.addInitScript(() => {
      window.mockFault = false;
      window.sharedFiles = [];
      if (!localStorage.getItem("native-library")) {
        const day = new Date().toISOString().slice(0, 10);
        localStorage.setItem("native-library", JSON.stringify({ version: 1, walks: [], spots: [], flags: [],
          futureLibrary: { keep: true }, notes: { [day]: { text: "最初のページ", steps: 321,
            futurePage: { keep: true }, paper: "grid", font: "serif", layout: [] } } }));
      }
      window.PlainWalkNative = { request: async (action, p = {}) => {
        if (action === "status") return { session: null };
        if (action === "storageRead") return JSON.parse(localStorage.getItem("native-" + p.key) || "null");
        if (action === "storageWrite") {
          if (p.key === "library" && window.mockFault) throw Error("Simulated notebook storage failure");
          localStorage.setItem("native-" + p.key, JSON.stringify(p.value));
        }
        if (action === "shareFile") window.sharedFiles.push(p);
        return null;
      } };
    });
    const page = await context.newPage(), errors = [];
    page.on("pageerror", e => errors.push(e.message));
    const button = name => page.getByRole("button", { name, exact: true });
    const saved = () => page.evaluate(() => JSON.parse(localStorage.getItem("native-library")));
    const day = new Date().toISOString().slice(0, 10), legacyID = `legacy:${day}`;
    const open = async () => { await button("マイマップ").click(); await button("メニュー").click(); await button("今日のノート").click(); await page.locator("#notePage").waitFor(); };
    await page.goto("http://127.0.0.1:4173");
    await open();
    assert.equal(await page.locator("#notePage").inputValue(), legacyID);
    assert.equal(await page.locator("#dailyNote").inputValue(), "最初のページ");
    await page.locator("#dailyNote").fill("元のページを編集");
    await page.locator("[data-action=noteNewPage]").click();
    await page.waitForFunction(id => document.querySelector("#notePage").value !== id, legacyID);
    const extraID = await page.locator("#notePage").inputValue();
    assert.equal(await page.locator("#notePage option").count(), 2);
    const addBounds = await page.locator("[data-action=noteNewPage]").boundingBox();
    assert.ok(addBounds.height >= 44 && addBounds.height <= 72, "New-page control must remain compact and touchable");
    const iconBounds = await page.locator("[data-action=noteNewPage] svg").boundingBox();
    assert.ok(iconBounds.width <= 32 && iconBounds.height <= 32, "A page action icon must not push the editor below the viewport");
    assert.equal((await saved()).notes[day].text, "元のページを編集");
    await page.locator("#dailyNote").fill("同じ日の二枚目");
    await page.locator("[data-save-note]").first().click();
    await page.waitForFunction(id => JSON.parse(localStorage.getItem("native-library")).notePages?.[id]?.text === "同じ日の二枚目", extraID);
    await page.screenshot({ path: artifact("notebook-multiple-pages.png") });

    // A quota/disk failure must not switch the visible draft or mutate committed data.
    await page.locator("#dailyNote").fill("保存失敗中も残す下書き");
    await page.evaluate(() => { window.mockFault = true; });
    await page.locator("#notePage").selectOption(legacyID);
    await page.waitForFunction(id => document.querySelector("#notePage").value === id, extraID);
    assert.equal(await page.locator("#dailyNote").inputValue(), "保存失敗中も残す下書き");
    assert.equal((await saved()).notePages[extraID].text, "同じ日の二枚目");
    await page.evaluate(() => { window.mockFault = false; });
    await page.locator("#notePage").selectOption(legacyID);
    await page.waitForFunction(() => document.querySelector("#dailyNote").value === "元のページを編集");
    assert.equal((await saved()).notePages[extraID].text, "保存失敗中も残す下書き");
    assert.deepEqual((await saved()).notes[day].futurePage, { keep: true });
    assert.equal((await saved()).notes[day].steps, 321);

    await page.locator("#notePage").selectOption(extraID);
    await page.locator("[data-share-note]").click();
    await page.waitForFunction(() => window.sharedFiles.length === 1);
    const shared = await page.evaluate(() => window.sharedFiles[0]);
    assert.equal(shared.name, `plainwalk-note-${day}.png`);
    const png = Buffer.from(shared.base64, "base64");
    assert.equal(png.subarray(1, 4).toString(), "PNG");
    assert.equal(png.readUInt32BE(16), 720);
    assert.equal(png.readUInt32BE(20), 960);
    await page.locator("[data-action=noteDeletePage]").click();
    await page.locator("[data-action=noteConfirmDelete]").click();
    await page.waitForFunction(id => document.querySelector("#notePage").value === id, legacyID);
    assert.equal((await saved()).notePages[extraID], undefined);
    assert.equal((await saved()).notes[day].text, "元のページを編集");

    // A note does not require any walk on its date, and survives a fresh load.
    await page.locator("#noteDate").fill("2000-01-01");
    await page.waitForFunction(() => document.querySelector("#noteDate").value === "2000-01-01" && document.querySelector("#dailyNote").value === "");
    await page.locator("#dailyNote").fill("歩かなかった日にも残す");
    await page.locator("[data-save-note]").first().click();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem("native-library")).notes?.["2000-01-01"]?.text === "歩かなかった日にも残す");
    await page.reload();
    await open();
    await page.locator("#noteDate").fill("2000-01-01");
    await page.waitForFunction(() => document.querySelector("#dailyNote").value === "歩かなかった日にも残す");
    await page.locator("#dailyNote").fill("閉じる前の下書き");
    await button("閉じる").click();
    await page.locator("[data-action=noteContinueEditing]").click();
    assert.equal(await page.locator("#dailyNote").inputValue(), "閉じる前の下書き");
    await button("閉じる").click();
    await page.locator("[data-action=noteSaveAndLeave]").click();
    await page.locator("#notePage").waitFor({ state: "hidden" });
    assert.equal((await saved()).notes["2000-01-01"].text, "閉じる前の下書き");

    const incoming = { version: 1, walks: [], spots: [], flags: [], notes: {
      [day]: { text: "同じ日付の取り込み元", steps: 999, importedFuture: { keep: true } },
    }, notePages: {
      "blank-a": { id: "blank-a", day, text: "" },
      "blank-b": { id: "blank-b", day, text: "" },
    } };
    const restore = async () => {
      await page.locator("#importFile").setInputFiles({ name: "notebooks.json", mimeType: "application/json", buffer: Buffer.from(JSON.stringify(incoming)) });
      await button("確認して取り込む").click();
      await page.getByText("バックアップを取り込みました。", { exact: true }).waitFor();
    };
    await restore();
    const afterImport = await saved();
    assert.equal(afterImport.notes[day].text, "元のページを編集");
    assert.equal(afterImport.notes[day].steps, 321);
    assert.ok(afterImport.notePages["blank-a"] && afterImport.notePages["blank-b"]);
    assert.ok(Object.values(afterImport.notePages).some(p => p.text === "同じ日付の取り込み元" && p.importedFuture.keep));
    await restore();
    assert.deepEqual((await saved()).notePages, afterImport.notePages);

    await open();
    await page.locator("#notePage").selectOption(legacyID);
    await page.locator("[data-action=noteDeletePage]").click();
    await page.locator("[data-action=noteConfirmDelete]").click();
    await page.waitForFunction(() => JSON.parse(localStorage.getItem("native-library")).notes[new Date().toISOString().slice(0, 10)].pageDeleted === true);
    assert.equal((await saved()).notes[day].steps, 321);
    assert.ok((await saved()).notePages["blank-a"] && (await saved()).notePages["blank-b"]);
    assert.deepEqual((await saved()).futureLibrary, { keep: true });
    assert.deepEqual(errors, []);
    console.log(`${engine === playwright.webkit ? "WebKit" : "Chromium"}: notebook same-day pages, atomic failure, selected PNG, deletion, metadata and nonwalking-day persistence passed.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
