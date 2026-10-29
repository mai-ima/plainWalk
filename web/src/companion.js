export function companionSVG(kind = "black", moving = false, heading = 0) {
  const palette = {
    black: ["#272a2c", "#53575a", "#17191b"],
    tabby: ["#bb8a55", "#dbb380", "#8d6038"],
    calico: ["#ece4d5", "#b9844a", "#36383a"],
    silver: ["#909ea7", "#c8d1d4", "#5f707b"],
  }[kind] || ["#272a2c", "#53575a", "#17191b"];
  const [a, b, c] = palette,
    tag = "cat-" + kind;
  const stripes =
    kind === "tabby" || kind === "silver"
      ? `<path d="M10 21h12M9 25h14M10 29h12M12 11l2 3m5-3-2 3" fill="none" stroke="${c}" stroke-width="2" opacity=".65"/>`
      : kind === "calico"
        ? `<path d="M9 20q4-4 7 2l-1 7-6-3z" fill="${b}"/><path d="M18 16q7 3 4 10l-4-1z" fill="${c}"/>`
        : "";
  return `<svg viewBox="0 0 34 48" class="companion ${moving ? "walking" : "sitting"}" style="transform:rotate(${Number(heading) || 0}deg)" aria-hidden="true"><defs><linearGradient id="${tag}" x1="0" y1="0" x2="1" y2="0"><stop stop-color="${a}"/><stop offset=".45" stop-color="${b}"/><stop offset="1" stop-color="${a}"/></linearGradient></defs><ellipse cx="17" cy="39" rx="10" ry="3" fill="#000" opacity=".09"/><path class="cat-tail" d="M18 34q10 1 9 8t-8 1" fill="none" stroke="${a}" stroke-width="4"/><path class="cat-leg left" d="M10 29v9q2 3 5 0V28" fill="${a}"/><path class="cat-leg right" d="M19 29v9q2 3 5 0V28" fill="${c}"/><path d="M9 18q-2 8 1 14 7 6 13-1 3-9-1-14z" fill="url(#${tag})"/><path d="M9 9 8 3l7 4 6-1 5-4-1 9q3 9-7 11Q7 21 8 12z" fill="url(#${tag})"/><path d="m10 6 1 5 3-2m9-3-1 5-3-2" stroke="${c}" stroke-width="1" fill="${c}"/>${stripes}<path d="M11 18q6 4 12-1" stroke="${c}" stroke-opacity=".4" stroke-width="1" fill="none"/></svg>`;
}
