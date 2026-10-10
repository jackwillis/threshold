import { describe, expect, test } from "bun:test";
import { allowedCenter, boundsOf, reachBounds, clampZoom, DEFAULT_LIMITS, distanceM, resolveLimits, violatesLimits, type Bounds, type LngLat } from "./camera";

const player: LngLat = [-89.384, 43.074];
const M_LON = 111_320 * Math.cos((43.074 * Math.PI) / 180);
const offset = (east: number, north: number): LngLat => [player[0] + east / M_LON, player[1] + north / 111_320];

describe("limits", () => {
  test("defaults match the design: zoom 17 to 19.5 and a 200 m tether", () => {
    expect(DEFAULT_LIMITS).toEqual({ minZoom: 17, maxZoom: 19.5, maxDisplacementM: 200 });
    expect(clampZoom(15, DEFAULT_LIMITS)).toBe(17);
    expect(clampZoom(21, DEFAULT_LIMITS)).toBe(19.5);
    expect(clampZoom(18.5, DEFAULT_LIMITS)).toBe(18.5);
  });
  test("overrides apply and unusable values fall back", () => {
    expect(resolveLimits({ maxDisplacementM: 0 }).maxDisplacementM).toBe(0);
    expect(resolveLimits({ minZoom: 16, maxZoom: 18, maxDisplacementM: 50 })).toEqual({ minZoom: 16, maxZoom: 18, maxDisplacementM: 50 });
    expect(resolveLimits({ maxDisplacementM: -5, minZoom: Number.NaN } as never)).toEqual(DEFAULT_LIMITS);
    expect(resolveLimits({ minZoom: 19, maxZoom: 18 }).maxZoom).toBe(19);
    expect(resolveLimits(null)).toEqual(DEFAULT_LIMITS);
  });
});

describe("tether", () => {
  test("distance is geographic: 100 m east and 100 m north measure alike", () => {
    expect(distanceM(player, offset(100, 0))).toBeCloseTo(100, 0);
    expect(distanceM(player, offset(0, 100))).toBeCloseTo(100, 0);
  });
  test("a centre inside the radius is untouched", () => {
    const inside = offset(120, -80);
    expect(allowedCenter(inside, player, DEFAULT_LIMITS)).toBe(inside);
    expect(violatesLimits(inside, player, DEFAULT_LIMITS)).toBe(false);
  });
  test("a centre beyond the radius is pulled back to it along the same bearing", () => {
    const far = offset(600, 800);
    const clamped = allowedCenter(far, player, DEFAULT_LIMITS);
    expect(distanceM(player, clamped)).toBeCloseTo(200, 0);
    expect(clamped[0] - player[0]).toBeGreaterThan(0);
    expect(violatesLimits(far, player, DEFAULT_LIMITS)).toBe(true);
    expect(violatesLimits(clamped, player, DEFAULT_LIMITS)).toBe(false);
  });
  test("a zero tether locks the centre to the player", () => {
    const locked = { ...DEFAULT_LIMITS, maxDisplacementM: 0 };
    const clamped = allowedCenter(offset(50, 50), player, locked);
    expect(distanceM(player, clamped)).toBeLessThan(0.01);
  });
  test("the clamp is idempotent, so the camera cannot oscillate", () => {
    for (const [e, n] of [[900, 0], [-300, 700], [0, -1000], [150, 150]] as const) {
      const once = allowedCenter(offset(e, n), player, DEFAULT_LIMITS);
      expect(allowedCenter(once, player, DEFAULT_LIMITS)).toEqual(once);
    }
  });
});

describe("world bounds", () => {
  // A box extending 120 m east and 500 m in every other direction from the player.
  const box = (east: number, west: number, north: number, south: number): Bounds => {
    const ne = offset(east, north); const sw = offset(-west, -south);
    return [sw[0], sw[1], ne[0], ne[1]];
  };
  test("the allowed region is the tether intersected with the bounds", () => {
    const bounds = box(120, 500, 500, 500);
    const clamped = allowedCenter(offset(190, 0), player, DEFAULT_LIMITS, bounds);
    expect(distanceM(player, clamped)).toBeLessThanOrEqual(200.5);
    expect((clamped[0] - player[0]) * M_LON).toBeLessThanOrEqual(120.5);
    expect(violatesLimits(clamped, player, DEFAULT_LIMITS, bounds)).toBe(false);
  });
  test("a player on or beyond the bounds can still be centred", () => {
    const tight = box(0, 500, 500, 500);
    expect(allowedCenter(player, player, DEFAULT_LIMITS, tight)).toEqual(player);
    const outside = box(-10, 500, 500, 500); // the bounds stop 10 m short of the player
    expect(distanceM(allowedCenter(player, player, DEFAULT_LIMITS, outside), player)).toBeLessThan(0.5);
  });
  test("a very small intersection still yields a valid centre near the player", () => {
    const sliver = box(2, 2, 2, 2);
    const clamped = allowedCenter(offset(100, 100), player, DEFAULT_LIMITS, sliver);
    expect(distanceM(player, clamped)).toBeLessThan(4);
  });
  test("boundsOf reads a polygon's extent", () => {
    expect(boundsOf([[[-89.4, 43.0], [-89.3, 43.0], [-89.3, 43.1], [-89.4, 43.0]]])).toEqual([-89.4, 43.0, -89.3, 43.1]);
    expect(boundsOf(undefined)).toBeNull();
  });
});

describe("reachBounds", () => {
  const boundary: Bounds = [-89.3918, 43.0699, -89.3694, 43.0801];
  const grown = (screen: number) => reachBounds(boundary, DEFAULT_LIMITS, screen);
  const metresWest = (b: Bounds) => (boundary[0] - b[0]) * M_LON;
  const metresSouth = (b: Bounds) => (boundary[1] - b[1]) * 111_320;

  test("grows the boundary by the tether plus half a screen at the minimum zoom, equally on every side", () => {
    // 0.436 m per pixel at zoom 17 and 43 degrees north: a 1366 px screen reaches about 298 m past the tether.
    const b = grown(1366);
    expect(metresWest(b)).toBeCloseTo(498, -1);
    expect(metresSouth(b)).toBeCloseTo(498, -1);
    expect((b[2] - boundary[2]) * M_LON).toBeCloseTo(metresWest(b), 3);
    expect((b[3] - boundary[3]) * 111_320).toBeCloseTo(metresSouth(b), 3);
  });
  test("a larger screen reaches further, so enlarging the window never exposes missing geography", () => {
    expect(metresWest(grown(3840))).toBeGreaterThan(metresWest(grown(1366)) + 500);
    expect(metresWest(grown(3840))).toBeCloseTo(1037, -1);
  });
  test("always covers at least the tether, and a smaller minimum zoom reaches further", () => {
    expect(metresWest(grown(0))).toBeCloseTo(200, 0);
    expect(metresWest(reachBounds(boundary, { ...DEFAULT_LIMITS, minZoom: 16 }, 1366))).toBeGreaterThan(metresWest(grown(1366)));
  });
});
