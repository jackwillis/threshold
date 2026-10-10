import type { Map as MapLibreMap, LayerSpecification } from "maplibre-gl";
import { SEASONS, SEASON_TOKENS, type AtlasTokens } from "./tokens";

export const MATERIALS = ["canopy", "water", "meadow"] as const;
export type Material = typeof MATERIALS[number];
export type Treatment = "baseline" | "subtle" | "painterly";
export const MATERIAL_SIZE = 512;
export const MATERIAL_PIXEL_RATIO = 2;

export function initialTreatment(search = location.search): Treatment {
  const value = new URLSearchParams(search).get("materials");
  return value === "baseline" || value === "painterly" ? value : "subtle";
}

export function materialId(material: Material, tokens: AtlasTokens): string {
  return `atlas-${material}-${tokens.canopy.slice(1)}`;
}

/** Load every seasonal image before adding patterned layers; switches then only change paint. */
export async function loadAtlasMaterials(map: MapLibreMap): Promise<void> {
  const images = await Promise.all(SEASONS.flatMap(season => MATERIALS.map(async material => {
    const id = materialId(material, SEASON_TOKENS[season]);
    const image = await map.loadImage(`/assets/materials/${id}.png`);
    return { id, image: image.data };
  })));
  for (const { id, image } of images) if (!map.hasImage(id)) map.addImage(id, image, { pixelRatio: MATERIAL_PIXEL_RATIO });
}

/** Transparent decorative overlays. Existing polygons do the masking; no new geography or sources. */
export function materialLayer(material: Material, t: AtlasTokens, treatment: Treatment): LayerSpecification {
  const strength = treatment === "baseline" ? 0 : treatment === "painterly" ? 0.85 : 0.5;
  return {
    id: `atlas-material-${material}`, type: "fill", source: "context", minzoom: 15.5,
    filter: ["==", ["get", "classification"], material === "water" ? "water" : "park"],
    paint: {
      "fill-pattern": materialId(material, t),
      "fill-opacity": ["interpolate", ["linear"], ["zoom"], 15.5, 0, 17, strength, 19.5, strength],
      // Recolouring should not briefly blend summer and autumn crowns.
      "fill-pattern-transition": { duration: 0 },
    },
  };
}
