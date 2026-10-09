import type maplibregl from "maplibre-gl";
import type { LineString, Point, Position } from "geojson";
import type { Feat } from "./geo";

export type LngLat = [number, number];

/** A requested anchor. The server resolves refs against the geography; positions here are advisory. */
export type AnchorRequest =
  | { kind: "point"; point: LngLat }
  | { kind: "node"; ref: string; point: LngLat }
  | { kind: "edge"; ref: string; offset: number; point: LngLat };

const NODE_SNAP_PX = 14;
const EDGE_SNAP_PX = 12;
const M_PER_DEG = 111_320;

type Px = { x: number; y: number };

function pixelDistanceToSegment(p: Px, a: Px, b: Px): { dist: number; t: number } {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lengthSq = dx * dx + dy * dy;
  const t = lengthSq === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq));
  return { dist: Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)), t };
}

/** Length in metres between two positions, using a local equirectangular approximation. */
function metres(a: Position, b: Position): number {
  const latMid = (((a[1] ?? 0) + (b[1] ?? 0)) / 2) * (Math.PI / 180);
  const dx = ((b[0] ?? 0) - (a[0] ?? 0)) * Math.cos(latMid) * M_PER_DEG;
  const dy = ((b[1] ?? 0) - (a[1] ?? 0)) * M_PER_DEG;
  return Math.hypot(dx, dy);
}

/**
 * Snaps a clicked position to the nearest visible intersection, else the nearest visible street
 * (with a fractional offset along it), else leaves it as a free point.
 */
export function snapAnchor(
  map: maplibregl.Map,
  lngLat: LngLat,
  features: Map<string, Feat>,
  visible: { nodes: boolean; edges: boolean },
): AnchorRequest {
  const p = map.project(lngLat);

  if (visible.nodes) {
    let best: { id: string; dist: number } | undefined;
    for (const [id, feature] of features) {
      if (!id.startsWith("node:")) continue;
      const [x, y] = (feature.geometry as Point).coordinates;
      if (x === undefined || y === undefined) continue;
      const q = map.project([x, y]);
      const dist = Math.hypot(q.x - p.x, q.y - p.y);
      if (dist <= NODE_SNAP_PX && (!best || dist < best.dist)) best = { id, dist };
    }
    if (best) {
      const [x, y] = (features.get(best.id)?.geometry as Point).coordinates;
      return { kind: "node", ref: best.id, point: [x ?? lngLat[0], y ?? lngLat[1]] };
    }
  }

  if (visible.edges) {
    // Cheap lon/lat bounding-box reject before projecting every vertex.
    const padLng = Math.abs(map.unproject([p.x + EDGE_SNAP_PX, p.y]).lng - lngLat[0]);
    const padLat = Math.abs(map.unproject([p.x, p.y + EDGE_SNAP_PX]).lat - lngLat[1]);
    let best: { id: string; dist: number; offset: number; point: LngLat } | undefined;

    for (const [id, feature] of features) {
      if (!id.startsWith("edge:")) continue;
      const coords = (feature.geometry as LineString).coordinates;
      let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
      for (const [x = 0, y = 0] of coords) {
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x);
        minY = Math.min(minY, y);
        maxY = Math.max(maxY, y);
      }
      if (lngLat[0] < minX - padLng || lngLat[0] > maxX + padLng || lngLat[1] < minY - padLat || lngLat[1] > maxY + padLat) continue;

      let along = 0;
      let nearest: { dist: number; metresAlong: number; point: LngLat } | undefined;
      let total = 0;
      for (let i = 1; i < coords.length; i++) total += metres(coords[i - 1] as Position, coords[i] as Position);

      for (let i = 1; i < coords.length; i++) {
        const a = coords[i - 1] as Position;
        const b = coords[i] as Position;
        const pa = map.project([a[0] ?? 0, a[1] ?? 0]);
        const pb = map.project([b[0] ?? 0, b[1] ?? 0]);
        const { dist, t } = pixelDistanceToSegment(p, pa, pb);
        const segment = metres(a, b);
        if (!nearest || dist < nearest.dist) {
          nearest = {
            dist,
            metresAlong: along + t * segment,
            point: [(a[0] ?? 0) + t * ((b[0] ?? 0) - (a[0] ?? 0)), (a[1] ?? 0) + t * ((b[1] ?? 0) - (a[1] ?? 0))],
          };
        }
        along += segment;
      }
      if (nearest && nearest.dist <= EDGE_SNAP_PX && (!best || nearest.dist < best.dist)) {
        best = { id, dist: nearest.dist, offset: total === 0 ? 0 : nearest.metresAlong / total, point: nearest.point };
      }
    }
    if (best) return { kind: "edge", ref: best.id, offset: best.offset, point: best.point };
  }

  return { kind: "point", point: lngLat };
}
