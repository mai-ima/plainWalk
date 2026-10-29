import { DEVICE_CHECKS, sanitizeNativeReport } from "./diagnostics.js";
export function createDeveloperUI(ctx) {
  const {
    $,
    esc,
    openPage,
    state,
    trace,
    native,
    nativeCall,
    saveConfig,
    download,
    toast,
    storageProbe,
  } = ctx;
  let snapshot = null,
    lastIO = null,
    frames = null,
    timer = null;
  const currentState = () => state();
  function table(rows) {
    return `<dl class="dev-facts">${rows.map(([k, v]) => `<div><dt>${esc(k)}</dt><dd>${esc(v ?? "不明")}</dd></div>`).join("")}</dl>`;
  }
  function refreshHTML() {
    const s = currentState();
    return `<section class="reference-section"><h3>実機検証</h3><div class="reference-group">${table(
      [
        [
          "実行環境",
          native
            ? snapshot?.native?.flavor === "playgrounds"
              ? "Swift Playgrounds"
              : "iOS アプリ"
            : "Web / PWA",
        ],
        ["記録", s.recording ? "記録中" : s.paused ? "一時停止" : "停止"],
        ["記録点", s.activePoints],
        ["GPS 精度", s.accuracy ? `±${Math.round(s.accuracy)} m` : "未取得"],
        [
          "最後の測位",
          s.fixAgeMs == null
            ? "未取得"
            : `${Math.round(s.fixAgeMs / 1000)} 秒前`,
        ],
        ["保存済みさんぽ", s.walks],
        ["画面", `${innerWidth} × ${innerHeight}`],
      ],
    )}</div><p>この画面を開くだけでは、新しい位置情報やカメラの権限を要求しません。</p></section><div class="two-buttons">${native ? '<button data-action="nativeDeveloper">SwiftUI の実機検証を開く</button>' : ""}<button data-action="devRefresh">状態を更新</button><button data-action="devStorage">保存を往復テスト</button><button data-action="devFrames">画面描画テスト</button><button data-action="devExport">診断 JSON を書き出す</button></div>${
      snapshot
        ? `<section class="reference-section"><h3>権限・環境</h3><div class="reference-group">${table(
            [
              [
                "位置情報",
                snapshot.native?.locationAuthorization ||
                  snapshot.browser.geolocationPermission,
              ],
              ["位置の精度", snapshot.native?.accuracyAuthorization],
              ["モーション", snapshot.native?.motionAuthorization],
              ["カメラ", snapshot.native?.cameraAuthorization],
              ["マイク", snapshot.native?.microphoneAuthorization],
              ["通知", snapshot.native?.notificationAuthorization],
              ["通信", snapshot.browser.online ? "オンライン" : "オフライン"],
              [
                "セキュア環境",
                snapshot.browser.secureContext ? "はい" : "いいえ",
              ],
              ["PWA", snapshot.browser.standalone ? "単独表示" : "通常表示"],
              [
                "低電力モード",
                snapshot.native?.lowPowerMode == null
                  ? "取得不可"
                  : snapshot.native.lowPowerMode
                    ? "オン"
                    : "オフ",
              ],
              [
                "空き容量",
                snapshot.native?.freeBytes != null
                  ? `${Math.round(snapshot.native.freeBytes / 1048576)} MB`
                  : snapshot.browser.storageQuota
                    ? `${Math.round((snapshot.browser.storageQuota - snapshot.browser.storageUsage) / 1048576)} MB（推定）`
                    : "不明",
              ],
            ],
          )}</div></section>`
        : ""
    }${lastIO ? `<p class="dev-result" role="status">保存の往復：${lastIO.ok ? "成功" : "失敗"} · ${lastIO.durationMs} ms</p>` : ""}${frames ? `<p class="dev-result" role="status">描画 ${frames.samples} 回 · 平均間隔 ${frames.averageMs} ms · 最長 ${frames.maxMs} ms</p>` : ""}<section class="reference-section"><h3>表示の検証</h3><div class="reference-group"><label class="reference-row"><span class="grow">タップ領域に枠を表示</span><input class="switch" type="checkbox" data-dev-setting="developerOutlines" ${s.config.developerOutlines ? "checked" : ""}></label><label class="reference-row"><span class="grow">GPS 状態を小さく常時表示</span><input class="switch" type="checkbox" data-dev-setting="developerHUD" ${s.config.developerHUD ? "checked" : ""}></label></div></section><section class="reference-section"><h3>端末で確認する項目</h3><div class="reference-group">${DEVICE_CHECKS.map(([key, label]) => `<button class="reference-row dev-check" data-dev-check="${key}"><span class="grow">${label}</span><span>${["未確認", "確認済み", "不具合あり"][s.config.deviceChecks?.[key] || 0]}</span></button>`).join("")}</div><p>タップするたびに結果が切り替わります。実機で確認した結果を自分で記録してください。</p></section><section class="reference-section"><h3>診断ログ · 最大 250 件</h3><div class="dev-log">${
      trace
        .entries()
        .slice(-25)
        .reverse()
        .map(
          (e) =>
            `<div><time>${esc(e.time.slice(11, 19))}</time><b>${esc(e.type)}</b><small>${esc(
              Object.entries(e)
                .filter(([k]) => !["time", "type"].includes(k))
                .map(([k, v]) => `${k}=${v}`)
                .join(" "),
            )}</small></div>`,
        )
        .join("") || "<p>まだログがありません。</p>"
    }</div><button class="secondary" data-action="devClear">診断ログを消去</button><p>座標・軌跡・写真・メモ・場所名を含めず、端末から自動送信しません。ログはこのタブの中で保持します。</p></section>`;
  }
  function open() {
    if (!currentState().config.developerMode) return;
    const html = refreshHTML();
    if ($("#contentPage").dataset.route === "開発者向け")
      $("#pageBody").innerHTML = html;
    else openPage("開発者向け", html, { grouped: true });
  }
  async function collect() {
    let permission = "取得不可",
      storage = {};
    try {
      permission = (await navigator.permissions.query({ name: "geolocation" }))
        .state;
    } catch {}
    try {
      storage = (await navigator.storage?.estimate?.()) || {};
    } catch {}
    const s = currentState();
    snapshot = {
      version: 1,
      createdAt: new Date().toISOString(),
      appVersion: "0.3.0",
      browser: {
        userAgent: navigator.userAgent.slice(0, 300),
        language: navigator.language,
        protocol: location.protocol,
        online: navigator.onLine,
        secureContext: isSecureContext,
        standalone:
          matchMedia("(display-mode: standalone)").matches ||
          navigator.standalone === true,
        visibility: document.visibilityState,
        geolocationPermission: permission,
        storageUsage: storage.usage ?? null,
        storageQuota: storage.quota ?? null,
        viewport: {
          width: innerWidth,
          height: innerHeight,
          dpr: devicePixelRatio,
        },
        capabilities: {
          geolocation: !!navigator.geolocation,
          camera: !!navigator.mediaDevices?.getUserMedia,
          mediaRecorder: typeof MediaRecorder !== "undefined",
          wakeLock: "wakeLock" in navigator,
          serviceWorker: !!navigator.serviceWorker?.controller,
        },
      },
      recording: {
        running: s.recording,
        paused: s.paused,
        points: s.activePoints,
        accuracy: s.accuracy || null,
        fixAgeMs: s.fixAgeMs,
      },
      library: { walks: s.walks, points: s.points },
      native: null,
    };
    if (native)
      try {
        snapshot.native = sanitizeNativeReport(await nativeCall("diagnostics"));
      } catch {
        trace.record("error", {
          source: "nativeDiagnostics",
          code: "unavailable",
        });
      }
    trace.record("diagnostics", { status: "refreshed" });
    return snapshot;
  }
  function apply() {
    const s = currentState();
    document.body.classList.toggle(
      "dev-outlines",
      !!s.config.developerMode && !!s.config.developerOutlines,
    );
    let hud = $("#developerHUD");
    if (!hud) {
      hud = document.createElement("output");
      hud.id = "developerHUD";
      hud.setAttribute("aria-label", "開発者向け GPS 状態");
      document.body.append(hud);
    }
    hud.hidden = !s.config.developerMode || !s.config.developerHUD;
    clearInterval(timer);
    timer = null;
    if (!hud.hidden) {
      const update = () => {
        const s = currentState();
        hud.textContent = `DEV · ${native ? "iOS" : "Web"} · ${s.recording ? "REC" : s.paused ? "PAUSE" : "IDLE"}\nGPS ${s.accuracy ? "±" + Math.round(s.accuracy) + "m" : "—"} · ${s.fixAgeMs == null ? "—" : Math.round(s.fixAgeMs / 1000) + "s"} · ${s.activePoints} points`;
      };
      update();
      timer = setInterval(update, 1000);
    }
  }
  async function change(el) {
    if (el.dataset.devSetting) {
      const s = currentState();
      s.config[el.dataset.devSetting] = el.checked;
      await saveConfig();
      apply();
      return true;
    }
    return false;
  }
  async function click(d) {
    if (!d.devCheck) return false;
    const s = currentState();
    s.config.deviceChecks = {
      ...s.config.deviceChecks,
      [d.devCheck]: ((s.config.deviceChecks?.[d.devCheck] || 0) + 1) % 3,
    };
    await saveConfig();
    open();
    return true;
  }
  return {
    open,
    apply,
    collect,
    change,
    click,
    actions: {
      developer: async () => {
        await collect();
        open();
      },
      devRefresh: async () => {
        await collect();
        open();
      },
      devStorage: async () => {
        const started = performance.now();
        try {
          if (native) {
            const result = await nativeCall("diagnosticsStorageTest");
            lastIO = { ok: result?.ok === true };
          } else {
            await storageProbe();
            lastIO = { ok: true };
          }
        } catch {
          lastIO = { ok: false };
        }
        lastIO.durationMs = Math.round(performance.now() - started);
        trace.record("storageProbe", {
          status: lastIO.ok ? "ok" : "failed",
          durationMs: lastIO.durationMs,
        });
        open();
      },
      devFrames: async () => {
        const times = [];
        let last = performance.now(),
          start = last;
        await new Promise((resolve) => {
          const tick = (now) => {
            times.push(now - last);
            last = now;
            if (now - start < 650) requestAnimationFrame(tick);
            else resolve();
          };
          requestAnimationFrame(tick);
        });
        frames = {
          samples: times.length,
          averageMs:
            Math.round((times.reduce((a, b) => a + b, 0) / times.length) * 10) /
            10,
          maxMs: Math.round(Math.max(...times) * 10) / 10,
        };
        open();
      },
      devExport: async () => {
        await collect();
        const checks = Object.fromEntries(
          DEVICE_CHECKS.map(([key]) => [
            key,
            ["unverified", "passed", "failed"][
              currentState().config.deviceChecks?.[key] || 0
            ],
          ]),
        );
        const report = {
          ...snapshot,
          checks,
          storageTest: lastIO,
          frameTest: frames,
          events: trace.entries(),
        };
        download(
          new Blob([JSON.stringify(report, null, 2)], {
            type: "application/json",
          }),
          "plainwalk-device-diagnostics.json",
        );
        toast("診断 JSON を書き出しました。");
      },
      devClear: () => {
        trace.clear();
        open();
      },
    },
  };
}
