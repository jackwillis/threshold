import type { Feature, FeatureCollection, LineString } from "geojson";

type Position = [number, number];
type Segment = { name: string; rank: 1 | 2; coords: Position[] };

const MAJOR = new Set(["primary", "secondary", "primary_link", "secondary_link", "tertiary", "tertiary_link"]);

const key = (p: Position) => `${p[0].toFixed(7)},${p[1].toFixed(7)}`;

/**
 * The imported network is cut at every intersection, so a street's name sits on many short edges, each
 * too short to carry its label. This joins edges of the same name end to end into long lines (stopping
 * where more than one continuation exists) so MapLibre's line-following labels have room.
 * Display only: it never touches the network or the authored data. `rank` 1 is an arterial, 2 anything else.
 */
export function streetLabelLines(edges: FeatureCollection): FeatureCollection<LineString> {
  const byName = new Map<string, Segment[]>();
  for (const f of edges.features) {
    const p = f.properties ?? {};
    if (typeof p.name !== "string" || p.classification !== "street" || f.geometry.type !== "LineString") continue;
    if (p.service) continue; // driveways and parking aisles are not worth a label
    const coords = f.geometry.coordinates as Position[];
    if (coords.length < 2) continue;
    const segment: Segment = { name: p.name, rank: MAJOR.has(String(p.highway)) ? 1 : 2, coords };
    (byName.get(p.name) ?? byName.set(p.name, []).get(p.name)!).push(segment);
  }

  const features: Feature<LineString>[] = [];
  for (const [name, segments] of byName) {
    const ends = new Map<string, number[]>();
    segments.forEach((s, i) => {
      for (const p of [s.coords[0]!, s.coords[s.coords.length - 1]!]) (ends.get(key(p)) ?? ends.set(key(p), []).get(key(p))!).push(i);
    });
    const used = new Set<number>();
    const extend = (line: Position[], atEnd: boolean): void => {
      for (;;) {
        const tip = atEnd ? line[line.length - 1]! : line[0]!;
        const here = ends.get(key(tip)) ?? [];
        if (here.length !== 2) return; // a dead end or a junction of three or more
        const i = here.find((n) => used.has(n) === false);
        if (i === undefined) return;
        used.add(i);
        let coords = segments[i]!.coords;
        const forward = key(coords[0]!) === key(tip);
        if (atEnd) { if (!forward) coords = [...coords].reverse(); line.push(...coords.slice(1)); }
        else { if (forward) coords = [...coords].reverse(); line.unshift(...coords.slice(0, -1)); }
      }
    };
    segments.forEach((s, i) => {
      if (used.has(i)) return;
      used.add(i);
      const line = [...s.coords];
      extend(line, true);
      extend(line, false);
      features.push({ type: "Feature", properties: { name, rank: s.rank }, geometry: { type: "LineString", coordinates: line } });
    });
  }
  return { type: "FeatureCollection", features };
}

type Ring = number[][];
const ringArea = (ring: Ring) => {
  let area = 0;
  for (let i = 0; i < ring.length - 1; i++) area += ring[i]![0]! * ring[i + 1]![1]! - ring[i + 1]![0]! * ring[i]![1]!;
  return Math.abs(area) / 2;
};

function inside(x: number, y: number, ring: Ring): boolean {
  let result = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i]!; const [xj, yj] = ring[j]!;
    if (yi! > y !== yj! > y && x < ((xj! - xi!) * (y - yi!)) / (yj! - yi!) + xi!) result = !result;
  }
  return result;
}

function edgeDistance(x: number, y: number, ring: Ring): number {
  let best = Infinity;
  for (let i = 0; i < ring.length - 1; i++) {
    const [ax, ay] = ring[i]!; const [bx, by] = ring[i + 1]!;
    const dx = bx! - ax!; const dy = by! - ay!; const len2 = dx * dx + dy * dy;
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((x - ax!) * dx + (y - ay!) * dy) / len2));
    best = Math.min(best, Math.hypot(x - (ax! + t * dx), y - (ay! + t * dy)));
  }
  return best;
}

/** A point well inside a polygon ring (an approximate pole of inaccessibility): coarse grid, then two refinements. */
export function labelPoint(ring: Ring): Position {
  const xs = ring.map((p) => p[0]!); const ys = ring.map((p) => p[1]!);
  const scale = Math.cos((((Math.min(...ys) + Math.max(...ys)) / 2) * Math.PI) / 180);
  const flat = ring.map((p): number[] => [p[0]! * scale, p[1]!]);
  let [x0, x1] = [Math.min(...xs) * scale, Math.max(...xs) * scale];
  let [y0, y1] = [Math.min(...ys), Math.max(...ys)];
  let best: [number, number] = [(x0 + x1) / 2, (y0 + y1) / 2];
  let bestD = inside(best[0], best[1], flat) ? edgeDistance(best[0], best[1], flat) : -1;
  const N = 16;
  for (let pass = 0; pass < 3; pass++) {
    const [dx, dy] = [(x1 - x0) / N, (y1 - y0) / N];
    for (let i = 0; i <= N; i++) for (let j = 0; j <= N; j++) {
      const [x, y] = [x0 + i * dx, y0 + j * dy];
      if (!inside(x, y, flat)) continue;
      const d = edgeDistance(x, y, flat);
      if (d > bestD) { bestD = d; best = [x, y]; }
    }
    [x0, x1, y0, y1] = [best[0] - dx * 1.5, best[0] + dx * 1.5, best[1] - dy * 1.5, best[1] + dy * 1.5];
  }
  return [best[0] / scale, best[1]];
}

/**
 * One label point per named park or lake (its largest polygon) and per named building. MapLibre would
 * otherwise repeat a large polygon's label in every tile it spans (Capitol Square showed four times),
 * and designer control over placement is the aim anyway. Display only; the geography is untouched.
 */
export function contextLabelPoints(context: FeatureCollection): FeatureCollection {
  const best = new Map<string, { area: number; point: Position; classification: string; name: string }>();
  let n = 0;
  for (const f of context.features) {
    const p = f.properties ?? {};
    if (typeof p.name !== "string" || !["park", "water", "building"].includes(String(p.classification))) continue;
    const polygons = f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.type === "MultiPolygon" ? f.geometry.coordinates : [];
    for (const rings of polygons) {
      const outer = rings[0];
      if (!outer || outer.length < 4) continue;
      const area = ringArea(outer);
      // Buildings are all kept (each is its own place); parks and lakes keep only their largest piece.
      const key = p.classification === "building" ? `b${n++}` : `${p.classification}:${p.name}`;
      if (area > (best.get(key)?.area ?? -1)) best.set(key, { area, point: labelPoint(outer), classification: String(p.classification), name: p.name });
    }
  }
  return {
    type: "FeatureCollection",
    features: [...best.values()].map((v) => ({ type: "Feature", properties: { name: v.name, classification: v.classification }, geometry: { type: "Point", coordinates: v.point } })),
  };
}
