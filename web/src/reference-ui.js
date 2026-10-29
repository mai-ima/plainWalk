import { companionSVG } from "./companion.js";
const sampleLine = (dashed = false, stylePreview = false) =>
  `<svg viewBox="0 0 44 44" aria-hidden="true" focusable="false"><path d="${stylePreview ? "M5 23C12 34 16 39 23 27S33 8 39 13" : "M10 29C19 29 20 15 32 15"}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ${dashed ? 'stroke-dasharray=".5 5"' : ""}/></svg>`;
const pinSample = (type) =>
  `<svg viewBox="0 0 44 44" aria-hidden="true" focusable="false">${type === "circle" ? '<circle cx="22" cy="22" r="11" fill="none" stroke="currentColor" stroke-width="1.5"/>' : type === "square" ? '<rect x="11" y="11" width="22" height="22" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/>' : type === "outline" ? '<circle cx="22" cy="22" r="10" fill="none" stroke="currentColor" stroke-width="1.8"/>' : type === "dot" ? '<circle cx="22" cy="22" r="4.2" fill="currentColor"/>' : '<rect x="12" y="12" width="20" height="21" rx="7" fill="white" stroke="#d4d4d4"/>'}${type === "dot" ? "" : '<path d="M22 28c-13-8-6-17 0-10 6-7 13 2 0 10" transform="translate(22 22) scale(.76) translate(-22 -22)" fill="currentColor" stroke="none"/>'}</svg>`;
function choice(key, value, label, inside, chosen) {
  return `<button data-layer-key="${key}" data-layer-value="${value}" class="layer-choice ${chosen ? "chosen" : ""}" aria-label="${label}" aria-pressed="${chosen ? "true" : "false"}"><span class="layer-choice-circle">${inside}</span><span>${label}</span></button>`;
}
function transportSVG(kind) {
  const paths = {
    walking:
      '<circle cx="14" cy="4" r="2"/><path d="m12 8-3 4-4 1m7-5 3 5 4 1m-7-6-2 8-4 6m4-6 5 2 1 5"/>',
    running:
      '<circle cx="16" cy="4" r="2"/><path d="m13 8-4 4-4-1m8-3 4 5 4-1m-8-4-3 7-6 2m6-2 5 3-2 5"/>',
    cycling:
      '<circle cx="5" cy="17" r="4"/><circle cx="20" cy="17" r="4"/><path d="m5 17 6-9 9 9M8 8h7M9 8l6 9H5m10-9-1-4h4"/>',
    vehicle:
      '<path d="m4 10 2-6h12l2 6M3 10h18v9H3zM6 19v3M18 19v3M6 14h2M16 14h2"/>',
  };
  return `<svg viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${paths[kind]}</svg>`;
}
function switchRow(key, label, value, icon = "") {
  return `<label class="reference-row">${icon ? `<span class="reference-row-icon">${icon}</span>` : ""}<span class="grow">${label}</span><input class="switch" type="checkbox" data-map-config="${key}" ${value ? "checked" : ""} aria-label="${label}"></label>`;
}
export function layersHTML(config, themes) {
  const themeRows = themes
    .map(([name, paper, ink], i) =>
      choice(
        "theme",
        i,
        name,
        `<span class="theme-preview" style="background:${paper};color:${ink}">${sampleLine()}</span>`,
        config.theme === i,
      ),
    )
    .join("");
  const lineRows = [
    ["solid", "実線"],
    ["dashed", "点線"],
  ]
    .map(([v, l]) =>
      choice("line", v, l, sampleLine(v === "dashed", true), config.line === v),
    )
    .join("");
  const pinRows = [
    ["badge", "バッジ"],
    ["circle", "丸"],
    ["square", "正方形"],
    ["outline", "輪郭"],
    ["dot", "点"],
  ]
    .map(([v, l]) =>
      choice(
        "pin",
        v,
        l,
        pinSample(v),
        (config.pin === "card" ? "badge" : config.pin) === v,
      ),
    )
    .join("");
  const catRows = [
    ["dot", "点"],
    ["black", "黒猫"],
    ["tabby", "茶トラ"],
    ["calico", "三毛"],
    ["silver", "サバトラ"],
  ]
    .map(([v, l]) =>
      choice(
        "locationMark",
        v,
        l,
        v === "dot"
          ? '<span class="location-dot-preview"></span>'
          : companionSVG(v),
        (config.locationMark || "dot") === v,
      ),
    )
    .join("");
  return `<section class="reference-section"><h3>配色</h3><div class="reference-choices" role="group" aria-label="配色">${themeRows}</div><p>選んだ配色はシェアカードとタイムラプス動画にも使われます。</p></section><section class="reference-section"><h3>線</h3><div class="reference-choices" role="group" aria-label="線">${lineRows}</div></section><section class="reference-section"><h3>写真ピン</h3><div class="reference-choices" role="group" aria-label="写真ピン">${pinRows}</div></section><section class="reference-section"><h3>現在地</h3><div class="reference-choices" role="group" aria-label="現在地">${catRows}</div><p>歩くと猫も歩き、止まると座ります。向いている方向を向きます。大きく引いたときは、どちらを選んでいても現在地はドットに戻ります。</p></section><section class="reference-section"><div class="reference-group">${switchRow("outline", "地図の輪郭を表示", config.outline)}</div><p>市区町村の境を薄い線で表示します。日本の境界データを利用しています。</p></section><section class="reference-section"><div class="reference-group">${switchRow("fadeOther", "記録中は他の軌跡を薄くする", config.fadeOther !== false)}</div><p>記録中は、他のすべての軌跡を薄くして、いま歩いている形を見やすくします。</p></section><section class="reference-section"><h3>移動手段</h3><div class="reference-group">${[
    ["walking", "徒歩", "walking"],
    ["running", "ランニング", "running"],
    ["cycling", "自転車", "cycling"],
    ["vehicle", "乗り物", "vehicle"],
  ]
    .map(([v, l, i]) =>
      switchRow(
        "transport:" + v,
        l,
        config.transportVisible?.[v] !== false,
        transportSVG(i),
      ),
    )
    .join(
      "",
    )}</div><p>オフにすると、その手段で動いた区間を白地図に描きません。歩いた距離と開拓距離は変わりません。手段はさんぽの詳細で直せます。</p></section><section class="reference-section"><div class="reference-group">${switchRow("thicken", "よく通る道を太く表示", config.thicken !== false)}${switchRow("smooth", "軌跡を整える", config.smooth !== false)}${switchRow("grid", "方眼グリッドを表示", config.grid)}${switchRow("highlight", "現在地のハイライト", config.highlight !== false)}${switchRow("showPhotos", "写真を表示", config.showPhotos !== false)}${switchRow("showTweets", "つぶやきを表示", config.showTweets)}</div></section>`;
}
export function settingsHTML(config, { native, icon }) {
  // Config can originate in a user-imported backup. Only a valid local time is
  // inserted into this HTML attribute; arbitrary imported text is never markup.
  const morningTime = typeof config.morningTime === "string" &&
    /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(config.morningTime)
    ? config.morningTime : "07:45";
  const link = (action, label, ico = "", value = "") =>
    `<button class="reference-row settings-link" data-action="${action}" aria-label="${label}">${ico ? `<span class="reference-row-icon">${icon(ico)}</span>` : ""}<span class="grow">${label}</span>${value ? `<span class="reference-value">${value}</span>` : ""}<span class="reference-chevron">›</span></button>`;
  const notice = native
    ? "位置情報を「常に」にすると、アプリを閉じた間の検知を設定できます。"
    : "Web では画面を閉じた間の移動検知はできません。記録中は画面を開いてお使いください。";
  return `<section class="reference-section"><h3>動き出したとき</h3><div class="reference-group">${[
    ["none", "何もしない"],
    ["notify", "知らせる"],
    ["record", "自動で記録する"],
  ]
    .map(
      ([v, l]) =>
        `<button class="reference-row settings-link" data-movement-policy="${v}"><span class="grow">${l}</span>${(config.movementPolicy || "none") === v ? '<span class="reference-check">✓</span>' : ""}</button>`,
    )
    .join(
      "",
    )}</div><p>${notice}</p>${native ? '<button class="text-link" data-action="systemSettings">iOS の設定を開く</button>' : ""}</section><section class="reference-section"><h3>自宅・職場・よく行く場所</h3><div class="reference-group">${switchRow("registeredPlaces", "登録した場所から記録", config.registeredPlaces)}${link("homePlace", "自宅", "home", config.homePlace ? "設定済み" : "未設定")}${link("workPlace", "職場", "building", config.workPlace ? "設定済み" : "未設定")}${link("addPlace", "場所を追加", "plus")}</div><p>場所はこの端末の中だけに置き、白地図には描きません。Web のバックグラウンド検知は対応していません。</p></section><section class="reference-section"><div class="reference-group">${switchRow("stayDeparture", "滞在した場所から記録", config.stayDeparture)}</div><p>長く滞在した場所を出たときの記録です。iOS アプリで利用する機能です。</p></section><section class="reference-section"><div class="reference-group"><label class="reference-row"><span class="grow">外観</span><select data-config="dark" class="row-select"><option value="light" ${config.dark === "light" ? "selected" : ""}>ライト</option><option value="dark" ${config.dark === "dark" ? "selected" : ""}>ダーク</option><option value="auto" ${config.dark === "auto" ? "selected" : ""}>端末に合わせる</option></select></label></div><p>ダークにすると、白地図が黒い紙に白いインクになります。</p></section><section class="reference-section"><div class="reference-group"><label class="reference-row"><span class="grow">単位</span><select data-config="units" class="row-select"><option value="auto" ${!config.units || config.units === "auto" ? "selected" : ""}>地域に合わせる (km)</option><option value="km" ${config.units === "km" ? "selected" : ""}>キロメートル</option><option value="mi" ${config.units === "mi" ? "selected" : ""}>マイル</option></select></label></div><p>距離・面積・速さの表示に使います。</p></section><section class="reference-section"><h3>歩数</h3><div class="reference-group">${link("steps", "1 日の歩数の目標", "target", config.goalEnabled ? Number(config.goal).toLocaleString() + " 歩" : "オフ")}</div><p>さんぽを記録していないときも、今日の歩数を確かめられます。</p></section><section class="reference-section"><h3>カメラ</h3><div class="reference-group">${link("lutSettings", "LUT", "camera")}</div></section><section class="reference-section"><h3>通知</h3><div class="reference-group">${switchRow("morningNotification", "朝の通知", config.morningNotification)}<label class="reference-row"><span class="grow">通知する時刻</span><input id="morningTime" type="time" value="${morningTime}" class="time-value"></label>${switchRow("weeklyNotification", "週間ふりかえりの通知", config.weeklyNotification)}${switchRow("interruptionNotification", "さんぽが途切れたら知らせる", config.interruptionNotification)}</div><p>出かける前に、そっとひと声かけます。いつでもオフにできます。Web では、アプリを閉じた間の通知を保証できません。</p></section><section class="reference-section"><h3>Apple ヘルスケア</h3><div class="reference-group">${switchRow("healthEnabled", "ヘルスケアを使う", config.healthEnabled, "<span>☷</span>")}${link("healthImport", "ワークアウトを選んで描く", "foot")}${switchRow("healthAutoSync", "自動で白地図に連携する", config.healthAutoSync)}</div><p>iOS アプリで許可した歩数や屋外ワークアウトを読み込みます。Web ブラウザからは取得できません。</p><div class="reference-group" style="margin-top:24px">${switchRow("healthSave", "さんぽをヘルスケアに保存", config.healthSave)}</div></section><section class="reference-section"><h3>取り込み</h3><div class="reference-group">${link("import", "ファイルからさんぽを取り込む", "upload")}</div><p>GPX / TCX ファイル。1 本の軌跡が 1 回のさんぽになります。</p></section><section class="reference-section"><h3>書き出し</h3><div class="reference-group">${link("gpxExportAll", "すべてのさんぽを GPX で書き出す", "download")}</div><p>すべてのさんぽを1つのGPXファイルにします。写真やらくがきは入りません。</p></section><section class="reference-section"><h3>バックアップ</h3><div class="reference-group">${link("backup", "バックアップを書き出す", "download")}${link(native ? "nativeRestore" : "import", "バックアップを取り込む", "upload")}</div><p>iPhone は「ファイルに保存」から、自分の iCloud Drive も選べます。</p></section><section class="reference-section"><h3>アプリについて</h3><div class="reference-group">${link("about", "バージョン", "", "0.3.0")}${link("diagnostics", "GPS の診断", "info")}${link("limitations", "対応範囲", "info")}</div></section><section class="reference-section"><h3>beta</h3><div class="reference-group">${switchRow("beta", "beta 機能", config.beta)}${config.beta ? switchRow("wake", "画面をスリープさせない", config.wake) + switchRow("accuracy", "GPS 精度を表示", config.accuracy) + link("demo", "体験モード", "foot") : ""}</div></section><section class="reference-section"><h3>開発者向け</h3><div class="reference-group">${switchRow("developerMode", "開発者モード", config.developerMode)}${config.developerMode ? link("developer", "実機検証・診断ログ", "info") : ""}</div><p>権限・GPS・保存と画面表示を端末で確認できます。診断ログは自分で書き出すまで端末の外に送りません。</p></section><section class="reference-section"><div class="reference-group"><button class="reference-row settings-link danger-button" data-action="resetData">データをリセット</button></div></section>`;
}
