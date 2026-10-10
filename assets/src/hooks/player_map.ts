import maplibregl from "maplibre-gl";
import type { FeatureCollection, LineString } from "geojson";
import { BACKGROUND, layerSpecs } from "../map/style";
import { destinationForKey } from "../map/shortcuts";

type Point = [number, number];
type Move = { destination: string; key: string | null; point: Point; geometry: LineString };
type State = { point: Point; turn: number; moves: Move[]; visited: Point[]; movement: { turn: number; geometry: LineString } | null; camera: number; zoom: number };
type Hook = {
  el: HTMLElement; map?: maplibregl.Map; ready: boolean; removed: boolean;
  lastTurn: number; lastCamera: number; frame?: number; animating: boolean;
  pushEvent(name: string, payload: object): void;
  state(): State; apply(): void; frameCamera(state: State, duration: number): void;
  set(name: string, data: FeatureCollection): void; animate(state: State): void;
  labels: maplibregl.Marker[]; pending: boolean; pendingTimer?: number; onKey?: (event: KeyboardEvent) => void;
  requestMove(destination: string): void; showLabels(moves: Move[]): void;
};
const empty: FeatureCollection = { type: "FeatureCollection", features: [] };
function points(positions: Point[], ids: string[] = []): FeatureCollection {
  return { type: "FeatureCollection", features: positions.map((coordinates, i) => ({
    type: "Feature", properties: { destination: ids[i] }, geometry: { type: "Point", coordinates },
  })) };
}
const pick = (e: KeyboardEvent) => ({ code: e.code, key: e.key, repeat: e.repeat, ctrlKey: e.ctrlKey, altKey: e.altKey, metaKey: e.metaKey, shiftKey: e.shiftKey, defaultPrevented: e.defaultPrevented, isComposing: e.isComposing });
const reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export const PlayerMap = {
  mounted(this: Hook) {
    this.ready = false; this.removed = false; this.lastTurn = -1; this.lastCamera = -1; this.animating = false; this.labels = []; this.pending = false;
    const canvas = this.el.querySelector<HTMLElement>("#player-map-canvas");
    if (!canvas) return;
    const state = this.state();
    const map = new maplibregl.Map({ container: canvas, center: state.point, zoom: state.zoom,
      style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": BACKGROUND } }] },
      attributionControl: { customAttribution: "© OpenStreetMap contributors" },
    });
    this.map = map;
    // Read-only map inspection and projection for browser verification.
    (window as unknown as { thresholdPlayerMap?: maplibregl.Map }).thresholdPlayerMap = map;
    map.on("load", async () => {
      try {
        const world = encodeURIComponent(this.el.dataset.world ?? "madison");
        const snapshot = this.el.dataset.snapshot;
        const query = snapshot ? `?generation=${encodeURIComponent(snapshot)}` : "";
        const data = await Promise.all(["edges", "context"].map(async layer => {
          const response = await fetch(`/worlds/${world}/${layer}${query}`, { cache: "no-store" });
          if (!response.ok) throw new Error(`Unable to load ${layer}.`);
          return await response.json() as FeatureCollection;
        }));
        if (this.removed) return;
        map.addSource("edges", { type: "geojson", data: data[0] ?? empty });
        map.addSource("context", { type: "geojson", data: data[1] ?? empty });
        for (const layer of layerSpecs("access_status", {})) {
          if (layer.id.startsWith("ctx-") || layer.id === "edges") {
            if (layer.id === "edges") layer.paint = { "line-color": "#96988e", "line-width": ["interpolate", ["linear"], ["zoom"], 15, 1, 19, 4], "line-opacity": 0.65 };
            map.addLayer(layer);
          }
        }
        for (const name of ["visited", "moves", "player", "route"]) map.addSource(name, { type: "geojson", data: empty });
        map.addLayer({ id: "walk-route", type: "line", source: "route", paint: { "line-color": "#128d7a", "line-width": 4, "line-opacity": 0.4 } });
        map.addLayer({ id: "visited-points", type: "circle", source: "visited", paint: { "circle-color": "#537468", "circle-radius": 3, "circle-opacity": 0.65 } });
        map.addLayer({ id: "move-glow", type: "circle", source: "moves", paint: { "circle-color": "#16b69e", "circle-radius": 26, "circle-opacity": 0.3, "circle-blur": 0.6 } });
        map.addLayer({ id: "move-marker", type: "circle", source: "moves", paint: { "circle-color": "#0e7d6c", "circle-radius": 11, "circle-stroke-color": "#fffdf4", "circle-stroke-width": 2 } });
        map.addLayer({ id: "player-halo", type: "circle", source: "player", paint: { "circle-color": "#253d36", "circle-radius": 17, "circle-opacity": 0.12 } });
        map.addLayer({ id: "player-marker", type: "circle", source: "player", paint: { "circle-color": "#263e37", "circle-radius": 8, "circle-stroke-color": "#fffdf4", "circle-stroke-width": 3 } });
        this.ready = true; this.apply();
      } catch (error) { if (!this.removed) this.pushEvent("map_failed", { message: String(error) }); }
    });
    map.on("click", event => {
      if (!this.ready || this.animating) return;
      const marker = map.queryRenderedFeatures([[event.point.x - 10, event.point.y - 10], [event.point.x + 10, event.point.y + 10]], { layers: ["move-marker"] })[0];
      if (marker) this.requestMove(marker.properties.destination);
    });
    this.onKey = event => {
      const destination = destinationForKey({ ...pick(event), target: event.target as HTMLElement | null }, this.state().moves, {
        idle: this.ready && !this.animating && !this.pending,
        modalOpen: document.querySelector('dialog[open], [aria-modal="true"], [role="dialog"]') !== null,
      });
      if (destination) { event.preventDefault(); this.requestMove(destination); }
    };
    window.addEventListener("keydown", this.onKey);
    map.on("mousemove", event => {
      if (!this.ready) return;
      map.getCanvas().style.cursor = map.queryRenderedFeatures(event.point, { layers: ["move-glow"] }).length ? "pointer" : "";
    });
  },
  updated(this: Hook) { this.apply(); },
  destroyed(this: Hook) {
    this.removed = true; if (this.frame) cancelAnimationFrame(this.frame);
    if (this.onKey) window.removeEventListener("keydown", this.onKey);
    window.clearTimeout(this.pendingTimer); this.showLabels([]); this.map?.remove();
  },
  // Clicks, panel buttons' siblings and number keys all end up here: one request at a time, always by destination id.
  requestMove(this: Hook, destination: string) {
    if (!this.ready || this.animating || this.pending) return;
    this.pending = true;
    this.pendingTimer = window.setTimeout(() => { this.pending = false; }, 1500);
    this.pushEvent("move", { destination, turn: this.state().turn });
  },
  showLabels(this: Hook, moves: Move[]) {
    for (const label of this.labels) label.remove();
    this.labels = [];
    const map = this.map;
    if (!map) return;
    for (const move of moves) {
      if (!move.key) continue;
      const element = document.createElement("div");
      element.className = "play-marker-label"; element.textContent = move.key; element.setAttribute("aria-hidden", "true");
      this.labels.push(new maplibregl.Marker({ element, anchor: "center" }).setLngLat(move.point).addTo(map));
    }
  },
  state(this: Hook): State { return JSON.parse(this.el.dataset.state ?? "{}") as State; },
  set(this: Hook, name: string, data: FeatureCollection) { (this.map?.getSource(name) as maplibregl.GeoJSONSource | undefined)?.setData(data); },
  apply(this: Hook) {
    if (!this.ready) return;
    const state = this.state();
    this.pending = false; window.clearTimeout(this.pendingTimer);
    this.set("visited", points(state.visited));
    this.showLabels(state.moves);
    this.set("moves", points(state.moves.map(m => m.point), state.moves.map(m => m.destination)));
    if (this.lastTurn >= 0 && state.turn !== this.lastTurn && state.movement?.turn === state.turn) {
      this.animate(state);
    } else if (!this.animating) { this.set("player", points([state.point])); }
    if (this.lastTurn === -1 || state.camera !== this.lastCamera || state.turn !== this.lastTurn) this.frameCamera(state, reduced() ? 0 : 650);
    this.lastTurn = state.turn; this.lastCamera = state.camera;
  },
  frameCamera(this: Hook, state: State, duration: number) {
    const bounds = new maplibregl.LngLatBounds(state.point, state.point);
    for (const location of state.moves) bounds.extend(location.point);
    this.map?.fitBounds(bounds, { padding: 85, maxZoom: state.zoom, duration });
  },
  animate(this: Hook, state: State) {
    if (this.frame) cancelAnimationFrame(this.frame);
    const route = state.movement?.geometry;
    if (!route || reduced()) { this.animating = false; this.set("player", points([state.point])); this.set("route", empty); return; }
    this.animating = true;
    this.set("route", { type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: route }] });
    const coords = route.coordinates as Point[];
    const lengths = [0];
    for (let i = 1; i < coords.length; i++) {
      const a = coords[i - 1]!; const b = coords[i]!;
      lengths.push(lengths[i - 1]! + Math.hypot((b[0] - a[0]) * Math.cos(a[1] * Math.PI / 180), b[1] - a[1]));
    }
    const total = lengths[lengths.length - 1]!; const started = performance.now();
    const duration = 750;
    const tick = (now: number) => {
      const fraction = Math.min(1, (now - started) / duration); const distance = fraction * total;
      let segment = 1;
      while (segment < lengths.length - 1 && lengths[segment]! < distance) segment++;
      const a = coords[segment - 1]!; const b = coords[segment]!;
      const span = lengths[segment]! - lengths[segment - 1]!;
      const t = span === 0 ? 1 : (distance - lengths[segment - 1]!) / span;
      this.set("player", points([[a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]]));
      if (fraction < 1) this.frame = requestAnimationFrame(tick);
      else { this.animating = false; this.set("player", points([state.point])); this.set("route", empty); }
    };
    this.frame = requestAnimationFrame(tick);
  },
};
