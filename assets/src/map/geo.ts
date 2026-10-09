import type { Feature, FeatureCollection, Geometry, Polygon, Position } from "geojson";

export type Bounds = [number, number, number, number];
export type Props = Record<string, unknown>;
export type Feat = Feature<Geometry, Props>;

export function boundsOf(geometry: Geometry): Bounds {
  const out: Bounds = [Infinity, Infinity, -Infinity, -Infinity];
  const visit = (c: unknown): void => {
    if (Array.isArray(c) && typeof c[0] === "number") {
      const [x, y] = c as Position;
      if (x !== undefined && y !== undefined) {
        out[0] = Math.min(out[0], x);
        out[1] = Math.min(out[1], y);
        out[2] = Math.max(out[2], x);
        out[3] = Math.max(out[3], y);
      }
    } else if (Array.isArray(c)) {
      c.forEach(visit);
    }
  };
  if (geometry.type !== "GeometryCollection") visit(geometry.coordinates);
  return out;
}

/** A polygon covering the whole world with the boundary cut out, to dim the buffer area. */
export function outsideMask(boundary: Polygon): Feature<Polygon> {
  const world: Position[] = [[-180, -85], [180, -85], [180, 85], [-180, 85], [-180, -85]];
  const holes = boundary.coordinates.map((ring) => [...ring].reverse());
  return { type: "Feature", properties: {}, geometry: { type: "Polygon", coordinates: [world, ...holes] } };
}

/** Index features by their `id` property so clicks resolve to the original (unstringified) properties. */
export function indexFeatures(collection: FeatureCollection<Geometry, Props>, into: Map<string, Feat>): void {
  for (const feature of collection.features) {
    const id = feature.properties?.id;
    if (typeof id === "string") into.set(id, feature);
  }
}
