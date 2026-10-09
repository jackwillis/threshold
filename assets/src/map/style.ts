import type { ExpressionSpecification, LayerSpecification } from "maplibre-gl";

export type Palette = Record<string, Record<string, string>>;
export type ColorBy = "access_status" | "access_basis" | "classification" | "component";

// Plain background only: no basemap by design (offline; the world's extent stays obvious).
export const BACKGROUND = "#f4f1ea";
const COMPONENT_COLORS = ["#d64545", "#2f7fc1", "#2e9e5b", "#8e5bd6", "#e0a020", "#16a3a3"];
const MAIN_COMPONENT_COLOR = "#7a8896";

/** Data-driven line color for the street layer. */
export function edgeColor(colorBy: ColorBy, palette: Palette): ExpressionSpecification {
  if (colorBy === "component") {
    const cases = COMPONENT_COLORS.flatMap((color, i): (number | string)[] => [i, color]);
    return [
      "case",
      ["==", ["get", "component"], 0],
      MAIN_COMPONENT_COLOR,
      ["match", ["%", ["to-number", ["get", "component"]], COMPONENT_COLORS.length], ...cases, MAIN_COMPONENT_COLOR],
    ] as unknown as ExpressionSpecification; // dynamic arity cannot be typed statically
  }
  const entries = Object.entries(palette[colorBy] ?? {}).flatMap(([value, color]) => [value, color]);
  return ["match", ["get", colorBy], ...entries, "#8b95a1"] as unknown as ExpressionSpecification; // dynamic arity cannot be typed statically
}

const classIs = (name: string): ExpressionSpecification => ["==", ["get", "classification"], name];
const geom = (type: string): ExpressionSpecification => ["==", ["geometry-type"], type];

/** Maps each UI layer toggle to the MapLibre layer ids it controls. */
export const LAYER_GROUPS: Record<string, string[]> = {
  edges: ["edges"],
  nodes: ["nodes"],
  buildings: ["ctx-building", "ctx-building-line"],
  plazas: ["ctx-plaza", "ctx-plaza-line"],
  parks: ["ctx-park"],
  water: ["ctx-water"],
  vertical: ["ctx-vertical-fill", "ctx-vertical-point"],
  boundary: ["boundary-line", "boundary-mask"],
  extent: ["extent-line"],
  authored: ["authored-closure-halo", "authored-closure", "authored-connection", "authored-location"],
};

/** Clickable layers, highest priority first. */
export const CLICK_PRIORITY = [
  "authored-location",
  "authored-connection",
  "nodes",
  "ctx-vertical-point",
  "edges",
  "ctx-vertical-fill",
  "ctx-building",
  "ctx-plaza",
  "ctx-park",
  "ctx-water",
];

export function layerSpecs(colorBy: ColorBy, palette: Palette): LayerSpecification[] {
  return [
    { id: "ctx-park", type: "fill", source: "context", filter: classIs("park"), paint: { "fill-color": "#cfe3c4" } },
    { id: "ctx-water", type: "fill", source: "context", filter: classIs("water"), paint: { "fill-color": "#b7d3ea" } },
    { id: "ctx-plaza", type: "fill", source: "context", filter: classIs("pedestrian_area"), paint: { "fill-color": "#e6dcc4", "fill-opacity": 0.8 } },
    { id: "ctx-plaza-line", type: "line", source: "context", filter: classIs("pedestrian_area"), paint: { "line-color": "#c9b98f", "line-width": 0.6 } },
    { id: "ctx-building", type: "fill", source: "context", filter: classIs("building"), paint: { "fill-color": "#d9d3c7" } },
    { id: "ctx-building-line", type: "line", source: "context", filter: classIs("building"), paint: { "line-color": "#b5ad9d", "line-width": 0.5 } },
    {
      id: "ctx-vertical-fill",
      type: "fill",
      source: "context",
      filter: ["all", classIs("vertical"), geom("Polygon")],
      paint: { "fill-color": "#8e5bd6", "fill-opacity": 0.25 },
    },
    {
      id: "edges",
      type: "line",
      source: "edges",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: {
        "line-color": edgeColor(colorBy, palette),
        "line-width": ["interpolate", ["linear"], ["zoom"], 13, 0.6, 16, 1.6, 19, 4],
        "line-opacity": 0.9,
      },
    },
    {
      id: "nodes",
      type: "circle",
      source: "nodes",
      minzoom: 16,
      paint: {
        "circle-radius": ["interpolate", ["linear"], ["zoom"], 16, 1.5, 19, 4],
        "circle-color": "#fff",
        "circle-stroke-color": "#333",
        "circle-stroke-width": 0.8,
      },
    },
    {
      id: "ctx-vertical-point",
      type: "circle",
      source: "context",
      filter: ["all", classIs("vertical"), geom("Point")],
      paint: { "circle-radius": 7, "circle-color": "#8e5bd6", "circle-stroke-color": "#fff", "circle-stroke-width": 2 },
    },
    { id: "boundary-mask", type: "fill", source: "mask", paint: { "fill-color": "#000", "fill-opacity": 0.08 } },
    { id: "boundary-line", type: "line", source: "boundary", paint: { "line-color": "#c0392b", "line-width": 2 } },
    { id: "extent-line", type: "line", source: "extent", paint: { "line-color": "#555", "line-width": 1.2, "line-dasharray": [3, 3] } },
    // Authored layer: closures highlight imported edges; connections and locations are fictional overlays.
    {
      id: "authored-closure-halo",
      type: "line",
      source: "edges",
      filter: ["in", ["get", "id"], ["literal", []]],
      paint: { "line-color": "#d64545", "line-width": 9, "line-opacity": 0.25 },
    },
    {
      id: "authored-closure",
      type: "line",
      source: "edges",
      filter: ["in", ["get", "id"], ["literal", []]],
      paint: { "line-color": "#d64545", "line-width": 3, "line-dasharray": [1.5, 1] },
    },
    { id: "authored-connection", type: "line", source: "authored-connections", paint: { "line-color": "#b5179e", "line-width": 3, "line-dasharray": [2, 2] } },
    {
      id: "authored-location",
      type: "circle",
      source: "authored-locations",
      paint: {
        "circle-radius": 8,
        "circle-color": ["match", ["get", "status"], "missing", "#ffffff", "moved", "#e0a020", "#0f9d8f"],
        "circle-stroke-color": ["match", ["get", "status"], "missing", "#d64545", "#ffffff"],
        "circle-stroke-width": ["match", ["get", "status"], "missing", 3, 2],
      },
    },
    { id: "sel-fill", type: "fill", source: "selection", filter: geom("Polygon"), paint: { "fill-color": "#ffd400", "fill-opacity": 0.35 } },
    { id: "sel-line", type: "line", source: "selection", filter: ["any", geom("LineString"), geom("Polygon")], paint: { "line-color": "#ff9f00", "line-width": 4, "line-opacity": 0.9 } },
    { id: "sel-point", type: "circle", source: "selection", filter: geom("Point"), paint: { "circle-radius": 12, "circle-color": "#ffd400", "circle-opacity": 0.5, "circle-stroke-color": "#333", "circle-stroke-width": 2 } },
  ];
}
