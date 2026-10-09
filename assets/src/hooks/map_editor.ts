import maplibregl from "maplibre-gl";
import type { Feature, FeatureCollection, Geometry, LineString, Point, Polygon, Position } from "geojson";
import {
  TerraDraw,
  TerraDrawPointMode,
  TerraDrawPolygonMode,
  TerraDrawSelectMode,
} from "terra-draw";
import { TerraDrawMapLibreGLAdapter } from "terra-draw-maplibre-gl-adapter";
import { BACKGROUND, CLICK_PRIORITY, LAYER_GROUPS, layerSpecs, edgeColor } from "../map/style";
import type { ColorBy, Palette } from "../map/style";
import { boundsOf, indexFeatures, outsideMask } from "../map/geo";
import type { Bounds, Feat, Props } from "../map/geo";
import { EMPTY_AUTHORED, buildAuthored } from "../map/authored";
import type { Authored, RefStatus } from "../map/authored";
import { snapAnchor } from "../map/snap";
import type { LngLat } from "../map/snap";

type Mode = "inspect" | "place" | "move" | "connect" | "close" | "boundary";

type ViewState = {
  layers: Record<string, boolean>;
  colorBy: ColorBy;
  palette: Palette;
  focus: { n: number; bounds: Bounds | null; object: string | null };
  authored: Authored;
  refStatus: RefStatus;
  boundary: Polygon;
  mode: Mode;
  selected: string | null;
  pendingFrom: string | null;
  dirty: boolean;
  rev: number;
  playable: "missing" | "fresh" | "stale";
};

type Hook = {
  el: HTMLElement;
  map?: maplibregl.Map;
  draw?: TerraDraw;
  ready: boolean;
  lastFocus: number;
  syncSignature: string;
  dirty: boolean;
  mode: Mode;
  features: Map<string, Feat>;
  playableBase: PlayableLocation[];
  boundaryFeatureId?: string | number;
  onBeforeUnload?: (event: BeforeUnloadEvent) => void;
  onKeyDown?: (event: KeyboardEvent) => void;
  pushEvent(event: string, payload: object): void;
  readState(): ViewState;
  apply(): void;
  showAuthored(map: maplibregl.Map, state: ViewState): void;
  syncDraw(state: ViewState): void;
  setupDraw(map: maplibregl.Map): void;
  onDrawFinish(id: string | number, action: string): void;
  onMapClick(event: maplibregl.MapMouseEvent): void;
  objectBounds(id: string | null): Bounds | null;
  showPlayable(map: maplibregl.Map, state: ViewState): void;
  highlightFeature(id: string | null, state: ViewState): Feature | undefined;
  load(map: maplibregl.Map): Promise<void>;
};

type PlayableLocation = { id: string; point: [number, number]; node: string; members: number; reasons: string[]; component: number; degree: number; override: string | null };
type PlayableConnection = { id: string; from: string; to: string; length_m: number; classes: string[]; parallel: number; edge_ids: string[] };
type PlayableDoc = { locations: PlayableLocation[]; connections: PlayableConnection[] };

const EMPTY: FeatureCollection = { type: "FeatureCollection", features: [] };
const CLICK_PAD_PX = 5;
const CLICK_MODES: Mode[] = ["inspect", "connect", "close"];
const BOUNDARY_EDIT_ACTIONS = ["dragCoordinate", "dragFeature", "dragCoordinateResize", "insertMidpoint", "deleteCoordinate", "edit"];

async function getJson<T>(world: string, layer: string): Promise<T> {
  const response = await fetch(`/worlds/${encodeURIComponent(world)}/${layer}`);
  if (!response.ok) throw new Error(`${layer}: HTTP ${response.status}`);
  return (await response.json()) as T;
}

/** Terra Draw rejects features silently; make that visible. */
function reportInvalid(results: { valid: boolean; reason?: string }[]): void {
  for (const result of results) if (!result.valid) console.error("Terra Draw rejected a feature:", result.reason);
}

const lngLat = (position: Position): LngLat => [position[0] ?? 0, position[1] ?? 0];

export const MapEditor = {
  mounted(this: Hook) {
    this.ready = false;
    this.lastFocus = 0;
    this.syncSignature = "";
    this.dirty = false;
    this.mode = "inspect";
    this.features = new Map();
    this.playableBase = [];

    const canvas = this.el.querySelector<HTMLElement>("#map-canvas");
    if (!canvas) return;
    const map = new maplibregl.Map({
      container: canvas,
      style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": BACKGROUND } }] },
      center: [-89.3806, 43.075],
      zoom: 15,
      attributionControl: { customAttribution: "© OpenStreetMap contributors" },
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }));
    this.map = map;
    // Handle for browser-driven tests and debugging.
    (window as unknown as { thresholdMap?: maplibregl.Map }).thresholdMap = map;

    map.on("load", () => {
      this.load(map)
        .then(() => {
          this.setupDraw(map);
          this.ready = true;
          this.apply();
          this.pushEvent("map_loaded", {});
        })
        .catch((error: unknown) => {
          this.pushEvent("map_failed", { message: `Could not load geography: ${String(error)}` });
        });
    });

    map.on("click", (event) => this.onMapClick(event));

    map.on("mousemove", (event) => {
      if (!CLICK_MODES.includes(this.mode)) return;
      const { x, y } = event.point;
      const hits = map.queryRenderedFeatures([[x - CLICK_PAD_PX, y - CLICK_PAD_PX], [x + CLICK_PAD_PX, y + CLICK_PAD_PX]], {
        layers: CLICK_PRIORITY.filter((id) => map.getLayer(id)),
      });
      map.getCanvas().style.cursor = hits.length > 0 ? "pointer" : "";
    });

    // Leaving the page (or reloading) with unsaved edits should ask first.
    this.onBeforeUnload = (event) => {
      if (this.dirty) {
        event.preventDefault();
        event.returnValue = "";
      }
    };
    this.onKeyDown = (event) => {
      if (event.key === "Escape" && this.mode !== "inspect") this.pushEvent("set_mode", { mode: "inspect" });
    };
    window.addEventListener("beforeunload", this.onBeforeUnload);
    window.addEventListener("keydown", this.onKeyDown);
  },

  updated(this: Hook) {
    this.apply();
  },

  destroyed(this: Hook) {
    if (this.onBeforeUnload) window.removeEventListener("beforeunload", this.onBeforeUnload);
    if (this.onKeyDown) window.removeEventListener("keydown", this.onKeyDown);
    this.draw?.stop();
    this.map?.remove();
  },

  readState(this: Hook): ViewState {
    return JSON.parse(this.el.dataset.state ?? "{}") as ViewState;
  },

  /** Click in an inspecting tool: report what was hit; the server decides what that means. */
  onMapClick(this: Hook, event: maplibregl.MapMouseEvent) {
    const map = this.map;
    if (!map || !this.ready || !CLICK_MODES.includes(this.mode)) return;
    const { x, y } = event.point;
    const hits = map.queryRenderedFeatures(
      [[x - CLICK_PAD_PX, y - CLICK_PAD_PX], [x + CLICK_PAD_PX, y + CLICK_PAD_PX]],
      { layers: CLICK_PRIORITY.filter((id) => map.getLayer(id)) },
    );
    const best = [...hits].sort((a, b) => CLICK_PRIORITY.indexOf(a.layer.id) - CLICK_PRIORITY.indexOf(b.layer.id))[0];
    const id = best?.properties?.id;
    const feature = typeof id === "string" ? this.features.get(id) : undefined;
    if (!best || !feature) {
      this.pushEvent("clear_selection", {});
      return;
    }
    this.pushEvent("pick", { layer: best.layer.id, id: feature.properties.id, properties: feature.properties });
  },

  /** Push the server-side view state (visibility, color, selection, boundary, tool) onto the map. */
  apply(this: Hook) {
    const map = this.map;
    if (!map || !this.ready) return;
    const state = this.readState();
    this.dirty = state.dirty;
    this.mode = state.mode;

    for (const [group, ids] of Object.entries(LAYER_GROUPS)) {
      const visible = state.layers[group] ?? true;
      for (const id of ids) {
        if (map.getLayer(id)) map.setLayoutProperty(id, "visibility", visible ? "visible" : "none");
      }
    }
    // While editing, Terra Draw draws the boundary / dragged points itself.
    if (state.mode === "boundary") map.setLayoutProperty("boundary-line", "visibility", "none");
    if (state.mode === "move") map.setLayoutProperty("authored-location", "visibility", "none");

    map.setPaintProperty("edges", "line-color", edgeColor(state.colorBy, state.palette));
    (map.getSource("boundary") as maplibregl.GeoJSONSource).setData({ type: "Feature", properties: {}, geometry: state.boundary });
    (map.getSource("mask") as maplibregl.GeoJSONSource).setData(outsideMask(state.boundary));
    this.showAuthored(map, state);

    this.showPlayable(map, state);

    // Highlight the pending location while connecting, else the selection.
    const highlighted = this.highlightFeature(state.pendingFrom ?? state.selected, state);
    (map.getSource("selection") as maplibregl.GeoJSONSource).setData(highlighted ?? EMPTY);

    this.syncDraw(state);

    if (state.focus.n !== this.lastFocus) {
      this.lastFocus = state.focus.n;
      const bounds = state.focus.bounds ?? this.objectBounds(state.focus.object);
      if (bounds) {
        const [w, s, e, n] = bounds;
        map.fitBounds([[w, s], [e, n]], { padding: 80, maxZoom: 19, duration: 600 });
      }
    }
  },

  /** What to highlight for a selected id: a closure marks its street, a playable connection its underlying edges. */
  highlightFeature(this: Hook, id: string | null, state: ViewState): Feature | undefined {
    if (!id) return undefined;
    const closure = state.authored.closures.find((c) => c.id === id);
    if (closure) return this.features.get(closure.edge) as Feature | undefined;
    if (id.startsWith("pc:")) {
      const connection = this.features.get(id)?.properties.edge_ids;
      if (!Array.isArray(connection)) return undefined;
      const lines: Position[][] = [];
      for (const edgeId of connection) {
        const g = this.features.get(String(edgeId))?.geometry;
        if (g && g.type === "LineString") lines.push(g.coordinates);
      }
      return { type: "Feature", properties: {}, geometry: { type: "MultiLineString", coordinates: lines } };
    }
    return this.features.get(id) as Feature | undefined;
  },

  /** Candidate playable locations, restyled immediately by the designer's retain/suppress decisions. */
  showPlayable(this: Hook, map: maplibregl.Map, state: ViewState) {
    if (this.playableBase.length === 0) return;
    const overrides = new Map((state.authored.playable_overrides ?? []).map((o) => [o.id, o.action]));
    const features: Feature<Point, Props>[] = this.playableBase.map((l) => ({
      type: "Feature",
      geometry: { type: "Point", coordinates: l.point },
      properties: { id: l.id, classification: "playable-location", reasons: l.reasons, members: l.members, degree: l.degree, component: l.component, override: overrides.get(l.id) ?? null },
    }));
    (map.getSource("playable-locations") as maplibregl.GeoJSONSource).setData({ type: "FeatureCollection", features });
    indexFeatures({ type: "FeatureCollection", features }, this.features);
  },

  /** Refresh authored sources whenever the server's working copy or reference statuses change. */
  showAuthored(this: Hook, map: maplibregl.Map, state: ViewState) {
    const built = buildAuthored(state.authored ?? EMPTY_AUTHORED, state.refStatus ?? {});
    (map.getSource("authored-locations") as maplibregl.GeoJSONSource).setData(built.locations);
    (map.getSource("authored-connections") as maplibregl.GeoJSONSource).setData(built.connections);
    const filter: maplibregl.FilterSpecification = ["in", ["get", "id"], ["literal", built.closureEdgeIds]];
    map.setFilter("authored-closure-halo", filter);
    map.setFilter("authored-closure", filter);
    for (const fc of [built.locations, built.connections]) indexFeatures(fc, this.features);
  },

  /** Where to zoom for an authored object: its point, or the edge a closure marks. */
  objectBounds(this: Hook, id: string | null): Bounds | null {
    if (!id) return null;
    const state = this.readState();
    const location = state.authored.locations.find((l) => l.id === id);
    if (location) {
      const [x, y] = location.anchor.point;
      const pad = 0.0004;
      return [x - pad, y - pad, x + pad, y + pad];
    }
    const closure = state.authored.closures.find((c) => c.id === id);
    const edge = closure && this.features.get(closure.edge);
    return edge ? boundsOf(edge.geometry) : null;
  },

  /** Terra Draw places points, drags locations and reshapes the boundary; the server stays authoritative. */
  setupDraw(this: Hook, map: maplibregl.Map) {
    const draw = new TerraDraw({
      adapter: new TerraDrawMapLibreGLAdapter({ map }),
      modes: [
        new TerraDrawPointMode({ styles: { pointColor: "#0f9d8f", pointWidth: 8, pointOutlineColor: "#ffffff", pointOutlineWidth: 2 } }),
        // Registered so polygon features (the boundary) are accepted into the store; drawing new polygons is not offered.
        new TerraDrawPolygonMode(),
        new TerraDrawSelectMode({
          flags: {
            point: { feature: { draggable: true } },
            polygon: { feature: { draggable: false, coordinates: { midpoints: true, draggable: true, deletable: true } } },
          },
        }),
      ],
    });
    draw.on("finish", (id, context) => this.onDrawFinish(id, context.action));
    (window as unknown as { thresholdDraw?: TerraDraw }).thresholdDraw = draw;
    draw.start();
    this.draw = draw;
  },

  /** Match Terra Draw's mode and contents to the server's tool and working copy. */
  syncDraw(this: Hook, state: ViewState) {
    const draw = this.draw;
    if (!draw) return;
    // Resync only when the tool or the server-side data changed, so drags are not interrupted.
    const signature = JSON.stringify([state.mode, state.rev, state.mode === "move" ? state.authored.locations : null, state.mode === "boundary" ? state.boundary : null]);
    if (signature === this.syncSignature) return;
    this.syncSignature = signature;

    draw.clear();
    this.boundaryFeatureId = undefined;
    switch (state.mode) {
      case "place":
        draw.setMode("point");
        break;
      case "move": {
        reportInvalid(
          draw.addFeatures(
          state.authored.locations.map((l) => ({
            type: "Feature" as const,
            geometry: { type: "Point" as const, coordinates: l.anchor.point },
            properties: { mode: "point", locationId: l.id },
          })),
          ),
        );
        draw.setMode("select");
        break;
      }
      case "boundary": {
        reportInvalid(draw.addFeatures([{ type: "Feature", geometry: state.boundary, properties: { mode: "polygon" } }]));
        const added = draw.getSnapshot()[0];
        if (added && added.id !== undefined) {
          this.boundaryFeatureId = added.id;
          draw.setMode("select");
          draw.selectFeature(added.id);
        }
        break;
      }
      default:
        draw.setMode("static");
    }
  },

  onDrawFinish(this: Hook, id: string | number, action: string) {
    const draw = this.draw;
    const map = this.map;
    if (!draw || !map) return;
    const feature = draw.getSnapshotFeature(id);
    if (!feature) return;
    const state = this.readState();
    const visible = { nodes: state.layers["nodes"] ?? false, edges: state.layers["edges"] ?? true };

    if (state.mode === "place" && action === "draw" && feature.geometry.type === "Point") {
      draw.removeFeatures([id]);
      const anchor = snapAnchor(map, lngLat((feature.geometry as Point).coordinates), this.features, visible);
      this.pushEvent("add_location", { anchor });
    } else if (state.mode === "move" && action === "dragFeature" && feature.geometry.type === "Point") {
      const locationId = feature.properties?.locationId;
      if (typeof locationId === "string") {
        const anchor = snapAnchor(map, lngLat((feature.geometry as Point).coordinates), this.features, visible);
        this.pushEvent("move_location", { id: locationId, anchor });
      }
    } else if (state.mode === "boundary" && id === this.boundaryFeatureId && BOUNDARY_EDIT_ACTIONS.includes(action) && feature.geometry.type === "Polygon") {
      this.pushEvent("update_boundary", { coordinates: (feature.geometry as Polygon).coordinates[0] });
    }
  },

  async load(this: Hook, map: maplibregl.Map) {
    const world = this.el.dataset.world ?? "";
    type Fc = FeatureCollection<Geometry, Props>;
    const [boundary, provenance, edges, nodes, context] = await Promise.all([
      getJson<Feature<Polygon>>(world, "boundary"),
      getJson<{ import_extent: Polygon }>(world, "provenance"),
      getJson<Fc>(world, "edges"),
      getJson<Fc>(world, "nodes"),
      getJson<Fc>(world, "context"),
    ]);
    for (const fc of [edges, nodes, context]) indexFeatures(fc, this.features);

    const extent: Feature<Polygon> = { type: "Feature", properties: {}, geometry: provenance.import_extent };
    map.addSource("context", { type: "geojson", data: context });
    map.addSource("edges", { type: "geojson", data: edges });
    map.addSource("nodes", { type: "geojson", data: nodes });
    map.addSource("boundary", { type: "geojson", data: boundary });
    map.addSource("extent", { type: "geojson", data: extent });
    map.addSource("mask", { type: "geojson", data: outsideMask(boundary.geometry) });
    map.addSource("playable-locations", { type: "geojson", data: EMPTY });
    map.addSource("playable-connections", { type: "geojson", data: EMPTY });
    map.addSource("authored-locations", { type: "geojson", data: EMPTY });
    map.addSource("authored-connections", { type: "geojson", data: EMPTY });
    map.addSource("selection", { type: "geojson", data: EMPTY });

    const state = this.readState();
    if (state.playable !== "missing") {
      try {
        const playable = await getJson<PlayableDoc>(world, "playable");
        this.playableBase = playable.locations;
        const byId = new Map(playable.locations.map((l) => [l.id, l]));
        const lines: Feature<LineString, Props>[] = [];
        for (const c of playable.connections) {
          const from = byId.get(c.from);
          const to = byId.get(c.to);
          if (!from || !to) continue;
          lines.push({
            type: "Feature",
            geometry: { type: "LineString", coordinates: [from.point, to.point] },
            properties: { id: c.id, classification: "playable-connection", length_m: c.length_m, classes: c.classes, parallel: c.parallel, edge_ids: c.edge_ids },
          });
        }
        const connections: FeatureCollection<LineString, Props> = { type: "FeatureCollection", features: lines };
        (map.getSource("playable-connections") as maplibregl.GeoJSONSource).setData(connections);
        indexFeatures(connections, this.features);
      } catch (error) {
        console.error("Could not load the playable layer:", error);
      }
    }
    for (const spec of layerSpecs(state.colorBy, state.palette)) map.addLayer(spec);

    const [w, s, e, n] = boundsOf(extent.geometry);
    map.fitBounds([[w, s], [e, n]], { padding: 40, duration: 0 });
  },
};
