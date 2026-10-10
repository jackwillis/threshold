import maplibregl from "maplibre-gl";
import type { FeatureCollection, Point as GeoPoint } from "geojson";
import { initialTreatment, loadAtlasMaterials } from "../map/atlas/materials";
import { loadAtlasFonts } from "../map/atlas/fonts";
import { MOVEMENT_SOURCES, atlasLayers, movementLayers } from "../map/atlas/style";
import { contextLabelPoints, streetLabelLines } from "../map/atlas/labels";
import { SEASON_TOKENS, type Season } from "../map/atlas/tokens";
import { bindSeasonButtons, initialSeason, paintPage } from "../map/atlas/season";

// Classic Atlas prototype (route /atlas): the real Madison geography in the atlas style, with one-hop
// movement markers computed from the authored connections. A visual study only: nothing here is saved
// and no movement rules run (the real rules stay on the server in /play).

type Point = [number, number];
type Place = { id: string; name: string; point: Point };
const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
const empty: FeatureCollection = { type: "FeatureCollection", features: [] };
const pointCollection = (items: { point: Point; properties?: Record<string, unknown> }[]): FeatureCollection => ({
  type: "FeatureCollection",
  features: items.map((i) => ({ type: "Feature", properties: i.properties ?? {}, geometry: { type: "Point", coordinates: i.point } as GeoPoint })),
});

const bearing = (a: Point, b: Point) => {
  const dx = (b[0] - a[0]) * Math.cos((a[1] * Math.PI) / 180);
  return (Math.atan2(dx, b[1] - a[1]) * 180) / Math.PI + (dx < 0 ? 360 : 0);
};

type Hook = { el: HTMLElement; map?: maplibregl.Map; removed?: boolean; season: Season; unbind?: () => void };

export const AtlasPrototype = {
  async mounted(this: Hook) {
    const params = new URLSearchParams(location.search);
    const treatment = initialTreatment();
    this.season = initialSeason();
    paintPage(this.el, this.season);
    const world = encodeURIComponent(this.el.dataset.world ?? "madison");
    const snapshot = this.el.dataset.snapshot;
    const canvas = this.el.querySelector<HTMLElement>("#atlas-canvas")!;
    try {
      // The faces must be loaded before MapLibre draws its first label: it caches every glyph it draws.
      const [, authored] = await Promise.all([
        loadAtlasFonts(),
        fetch(`/worlds/${world}/authored`, { cache: "no-store" }).then((r) => r.json() as Promise<{ locations: { id: string; name: string; anchor: { point: Point } }[]; connections: { from: string; to: string }[] }>),
      ]);
      const places = new Map<string, Place>(authored.locations.map((l) => [l.id, { id: l.id, name: l.name, point: l.anchor.point }]));
      const neighbours = new Map<string, string[]>();
      for (const c of authored.connections) {
        if (!places.has(c.from) || !places.has(c.to)) continue;
        neighbours.set(c.from, [...(neighbours.get(c.from) ?? []), c.to]);
        neighbours.set(c.to, [...(neighbours.get(c.to) ?? []), c.from]);
      }
      const wanted = params.get("at");
      let here = (wanted && places.get(wanted)) || [...places.values()].sort((a, b) => (neighbours.get(b.id)?.length ?? 0) - (neighbours.get(a.id)?.length ?? 0))[0]!;
      const visited = new Set<string>([here.id]);

      const [lng0, lat0] = params.has("lng") ? [Number(params.get("lng")), Number(params.get("lat"))] : here.point;
      const pad = 0.0075;
      const box = [lng0 - pad * 1.4, lat0 - pad, lng0 + pad * 1.4, lat0 + pad].map((v) => v.toFixed(6)).join(",");
      const query = `${snapshot ? `generation=${encodeURIComponent(snapshot)}&` : ""}bbox=${box}`;
      const [edges, context] = await Promise.all(["edges", "context"].map((l) => fetch(`/worlds/${world}/${l}?${query}`).then((r) => r.json() as Promise<FeatureCollection>)));
      if (this.removed) return;

      const sources: Record<string, { type: "geojson"; data: FeatureCollection }> = {
        edges: { type: "geojson", data: edges! }, context: { type: "geojson", data: context! }, "context-labels": { type: "geojson", data: contextLabelPoints(context!) }, "street-labels": { type: "geojson", data: streetLabelLines(edges!) },
      };
      for (const name of MOVEMENT_SOURCES) sources[name] = { type: "geojson", data: empty };
      const map = new maplibregl.Map({
        container: canvas, center: [lng0, lat0], zoom: Number(params.get("zoom") ?? 18),
        minZoom: 13, maxZoom: 20.5, attributionControl: { customAttribution: "© OpenStreetMap contributors" },
        // No `glyphs` URL on purpose: MapLibre then draws all text itself from the bundled font faces.
        style: { version: 8, sources, layers: [] },
      });
      this.map = map;
      (window as unknown as { thresholdAtlas?: maplibregl.Map }).thresholdAtlas = map;
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");

      const set = (name: string, data: FeatureCollection) => (map.getSource(name) as maplibregl.GeoJSONSource).setData(data);
      const present = () => {
        const next = (neighbours.get(here.id) ?? []).map((id) => places.get(id)!).sort((a, b) => bearing(here.point, a.point) - bearing(here.point, b.point));
        set("player", pointCollection([{ point: here.point }]));
        set("moves", pointCollection(next.map((p, i) => ({ point: p.point, properties: { id: p.id, key: KEYS[i] ?? "" } }))));
        set("route", { type: "FeatureCollection", features: next.map((p) => ({ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: [here.point, p.point] } })) });
        set("visited", pointCollection([...visited].filter((id) => id !== here.id).map((id) => ({ point: places.get(id)!.point }))));
        set("authored-places", pointCollection([...places.values()].filter((p) => p.id !== here.id && !next.includes(p)).map((p) => ({ point: p.point, properties: p.name === "New location" ? {} : { name: p.name } }))));
        this.el.querySelector("#atlas-here")!.textContent = here.name;
      };
      map.on("load", async () => {
        try {
          await loadAtlasMaterials(map);
          if (this.removed) return;
          const current = SEASON_TOKENS[this.season];
          for (const layer of [...atlasLayers(current, treatment), ...movementLayers(current)]) map.addLayer(layer);
          present();
          map.once("idle", () => { if (!this.removed) this.el.dataset.ready = "true"; });
        } catch (error) { if (!this.removed) this.el.querySelector("#atlas-error")!.textContent = `The atlas could not load: ${String(error)}`; }
      });
      map.on("click", (event) => {
        if (this.el.dataset.ready !== "true") return;
        const hit = map.queryRenderedFeatures([[event.point.x - 12, event.point.y - 12], [event.point.x + 12, event.point.y + 12]], { layers: ["move-marker"] })[0];
        const target = hit && places.get(String(hit.properties.id));
        if (!target) return;
        here = target; visited.add(target.id); present();
        map.easeTo({ center: target.point, duration: matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 500 });
      });
      map.on("mousemove", (event) => { if (this.el.dataset.ready !== "true") return; map.getCanvas().style.cursor = map.queryRenderedFeatures(event.point, { layers: ["move-marker"] }).length ? "pointer" : ""; });

      this.unbind = bindSeasonButtons(this.el, map, (season) => { this.season = season; }, treatment);
    } catch (error) {
      this.el.querySelector("#atlas-error")!.textContent = `The atlas could not load: ${String(error)}`;
    }
  },
  destroyed(this: Hook) { this.removed = true; this.unbind?.(); this.map?.remove(); },
};
