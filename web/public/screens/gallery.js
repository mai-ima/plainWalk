const $ = (selector) => document.querySelector(selector);
const grid = $("#screen-grid");
const empty = $("#empty-state");
const search = $("#search");
const category = $("#category");
const viewer = $("#viewer");
const imageStage = $("#image-stage");
const viewerImage = $("#viewer-image");
const state = { screens: [], filtered: [], platform: "all", current: -1, opener: null, loaded: false };
const platformNames = { native: "Swift", web: "Web" };
const stateNames = { empty: "初期状態", populated: "記録あり", fixture: "検証用データ", captured: "撮影済み", missing: "未撮影", "physical-only": "実機で確認", unsupported: "未対応", pending: "準備中", error: "撮影失敗" };

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}
function imageURL(screen) {
  if (typeof screen.image !== "string" || !/^images\/[a-zA-Z0-9._-]+\.(?:png|jpe?g|webp)$/i.test(screen.image)) return null;
  return new URL(screen.image, location.href.split("#")[0]).href;
}
function available(screen) { return screen.status === "captured" && Boolean(imageURL(screen)); }
function meta(screen) {
  return [screen.category, stateNames[screen.state] || screen.state, screen.part > 1 ? `続き ${screen.part}` : ""].filter(Boolean).join(" · ");
}
const observer = "IntersectionObserver" in window ? new IntersectionObserver((entries) => {
  for (const entry of entries) if (entry.isIntersecting) {
    const image = entry.target;
    image.src = image.dataset.src;
    observer.unobserve(image);
  }
}, { rootMargin: "100px" }) : null;

function render() {
  observer?.disconnect();
  const query = search.value.trim().toLocaleLowerCase("ja");
  state.filtered = state.screens.filter((screen) =>
    (state.platform === "all" || screen.platform === state.platform) &&
    (category.value === "all" || screen.category === category.value) &&
    (!query || [screen.title, screen.category, screen.state, stateNames[screen.state], platformNames[screen.platform]].filter(Boolean).join(" ").toLocaleLowerCase("ja").includes(query))
  );
  const fragment = document.createDocumentFragment();
  for (const screen of state.filtered) {
    const card = element("article", "screen-card");
    if (available(screen)) {
      const button = element("button", "screen-open");
      button.type = "button";
      button.setAttribute("aria-label", `${platformNames[screen.platform]}・${screen.title}${screen.part > 1 ? ` 続き ${screen.part}` : ""}を大きく見る`);
      const thumb = element("div", "screen-thumb");
      const image = element("img");
      image.alt = "";
      image.width = 393;
      image.height = 852;
      image.loading = "lazy";
      image.decoding = "async";
      image.dataset.src = imageURL(screen);
      image.addEventListener("load", () => image.classList.add("loaded"), { once: true });
      thumb.append(image, element("span", "screen-platform", platformNames[screen.platform]));
      button.append(thumb);
      button.addEventListener("click", () => openViewer(screen, button));
      card.append(button);
      if (observer) observer.observe(image); else image.src = image.dataset.src;
    } else {
      const placeholder = element("div", "screen-missing");
      placeholder.append(element("span", "", "▧"), element("strong", "", stateNames[screen.status] || "未撮影"));
      if (screen.note) placeholder.append(element("small", "", screen.note));
      card.append(placeholder);
    }
    const info = element("div", "screen-info");
    info.append(element("h3", "", screen.title), element("p", "screen-meta", meta(screen)));
    card.append(info);
    fragment.append(card);
  }
  grid.replaceChildren(fragment);
  $("#result-count").textContent = `${state.filtered.filter(available).length} 枚${state.filtered.some((screen) => !available(screen)) ? ` / ${state.filtered.length} 項目` : ""}`;
  empty.hidden = state.filtered.length > 0;
  const platformPending = state.platform !== "all" && !state.screens.some((screen) => screen.platform === state.platform) && !query && category.value === "all";
  if (platformPending) {
    empty.querySelector("h2").textContent = `${platformNames[state.platform]} 版の画像は準備中です`;
    empty.querySelector("p").textContent = "準備ができた画面から、ここに並びます。";
  } else if (state.screens.length) {
    empty.querySelector("h2").textContent = "見つかりませんでした";
    empty.querySelector("p").textContent = "検索する言葉や、種類・分類を変えてみてください。";
  }
}

function activeScreens() { return state.filtered.filter(available); }
function selectPlatform(platform) {
  state.platform = platform;
  for (const tab of document.querySelectorAll("[data-platform]")) {
    const selected = tab.dataset.platform === platform;
    tab.classList.toggle("active", selected);
    tab.setAttribute("aria-pressed", String(selected));
  }
  render();
}
function setViewerScreen(index) {
  const screens = activeScreens();
  if (!screens.length) return;
  state.current = Math.max(0, Math.min(index, screens.length - 1));
  const screen = screens[state.current];
  $("#viewer-title").textContent = screen.title;
  $("#viewer-subtitle").textContent = [platformNames[screen.platform], meta(screen)].filter(Boolean).join(" · ");
  viewerImage.alt = `${platformNames[screen.platform]}版 ${screen.title}の撮影画像${screen.part > 1 ? `、続き ${screen.part}` : ""}`;
  viewerImage.src = imageURL(screen);
  imageStage.dataset.zoom = "false";
  $("#viewer-zoom").textContent = "拡大";
  $("#viewer-zoom").setAttribute("aria-pressed", "false");
  imageStage.scrollTop = 0;
  imageStage.scrollLeft = 0;
  $("#viewer-position").textContent = `${state.current + 1} / ${screens.length}`;
  $("#viewer-prev").disabled = state.current === 0;
  $("#viewer-next").disabled = state.current === screens.length - 1;
  return screen;
}
function hashFor(screen) { return `#screen=${encodeURIComponent(screen.id)}`; }
function openViewer(screen, opener, push = true) {
  const index = activeScreens().findIndex((item) => item.id === screen.id);
  if (index < 0) return;
  state.opener = opener || null;
  setViewerScreen(index);
  if (!viewer.open) viewer.showModal();
  $("#viewer-close").focus({ preventScroll: true });
  if (push) history.pushState({ plainwalkScreenViewer: true }, "", hashFor(screen));
}
function closeViewer() {
  if (history.state?.plainwalkScreenViewer) history.back();
  else {
    history.replaceState(history.state, "", location.pathname + location.search);
    syncViewerFromURL();
  }
}
function syncViewerFromURL() {
  if (!state.loaded) return;
  const key = new URLSearchParams(location.hash.slice(1)).get("screen");
  const screen = state.screens.find((item) => item.id === key && available(item));
  if (!screen) {
    if (viewer.open) viewer.close();
    return;
  }
  if (!state.filtered.some((item) => item.id === screen.id)) {
    search.value = "";
    category.value = "all";
    selectPlatform("all");
  }
  // A single history navigation may emit both popstate and hashchange.
  // Keep an already synchronized viewer intact, including its zoom/scroll.
  if (viewer.open && activeScreens()[state.current]?.id === screen.id) return;
  const card = grid.children[state.filtered.findIndex((item) => item.id === screen.id)];
  openViewer(screen, card?.querySelector(".screen-open"), false);
}
function stepViewer(delta) {
  const screen = setViewerScreen(state.current + delta);
  if (screen) history.replaceState(history.state, "", hashFor(screen));
}
$("#viewer-close").addEventListener("click", closeViewer);
$("#viewer-prev").addEventListener("click", () => stepViewer(-1));
$("#viewer-next").addEventListener("click", () => stepViewer(1));
$("#viewer-zoom").addEventListener("click", () => {
  const zoom = imageStage.dataset.zoom !== "true";
  imageStage.dataset.zoom = String(zoom);
  $("#viewer-zoom").textContent = zoom ? "幅に合わせる" : "拡大";
  $("#viewer-zoom").setAttribute("aria-pressed", String(zoom));
});
viewer.addEventListener("cancel", (event) => { event.preventDefault(); closeViewer(); });
viewer.addEventListener("close", () => {
  if (viewer.open) return; // Back/Forward may reopen before a queued close event.
  viewerImage.removeAttribute("src");
  state.opener?.focus({ preventScroll: true });
});
window.addEventListener("popstate", syncViewerFromURL);
window.addEventListener("hashchange", syncViewerFromURL);
window.addEventListener("keydown", (event) => {
  if (!viewer.open) return;
  if (event.key === "ArrowLeft") { event.preventDefault(); stepViewer(-1); }
  if (event.key === "ArrowRight") { event.preventDefault(); stepViewer(1); }
});
for (const tab of document.querySelectorAll("[data-platform]")) tab.addEventListener("click", () => selectPlatform(tab.dataset.platform));
search.addEventListener("input", render);
category.addEventListener("change", render);

try {
  const response = await fetch("manifest.json", { cache: "no-store" });
  if (!response.ok) throw new Error("Manifest unavailable");
  const manifest = await response.json();
  state.screens = Array.isArray(manifest.screens) ? manifest.screens.filter((screen) => screen && typeof screen.id === "string" && typeof screen.title === "string" && ["web", "native"].includes(screen.platform)) : [];
  const categories = [...new Set(state.screens.map((screen) => screen.category).filter(Boolean))];
  for (const name of categories) {
    const option = element("option", "", name); option.value = name; category.append(option);
  }
  const web = state.screens.filter((screen) => screen.platform === "web" && available(screen)).length;
  const native = state.screens.filter((screen) => screen.platform === "native" && available(screen)).length;
  const pending = state.screens.filter((screen) => !available(screen)).length;
  $("#capture-summary").textContent = state.screens.length ? `Web ${web} 枚 / Swift ${native} 枚${pending ? ` · 未撮影など ${pending} 項目` : ""}` : "画像は準備中です。";
  const date = new Date(manifest.generatedAt);
  if (Number.isFinite(date.getTime())) $("#updated-at").textContent = `更新 ${date.toLocaleString("ja-JP", { year: "numeric", month: "long", day: "numeric", hour: "2-digit", minute: "2-digit" })}`;
  state.loaded = true;
  render();
  syncViewerFromURL();
} catch {
  $("#capture-summary").textContent = "画像は準備中です。";
  render();
}
