import { describe, expect, test } from "bun:test";
import { inflateSync } from "node:zlib";
import { readFile } from "node:fs/promises";
import { Tile, crown, generateMaterial, grain, png, washAt, PARAMETERS } from "../../../scripts/watercolor";
import { SEASONS, SEASON_TOKENS } from "./tokens";
import { MATERIALS, materialId, initialTreatment, MATERIAL_PIXEL_RATIO, MATERIAL_SIZE } from "./materials";
import { applySeason, atlasLayers, movementLayers } from "./style";
import type { Map as MapLibreMap } from "maplibre-gl";

const t = SEASON_TOKENS.summer;
describe("watercolor materials", () => {
  test("fixed seed produces identical RGBA and checked-in PNGs in every season", async () => {
    for (const season of SEASONS) for (const material of MATERIALS) {
      const tokens = SEASON_TOKENS[season];
      const first = generateMaterial(material, tokens);
      expect(first.data).toEqual(generateMaterial(material, tokens).data);
      const encoded = png(first);
      expect(encoded).toEqual(await readFile(new URL(`../../../../priv/static/assets/materials/${materialId(material, tokens)}.png`, import.meta.url)));
      // Decode IDAT to prove the PNG contains exactly the raster, including transparent pixels.
      const compressedLength = encoded.readUInt32BE(33);
      const rows = inflateSync(encoded.subarray(41, 41 + compressedLength));
      for (let y = 0; y < first.size; y++) {
        expect(rows[y * (first.size * 4 + 1)]).toBe(1);
        const row = Buffer.from(rows.subarray(y * (first.size * 4 + 1) + 1, (y + 1) * (first.size * 4 + 1)));
        for (let x = 4; x < row.length; x++) row[x] = (row[x]! + row[x - 4]!) & 255;
        expect(row).toEqual(Buffer.from(first.data.subarray(y * first.size * 4, (y + 1) * first.size * 4)));
      }
    }
  });
  test("seed changes canopy arrangement; seasonal recolouring preserves coverage", () => {
    const summer = generateMaterial("canopy", t);
    expect(summer.data).not.toEqual(generateMaterial("canopy", t, PARAMETERS.seed + 1).data);
    const alpha = (data: Uint8Array) => data.filter((_, i) => i % 4 === 3);
    for (const season of SEASONS) expect(alpha(generateMaterial("canopy", SEASON_TOKENS[season]).data)).toEqual(alpha(summer.data));
    const coverage = alpha(summer.data).filter(a => a > 0).length / (summer.size ** 2);
    expect(coverage).toBeGreaterThan(0.1); expect(coverage).toBeLessThan(0.4);
  });
  test("crown rims, highlights and grain wrap exactly across corners", () => {
    const a = new Tile(64); const b = new Tile(64);
    const colors: [number, number, number][] = [[80, 120, 70], [170, 190, 130], [55, 90, 60]];
    crown(a, 0, 1, 14, 1.2, colors, 42);
    crown(b, 64, 65, 14, 1.2, colors, 42);
    expect(a.data).toEqual(b.data);
    expect(a.data[3]).toBeGreaterThan(0);
    expect(a.data[(64 * 64 - 1) * 4 + 3]).toBeGreaterThan(0);
    expect(grain(0, 0, 64, 42)).toBe(grain(64, 64, 64, 42));
  });
  test("water wash is periodic in value and slope", () => {
    for (let i = 0; i < 512; i += 13) {
      expect(washAt(0, i, 512)).toBeCloseTo(washAt(512, i, 512), 12);
      expect(washAt(i, 0, 512)).toBeCloseTo(washAt(i, 512, 512), 12);
      const eps = 0.001;
      expect(washAt(eps, i, 512) - washAt(-eps, i, 512)).toBeCloseTo(washAt(512 + eps, i, 512) - washAt(512 - eps, i, 512), 12);
    }
  });
  test("tiles are power-of-two, retina resolution with bounded memory", () => {
    expect(MATERIAL_SIZE & (MATERIAL_SIZE - 1)).toBe(0);
    expect(MATERIAL_SIZE / MATERIAL_PIXEL_RATIO).toBe(256);
    expect(MATERIAL_SIZE ** 2 * 4 * SEASONS.length * MATERIALS.length).toBe(12 * 1024 * 1024);
  });
});
describe("material style", () => {
  test("comparison strengths change paint only and stay beneath buildings and labels", () => {
    const structure = (layers: ReturnType<typeof atlasLayers>) => layers.map(l => ({ ...l, paint: undefined }));
    const base = atlasLayers(t, "baseline");
    for (const treatment of ["subtle", "painterly"] as const) {
      expect(structure(atlasLayers(t, treatment))).toEqual(structure(base));
    }
    const ids = base.map(l => l.id);
    for (const material of MATERIALS) {
      expect(ids.indexOf(`atlas-material-${material}`)).toBeLessThan(ids.indexOf("ctx-building"));
      expect(ids.indexOf(`atlas-material-${material}`)).toBeLessThan(ids.indexOf("label-street"));
    }
    expect(initialTreatment("?materials=baseline")).toBe("baseline");
    expect(initialTreatment("?materials=painterly")).toBe("painterly");
    expect(initialTreatment("?materials=unknown")).toBe("subtle");
  });
  test("season switches only repaint existing layers and retain the chosen strength", () => {
    const calls: [string, string, unknown][] = [];
    const map = { getLayer: (id: string) => ({ id }), setPaintProperty: (id: string, key: string, value: unknown) => calls.push([id, key, value]) } as unknown as MapLibreMap;
    applySeason(map, SEASON_TOKENS.autumn, "painterly");
    const layers = [...atlasLayers(SEASON_TOKENS.autumn, "painterly"), ...movementLayers(SEASON_TOKENS.autumn)];
    for (const layer of layers) for (const [key, value] of Object.entries((layer as { paint?: Record<string, unknown> }).paint ?? {})) expect(calls).toContainEqual([layer.id, key, value]);
  });
});
