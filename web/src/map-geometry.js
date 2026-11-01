import { R, project, unproject, validPoint } from "./core.js";

export const WORLD_WIDTH = 2 * Math.PI * R;

// Choose a periodic copy without a loop over the number of wrapped worlds.
// Reduce before subtraction so finite, very distant world coordinates cannot
// overflow merely while calculating their difference.
export function nearestWorldX(x, referenceX) {
  if (!Number.isFinite(x) || !Number.isFinite(referenceX)) return x;
  let delta = (x % WORLD_WIDTH) - (referenceX % WORLD_WIDTH);
  delta -= WORLD_WIDTH * Math.round(delta / WORLD_WIDTH);
  return referenceX + delta;
}

// Preserve input indices: a null ends a local streak just like a break marker.
// Separate streaks remain near the first valid point's selected world, while
// continuous streaks follow their previous unwrapped point across the seam.
// These coordinates are for drawing; stored geographic points are not changed.
export function projectTrail(points, referenceX = undefined) {
  let anchorX;
  let previousX = null;
  return Array.from(points, (point) => {
    if (!validPoint(point)) {
      previousX = null;
      return null;
    }
    const [rawX, y] = project(point);
    if (anchorX === undefined) {
      anchorX = Number.isFinite(referenceX)
        ? nearestWorldX(rawX, referenceX)
        : rawX;
    }
    const x = nearestWorldX(
      rawX,
      previousX === null || point.break ? anchorX : previousX,
    );
    previousX = x;
    return [x, y];
  });
}

// Screen input can refer to any periodic world. Only normalize longitude;
// preserve the inverse projection's latitude so callers can reject it rather
// than silently moving an out-of-range input to an invented latitude.
export function unprojectWrapped(x, y) {
  const point = unproject(x, y);
  let lon = point.lon % 360;
  if (lon < -180) lon += 360;
  else if (lon >= 180) lon -= 360;
  return { ...point, lon };
}
