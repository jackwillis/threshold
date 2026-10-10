// Camera rules for the player-facing Field Atlas: a constrained, player-centred view rather than
// a free map. Pure geometry only (no MapLibre), so the rules can be tested and reused. The camera
// is a presentation rule; the server alone decides which moves are legal.

export type LngLat = [number, number];
/** [west, south, east, north] in degrees. */
export type Bounds = [number, number, number, number];

export type CameraLimits = {
  minZoom: number;
  maxZoom: number;
  /** How far, in metres, the camera centre may be from the player. 0 locks it to the player. */
  maxDisplacementM: number;
};

export const DEFAULT_LIMITS: CameraLimits = { minZoom: 17, maxZoom: 19.5, maxDisplacementM: 200 };

const M_PER_DEG = 111_320;

/** Server-provided overrides, ignoring anything that is not a usable number. */
export function resolveLimits(overrides: Partial<CameraLimits> | null | undefined): CameraLimits {
  const pick = (value: unknown, fallback: number, min: number) =>
    typeof value === "number" && Number.isFinite(value) && value >= min ? value : fallback;
  const minZoom = pick(overrides?.minZoom, DEFAULT_LIMITS.minZoom, 0);
  const maxZoom = Math.max(minZoom, pick(overrides?.maxZoom, DEFAULT_LIMITS.maxZoom, 0));
  return { minZoom, maxZoom, maxDisplacementM: pick(overrides?.maxDisplacementM, DEFAULT_LIMITS.maxDisplacementM, 0) };
}

export const clampZoom = (zoom: number, limits: CameraLimits): number => Math.min(limits.maxZoom, Math.max(limits.minZoom, zoom));

/** Geographic distance in metres between two points (local planar approximation, exact enough at street scale). */
export function distanceM(a: LngLat, b: LngLat): number {
  const scale = Math.cos(((a[1] + b[1]) / 2) * Math.PI / 180);
  return Math.hypot((b[0] - a[0]) * scale * M_PER_DEG, (b[1] - a[1]) * M_PER_DEG);
}

/**
 * The allowed camera centres are the disc of `maxDisplacementM` around the player intersected
 * with the world's bounding box (grown, if need be, to contain the player, so the region is never
 * empty). Returns the allowed centre nearest to `center`; a centre already allowed is returned
 * unchanged, which also makes the function idempotent, so the camera cannot oscillate.
 */
export function allowedCenter(center: LngLat, player: LngLat, limits: CameraLimits, bounds?: Bounds | null): LngLat {
  const mx = M_PER_DEG * Math.cos(player[1] * Math.PI / 180);
  const my = M_PER_DEG;
  const radius = limits.maxDisplacementM;
  const box = bounds
    ? {
        west: (Math.min(bounds[0], player[0]) - player[0]) * mx, east: (Math.max(bounds[2], player[0]) - player[0]) * mx,
        south: (Math.min(bounds[1], player[1]) - player[1]) * my, north: (Math.max(bounds[3], player[1]) - player[1]) * my,
      }
    : null;
  let x = (center[0] - player[0]) * mx;
  let y = (center[1] - player[1]) * my;
  const inside = () => Math.hypot(x, y) <= radius + 1e-6 && (!box || (x >= box.west - 1e-6 && x <= box.east + 1e-6 && y >= box.south - 1e-6 && y <= box.north + 1e-6));
  // Alternating projections onto two convex sets that share the player's position converge to a point in both.
  for (let i = 0; i < 12 && !inside(); i++) {
    const length = Math.hypot(x, y);
    if (length > radius) { x = (x / length) * radius; y = (y / length) * radius; }
    if (box) { x = Math.min(box.east, Math.max(box.west, x)); y = Math.min(box.north, Math.max(box.south, y)); }
  }
  if (inside()) return center[0] === player[0] + x / mx && center[1] === player[1] + y / my ? center : [player[0] + x / mx, player[1] + y / my];
  return player; // The player's own position is always a valid centre.
}

/** True when the centre is outside the allowed region by more than a metre. */
export function violatesLimits(center: LngLat, player: LngLat, limits: CameraLimits, bounds?: Bounds | null): boolean {
  return distanceM(center, allowedCenter(center, player, limits, bounds)) > 1;
}

/** The bounding box of a polygon ring list (GeoJSON `coordinates`), or null. */
export function boundsOf(polygon: number[][][] | undefined): Bounds | null {
  const points = polygon?.flat() ?? [];
  if (points.length === 0) return null;
  const lons = points.map(p => p[0]!);
  const lats = points.map(p => p[1]!);
  return [Math.min(...lons), Math.min(...lats), Math.max(...lons), Math.max(...lats)];
}

/**
 * The area the player map must have geography for: the playable boundary grown by the tether plus
 * half the largest screen dimension at the minimum zoom (the widest view the camera can show).
 * Sizing from the screen rather than the window keeps edges from going missing when the window is
 * enlarged after loading. Metres per CSS pixel use MapLibre's 512 px tiles.
 */
export function reachBounds(bounds: Bounds, limits: CameraLimits, screenPx: number): Bounds {
  const lat = (bounds[1] + bounds[3]) / 2;
  const metresPerPixel = (78271.517 * Math.cos((lat * Math.PI) / 180)) / 2 ** limits.minZoom;
  const margin = limits.maxDisplacementM + (screenPx / 2) * metresPerPixel;
  const dLat = margin / M_PER_DEG;
  const dLon = margin / (M_PER_DEG * Math.cos((lat * Math.PI) / 180));
  return [bounds[0] - dLon, bounds[1] - dLat, bounds[2] + dLon, bounds[3] + dLat];
}
