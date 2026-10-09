import type { Feature, FeatureCollection, LineString, Point } from "geojson";
import type { Props } from "./geo";

type Status = "ok" | "moved" | "missing";

type Location = {
  id: string;
  name: string;
  notes: string;
  anchor: { kind: "node" | "edge" | "point"; ref?: string; point: [number, number]; offset?: number };
};
type Connection = { id: string; from: string; to: string; kind: string; notes: string };
type Closure = { id: string; edge: string; kind: string; reason: string };

export type Authored = { locations: Location[]; connections: Connection[]; closures: Closure[] };
export type RefStatus = Record<string, Status>;

export const EMPTY_AUTHORED: Authored = { locations: [], connections: [], closures: [] };

export type AuthoredLayers = {
  locations: FeatureCollection<Point, Props>;
  connections: FeatureCollection<LineString, Props>;
  closureEdgeIds: string[];
  closures: Map<string, Closure>;
};

/**
 * Builds map features from the server's authored document. Objects whose geography reference is
 * missing stay visible at their recorded position, flagged `detached`.
 */
export function buildAuthored(authored: Authored, status: RefStatus): AuthoredLayers {
  const byId = new Map(authored.locations.map((l) => [l.id, l]));
  const locations: Feature<Point, Props>[] = authored.locations.map((l) => ({
    type: "Feature",
    geometry: { type: "Point", coordinates: l.anchor.point },
    properties: {
      id: l.id,
      classification: "location",
      name: l.name,
      notes: l.notes,
      anchor: l.anchor.kind,
      ref: l.anchor.ref ?? null,
      status: status[l.id] ?? "ok",
    },
  }));

  const connections: Feature<LineString, Props>[] = [];
  for (const c of authored.connections) {
    const from = byId.get(c.from);
    const to = byId.get(c.to);
    if (!from || !to) continue;
    connections.push({
      type: "Feature",
      geometry: { type: "LineString", coordinates: [from.anchor.point, to.anchor.point] },
      properties: { id: c.id, classification: "connection", kind: c.kind, from: c.from, to: c.to, notes: c.notes },
    });
  }

  return {
    locations: { type: "FeatureCollection", features: locations },
    connections: { type: "FeatureCollection", features: connections },
    closureEdgeIds: authored.closures.map((c) => c.edge),
    closures: new Map(authored.closures.map((c) => [c.id, c])),
  };
}
