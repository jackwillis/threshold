import maplibregl from "maplibre-gl";
import type { FeatureCollection, LineString } from "geojson";
import { initialTreatment, loadAtlasMaterials } from "../map/atlas/materials";
import { loadAtlasFonts } from "../map/atlas/fonts";
import { MOVEMENT_SOURCES, atlasLayers, movementLayers } from "../map/atlas/style";
import { contextLabelPoints, streetLabelLines } from "../map/atlas/labels";
import { bindSeasonButtons, initialSeason, paintPage } from "../map/atlas/season";
import { SEASON_TOKENS, type Season } from "../map/atlas/tokens";
import { destinationForKey } from "../map/shortcuts";
import { allowedCenter, clampZoom, reachBounds, resolveLimits, violatesLimits, type Bounds, type CameraLimits } from "../map/camera";

type Point = [number, number];
type Move = { destination: string; key: string | null; point: Point; geometry: LineString };
type State = { point: Point; turn: number; moves: Move[]; visited: Point[]; movement: { turn: number; geometry: LineString } | null; camera: number; zoom: number; bounds: Bounds | null; limits: Partial<CameraLimits> };
type Hook = {
  el: HTMLElement; map?: maplibregl.Map; ready: boolean; removed: boolean;
  lastTurn: number; lastCamera: number; frame?: number; animating: boolean;
  pushEvent(name: string, payload: object): void;
  state(): State; apply(): void; frameCamera(state: State, duration: number): void;
  set(name: string, data: FeatureCollection): void; animate(state: State): void;
  unbindSeason?: () => void; season: Season; chrome?: HTMLElement | null; pending: boolean; pendingTimer?: number; onKey?: (event: KeyboardEvent) => void;
  requestMove(destination: string): void;
  limits: CameraLimits; settling: boolean; keepCameraNearPlayer(animated: boolean): void;
};
const empty: FeatureCollection = { type: "FeatureCollection", features: [] };
function points(positions: Point[], ids: string[] = [], keys: (string | null)[] = []): FeatureCollection {
  return { type: "FeatureCollection", features: positions.map((coordinates, i) => ({
    type: "Feature", properties: { destination: ids[i], key: keys[i] ?? "" }, geometry: { type: "Point", coordinates },
  })) };
}
const pick = (e: KeyboardEvent) => ({ code: e.code, key: e.key, repeat: e.repeat, ctrlKey: e.ctrlKey, altKey: e.altKey, metaKey: e.metaKey, shiftKey: e.shiftKey, defaultPrevented: e.defaultPrevented, isComposing: e.isComposing });
const reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export const PlayerMap = {
  mounted(this: Hook) {
    this.ready = false; this.removed = false; this.lastTurn = -1; this.lastCamera = -1; this.animating = false; this.pending = false;
    const canvas = this.el.querySelector<HTMLElement>("#player-map-canvas");
    if (!canvas) return;
    const state = this.state();
    this.limits = resolveLimits(state.limits); this.settling = false;
    const map = new maplibregl.Map({ container: canvas, center: state.point, zoom: clampZoom(state.zoom, this.limits),
      minZoom: this.limits.minZoom, maxZoom: this.limits.maxZoom,
      // No `glyphs` URL on purpose: MapLibre draws all map text itself from the bundled Classic Atlas faces.
      style: { version: 8, sources: {}, layers: [] },
      attributionControl: { customAttribution: "© OpenStreetMap contributors" },
    });
    this.map = map;
    // Season is a display preference only (CSS variables and map paint); the server never sees it.
    this.season = initialSeason();
    const season = this.season;
    const treatment = initialTreatment();
    this.chrome = this.el.querySelector<HTMLElement>("#play-chrome");
    if (this.chrome) { paintPage(this.chrome, season); this.unbindSeason = bindSeasonButtons(this.chrome, map, s => { this.season = s; }, treatment); }
    const fonts = loadAtlasFonts();
    // Read-only map inspection and projection for browser verification.
    (window as unknown as { thresholdPlayerMap?: maplibregl.Map }).thresholdPlayerMap = map;
    map.on("load", async () => {
      try {
        const world = encodeURIComponent(this.el.dataset.world ?? "madison");
        const snapshot = this.el.dataset.snapshot;
        // Only the area the camera can reach: the playable boundary plus the tether and the widest view the screen allows.
        const area = this.state().bounds;
        const reach = area ? reachBounds(area, this.limits, Math.max(screen.width, screen.height)) : null;
        const box = reach ? reach.map(v => v.toFixed(6)).join(",") : "";
        const query = [snapshot ? `generation=${encodeURIComponent(snapshot)}` : "", box ? `bbox=${box}` : ""].filter(Boolean).join("&");
        const data = await Promise.all(["edges", "context"].map(async layer => {
          const response = await fetch(`/worlds/${world}/${layer}${query ? `?${query}` : ""}`, { cache: "no-store" });
          if (!response.ok) throw new Error(`Unable to load ${layer}.`);
          return await response.json() as FeatureCollection;
        }));
        if (this.removed) return;
        // The faces must be loaded before the first label is drawn: MapLibre caches every glyph it draws.
        await Promise.all([fonts, loadAtlasMaterials(map)]);
        if (this.removed) return;
        const edges = data[0] ?? empty; const context = data[1] ?? empty;
        map.addSource("edges", { type: "geojson", data: edges });
        map.addSource("context", { type: "geojson", data: context });
        map.addSource("street-labels", { type: "geojson", data: streetLabelLines(edges) });
        map.addSource("context-labels", { type: "geojson", data: contextLabelPoints(context) });
        for (const name of MOVEMENT_SOURCES) map.addSource(name, { type: "geojson", data: empty });
        // The layer stack is shared with the /atlas prototype; this page paints the player's season.
        const tokens = SEASON_TOKENS[this.season];
        for (const layer of [...atlasLayers(tokens, treatment), ...movementLayers(tokens)]) map.addLayer(layer);
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
    // Dragging, wheel and pinch cannot take the camera centre more than the tether from the player (and never
    // outside the world's bounds); programmatic moves are checked once they settle.
    map.on("move", event => { if (event.originalEvent) this.keepCameraNearPlayer(false); });
    map.on("moveend", () => { if (!this.settling) this.keepCameraNearPlayer(true); });
    map.on("mousemove", event => {
      if (!this.ready) return;
      map.getCanvas().style.cursor = map.queryRenderedFeatures(event.point, { layers: ["move-glow"] }).length ? "pointer" : "";
    });
  },
  // A LiveView patch can drop attributes the hook set on #play-chrome; restore them from the remembered season.
  updated(this: Hook) { if (this.chrome) paintPage(this.chrome, this.season); this.apply(); },
  destroyed(this: Hook) {
    this.removed = true; if (this.frame) cancelAnimationFrame(this.frame);
    if (this.onKey) window.removeEventListener("keydown", this.onKey);
    window.clearTimeout(this.pendingTimer); this.unbindSeason?.(); this.map?.remove();
  },
  // Clicks, panel buttons' siblings and number keys all end up here: one request at a time, always by destination id.
  requestMove(this: Hook, destination: string) {
    if (!this.ready || this.animating || this.pending) return;
    this.pending = true;
    this.pendingTimer = window.setTimeout(() => { this.pending = false; }, 1500);
    this.pushEvent("move", { destination, turn: this.state().turn });
  },
  keepCameraNearPlayer(this: Hook, animated: boolean) {
    const map = this.map; if (!map || !this.ready) return;
    const state = this.state(); const center = map.getCenter().toArray() as [number, number];
    if (!violatesLimits(center, state.point, this.limits, state.bounds)) return;
    const target = allowedCenter(center, state.point, this.limits, state.bounds);
    if (!animated || reduced()) { map.setCenter(target); return; }
    this.settling = true;
    map.once("moveend", () => { this.settling = false; });
    map.easeTo({ center: target, duration: 250 });
  },
  state(this: Hook): State { return JSON.parse(this.el.dataset.state ?? "{}") as State; },
  set(this: Hook, name: string, data: FeatureCollection) { (this.map?.getSource(name) as maplibregl.GeoJSONSource | undefined)?.setData(data); },
  apply(this: Hook) {
    if (!this.ready) return;
    const state = this.state();
    this.pending = false; window.clearTimeout(this.pendingTimer);
    this.set("visited", points(state.visited));
    this.set("moves", points(state.moves.map(m => m.point), state.moves.map(m => m.destination), state.moves.map(m => m.key)));
    if (this.lastTurn >= 0 && state.turn !== this.lastTurn && state.movement?.turn === state.turn) {
      this.animate(state);
    } else if (!this.animating) { this.set("player", points([state.point])); }
    if (this.lastTurn === -1 || state.camera !== this.lastCamera || state.turn !== this.lastTurn) this.frameCamera(state, reduced() ? 0 : 650);
    this.lastTurn = state.turn; this.lastCamera = state.camera;
  },
  frameCamera(this: Hook, state: State, duration: number) {
    const bounds = new maplibregl.LngLatBounds(state.point, state.point);
    for (const location of state.moves) bounds.extend(location.point);
    this.map?.fitBounds(bounds, { padding: 85, maxZoom: clampZoom(state.zoom, this.limits), duration });
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
