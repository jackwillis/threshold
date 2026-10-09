import maplibregl from "maplibre-gl";
import type { Feature, FeatureCollection, Geometry, Polygon } from "geojson";
import { BACKGROUND, CLICK_PRIORITY, LAYER_GROUPS, layerSpecs, edgeColor } from "../map/style";
import type { ColorBy, Palette } from "../map/style";
import { boundsOf, indexFeatures, outsideMask } from "../map/geo";
import { EMPTY_AUTHORED, buildAuthored } from "../map/authored";
import type { Authored, RefStatus } from "../map/authored";
import type { Bounds, Feat, Props } from "../map/geo";

// Terra Draw (editing) is installed but intentionally not started in the read-only viewer: it
// captures clicks and would interfere with selection. It is wired in when editing begins.

type ViewState = {
  layers: Record<string, boolean>;
  colorBy: ColorBy;
  palette: Palette;
  focus: { n: number; bounds: Bounds | null; object: string | null };
  authored: Authored;
  refStatus: RefStatus;
};

type Hook = {
  el: HTMLElement;
  map?: maplibregl.Map;
  ready: boolean;
  lastFocus: number;
  features: Map<string, Feat>;
  pushEvent(event: string, payload: object): void;
  readState(): ViewState;
  apply(): void;
  showAuthored(map: maplibregl.Map, state: ViewState): void;
  objectBounds(id: string | null): Bounds | null;
  load(map: maplibregl.Map): Promise<void>;
};

const EMPTY: FeatureCollection = { type: "FeatureCollection", features: [] };
const CLICK_PAD_PX = 5;

async function getJson<T>(world: string, layer: string): Promise<T> {
  const response = await fetch(`/worlds/${encodeURIComponent(world)}/${layer}`);
  if (!response.ok) throw new Error(`${layer}: HTTP ${response.status}`);
  return (await response.json()) as T;
}

export const MapEditor = {
  mounted(this: Hook) {
    this.ready = false;
    this.lastFocus = 0;
    this.features = new Map();

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

    map.on("load", () => {
      this.load(map)
        .then(() => {
          this.ready = true;
          this.apply();
          this.pushEvent("map_loaded", {});
        })
        .catch((error: unknown) => {
          this.pushEvent("map_failed", { message: `Could not load geography: ${String(error)}` });
        });
    });

    map.on("click", (event) => {
      const { x, y } = event.point;
      const hits = map.queryRenderedFeatures(
        [[x - CLICK_PAD_PX, y - CLICK_PAD_PX], [x + CLICK_PAD_PX, y + CLICK_PAD_PX]],
        { layers: CLICK_PRIORITY.filter((id) => map.getLayer(id)) },
      );
      const best = [...hits].sort((a, b) => CLICK_PRIORITY.indexOf(a.layer.id) - CLICK_PRIORITY.indexOf(b.layer.id))[0];
      const id = best?.properties?.id;
      const feature = typeof id === "string" ? this.features.get(id) : undefined;
      const source = map.getSource("selection") as maplibregl.GeoJSONSource;
      if (!best || !feature) {
        source.setData(EMPTY);
        this.pushEvent("clear_selection", {});
        return;
      }
      source.setData(feature as Feature);
      this.pushEvent("select", { layer: best.layer.id, id: feature.properties.id, properties: feature.properties });
    });

    map.on("mousemove", (event) => {
      const { x, y } = event.point;
      const hits = map.queryRenderedFeatures([[x - CLICK_PAD_PX, y - CLICK_PAD_PX], [x + CLICK_PAD_PX, y + CLICK_PAD_PX]], {
        layers: CLICK_PRIORITY.filter((id) => map.getLayer(id)),
      });
      map.getCanvas().style.cursor = hits.length > 0 ? "pointer" : "";
    });
  },

  updated(this: Hook) {
    this.apply();
  },

  destroyed(this: Hook) {
    this.map?.remove();
  },

  readState(this: Hook): ViewState {
    return JSON.parse(this.el.dataset.state ?? "{}") as ViewState;
  },

  /** Push the server-side view state (visibility, color mode, focus) onto the map. */
  apply(this: Hook) {
    const map = this.map;
    if (!map || !this.ready) return;
    const state = this.readState();
    for (const [group, ids] of Object.entries(LAYER_GROUPS)) {
      const visible = state.layers[group] ?? true;
      for (const id of ids) {
        if (map.getLayer(id)) map.setLayoutProperty(id, "visibility", visible ? "visible" : "none");
      }
    }
    map.setPaintProperty("edges", "line-color", edgeColor(state.colorBy, state.palette));
    this.showAuthored(map, state);
    if (state.focus.n !== this.lastFocus) {
      this.lastFocus = state.focus.n;
      const bounds = state.focus.bounds ?? this.objectBounds(state.focus.object);
      if (bounds) {
        const [w, s, e, n] = bounds;
        map.fitBounds([[w, s], [e, n]], { padding: 80, maxZoom: 19, duration: 600 });
      }
    }
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
    map.addSource("authored-locations", { type: "geojson", data: EMPTY });
    map.addSource("authored-connections", { type: "geojson", data: EMPTY });
    map.addSource("selection", { type: "geojson", data: EMPTY });

    const state = this.readState();
    for (const spec of layerSpecs(state.colorBy, state.palette)) map.addLayer(spec);

    const [w, s, e, n] = boundsOf(extent.geometry);
    map.fitBounds([[w, s], [e, n]], { padding: 40, duration: 0 });
  },
};
