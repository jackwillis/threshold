# Classic Atlas: typography decision and first baseline

Date: October 9, 2026. Status: decided, prototyped at `/atlas` and applied to `/play` (October 9, 2026). The editor still uses its diagnostic style.

## Decision

- **Renderer:** MapLibre 5.24 stays. No upgrade to 6 is needed.
- **Map text:** native MapLibre symbol layers, using **locally bundled font faces, with no glyph PBFs and no glyph server.**
- **Typeface:** EB Garamond (SIL Open Font License, via `@fontsource/eb-garamond`): regular, italic, medium and semibold, Latin subset, 4 woff2 files (about 95 KB). `bun build.ts` copies them to `/assets/fonts`.
- **HUD and dialogue:** ordinary HTML/CSS. The same faces are available to CSS (`--atlas-serif`); interface text uses the system sans stack. No map text pipeline is involved.
- **Curved and designer labels:** native line-placement labels first. Evidence below; a Canvas overlay is not needed for this baseline.

## What MapLibre 5.24 does (verified in `maplibre-gl-dev.js` and in Firefox)

If a style declares **no `glyphs` URL**, MapLibre does not request glyph PBFs at all. It draws every glyph itself with TinySDF at 2x resolution, using the layer's `text-font` entries as a CSS font-family list, and weight/style are sniffed from the **name** of the first entry ("... Italic", "... Medium", "... Semibold"). This was previously documented only for CJK (`localIdeographFontFamily`); it applies to all text when the style opts out of server fonts. So the earlier assumption that offline style meant no labels was out of date.

So: faces are registered under names that encode weight and style (`Atlas Serif`, `Atlas Serif Italic`, `Atlas Serif Medium`, `Atlas Serif Semibold`; `assets/src/map/atlas/fonts.ts`), and `text-font: ["Atlas Serif Italic"]` picks one.

## Limitations found

1. **Await the fonts before the map first needs text.** MapLibre caches every glyph it draws; a glyph drawn in a fallback font before the face loads stays wrong. `loadAtlasFonts()` must resolve first (the prototype does this).
2. **All or nothing per style.** With no `glyphs` URL every layer's text is drawn locally; PBF fontstacks cannot be mixed in.
3. **No kerning, ligatures or OpenType features.** Each character is drawn alone and positioned by its advance. Mixed-case labels lack pair kerning ("Wa", "Te"). Spaced capitals (the arterial labels) are unaffected and look right; at 10-11 px lowercase it is visible if you look for it. Small caps and old-style numerals are not available; numerals on markers render lining, which suits them.
4. **Latin subset only.** Latin-1 plus common punctuation. Other characters fall back to the generic sans-serif. `latin-ext` can be added if names need it.
5. **Large polygons repeat their label in every tile they span** (Capitol Square appeared four times). The prototype computes one label point per named park, lake and building (`contextLabelPoints`) and labels those points instead. Same hand-placed spirit the labels memo wants.
6. **Street names live on short edges** (the network is cut at every intersection), too short to carry text. `streetLabelLines` joins same-named edges into long lines for display only (stopping at junctions); the network is untouched.
7. **Line labels repeat at `symbol-spacing`.** A designer-placed Bezier label needs a large spacing to appear once, and MapLibre, not the designer, chooses where along the line the text sits and how it is stretched. Size and letter-spacing are the available fitting controls; there is no "fit text to curve". That is the gap a future Canvas/WebGL label renderer would close; not needed yet.
8. **Collisions:** MapLibre hides labels that collide; the player marker is a circle layer and is not a collision participant, so it can sit over a label (the Capitol label under the player marker). Acceptable now; revisit with marker/label priorities.
9. **Not measured:** first-draw cost of many new glyphs on the main thread, and mobile rendering.

## Bezier-label evaluation (feasibility only)

A cubic Bezier sampled to 61 points as a GeoJSON LineString, labelled with `symbol-placement: line` in italic Garamond at 20 px with 0.12 em tracking, follows the S-curve cleanly through the strong bend (`docs/atlas-prototype/bezier-label-test.png`; built ad hoc in the page, not committed code). It repeated three times at the default spacing (limitation 7). The Studio labels workflow, storage schema and editing UI are not built.

## Token system

`assets/src/map/atlas/tokens.ts` holds every colour as a token with the same keys for `spring`, `summer`, `autumn` and `winter`, plus type names and a `cssVariables()` export that the page uses for the HUD. `style.ts` builds the layer stack from tokens: ids, sources, filters and layout are identical in every season; only paint changes, and `applySeason(map, tokens)` re-paints in place (no rebuild). Bun tests assert that structure is identical across seasons, that every colour is a plain token, and that text and markers meet contrast minimums against each season's ground, parks and water (this caught three failing label colours while building it).

## The prototype

`/atlas` (LiveView `AtlasLive` plus the `AtlasPrototype` hook): real Madison geography from the world endpoints (clipped by bbox), warm ivory ground, sage parks, pale blue lakes, building footprints with named buildings in italic, restrained pale roads with fine casings, dashed paths, arterial labels in spaced capitals, minor streets in roman, one-hop numbered markers (numbers run clockwise from north) computed from the authored connections, a season switcher, and `?season=`, `?lng=&lat=&zoom=`, `?at=<loc id>` parameters. Clicking a numbered marker moves the player to that place. It is a visual study: no rules run, nothing is saved, and `/play` is unchanged. Screenshots: `docs/atlas-prototype/`.

## Applied to `/play`

`player_map.ts` now builds its layers from the same `atlasLayers`/`movementLayers`, `street-labels` and `context-labels` sources and `season.ts` as the prototype; the old inline layer set and the DOM numeral markers are gone (numerals are a native `move-key` text layer, so they scale and stay in the map's own collision-free path). Movement, numbering, camera limits, the keyboard handler, the panel and server validation are untouched. A season switcher sits in an `#play-chrome` block that LiveView does not patch; its buttons have no `phx-click`, season is remembered in `localStorage` (and `?season=`) and never reaches the server, progress or saves. `updated()` repaints the chrome after a patch. Verified in headless Firefox against a scratch world and a scratch PostgreSQL database: start, season switch (turn, visited, moves, centre and zoom unchanged), key `1` move, reload restoring the saved turn, a panel-button move after switching season, and a 420 px wide layout. Reduced motion, touch and screen readers were not separately tested; the panel and its buttons are unchanged, markers remain `aria-hidden` map content as before.

## Not done (for later increments)

Applying the style to the editor; contours and relief; seasonal overlay layers (snow wash, leaf tint); radio overlay; Studio labels layer; building shadows; label priority against markers; the glyph question for non-Latin names.
