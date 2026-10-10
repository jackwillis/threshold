import { TYPE } from "./tokens";

// EB Garamond (SIL Open Font License), shipped in the bundle from @fontsource and copied to
// /assets/fonts by `bun build.ts`. MapLibre 5.x draws map text itself with these faces when a style
// declares no `glyphs` URL, so no glyph PBFs and no network are involved.
//
// MapLibre reads weight and style from the *name* of the first `text-font` entry ("... Italic",
// "... Medium", "... Semibold"), so each face is registered under that name.
const FACES: { family: string; file: string; weight: string; style: string }[] = [
  { family: TYPE.serif, file: "eb-garamond-latin-400-normal.woff2", weight: "400", style: "normal" },
  { family: TYPE.serifItalic, file: "eb-garamond-latin-400-italic.woff2", weight: "400", style: "italic" },
  { family: TYPE.serifMedium, file: "eb-garamond-latin-500-normal.woff2", weight: "500", style: "normal" },
  { family: TYPE.serifSemibold, file: "eb-garamond-latin-600-normal.woff2", weight: "600", style: "normal" },
];

let loading: Promise<void> | undefined;

/**
 * Loads the atlas faces into `document.fonts`. Await this before the map first needs text: MapLibre
 * caches every glyph it draws, so a glyph drawn in a fallback font before the face loads would stay wrong.
 */
export function loadAtlasFonts(base = "/assets/fonts"): Promise<void> {
  loading ??= Promise.all(
    FACES.map(async ({ family, file, weight, style }) => {
      const face = new FontFace(family, `url(${base}/${file})`, { weight, style });
      document.fonts.add(await face.load());
    }),
  ).then(() => undefined);
  return loading;
}
