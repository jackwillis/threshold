// Small offline rasterizer. All stamps and grain live on a torus: crossing an edge continues on
// the opposite edge, including highlights and pooling. RGBA is straight alpha, as PNG expects.
import { deflateSync } from "node:zlib";
import type { AtlasTokens } from "../src/map/atlas/tokens";
import { MATERIAL_SIZE, type Material } from "../src/map/atlas/materials";

export const PARAMETERS = { seed: 0x41544c53, size: MATERIAL_SIZE, clusters: 32, crownRadius: [10, 17] as const, grassMarks: 260 };
type RGB = [number, number, number];
const rgb = (hex: string): RGB => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)) as RGB;
const wrap = (n: number, size: number) => ((n % size) + size) % size;
export function random(seed: number): () => number {
  let state = seed >>> 0 || 1;
  return () => {
    state ^= state << 13; state ^= state >>> 17; state ^= state << 5;
    return (state >>> 0) / 4294967296;
  };
}

export class Tile {
  readonly data: Uint8Array;
  constructor(readonly size: number) { this.data = new Uint8Array(size * size * 4); }
  blend(x: number, y: number, color: RGB, opacity: number): void {
    const i = (wrap(y, this.size) * this.size + wrap(x, this.size)) * 4;
    const a = Math.max(0, Math.min(1, opacity));
    const old = this.data[i + 3]! / 255; const out = a + old * (1 - a);
    if (!out) return;
    for (let c = 0; c < 3; c++) this.data[i + c] = Math.round((color[c]! * a + this.data[i + c]! * old * (1 - a)) / out);
    this.data[i + 3] = Math.round(out * 255);
  }
}

// Periodic fine pigment grain, independent of stamp order or season. No discontinuous tile edges.
export function grain(x: number, y: number, size: number, seed: number): number {
  let h = (wrap(x, size) + wrap(y, size) * size) ^ seed;
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b); h = Math.imul(h ^ (h >>> 16), 0x45d9f3b);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/** Feathered irregular crown with an asymmetric light wash and a broken pooling rim. */
export function crown(tile: Tile, x: number, y: number, radius: number, phase: number, colors: RGB[], seed: number): void {
  const reach = Math.ceil(radius * 1.35);
  for (let dy = -reach; dy <= reach; dy++) for (let dx = -reach; dx <= reach; dx++) {
    const angle = Math.atan2(dy, dx);
    const edge = radius * (1 + 0.13 * Math.sin(5 * angle + phase) + 0.08 * Math.cos(3 * angle - phase) + 0.04 * Math.sin(9 * angle + phase));
    const d = Math.hypot(dx, dy) / edge;
    if (d > 1.07) continue;
    const g = grain(Math.floor((x + dx) / 2), Math.floor((y + dy) / 2), tile.size / 2, seed);
    const feather = Math.min(1, Math.max(0, (1.07 - d) * edge / 2.5));
    const wash = (0.28 + 0.17 * g + 0.12 * Math.sin(dx * 0.22 + phase) * Math.cos(dy * 0.17)) * feather;
    tile.blend(x + dx, y + dy, colors[0]!, wash);
    // Gentle northwest light; no hard stroke around every tree.
    const light = Math.max(0, 1 - Math.hypot(dx + radius * 0.25, dy + radius * 0.3) / (radius * 0.8));
    tile.blend(x + dx, y + dy, colors[1]!, light * 0.4 * feather);
    const pool = Math.exp(-(((d - 0.84) / 0.11) ** 2)) * (0.5 + 0.5 * Math.sin(angle * 3 + phase));
    tile.blend(x + dx, y + dy, colors[2]!, pool * 0.22 * feather * (0.7 + g * 0.3));
  }
}

export function generateMaterial(material: Material, t: AtlasTokens, seed = PARAMETERS.seed): Tile {
  const tile = new Tile(PARAMETERS.size); const next = random(seed);
  if (material === "canopy") {
    const colors = [rgb(t.canopy), rgb(t.canopyHighlight), rgb(t.canopyPool)];
    for (let cluster = 0; cluster < PARAMETERS.clusters; cluster++) {
      const cx = next() * tile.size; const cy = next() * tile.size;
      const count = 2 + Math.floor(next() * 4);
      for (let i = 0; i < count; i++) {
        const angle = next() * Math.PI * 2; const offset = next() * 33;
        const radius = PARAMETERS.crownRadius[0] + next() * (PARAMETERS.crownRadius[1] - PARAMETERS.crownRadius[0]);
        crown(tile, Math.round(cx + Math.cos(angle) * offset), Math.round(cy + Math.sin(angle) * offset), radius, next() * 6.28, colors, seed);
      }
    }
  }
  if (material === "water" || material === "meadow") {
    const color = rgb(material === "water" ? t.waterPigment : t.grass);
    for (let y = 0; y < tile.size; y++) for (let x = 0; x < tile.size; x++) {
      const wash = washAt(x, y, tile.size);
      const g = washAt(x * 16, y * 16, tile.size);
      const opacity = material === "water" ? (0.025 + wash * 0.15) * (0.85 + g * 0.15) : wash * 0.045;
      tile.blend(x, y, color, opacity);
    }
    if (material === "meadow") for (let i = 0; i < PARAMETERS.grassMarks; i++) {
      const x = next() * tile.size; const y = next() * tile.size;
      for (let blade = 0; blade < 3; blade++) {
        const length = 2 + next() * 3;
        bladeStroke(tile, x, y, x + (blade - 1) * 2.4, y - length, color);
      }
    }
  }
  // Four-step quantisation removes invisible sub-pixel pigment differences and keeps files small.
  for (let i = 0; i < tile.data.length; i++) tile.data[i] = Math.min(255, Math.round(tile.data[i]! / 4) * 4);
  return tile;
}

/** Broad pigment clouds with integer wave vectors: the value and slope match at both edges. */
export function washAt(x: number, y: number, size: number): number {
  const u = x * Math.PI * 2 / size; const v = y * Math.PI * 2 / size;
  return (Math.sin(2 * u + v + 0.8) * 0.4 + Math.cos(u - 3 * v + 1.7) * 0.3 + Math.sin(5 * u + 4 * v + 2.2) * 0.18 + Math.cos(11 * u - 7 * v) * 0.12 + 1) / 2;
}
function bladeStroke(tile: Tile, ax: number, ay: number, bx: number, by: number, color: RGB): void {
  const dx = bx - ax; const dy = by - ay; const len2 = dx * dx + dy * dy;
  for (let y = Math.floor(by - 1); y <= Math.ceil(ay + 1); y++) for (let x = Math.floor(Math.min(ax, bx) - 1); x <= Math.ceil(Math.max(ax, bx) + 1); x++) {
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / len2));
    const distance = Math.hypot(x - ax - t * dx, y - ay - t * dy);
    tile.blend(x, y, color, Math.max(0, 1 - distance) * 0.28 * (1 - t * 0.45));
  }
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const b of bytes) {
    crc ^= b;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(name: string, data: Uint8Array): Buffer {
  const type = Buffer.from(name); const out = Buffer.alloc(data.length + 12);
  out.writeUInt32BE(data.length); out.set(type, 4); out.set(data, 8);
  out.writeUInt32BE(crc32(Buffer.concat([type, data])), data.length + 8);
  return out;
}
/** Fixed PNG encoding: no timestamps, platform fonts, canvas or external image dependency. */
export function png(tile: Tile): Buffer {
  const header = Buffer.alloc(13); header.writeUInt32BE(tile.size); header.writeUInt32BE(tile.size, 4);
  header[8] = 8; header[9] = 6; // 8-bit RGBA
  const rows = Buffer.alloc((tile.size * 4 + 1) * tile.size);
  for (let y = 0; y < tile.size; y++) {
    const row = y * (tile.size * 4 + 1); rows[row] = 1; // PNG Sub filter
    for (let x = 0; x < tile.size * 4; x++) {
      const i = y * tile.size * 4 + x;
      rows[row + 1 + x] = (tile.data[i]! - (x >= 4 ? tile.data[i - 4]! : 0)) & 255;
    }
  }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header), chunk("IDAT", deflateSync(rows, { level: 9 })), chunk("IEND", new Uint8Array())]);
}
