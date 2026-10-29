const imageCache = new Map();
export function loadImage(src) {
  if (!imageCache.has(src))
    imageCache.set(
      src,
      new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => {
          imageCache.delete(src);
          reject(Error("ノートの画像を読み取れません。"));
        };
        image.src = src;
      }),
    );
  return imageCache.get(src);
}
export function wrapText(ctx, text, width, maxLines = 18) {
  const lines = [];
  let line = "";
  for (const ch of String(text)) {
    if (ch === "\n" || ctx.measureText(line + ch).width > width) {
      lines.push(line);
      line = "";
      if (ch === "\n") continue;
      if (lines.length >= maxLines) return lines;
    }
    line += ch;
  }
  if (line) lines.push(line);
  return lines.slice(0, maxLines);
}
export async function drawNotebook(canvas, note, { selection = null } = {}) {
  const ctx = canvas.getContext("2d");
  const w = 720,
    h = 960;
  canvas.width = w;
  canvas.height = h;
  ctx.fillStyle =
    { plain: "#fbfaf7", grid: "#fafbf9", lined: "#fffefb", kraft: "#e7d6b7" }[
      note.paper
    ] || "#fbfaf7";
  ctx.fillRect(0, 0, w, h);
  if (note.paper === "grid" || note.paper === "lined") {
    ctx.strokeStyle = "#cbd0c44d";
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let y = 90; y < h; y += 32) {
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
    }
    if (note.paper === "grid")
      for (let x = 8; x < w; x += 32) {
        ctx.moveTo(x, 0);
        ctx.lineTo(x, h);
      }
    ctx.stroke();
  }
  ctx.fillStyle = "#72796c";
  ctx.font = "16px -apple-system,sans-serif";
  ctx.fillText("PLAINWALK   " + (note.day || ""), 40, 50);
  ctx.fillStyle = "#293126";
  ctx.font = `${note.font === "serif" ? "25px Georgia,serif" : note.font === "mono" ? "23px monospace" : "24px -apple-system,sans-serif"}`;
  const lines = wrapText(ctx, note.text || "", 640, 24);
  lines.forEach((line, i) => ctx.fillText(line, 40, 110 + i * 36));
  if (note.stickers) {
    ctx.font = "40px -apple-system,sans-serif";
    ctx.fillText(note.stickers, 40, Math.min(910, 150 + lines.length * 36));
  }
  const items = note.layout || [];
  await Promise.all(
    items.filter((i) => i.src).map((i) => loadImage(i.src).catch(() => null)),
  );
  for (const item of items) {
    ctx.save();
    const x = Number(item.x) || 0,
      y = Number(item.y) || 0,
      width = Math.max(30, Math.min(600, Number(item.width) || 150)),
      height = width / (item.ratio || 1);
    ctx.translate(x, y);
    ctx.rotate(((Number(item.rotation) || 0) * Math.PI) / 180);
    if (item.type === "emoji") {
      ctx.font = width + "px -apple-system,sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(item.text || "✦", 0, 0);
    } else if (item.src) {
      const image = await loadImage(item.src).catch(() => null);
      if (image) {
        if (item.type === "photo") {
          ctx.shadowColor = "#00000018";
          ctx.shadowBlur = 8;
          ctx.shadowOffsetY = 5;
          ctx.fillStyle = "white";
          ctx.fillRect(
            -width / 2 - 8,
            -height / 2 - 8,
            width + 16,
            height + 30,
          );
          ctx.shadowBlur = 0;
          ctx.shadowOffsetY = 0;
        }
        if (item.finish === "foil" || item.finish === "holo") {
          ctx.shadowColor = item.finish === "foil" ? "#b89545" : "#94bde5";
          ctx.shadowBlur = 0;
          for (const [dx, dy] of [
            [-3, 0],
            [3, 0],
            [0, -3],
            [0, 3],
          ]) {
            ctx.shadowOffsetX = dx;
            ctx.shadowOffsetY = dy;
            ctx.drawImage(image, -width / 2, -height / 2, width, height);
          }
          ctx.shadowOffsetX = 0;
          ctx.shadowOffsetY = 0;
        }
        ctx.drawImage(image, -width / 2, -height / 2, width, height);
        if (item.finish === "foil" || item.finish === "holo") {
          const mask = document.createElement("canvas");
          mask.width = Math.ceil(width);
          mask.height = Math.ceil(height);
          const mc = mask.getContext("2d");
          mc.drawImage(image, 0, 0, width, height);
          mc.globalCompositeOperation = "source-atop";
          const gradient = mc.createLinearGradient(0, 0, width, height);
          const colors =
            item.finish === "foil"
              ? ["#e7c96b50", "#fff6c330", "#ad812d60"]
              : ["#80d5f250", "#d99de550", "#f9dfa950", "#8edcd050"];
          colors.forEach((c, i) =>
            gradient.addColorStop(i / (colors.length - 1), c),
          );
          mc.fillStyle = gradient;
          mc.fillRect(0, 0, width, height);
          ctx.drawImage(mask, -width / 2, -height / 2, width, height);
        }
      }
    }
    if (selection === item.id) {
      ctx.strokeStyle = "#7190aa";
      ctx.lineWidth = 2;
      ctx.setLineDash([5, 4]);
      ctx.strokeRect(-width / 2 - 8, -height / 2 - 8, width + 16, height + 16);
    }
    ctx.restore();
  }
}
export function hitItem(items, x, y) {
  for (let i = items.length - 1; i >= 0; i--) {
    const item = items[i],
      angle = (-(Number(item.rotation) || 0) * Math.PI) / 180,
      dx = x - item.x,
      dy = y - item.y,
      rx = dx * Math.cos(angle) - dy * Math.sin(angle),
      ry = dx * Math.sin(angle) + dy * Math.cos(angle),
      w = item.width || 150,
      h = w / (item.ratio || 1);
    if (Math.abs(rx) <= w / 2 + 10 && Math.abs(ry) <= h / 2 + 10) return item;
  }
  return null;
}
export async function lassoCutout(src, points) {
  if (points.length < 3) throw Error("被写体を 3 点以上で囲んでください。");
  const image = await loadImage(src),
    canvas = document.createElement("canvas");
  canvas.width = image.width;
  canvas.height = image.height;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(image, 0, 0);
  ctx.globalCompositeOperation = "destination-in";
  ctx.beginPath();
  points.forEach(([x, y], i) => {
    i
      ? ctx.lineTo(x * image.width, y * image.height)
      : ctx.moveTo(x * image.width, y * image.height);
  });
  ctx.closePath();
  ctx.fill();
  return {
    src: canvas.toDataURL("image/png"),
    ratio: image.width / image.height,
  };
}
