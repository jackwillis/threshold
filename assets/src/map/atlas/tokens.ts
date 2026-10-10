// Classic Atlas design tokens. Every colour the atlas draws lives here; a season is just a different
// set of values for the same keys. Geometry, layer ids and filters never depend on the season.

export type Season = "spring" | "summer" | "autumn" | "winter";
export const SEASONS: Season[] = ["spring", "summer", "autumn", "winter"];

export type AtlasTokens = {
  ground: string;
  water: string; waterEdge: string;
  park: string; parkEdge: string;
  canopy: string; canopyHighlight: string; canopyPool: string; grass: string; waterPigment: string;
  plaza: string;
  building: string; buildingEdge: string;
  roadFill: string; roadCasing: string;
  path: string;
  // Text inks, each chosen to read on the surface it labels. `halo` is the surface colour behind label outlines.
  ink: string; inkWater: string; inkPark: string; inkMuted: string; halo: string;
  // Movement and place markers. `numeral` is the digit colour on `destination`.
  player: string; destination: string; numeral: string; authored: string; visited: string; route: string;
};

export const SEASON_TOKENS: Record<Season, AtlasTokens> = {
  summer: {
    canopy: "#72915d", canopyHighlight: "#adc48b", canopyPool: "#486748", grass: "#7e9663", waterPigment: "#789eaf",
    ground: "#f3ecd9",
    water: "#bcd6e4", waterEdge: "#97b8cc",
    park: "#c6d8b0", parkEdge: "#a7be8f",
    plaza: "#ece1c6",
    building: "#e3d6bb", buildingEdge: "#b9a784",
    roadFill: "#fcf8ee", roadCasing: "#cbbd9c",
    path: "#a8987a",
    ink: "#43382b", inkWater: "#33566e", inkPark: "#3c5a30", inkMuted: "#6d5f4b", halo: "#f6f0e0",
    player: "#263e37", destination: "#0e6f61", numeral: "#fffdf4", authored: "#b4741a", visited: "#5f7d70", route: "#128d7a",
  },
  spring: {
    canopy: "#81a466", canopyHighlight: "#c1d59d", canopyPool: "#5b804e", grass: "#8ba76a", waterPigment: "#83b1c4",
    ground: "#f4efdc",
    water: "#c3deea", waterEdge: "#9fc2d3",
    park: "#c3dfa6", parkEdge: "#a2c785",
    plaza: "#eee4ca",
    building: "#e6d9c0", buildingEdge: "#bcaa88",
    roadFill: "#fdf9ef", roadCasing: "#cdc09f",
    path: "#a99b7d",
    ink: "#43382b", inkWater: "#335c76", inkPark: "#375e2b", inkMuted: "#6d5f4b", halo: "#f7f2e2",
    player: "#263e37", destination: "#0e6f61", numeral: "#fffdf4", authored: "#b4741a", visited: "#5f7d70", route: "#128d7a",
  },
  autumn: {
    canopy: "#b9914e", canopyHighlight: "#d7b974", canopyPool: "#906943", grass: "#a19760", waterPigment: "#7e9faa",
    ground: "#f1e5cd",
    water: "#b4cbd3", waterEdge: "#8fabb6",
    park: "#d3cb98", parkEdge: "#b8ad78",
    plaza: "#eadcbf",
    building: "#e6d1b3", buildingEdge: "#b79f7a",
    roadFill: "#faf3e4", roadCasing: "#c9b793",
    path: "#a48f6c",
    ink: "#41342a", inkWater: "#2f5361", inkPark: "#6b4a1d", inkMuted: "#6a5844", halo: "#f4ead4",
    player: "#2a3a33", destination: "#0e6a5c", numeral: "#fffdf4", authored: "#a8611a", visited: "#6a7b66", route: "#12806f",
  },
  winter: {
    canopy: "#a5b3a5", canopyHighlight: "#d8e1d6", canopyPool: "#7d928b", grass: "#a1aea0", waterPigment: "#8cabbf",
    ground: "#eef0ee",
    water: "#c3d0da", waterEdge: "#9eb0be",
    park: "#dfe7dd", parkEdge: "#bfcbbc",
    plaza: "#f3f3f0",
    building: "#f8f8f6", buildingEdge: "#aeb4ba",
    roadFill: "#ffffff", roadCasing: "#c4cacf",
    path: "#9ba3aa",
    ink: "#2f3841", inkWater: "#3b586d", inkPark: "#40604a", inkMuted: "#5b6670", halo: "#f4f6f4",
    player: "#233a42", destination: "#0e6577", numeral: "#ffffff", authored: "#a8661a", visited: "#62767c", route: "#12768a",
  },
};

/** Typefaces. The names double as MapLibre `text-font` stacks, so they must match `fonts.ts`. */
export const TYPE = {
  serif: "Atlas Serif",
  serifItalic: "Atlas Serif Italic",
  serifMedium: "Atlas Serif Medium",
  serifSemibold: "Atlas Serif Semibold",
  // HUD and dialogue text is ordinary HTML/CSS, not map text.
  hudSans: 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
} as const;

/** CSS custom properties for HTML/HUD surfaces, so the page and the map share one palette. */
export function cssVariables(tokens: AtlasTokens): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(tokens)) out[`--atlas-${key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`] = value;
  out["--atlas-serif"] = `"${TYPE.serif}", Georgia, serif`;
  out["--atlas-sans"] = TYPE.hudSans;
  return out;
}

// --- Contrast (WCAG relative luminance) -------------------------------------------------------

function luminance(hex: string): number {
  const channel = (i: number) => {
    const v = parseInt(hex.slice(1 + i * 2, 3 + i * 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(0) + 0.7152 * channel(1) + 0.0722 * channel(2);
}

export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}
