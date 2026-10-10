import type { ExpressionSpecification, LayerSpecification, Map as MapLibreMap } from "maplibre-gl";
import { TYPE, type AtlasTokens } from "./tokens";

// The Classic Atlas layer stack. `atlasLayers(tokens)` returns the same layers (ids, sources, filters,
// layout) for every season; only paint values come from the tokens. `applySeason` therefore switches
// season by re-painting, never by rebuilding the map.
//
// Sources the stack expects: `context` and `edges` (the world's geography), `street-labels` (named
// streets merged into long lines) and `context-labels` (one point per named park, lake or building),
// both built by labels.ts, and the movement sources below.

const classIs = (name: string): ExpressionSpecification => ["==", ["get", "classification"], name];
// Park, lake and building names come from one label point each (see `contextLabelPoints`).
const named = (name: string): ExpressionSpecification => classIs(name);
const zoomRamp = (...stops: [number, number][]): ExpressionSpecification =>
  ["interpolate", ["linear"], ["zoom"], ...stops.flat()] as ExpressionSpecification;

// Road width by class and zoom: restrained, a fine casing around a pale fill.
const MAJOR = ["primary", "secondary", "primary_link", "secondary_link"];
const MID = ["tertiary", "tertiary_link"];
function roadWidth(major: [number, number], mid: [number, number], minor: [number, number]): ExpressionSpecification {
  const byClass = (i: 0 | 1): ExpressionSpecification =>
    ["match", ["get", "highway"], MAJOR, major[i], MID, mid[i], minor[i]] as unknown as ExpressionSpecification;
  return ["interpolate", ["linear"], ["zoom"], 15, byClass(0), 19.5, byClass(1)] as ExpressionSpecification;
}

const serif = (font: string) => [font];
const labelBase = {
  "text-field": ["get", "name"] as ExpressionSpecification,
  "text-padding": 4,
};

export function atlasLayers(t: AtlasTokens): LayerSpecification[] {
  const halo = { "text-halo-color": t.halo, "text-halo-width": 1.6, "text-halo-blur": 0.4 };
  return [
    { id: "atlas-ground", type: "background", paint: { "background-color": t.ground } },
    { id: "ctx-water", type: "fill", source: "context", filter: classIs("water"), paint: { "fill-color": t.water } },
    { id: "ctx-water-edge", type: "line", source: "context", filter: classIs("water"), paint: { "line-color": t.waterEdge, "line-width": 1 } },
    { id: "ctx-park", type: "fill", source: "context", filter: classIs("park"), paint: { "fill-color": t.park } },
    { id: "ctx-park-edge", type: "line", source: "context", filter: classIs("park"), paint: { "line-color": t.parkEdge, "line-width": 0.8, "line-dasharray": [3, 2] } },
    { id: "ctx-plaza", type: "fill", source: "context", filter: classIs("pedestrian_area"), paint: { "fill-color": t.plaza } },
    { id: "ctx-building", type: "fill", source: "context", filter: classIs("building"), paint: { "fill-color": t.building } },
    {
      id: "ctx-building-edge", type: "line", source: "context", filter: classIs("building"), minzoom: 15,
      paint: { "line-color": t.buildingEdge, "line-width": zoomRamp([15, 0.3], [19, 0.9]) },
    },
    {
      id: "edges-path", type: "line", source: "edges", filter: classIs("path"), minzoom: 15.5,
      layout: { "line-cap": "butt", "line-join": "round" },
      paint: { "line-color": t.path, "line-width": zoomRamp([15.5, 0.5], [19.5, 1.4]), "line-dasharray": [2.5, 1.5] },
    },
    {
      id: "edges-alley", type: "line", source: "edges", filter: classIs("alley"), minzoom: 15.5,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": t.roadCasing, "line-width": zoomRamp([15.5, 0.8], [19.5, 3]) },
    },
    {
      id: "edges-casing", type: "line", source: "edges", filter: classIs("street"),
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": t.roadCasing, "line-width": roadWidth([4, 20], [3.4, 15], [2.6, 11]) },
    },
    {
      id: "edges-fill", type: "line", source: "edges", filter: classIs("street"),
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": t.roadFill, "line-width": roadWidth([2.8, 17], [2.2, 12.5], [1.6, 9]) },
    },
    // --- Labels ---
    {
      id: "label-water", type: "symbol", source: "context-labels", filter: named("water"),
      layout: { ...labelBase, "text-font": serif(TYPE.serifItalic), "text-size": zoomRamp([13, 13], [19, 22]), "text-letter-spacing": 0.2, "text-max-width": 8 },
      paint: { "text-color": t.inkWater, ...halo },
    },
    {
      id: "label-park", type: "symbol", source: "context-labels", filter: named("park"), minzoom: 14.5,
      layout: { ...labelBase, "text-font": serif(TYPE.serifItalic), "text-size": zoomRamp([14.5, 11], [19, 17]), "text-letter-spacing": 0.08, "text-max-width": 7 },
      paint: { "text-color": t.inkPark, ...halo },
    },
    {
      id: "label-building", type: "symbol", source: "context-labels", filter: named("building"), minzoom: 17.3,
      layout: { ...labelBase, "text-font": serif(TYPE.serifItalic), "text-size": zoomRamp([17.3, 10.5], [19.5, 13]), "text-max-width": 6 },
      paint: { "text-color": t.inkMuted, ...halo },
    },
    {
      id: "label-street-major", type: "symbol", source: "street-labels", filter: ["==", ["get", "rank"], 1],
      layout: {
        ...labelBase, "text-font": serif(TYPE.serifMedium), "symbol-placement": "line", "symbol-spacing": 420,
        "text-size": zoomRamp([15, 10], [19.5, 17]), "text-letter-spacing": 0.2, "text-transform": "uppercase", "text-max-angle": 30,
      },
      paint: { "text-color": t.ink, ...halo },
    },
    {
      id: "label-street", type: "symbol", source: "street-labels", filter: ["==", ["get", "rank"], 2], minzoom: 15.8,
      layout: {
        ...labelBase, "text-font": serif(TYPE.serif), "symbol-placement": "line", "symbol-spacing": 320,
        "text-size": zoomRamp([15.8, 10.5], [19.5, 16.5]), "text-letter-spacing": 0.05, "text-max-angle": 30,
      },
      paint: { "text-color": t.ink, ...halo },
    },
  ] as LayerSpecification[];
}

/** Movement and place markers: the one restrained accent. Sources: authored-places, visited, route, moves, player. */
export const MOVEMENT_SOURCES = ["authored-places", "visited", "route", "moves", "player"] as const;

export function movementLayers(t: AtlasTokens): LayerSpecification[] {
  return [
    { id: "walk-route", type: "line", source: "route", layout: { "line-cap": "round" }, paint: { "line-color": t.route, "line-width": 3, "line-opacity": 0.45 } },
    {
      id: "authored-place", type: "circle", source: "authored-places",
      paint: { "circle-color": t.authored, "circle-radius": zoomRamp([15, 3.5], [19, 6]), "circle-stroke-color": t.halo, "circle-stroke-width": 1.5 },
    },
    {
      id: "label-authored", type: "symbol", source: "authored-places", minzoom: 16.5,
      layout: { ...labelBase, "text-font": serif(TYPE.serifSemibold), "text-size": zoomRamp([16.5, 11], [19.5, 15]), "text-anchor": "top", "text-offset": [0, 0.9], "text-max-width": 8 },
      paint: { "text-color": t.authored, "text-halo-color": t.halo, "text-halo-width": 1.8 },
    },
    { id: "visited-ring", type: "circle", source: "visited", paint: { "circle-color": t.visited, "circle-radius": 3, "circle-opacity": 0.7 } },
    { id: "move-glow", type: "circle", source: "moves", paint: { "circle-color": t.route, "circle-radius": 22, "circle-opacity": 0.22, "circle-blur": 0.7 } },
    { id: "move-marker", type: "circle", source: "moves", paint: { "circle-color": t.destination, "circle-radius": 11.5, "circle-stroke-color": t.numeral, "circle-stroke-width": 2 } },
    {
      id: "move-key", type: "symbol", source: "moves",
      layout: { "text-field": ["get", "key"], "text-font": serif(TYPE.serifSemibold), "text-size": 15, "text-allow-overlap": true, "text-ignore-placement": true },
      paint: { "text-color": t.numeral },
    },
    { id: "player-halo", type: "circle", source: "player", paint: { "circle-color": t.player, "circle-radius": 18, "circle-opacity": 0.12 } },
    { id: "player-marker", type: "circle", source: "player", paint: { "circle-color": t.player, "circle-radius": 8, "circle-stroke-color": t.numeral, "circle-stroke-width": 3 } },
  ] as LayerSpecification[];
}

/** Switches season in place: same layers, new paint values. */
export function applySeason(map: MapLibreMap, tokens: AtlasTokens): void {
  for (const layer of [...atlasLayers(tokens), ...movementLayers(tokens)]) {
    if (!map.getLayer(layer.id)) continue;
    const paint = (layer as { paint?: Record<string, unknown> }).paint ?? {};
    for (const [key, value] of Object.entries(paint)) map.setPaintProperty(layer.id, key, value);
  }
}
