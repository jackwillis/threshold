import { describe, expect, test } from "bun:test";
import type { FeatureCollection } from "geojson";
import { SEASONS, SEASON_TOKENS, contrast, cssVariables } from "./tokens";
import { atlasLayers, movementLayers } from "./style";
import { contextLabelPoints, labelPoint, streetLabelLines } from "./labels";

const structure = (layers: ReturnType<typeof atlasLayers>) =>
  layers.map((l) => ({ ...l, paint: undefined }));

describe("seasons", () => {
  test("define exactly the same tokens", () => {
    const keys = Object.keys(SEASON_TOKENS.summer).sort();
    for (const season of SEASONS) expect(Object.keys(SEASON_TOKENS[season]).sort()).toEqual(keys);
  });

  test("change paint only: ids, sources, filters and layout are identical", () => {
    const base = atlasLayers(SEASON_TOKENS.summer);
    const move = movementLayers(SEASON_TOKENS.summer);
    for (const season of SEASONS) {
      expect(structure(atlasLayers(SEASON_TOKENS[season]))).toEqual(structure(base));
      expect(structure(movementLayers(SEASON_TOKENS[season]))).toEqual(structure(move));
    }
    expect(JSON.stringify(atlasLayers(SEASON_TOKENS.winter))).not.toEqual(JSON.stringify(base));
  });

  test("every colour is a plain hex token", () => {
    for (const season of SEASONS) for (const value of Object.values(SEASON_TOKENS[season])) expect(value).toMatch(/^#[0-9a-f]{6}$/);
  });

  test("text and markers stay legible in every season", () => {
    for (const season of SEASONS) {
      const t = SEASON_TOKENS[season];
      const check = (name: string, a: string, b: string, minimum: number) =>
        expect(contrast(a, b), `${season}: ${name}`).toBeGreaterThanOrEqual(minimum);
      check("street labels on ground", t.ink, t.ground, 7);
      check("street labels on road fill", t.ink, t.roadFill, 7);
      check("water labels on water", t.inkWater, t.water, 4.5);
      check("park labels on park", t.inkPark, t.park, 4.5);
      check("building labels on ground", t.inkMuted, t.ground, 4.5);
      check("authored labels on ground", t.authored, t.ground, 3);
      check("numerals on destination markers", t.numeral, t.destination, 4.5);
      check("destination marker on ground", t.destination, t.ground, 3);
      check("destination marker on park", t.destination, t.park, 3);
      check("player on ground", t.player, t.ground, 3);
      check("player on park", t.player, t.park, 3);
    }
  });

  test("css variables cover every token", () => {
    const vars = cssVariables(SEASON_TOKENS.autumn);
    expect(vars["--atlas-ground"]).toBe(SEASON_TOKENS.autumn.ground);
    expect(vars["--atlas-road-fill"]).toBe(SEASON_TOKENS.autumn.roadFill);
    expect(vars["--atlas-serif"]).toContain("Atlas Serif");
  });
});

describe("street label lines", () => {
  const edge = (name: string, coords: number[][], highway = "residential"): FeatureCollection["features"][number] => ({
    type: "Feature", properties: { name, highway, classification: "street" }, geometry: { type: "LineString", coordinates: coords },
  });

  test("joins same-named edges end to end, whatever their direction", () => {
    const out = streetLabelLines({ type: "FeatureCollection", features: [
      edge("Main", [[0, 0], [1, 0]]), edge("Main", [[2, 0], [1, 0]]), edge("Main", [[2, 0], [3, 0]]),
    ] });
    expect(out.features).toHaveLength(1);
    const line = out.features[0]!.geometry.coordinates;
    expect(line.map((p) => p[0])).toEqual(line[0]![0] === 0 ? [0, 1, 2, 3] : [3, 2, 1, 0]);
  });

  test("stops at junctions and keeps different names apart", () => {
    const out = streetLabelLines({ type: "FeatureCollection", features: [
      edge("Main", [[0, 0], [1, 0]]), edge("Main", [[1, 0], [2, 0]]), edge("Main", [[1, 0], [1, 1]]), edge("Side", [[5, 5], [6, 5]]),
    ] });
    expect(out.features.filter((f) => f.properties!.name === "Main")).toHaveLength(3);
    expect(out.features.filter((f) => f.properties!.name === "Side")).toHaveLength(1);
  });

  test("ranks arterials and skips unnamed, path and service edges", () => {
    const out = streetLabelLines({ type: "FeatureCollection", features: [
      edge("Big", [[0, 0], [1, 0]], "primary"),
      { type: "Feature", properties: { classification: "street" }, geometry: { type: "LineString", coordinates: [[0, 1], [1, 1]] } },
      { type: "Feature", properties: { name: "Trail", classification: "path" }, geometry: { type: "LineString", coordinates: [[0, 2], [1, 2]] } },
      { type: "Feature", properties: { name: "Lot", classification: "street", service: "parking_aisle" }, geometry: { type: "LineString", coordinates: [[0, 3], [1, 3]] } },
    ] });
    expect(out.features).toHaveLength(1);
    expect(out.features[0]!.properties).toEqual({ name: "Big", rank: 1 });
  });
});

describe("context label points", () => {
  const square = (name: string, size: number, classification = "park", at = 0) => ({
    type: "Feature" as const, properties: { name, classification },
    geometry: { type: "Polygon" as const, coordinates: [[[at, 0], [at + size, 0], [at + size, size], [at, size], [at, 0]]] },
  });
  const names = (c: FeatureCollection) => c.features.map((f) => `${f.properties!.classification}:${f.properties!.name}`).sort();

  test("one point per named park or lake (its largest piece), every named building", () => {
    const out = contextLabelPoints({ type: "FeatureCollection", features: [
      square("Square", 1), square("Square", 3, "park", 10), square("Lake", 1, "water"), square("Hall", 1, "building"), square("Hall", 1, "building", 5),
    ] });
    expect(names(out)).toEqual(["building:Hall", "building:Hall", "park:Square", "water:Lake"]);
    const park = out.features.find((f) => f.properties!.name === "Square")!.geometry as { coordinates: number[] };
    expect(park.coordinates[0]).toBeGreaterThan(10); // the large piece
  });

  test("ignores unnamed and other classes, and leaves the input alone", () => {
    const input = { type: "FeatureCollection" as const, features: [{ ...square("x", 1), properties: { classification: "park" } }, square("Plaza", 1, "pedestrian_area")] };
    expect(contextLabelPoints(input).features).toHaveLength(0);
    expect(input.features[1]!.properties).toEqual({ name: "Plaza", classification: "pedestrian_area" });
  });

  test("a label point lies inside a concave polygon", () => {
    // An L shape: its bounding-box centre is outside the polygon.
    const ring = [[0, 0], [10, 0], [10, 2], [2, 2], [2, 10], [0, 10], [0, 0]];
    const [x, y] = labelPoint(ring);
    const inL = (x >= 0 && x <= 10 && y >= 0 && y <= 2) || (x >= 0 && x <= 2 && y >= 0 && y <= 10);
    expect(inL).toBe(true);
  });
});
