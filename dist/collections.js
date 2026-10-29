import { distance, validPoint, validateCollections } from "./core.js";

// Collections use the same local library and backup as walks. No server receives them.
export function createCollections(ctx) {
  const {
    $,
    esc,
    icon,
    state,
    save,
    sheet,
    openPage,
    switchTab,
    draw,
    fit,
    id,
    toast,
    download,
    screenToPoint,
    paths,
  } = ctx;
  let draft = null,
    drawingPointer = null,
    stroke = null;
  const library = () => state().data;
  const allStickers = () =>
    Object.entries(library().notes).flatMap(([day, note]) =>
      (note.layout || [])
        .filter((i) => i.type === "sticker")
        .map((i) => ({ ...i, day })),
    );
  function page(title, html, options) {
    if ($("#contentPage").dataset.route === title) {
      ctx.closeSheet();
      $("#pageBody").innerHTML = html;
    } else openPage(title, html, options);
  }
  function bookmarks() {
    const items = library().bookmarks || [];
    page(
      "気になる場所",
      items.length
        ? `<div class="reference-group">${items.map((p) => `<button class="reference-row collection-place" data-bookmark="${esc(p.id)}">${icon("flag")}<span class="grow">${esc(p.name)}</span><span class="chevron">›</span></button>`).join("")}</div>`
        : '<section class="collection-message"><h2>気になる場所はまだありません</h2><p>答え合わせマップで場所を探して、しおりを押すとここに入ります。行ってみたくなったら「ここへ向かう」。白地図に旗が立って方角を示します。</p></section>',
    );
  }
  function bookmarkAdd(p) {
    sheet(
      "気になる場所を保存",
      `<label class="form-label">場所の名前</label><input id="bookmarkName" maxlength="60" placeholder="いつか寄りたい場所"><button class="primary" data-bookmark-save="${p.lat},${p.lon}">しおりを挟む</button>`,
    );
  }
  function stickers() {
    const items = allStickers();
    page(
      "ステッカー",
      `<section class="collection-outline">${ctx.row("stickerExchange", "近くの人と交換・あげる", "exchange", "1 枚ずつ選んで、画像で渡せます。")}</section>${items.length ? `<div class="sticker-grid">${items.map((i) => `<button data-sticker-item="${esc(i.id)}"><img src="${esc(i.src)}" alt="${esc(i.day)} のステッカー"><small>${esc(i.day)}</small></button>`).join("")}</div>` : '<p class="collection-note">ここいいなの写真から切り抜いたステッカーが、ここに集まります。</p>'}`,
    );
  }
  function doodles() {
    const items = library().doodles || [];
    page(
      "らくがき",
      `<section class="collection-outline collection-intro"><h2>答え合わせマップに絵を描いて、いつか歩いてみる。</h2><p>白地図の右上から答え合わせマップを開いて「らくがき」を押すか、ここから始めます。1 本指で道をなぞって描いた絵を、歩くまで取っておきます。</p><button class="primary compact" data-action="doodleStart">${icon("pen")}らくがきを描く</button></section>${items.map((d) => `<button class="walk-card" data-doodle="${esc(d.id)}">${ctx.miniSvg(d.points)}<span class="grow stack"><strong>${esc(d.name)}</strong><small>${new Date(d.created).toLocaleDateString("ja-JP")}</small></span><span>›</span></button>`).join("")}`,
      {
        right: `<button class="circle" data-action="doodleStart" aria-label="らくがきを描く">${icon("pen")}</button>`,
      },
    );
  }
  function startDoodle() {
    if (state().editing || state().active) {
      toast("記録や軌跡の修正を終えてから、らくがきを描けます。");
      return;
    }
    switchTab("map");
    ctx.setAnswer(true);
    ctx.setFollow(false);
    draft = [];
    $("#doodleToolbar").hidden = false;
    $("#mapBanner").hidden = false;
    $("#mapBanner").textContent = "1 本指で描く · 完了すると保存します";
    $("#mapBanner").onclick = null;
    $("#mapPage").classList.add("drawing-doodle");
    draw();
  }
  function endDoodle() {
    draft = null;
    stroke = null;
    drawingPointer = null;
    $("#doodleToolbar").hidden = true;
    $("#mapBanner").hidden = true;
    $("#mapPage").classList.remove("drawing-doodle");
    draw();
  }
  function sharedMaps() {
    const maps = library().sharedMaps || [];
    page(
      "共有の白地図",
      `${maps.length ? maps.map((m) => `<button class="walk-card" data-shared-map="${esc(m.id)}">${ctx.miniSvg(m.walks.flatMap((w) => w.points.map((p, i) => ({ ...p, break: i === 0 || p.break }))))}<span class="grow stack"><strong>${esc(m.name)}</strong><small>${m.walks.length} 本の道</small></span><span>›</span></button>`).join("") : '<section class="collection-message"><h2>共有の白地図はまだありません</h2><p>紙を作って、送りたいさんぽの線だけをまとめられます。</p></section>'}<button class="reference-group collection-create" data-action="sharedCreate">${icon("plus")}紙を作る</button><p class="collection-note">この Web 版では白地図ファイルを渡して共有します。写真やメモ、日時は含めません。招待リンクでの共同編集や自動同期には対応していません。</p>`,
      { grouped: true },
    );
  }
  const actions = {
    bookmarks,
    stickers,
    doodles,
    sharedMaps,
    doodleStart: startDoodle,
    doodleCancel: endDoodle,
    doodleUndo: () => {
      if (draft) {
        const i = draft.findLastIndex((p) => p.break);
        draft.splice(i < 0 ? 0 : i);
        draw();
      }
    },
    doodleSave: async () => {
      if (!draft || draft.length < 2) {
        toast("地図をなぞって、線を描いてください。");
        return;
      }
      const item = {
        id: id(),
        name: "らくがき",
        created: Date.now(),
        points: structuredClone(draft),
      };
      (library().doodles ||= []).push(item);
      try {
        await save();
      } catch (e) {
        library().doodles.pop();
        throw e;
      }
      endDoodle();
      doodles();
      toast("らくがきを保存しました。");
    },
    bookmarkPick: () => {
      switchTab("map");
      ctx.setAnswer(true);
      ctx.pickMode("bookmark");
    },
    stickerExchange: () =>
      sheet(
        "ステッカーをあげる",
        '<p>ステッカーを選んで「画像を渡す」を押すと、AirDrop や対応する共有先へ渡せます。</p><p class="subtle">iPhone を近づける交換には対応していません。</p>',
      ),
    sharedCreate: () =>
      sheet(
        "紙を作る",
        `<label class="form-label">紙の名前</label><input id="sharedName" maxlength="60" placeholder="みんなのさんぽ"><p class="subtle">自分で選んださんぽの線だけを入れます。</p>${
          library().walks.length
            ? library()
                .walks.map(
                  (w) =>
                    `<label class="row"><input type="checkbox" data-shared-walk="${esc(w.id)}"><span>${esc(w.name)}</span></label>`,
                )
                .join("")
            : '<p class="subtle">まださんぽがありません。空の紙を作れます。</p>'
        }<button class="primary" data-action="sharedSave">紙を作る</button>`,
      ),
    sharedSave: async () => {
      const selected = [
        ...document.querySelectorAll("[data-shared-walk]:checked"),
      ].map((el) => el.dataset.sharedWalk);
      const item = {
        id: id(),
        name: $("#sharedName").value.trim() || "みんなのさんぽ",
        walks: library()
          .walks.filter((w) => selected.includes(w.id))
          .map((w) => ({
            id: w.id,
            points: w.points.map(({ lat, lon, break: gap }) => ({
              lat,
              lon,
              ...(gap ? { break: true } : {}),
            })),
          })),
      };
      (library().sharedMaps ||= []).push(item);
      try {
        await save();
      } catch (e) {
        library().sharedMaps.pop();
        throw e;
      }
      sharedMaps();
    },
  };
  async function click(d) {
    if (d.bookmarkSave) {
      const [lat, lon] = d.bookmarkSave.split(",").map(Number);
      if (!validPoint({ lat, lon })) return true;
      (library().bookmarks ||= []).push({
        id: id(),
        name: $("#bookmarkName").value.trim() || "気になる場所",
        lat,
        lon,
      });
      await save();
      bookmarks();
      toast("しおりを挟みました。");
      return true;
    }
    if (d.bookmark) {
      const p = library().bookmarks.find((p) => p.id === d.bookmark);
      if (!p) return true;
      sheet(
        p.name,
        `<p class="subtle">${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}</p><button class="primary" data-bookmark-go="${esc(p.id)}">ここへ向かう</button><button class="secondary" data-bookmark-view="${esc(p.id)}">地図で見る</button><button class="secondary danger-button" data-bookmark-remove="${esc(p.id)}">しおりを外す</button>`,
      );
      return true;
    }
    if (d.bookmarkGo || d.bookmarkView) {
      const p = library().bookmarks.find(
        (p) => p.id === (d.bookmarkGo || d.bookmarkView),
      );
      if (!p) return true;
      if (d.bookmarkGo) {
        library().flags.unshift({ ...p, id: id() });
        await save();
        ctx.setAnswer(false);
      }
      ctx.closeSheet();
      switchTab("map");
      fit([p]);
      ctx.setFollow(false);
      draw();
      return true;
    }
    if (d.bookmarkRemove) {
      library().bookmarks = library().bookmarks.filter(
        (p) => p.id !== d.bookmarkRemove,
      );
      await save();
      ctx.closeSheet();
      bookmarks();
      return true;
    }
    if (d.stickerItem) {
      const i = allStickers().find((i) => i.id === d.stickerItem);
      if (i)
        sheet(
          "ステッカー",
          `<img class="sticker-preview" src="${esc(i.src)}" alt="切り抜いたステッカー"><button class="primary" data-sticker-export="${esc(i.id)}">画像を渡す</button><button class="secondary" data-day-note="${esc(i.day)}">ノートで見る</button>`,
        );
      return true;
    }
    if (d.stickerExport) {
      const i = allStickers().find((i) => i.id === d.stickerExport);
      if (i)
        await shareFile(
          await (await fetch(i.src)).blob(),
          `plainwalk-sticker-${i.day}.png`,
        );
      return true;
    }
    if (d.doodle) {
      const item = library().doodles.find((p) => p.id === d.doodle);
      if (item)
        sheet(
          item.name,
          `${ctx.miniSvg(item.points, "walk-thumbnail")}<button class="primary" data-doodle-view="${esc(item.id)}">地図で見る</button><button class="secondary danger-button" data-doodle-remove="${esc(item.id)}">らくがきを削除</button>`,
        );
      return true;
    }
    if (d.doodleView) {
      const item = library().doodles.find((p) => p.id === d.doodleView);
      if (item) {
        ctx.closeSheet();
        switchTab("map");
        fit(item.points);
        draw();
      }
      return true;
    }
    if (d.doodleRemove) {
      library().doodles = library().doodles.filter(
        (p) => p.id !== d.doodleRemove,
      );
      await save();
      ctx.closeSheet();
      doodles();
      draw();
      return true;
    }
    if (d.sharedMap) {
      const m = library().sharedMaps.find((m) => m.id === d.sharedMap);
      if (m)
        sheet(
          m.name,
          `<p>${m.walks.length} 本の道を入れています。</p><button class="primary" data-shared-export="${esc(m.id)}">白地図ファイルを渡す</button><button class="secondary danger-button" data-shared-remove="${esc(m.id)}">この紙を削除</button>`,
        );
      return true;
    }
    if (d.sharedExport) {
      const m = library().sharedMaps.find((m) => m.id === d.sharedExport);
      if (m)
        await shareFile(
          new Blob(
            [JSON.stringify({ type: "plainwalk-white-map", version: 1, ...m })],
            { type: "application/json" },
          ),
          "plainwalk-white-map.json",
        );
      return true;
    }
    if (d.sharedRemove) {
      library().sharedMaps = library().sharedMaps.filter(
        (m) => m.id !== d.sharedRemove,
      );
      await save();
      ctx.closeSheet();
      sharedMaps();
      return true;
    }
    return false;
  }
  function render() {
    const all = (library().doodles || []).flatMap((d) =>
      d.points.flatMap((p, i) =>
        p.done
          ? []
          : [{ ...p, break: i === 0 || p.break || d.points[i - 1]?.done }],
      ),
    );
    if (draft) all.push(...draft);
    $("#doodles").innerHTML = all.length
      ? `<path d="${paths(all)}" fill="none" stroke="var(--map-ink)" stroke-opacity=".35" stroke-dasharray="3 6" stroke-width="2" stroke-linecap="round"/>`
      : "";
  }
  function attach(viewport) {
    viewport.addEventListener(
      "pointerdown",
      (e) => {
        if (!draft) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        if (drawingPointer !== null) return;
        drawingPointer = e.pointerId;
        viewport.setPointerCapture(e.pointerId);
        const r = viewport.getBoundingClientRect();
        stroke = { x: e.clientX - r.left, y: e.clientY - r.top };
        draft.push({ ...screenToPoint(stroke.x, stroke.y), break: true });
        draw();
      },
      true,
    );
    viewport.addEventListener(
      "pointermove",
      (e) => {
        if (!draft) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        if (e.pointerId !== drawingPointer) return;
        const r = viewport.getBoundingClientRect(),
          x = e.clientX - r.left,
          y = e.clientY - r.top;
        if (Math.hypot(x - stroke.x, y - stroke.y) < 3 || draft.length >= 10000)
          return;
        draft.push(screenToPoint(x, y));
        stroke = { x, y };
        draw();
      },
      true,
    );
    for (const event of ["pointerup", "pointercancel"])
      viewport.addEventListener(
        event,
        (e) => {
          if (!draft) return;
          e.preventDefault();
          e.stopImmediatePropagation();
          if (e.pointerId === drawingPointer) {
            drawingPointer = null;
            stroke = null;
          }
        },
        true,
      );
  }
  async function shareFile(blob, name) {
    const file = new File([blob], name, { type: blob.type });
    if (navigator.canShare?.({ files: [file] })) {
      try {
        await navigator.share({ files: [file], title: name });
      } catch (e) {
        if (e.name !== "AbortError") throw e;
      }
    } else download(blob, name);
  }
  async function importWhiteMap(value) {
    const incoming = validateCollections({ sharedMaps: [value] }).sharedMaps[0];
    const maps = (library().sharedMaps ||= []);
    const existing = maps.find((m) => m.id === incoming.id);
    if (existing) {
      existing.walks.push(
        ...incoming.walks.filter(
          (w) => !existing.walks.some((p) => p.id === w.id),
        ),
      );
    } else maps.push(incoming);
    await save();
    sharedMaps();
    toast("共有の白地図を取り込みました。");
  }
  let lastProgressSave = 0;
  function progress(point) {
    if (!state().active || point.accuracy > 40) return;
    let changed = false;
    for (const d of library().doodles || [])
      for (const p of d.points) {
        if (
          point.t >= d.created &&
          !p.done &&
          Math.abs(p.lat - point.lat) < 0.0002 &&
          Math.abs(p.lon - point.lon) < 0.0004 &&
          distance(p, point) < 15
        ) {
          p.done = true;
          changed = true;
        }
      }
    if (changed && Date.now() - lastProgressSave > 5000) {
      lastProgressSave = Date.now();
      save().catch(() => {});
    }
  }
  return {
    actions,
    click,
    render,
    attach,
    bookmarkAdd,
    importWhiteMap,
    progress,
  };
}
