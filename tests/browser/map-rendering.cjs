const assert = require("node:assert/strict");
const { playwright, chromiumExecutable, webkitExecutable, fixture, artifact } = require("./support.cjs");

// User-visible rendering regressions, with data confined to fresh browser contexts.
// This is mobile browser emulation, not GPS or physical iPhone validation.
(async () => {
  const engine = process.env.PW_ENGINE === "webkit" ? playwright.webkit : playwright.chromium;
  const browser = await engine.launch({
    headless: true,
    executablePath: engine === playwright.webkit ? webkitExecutable : chromiumExecutable,
    args: engine === playwright.chromium ? ["--no-sandbox"] : [],
  });
  const now = Date.now();
  const dateline = {
    id: "rendering-dateline", name: "日付変更線の検証", start: now - 120000, end: now,
    points: [
      { lat: 0, lon: 179.9999, t: now - 120000 },
      { lat: 0, lon: -179.9999, t: now },
    ],
  };
  const replay = {
    id: "rendering-replay", name: "再生の検証", start: now - 240000, end: now,
    points: [
      { lat: 35.68, lon: 139.76, t: now - 240000 },
      { lat: 35.6805, lon: 139.76, t: now - 160000 },
      { lat: 35.6805, lon: 139.7605, t: now - 80000 },
      { lat: 35.681, lon: 139.7605, t: now },
    ],
  };
  const library = {
    version: 1, walks: [dateline, replay], spots: [], notes: {},
    flags: [
      { id: "dateline-east", name: "東側", lat: 0, lon: 179.9999 },
      { id: "dateline-west", name: "西側", lat: 0, lon: -179.9999 },
    ],
    bookmarks: [], doodles: [], sharedMaps: [],
  };
  const failures = [];
  const button = (page, name) => page.getByRole("button", { name, exact: true });
  // Only the retired tilt action needs a direct event route: it has no visible
  // browser control after being replaced with an availability explanation.
  async function dispatch(page, dataset) {
    await page.evaluate((values) => {
      const control = document.createElement("button");
      Object.assign(control.dataset, values);
      document.body.append(control);
      control.click();
      control.remove();
    }, dataset);
  }
  async function closeSheet(page) {
    const overlay = page.locator("#overlay");
    if (await overlay.isVisible()) await page.locator('#sheet > header [data-action="close"]').click();
    await overlay.waitFor({ state: "hidden" });
  }
  async function openWalk(page, id) {
    await button(page, "記録").click();
    await page.locator(`[data-walk="${id}"]`).click();
    await page.locator(`#sheetBody [data-map-walk="${id}"]`).waitFor();
  }
  async function openSpotForm(page) {
    await button(page, "プロフィール").click();
    await button(page, "写真を取り込む").click();
    await button(page, "地図から場所を選ぶ").click();
    await page.locator("#mapViewport").tap({ position: { x: 130, y: 240 } });
    await page.locator('[data-spot-mode="photo"]').waitFor();
  }
  async function verifyVideoPlayback(video) {
    await video.evaluate(async (node) => {
      if (node.readyState < 2) await new Promise((resolve, reject) => {
        const finish = (error) => {
          clearTimeout(timer); node.removeEventListener("loadeddata", ready); node.removeEventListener("error", failed);
          error ? reject(error) : resolve();
        };
        const ready = () => finish(), failed = () => finish(Error(node.error?.message));
        const timer = setTimeout(() => finish(Error("Imported video has no decoded frame")), 8000);
        node.addEventListener("loadeddata", ready, { once: true });
        node.addEventListener("error", failed, { once: true });
      });
    });
    const decoded = await video.evaluate((node) => ({ duration: node.duration, width: node.videoWidth, height: node.videoHeight }));
    assert.deepEqual(decoded, { duration: 2, width: 320, height: 240 }, "The real two-second fixture must decode at its original dimensions");
    await video.evaluate((node) => { node.muted = true; return node.play(); });
    await video.page().waitForFunction(() => {
      const node = document.querySelector("#spotVideoPreview") || document.querySelector("#sheetBody video");
      return node?.currentTime > 0.05 && node.readyState >= 2;
    });
    await video.evaluate((node) => node.pause());
  }
  async function scenario(name, run, options = {}) {
    if(process.env.PW_SCENARIO && !name.includes(process.env.PW_SCENARIO))return;
    const context = await browser.newContext({
      viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true,
      timezoneId: "UTC", locale: "ja-JP", acceptDownloads: true, serviceWorkers: "block", ...options,
    });
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    try {
      await page.goto("http://127.0.0.1:4173");
      await page.evaluate(async (value) => {
        await new Promise((resolve, reject) => {
          const request = indexedDB.open("plainwalk-web", 1);
          request.onupgradeneeded = () => {
            if (!request.result.objectStoreNames.contains("data")) request.result.createObjectStore("data");
          };
          request.onsuccess = () => {
            const db = request.result;
            const transaction = db.transaction("data", "readwrite");
            const store = transaction.objectStore("data");
            store.put(value, "library");
            store.put({ dark: "light", smooth: false, thicken: false, morningTime: "07:45", reduce: true }, "config");
            store.put(null, "active");
            transaction.oncomplete = () => { db.close(); resolve(); };
            transaction.onerror = () => reject(transaction.error);
            transaction.onabort = () => reject(transaction.error);
          };
          request.onerror = () => reject(request.error);
        });
      }, library);
      await page.reload();
      await page.waitForFunction(()=>Number(document.querySelector("#totalNew")?.textContent)>0);
      await run(page);
      assert.deepEqual(errors, [], `${name}: uncaught browser errors`);
      console.log(`${engine === playwright.webkit ? "WebKit" : "Chromium"}: ${name} passed.`);
    } catch (error) {
      failures.push(`${name}: ${error.message}${errors.length?" / browser errors: "+errors.join("; "):""}`);
      await page.screenshot({path:artifact("map-rendering-failure-preview.png")}).catch(()=>{});
    } finally {
      await context.close();
    }
  }
  try {
    await scenario("short antimeridian track, visible flags and normalized picked longitude", async (page) => {
      await openWalk(page, dateline.id);
      await page.locator(`[data-map-walk="${dateline.id}"]`).click();
      await page.waitForFunction(() => document.querySelectorAll("#trails path").length === 1 && document.querySelectorAll("#pins [data-flag]").length === 2);
      const geometry = await page.evaluate(() => {
        const viewport = document.querySelector("#mapViewport").getBoundingClientRect();
        const line = document.querySelector("#trails path").getBoundingClientRect();
        const markers = [...document.querySelectorAll("#pins [data-flag]")].map((node) => {
          const rect = node.getBoundingClientRect();
          return { id: node.dataset.flag, x: rect.x, right: rect.right, y: rect.y, bottom: rect.bottom, center: rect.x + rect.width / 2 };
        });
        return { viewport: { x: viewport.x, right: viewport.right, y: viewport.y, bottom: viewport.bottom }, line: { x: line.x, right: line.right, y: line.y, bottom: line.bottom, width: line.width }, markers };
      });
      assert.ok(geometry.line.width > 5 && geometry.line.width < 200, `A22m crossing must remain a local line, got${geometry.line.width}px`);
      assert.ok(geometry.line.x >= geometry.viewport.x - 1 && geometry.line.right <= geometry.viewport.right + 1, "Dateline track must fit horizontally inside the map");
      assert.ok(geometry.line.y >= geometry.viewport.y && geometry.line.bottom <= geometry.viewport.bottom, "Dateline track must fit vertically inside the map");
      assert.equal(geometry.markers.length, 2, "Flags on both sides of180° must render");
      for (const marker of geometry.markers) {
        assert.ok(marker.x >= geometry.viewport.x && marker.right <= geometry.viewport.right, `${marker.id} must remain horizontally visible`);
        assert.ok(marker.y >= geometry.viewport.y && marker.bottom <= geometry.viewport.bottom, `${marker.id} must remain vertically visible`);
      }
      const scale=Number((await page.locator("#scaleText").textContent()).replace(/[^0-9.]/g,""));
      assert.ok(scale>=30&&scale<=33,"Scale must use the equatorial viewport latitude, not a fixedJapanese latitude");
      const separation = Math.abs(geometry.markers[0].center - geometry.markers[1].center);
      assert.ok(separation > 5 && separation < 200, "Distinct neighboring dateline markers must not wrap offscreen or collapse");
      await button(page, "答え合わせマップ").click();
      for (const x of [320, 70]) {
        await button(page, "目的地を決める").click();
        await page.locator("#mapViewport").tap({ position: { x, y: 300 } });
        await page.locator("#flagLon").waitFor();
        const longitude = Number(await page.locator("#flagLon").inputValue());
        assert.ok(Number.isFinite(longitude) && longitude >= -180 && longitude <= 180, `Picked longitude must be normalized, got${longitude}`);
        await closeSheet(page);
      }
    });
    await scenario("answer map destination, opaque doodle action and truthful tilt explanation", async (page) => {
      await button(page, "答え合わせマップ").click();
      const destination = button(page, "目的地を決める");
      await destination.waitFor();
      assert.equal(await destination.getAttribute("data-action"), "flagPick");
      const color = await button(page, "らくがき").evaluate((node) => getComputedStyle(node).backgroundColor);
      const channels = color.match(/[\d.]+/g).map(Number);
      assert.ok(channels.slice(0, 3).every((channel) => channel >= 245), `Doodle action must have a white background, got${color}`);
      assert.ok(channels.length < 4 || channels[3] === 1, `Doodle action must be opaque, got${color}`);
      await dispatch(page, { action: "tilt" });
      await page.getByRole("heading", { name: "地図の傾斜表示", exact: true }).waitFor();
      for (const selector of ["#mapViewport", "#map", "#tiles"]) {
        assert.equal(await page.locator(selector).evaluate((node) => getComputedStyle(node).transform), "none", "Web map and tiles must not imply real3D by a CSS transform");
      }
    });
    await scenario("browser HealthKit availability and readable notification time", async (page) => {
      await button(page, "プロフィール").click();
      await button(page, "設定").click();
      const time = page.locator("#morningTime");
      await time.scrollIntoViewIfNeeded();
      assert.equal(await time.inputValue(), "07:45");
      const bounds = await time.evaluate((node) => {
        const field = node.getBoundingClientRect(), row = node.closest("label").getBoundingClientRect();
        const label = node.closest("label").querySelector(".grow").getBoundingClientRect();
        return { width: field.width, x: field.x, right: field.right, rowX: row.x, rowRight: row.right, labelRight: label.right };
      });
      assert.ok(bounds.width >= 100, "The time input needs room for both hour and minute digits");
      assert.ok(bounds.x >= bounds.rowX && bounds.right <= bounds.rowRight + 1, "The time input must fit its row");
      assert.ok(bounds.x >= bounds.labelRight, "The time input must not overlap its label");
      await time.fill("23:59");
      assert.equal(await time.inputValue(), "23:59");
      await page.screenshot({ path: artifact("map-rendering-time-preview.png"), animations: "disabled" });
      await page.getByRole("button", { name: "ワークアウトを選んで描く", exact: true }).click();
      await page.getByText(/Web版ではAppleヘルスケアのワークアウトを読み込めません/).waitFor();
      assert.equal(await page.locator('#sheetBody button[data-action="healthLoad"]').count(), 0, "The browser must not offer a nonfunctional HealthKit permission action");
      assert.equal(await page.getByRole("button", { name: "許可して読み込む", exact: true }).count(), 0);
      await closeSheet(page);
      await button(page,"自宅").click();
      await page.getByText(/現在のWeb版・Swift版では未実装/).waitFor();
    });
    await scenario("replay uses one dash coordinate system through partial and complete progress", async (page) => {
      await openWalk(page, replay.id);
      await page.locator(`[data-replay-walk="${replay.id}"]`).click();
      const path = page.locator("#replayCanvas path").first(), slider = page.locator("#replayRange");
      await path.waitFor();
      assert.equal(await path.getAttribute("vector-effect"), null, "Replay dash geometry must not be mixed with a non-scaling stroke");
      assert.equal(await slider.inputValue(), "0");
      const initial = await path.evaluate((node) => ({ length: node.getTotalLength(), offset: parseFloat(getComputedStyle(node).strokeDashoffset) }));
      assert.ok(initial.length > 0 && Math.abs(initial.offset - initial.length) < 0.1, "Zero progress must hide the entire route in SVG units");
      await slider.focus();
      await slider.press("ArrowRight");
      await slider.press("ArrowRight");
      assert.equal(await slider.inputValue(), "2");
      const partial = await path.evaluate((node) => parseFloat(getComputedStyle(node).strokeDashoffset));
      assert.ok(partial > 0 && partial < initial.offset, "Middle progress must reveal some but not all of the route");
      await slider.press("End");
      assert.equal(await slider.inputValue(), "4");
      const complete = await path.evaluate((node) => parseFloat(getComputedStyle(node).strokeDashoffset));
      assert.ok(Math.abs(complete) < 0.1, "Full progress must leave the whole route visible");
      assert.match(await page.locator("#replayLabel").textContent(), /^4\s*\/\s*4$/);
    });
    await scenario("photo-only films and LUT are unavailable in video mode", async (page) => {
      await openSpotForm(page);
      assert.equal(await page.locator(".film-options").isVisible(), true);
      await page.locator('[data-spot-mode="video"]').click();
      await page.getByText("フィルム・LUTは写真専用です。動画の色は加工せず保存します。", { exact: true }).waitFor();
      assert.equal(await page.locator(".film-options").isVisible(), false);
      assert.equal(await page.locator(".film-advanced").isVisible(), false);
      // VP8 is the portable success fixture; MP4 decoder availability is checked
      // independently below. Both files contain real frames, without media mocks.
      await page.locator("#spotVideo").setInputFiles(fixture("clip.webm"));
      // readVideo bounds metadata and seek separately at8s, so this budget covers
      // both product deadlines and fails with their Japanese error if either stalls.
      await page.locator("#spotVideoPreview").waitFor({ state: "visible", timeout: 20000 });
      await verifyVideoPlayback(page.locator("#spotVideoPreview"));
      assert.equal(await page.locator(".film-options").isVisible(), false, "Selecting an imported video must not restore photo filters");
      await page.locator('[data-spot-mode="photo"]').click();
      assert.equal(await page.locator(".film-options").isVisible(), true);
      assert.equal(await page.locator(".film-advanced").isVisible(), true);
      assert.equal(await page.getByText("フィルム・LUTは写真専用です。動画の色は加工せず保存します。", { exact: true }).isVisible(), false);
      await page.locator('[data-spot-mode="video"]').click();
      await page.locator("#spotText").fill("加工しない動画の保存");
      await button(page, "この場所に残す").click();
      await page.locator("#overlay").waitFor({ state: "hidden" });
      await button(page, "プロフィール").click();
      await button(page, "ここいいな").click();
      await button(page, /加工しない動画の保存/).click();
      const saved = page.locator("#sheetBody video");
      assert.match(await saved.getAttribute("src"), /^data:video\/webm;base64,/);
      await verifyVideoPlayback(saved);
    });
    await scenario("MP4 imports decode or report an actual unsupported decoder", async (page) => {
      await openSpotForm(page);
      await page.evaluate(() => {
        window.videoImportDiagnostics = { canPlayType: document.createElement("video").canPlayType('video/mp4; codecs="avc1.64000d"'), events: [] };
        const create = document.createElement.bind(document);
        document.createElement = (...args) => {
          const node = create(...args);
          if (String(args[0]).toLowerCase() === "video") {
            for (const type of ["loadedmetadata", "loadeddata", "seeking", "seeked", "error"]) {
              node.addEventListener(type, () => window.videoImportDiagnostics.events.push({ type, readyState: node.readyState, duration: Number.isFinite(node.duration) ? node.duration : null, width: node.videoWidth, height: node.videoHeight, error: node.error ? { code: node.error.code, message: node.error.message } : null }));
            }
          }
          return node;
        };
      });
      await page.locator("#spotVideo").setInputFiles(fixture("clip.mp4"));
      try {
        await page.waitForFunction(() => !document.querySelector("#spotVideoPreview").hidden || document.querySelector("#toast").textContent.trim(), null, { timeout: 20000 });
        const diagnostics = await page.evaluate(() => ({ ...window.videoImportDiagnostics, toast: document.querySelector("#toast").textContent.trim() }));
        console.log("MP4 import diagnostics:", JSON.stringify(diagnostics));
        if (await page.locator("#spotVideoPreview").isVisible()) {
          await verifyVideoPlayback(page.locator("#spotVideoPreview"));
        } else {
          const actualDecoderError = diagnostics.events.some((event) => event.type === "error" && [3, 4].includes(event.error?.code));
          assert.ok(actualDecoderError, `Only an actual unsupported/failed decoder may reject MP4; a stalled import must fail: ${JSON.stringify(diagnostics)}`);
          assert.match(diagnostics.toast, /^(この動画形式を読み取れません。MP4 または WebM をお試しください。|動画の画像を読み取れません。)$/);
          assert.equal(await page.locator("#spotVideoPreview").isVisible(), false);
        }
      } catch (error) {
        const diagnostics = await page.evaluate(() => ({ ...window.videoImportDiagnostics, toast: document.querySelector("#toast").textContent.trim() }));
        throw Error(`${error.message} / MP4 import diagnostics: ${JSON.stringify(diagnostics)}`);
      }
    });
    await scenario("boundary loading errors have a Japanese retry route", async page=>{
      const pattern="**/data/japan-municipalities.geojson";
      await page.route(pattern,route=>route.abort());
      await button(page,"プロフィール").click();await button(page,"エリアと開拓のバッジ").click();
      await page.getByRole("heading",{name:"街の境界を読み込めませんでした",exact:true}).waitFor();
      await page.unroute(pattern);await button(page,"再試行").click();
      await page.locator("[data-area]").first().waitFor();
      assert.equal(await page.getByText("Failed to fetch",{exact:true}).count(),0);
    });
    await scenario("a pasted notebook route remains legible after rasterization", async page=>{
      // Keep the note local: the general map fixture also has a separate walk near180deg.
      await replaceLibrary(page,{...library,walks:[replay],flags:[]});
      const key=new Date(replay.start).toISOString().slice(0,10);
      await dispatch(page,{dayNote:key});await page.locator("#noteCanvas").waitFor();
      await button(page,"道を貼る").click();await page.locator("#noteItemControls").waitFor({state:"visible"});
      await button(page,"ノートを保存").click();
      const ink=await page.evaluate(async day=>{
        const note=await new Promise((resolve,reject)=>{const r=indexedDB.open("plainwalk-web",1);r.onsuccess=()=>{const db=r.result,q=db.transaction("data").objectStore("data").get("library");q.onsuccess=()=>{resolve(q.result.notes[day]);db.close();};q.onerror=()=>reject(q.error);};});
        const src=note.layout.find(i=>i.type==="route").src,image=new Image();image.src=src;await image.decode();
        const c=document.createElement("canvas");c.width=image.width;c.height=image.height;const ctx=c.getContext("2d");ctx.drawImage(image,0,0);const pixels=ctx.getImageData(0,0,c.width,c.height).data;
        let dark=0;for(let i=0;i<pixels.length;i+=4)if(pixels[i+3]>128&&pixels[i]<100&&pixels[i+1]<100&&pixels[i+2]<100)dark++;
        return {dark,width:c.width,height:c.height};
      },key);
      assert.ok(ink.dark>1500,`Route ink must survive reduction into a note item; got${ink.dark} opaque dark pixels in${ink.width}x${ink.height}`);
      await page.screenshot({path:artifact("map-rendering-note-route-preview.png"),animations:"disabled"});
    });
    async function replaceLibrary(page, value, active = null) {
      await page.evaluate(async ({value,active}) => new Promise((resolve,reject)=>{
        const r=indexedDB.open("plainwalk-web",1);
        r.onsuccess=()=>{const db=r.result,t=db.transaction("data","readwrite"),s=t.objectStore("data");s.put(value,"library");s.put(active,"active");t.oncomplete=()=>{db.close();resolve();};t.onerror=()=>reject(t.error);};r.onerror=()=>reject(r.error);
      }),{value,active});
      await page.reload();
      await page.waitForFunction(()=>Number(document.querySelector("#totalNew")?.textContent)>0);
    }
    await scenario("active recording remains chronological when a later workout was imported", async page => {
      const at=Date.now(),point=(lon,t)=>({lat:0.00001,lon,t});
      const later={id:"later-workout",name:"後から始まったワークアウト",start:at-30000,end:at-20000,points:[point(0.00001,at-30000),point(0.000019,at-20000)]};
      const active={id:"earlier-active",name:"記録中",start:at-120000,points:[point(0.000001,at-120000),point(0.00009,at-60000)],pausedMs:0,pauseAt:at-60000};
      await replaceLibrary(page,{...library,walks:[later],flags:[]},active);
      await button(page,"ここまでを保存").waitFor();
      const before=(await page.locator("#totalNew").textContent()).trim();
      assert.equal(before,"0.01","The earlier9.9m active passage must precede the later1m workout in the same cell");
      await button(page,"ここまでを保存").click();
      await page.locator('[data-save-walk="earlier-active"]').waitFor();
      await closeSheet(page);
      await button(page,"マイマップ").click();
      assert.equal((await page.locator("#totalNew").textContent()).trim(),before,"Saving must not change total exploration through a different chronology");
    });
    await scenario("today exploration includes the current-day portion of a midnight crossing", async page => {
      const fixed=new Date("2026-11-01T00:00:30Z");await page.clock.install({time:fixed});
      const crossing={id:"midnight",name:"日付をまたぐさんぽ",start:Date.parse("2026-10-31T23:59:30Z"),end:+fixed,points:[{lat:0.00001,lon:0.000001,t:Date.parse("2026-10-31T23:59:30Z")},{lat:0.00001,lon:0.001,t:+fixed}]};
      await replaceLibrary(page,{...library,walks:[crossing],flags:[]});
      const today=Number(await page.locator("#todayNew").textContent()),total=Number(await page.locator("#totalNew").textContent());
      assert.ok(today>0.03&&today<0.08&&total>today,`About55m of the111m crossing belongs to today, got today=${today}km total=${total}km`);
    });
    if(engine === playwright.chromium)await scenario("same-date timezone changes invalidate the daily exploration cache",async page=>{
      const cdp=await page.context().newCDPSession(page);
      await cdp.send("Emulation.setTimezoneOverride",{timezoneId:"UTC"});
      await page.clock.install({time:new Date("2026-11-01T12:00:00Z")});
      const t=Date.parse("2026-10-31T18:00:00Z"),w={id:"timezone",name:"時差のある記録",start:t,end:t+60000,points:[{lat:35,lon:139,t},{lat:35,lon:139.01,t:t+60000}]};
      await replaceLibrary(page,{...library,walks:[w],flags:[]});
      assert.equal((await page.locator("#todayNew").textContent()).trim(),"0.00");
      await cdp.send("Emulation.setTimezoneOverride",{timezoneId:"Asia/Tokyo"});
      await page.evaluate(()=>document.dispatchEvent(new Event("visibilitychange")));
      await page.waitForFunction(()=>Number(document.querySelector("#todayNew").textContent)>0.8);
      assert.ok(Number(await page.locator("#todayNew").textContent())<1,"A910m prior-UTC-day walk belongs to today'sJapanese calendar day");
    },{timezoneId:undefined});
    await scenario("live GPS updates accumulate only newly accepted edges", async page => {
      const at=Date.now(),history={id:"long-history",name:"以前の道",start:at-86400000,end:at-86400000+500000,points:Array.from({length:501},(_,i)=>({lat:35.68,lon:139.76+i*0.00001,t:at-86400000+i*1000}))};
      await replaceLibrary(page,{...library,walks:[history],flags:[]});
      await page.evaluate(async ()=>{
        navigator.geolocation.watchPosition=callback=>{window.captureGPS=callback;return 123;};
        const {ExplorationAccumulator}=await import("/core.js"),append=ExplorationAccumulator.prototype.append;
        window.captureAppendCalls=0;ExplorationAccumulator.prototype.append=function(...args){window.captureAppendCalls++;return append.apply(this,args);};
      });
      await button(page,"散歩を始める").click();await button(page,"散歩を始める").last().click();
      await page.waitForFunction(()=>typeof window.captureGPS==="function");
      await page.evaluate(()=>{const t=Date.now();window.captureGPS({coords:{latitude:35.6815,longitude:139.762,accuracy:5},timestamp:t});window.captureGPS({coords:{latitude:35.6815,longitude:139.7622,accuracy:5},timestamp:t+10000});});
      const calls=await page.evaluate(()=>window.captureAppendCalls);
      assert.equal(calls,1,"Two new GPS points must append one edge without replaying the501-point history");
    });
    assert.deepEqual(failures, [], failures.join("\n"));
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
