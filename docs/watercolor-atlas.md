# Procedural watercolor atlas

October 9, 2026. Independent visual experiment based on `867f01e`, on branch
`feature/watercolor-atlas`. Final worktree: `/home/jack/code/threshold-watercolor`.
No gameplay, GIS, schema, persistence or world-data changes. Integration awaits designer review.

## Recommendation and comparisons

Use **subtle** (the default): illustrated canopy clusters, quiet water pigment clouds and sparse
meadow tufts over the existing seasonal base fills. Buildings, paths, streets, labels and movement
markers retain their precise original rendering. The stronger treatment is available for comparison.

![Summer and autumn: baseline, subtle, painterly](watercolor-atlas/comparison.jpg)

The six comparison originals use the same James Madison Park / Mendota extent, centre
`[-89.3835, 43.0815]`, zoom 17 and 887 × 886 viewport. No authored navigation stops lie inside that
park view, so player usability is demonstrated separately at Capitol Square:

![Player map with numbered destinations](watercolor-atlas/play-summer.jpg)

Additional evidence: [autumn player](watercolor-atlas/play-autumn.jpg),
[420 px mobile](watercolor-atlas/play-mobile.jpg), [zoom 19.5 detail](watercolor-atlas/detail-19.5.jpg),
[spring](watercolor-atlas/spring.jpg), [winter](watercolor-atlas/winter.jpg),
[Monona / B.B. Clarke Beach](watercolor-atlas/monona.jpg).

To compare locally, run the worktree's app against a **scratch world copy** and, for `/play`, a
scratch database on the disposable PostgreSQL service at port 5433. Open:

```text
/atlas?season=summer&materials=baseline&lng=-89.3835&lat=43.0815&zoom=17
/atlas?season=summer&materials=subtle&lng=-89.3835&lat=43.0815&zoom=17
/atlas?season=summer&materials=painterly&lng=-89.3835&lat=43.0815&zoom=17
```

Replace `summer` with `autumn`. `/play` also accepts `?materials=baseline|subtle|painterly`.
Treatment is a URL-only review preference; season continues to use the existing switcher and
storage. Neither is sent to the server or saved as gameplay progress.

## Implementation

- `assets/scripts/watercolor.ts`: seeded pure TypeScript rasterizer and PNG encoder using Bun's
  existing zlib support. No new packages, platform canvas, remote textures, fonts or services.
- `assets/scripts/build-materials.ts`: builds or checks the twelve checked-in PNGs in
  `priv/static/assets/materials/`. `make assets` regenerates them; `make check-assets` requires
  byte-identical files. Direct commands: `cd assets && bun run materials` / `bun run materials:check`.
- `assets/src/map/atlas/materials.ts`: loads all images before layers are added, then uses native
  `fill-pattern` overlays. 512 × 512 PNGs registered at pixel ratio 2 (256 logical pixels).
- Seasonal pigment colours live in the existing `tokens.ts`. Seed, density and crown radius live
  in `PARAMETERS`. Geometry and coverage are identical across seasons. Autumn uses ochre, lighter
  gold and brown pooling; winter is a desaturated impression, with a bare-tree material deferred.
- The same `atlasLayers` stack serves `/atlas` and `/play`; `applySeason` repaints existing layers
  in place and preserves comparison strength. A season chosen during asynchronous startup is
  honoured when the layers are finally installed.

Canopies use irregular lobed crowns, asymmetric highlights and broken pooling rims in small,
uneven clusters. Stamps wrap on a torus, including pigment grain. Water uses several periodic
smooth pigment fields; meadow adds tiny tapered blade clusters to a faint wash. Small pigment
quantisation and PNG Sub filtering keep the assets compact. The transparent patterns are masked
by the existing polygons, beneath outlines, buildings and all navigation content.

The pinned geography exposes a broad `park` class, not a reliable tree-versus-lawn subdivision.
Both meadow and sparse canopy are therefore illustrative layers on parks. They are **not surveyed
tree locations**. Water uses only `classification=water`. No data is inferred, changed or acquired.
Adding finer vegetation classifications requires a separate GIS decision.

## Verification and performance observations

`THRESHOLD_TEST_DATABASE_URL=postgres://threshold:threshold_local@localhost:5433/threshold_test make check`
passed, including database tests: **301 Elixir, 42 Bun, 38 Python tests**, TypeScript, formatter,
warnings-as-errors, ruff, world validation and byte-identical geographic rebuild. Existing Shapely
transform deprecation warnings remain. Targeted tests cover deterministic pixels/PNG encoding,
checked-in assets, seasonal coverage, corner wrapping, periodic wash value/slope, layering and
paint-only season/treatment changes.

Browser verification used the Codex in-app browser, `/tmp/threshold-watercolor-worlds` copied
from the current Madison data and `threshold_watercolor_scratch_test` on port 5433. Existing
migrations were applied **only** to that disposable scratch database. Verified:

- All four season materials and the player map initialize; Mendota and Monona render.
- Summer/autumn comparison views, park names, building footprints, street labels and numbered
  destinations remain legible. No visible tile-edge seams in the inspected views.
- Each season switch preserves the complete server `data-state` byte for byte, including turn,
  point, visited locations, moves and camera instruction. Keyboard `1` advanced turn 0 → 1;
  reload restored turn 1 and two visited places. A mobile panel move advanced to turn 2.
- 420 × 900 presentation retains the map, season controls and movement panel. Recenter after
  resizing fits the numbered destinations; automatic camera refitting on viewport resize remains
  the existing behaviour. Touch was not tested.
- Native zoom-control transition 17 → 18, panning and a separate 19.5 detail view were exercised.
  No obvious stalls appeared in these interactions. This is a qualitative observation, **not an
  FPS benchmark**; screenshot automation cannot establish animation frame pacing.
- Final material assets total **551,023 bytes** (about 538 KiB), with no added dependencies.
  Twelve decoded RGBA images occupy **12 MiB** before MapLibre atlas/GPU overhead, which was not
  measured. The current-season patterns also occupy per-tile MapLibre atlases. Only three added
  fill layers; no texture generation or custom shader runs in the browser. A local asset rebuild
  took roughly 1.2 seconds including texture generation and bundling.

A `MutationObserver.observe` console error also appeared on the original baseline before changes
and in the final browser session; its source was not identified. No final pattern-image/style load
warnings were observed. Initial incomplete development builds emitted missing-image warnings;
those were resolved before final capture. No claim of an entirely clean browser console is made.

## Limitations and next decisions

Native patterns follow MapLibre's integer-zoom scale crossfade. During zoom they can softly change
scale/arrangement; **individual crowns do not retain fixed geographic positions**. They remain
anchored while panning. Repetition can be recognised on a broad uniform park or lake when looking
for it, particularly at the stronger setting. Subtle opacity is the recommended compromise. Native
patterns are sufficient for this decorative prototype; if fixed positions become a requirement,
the smallest next experiment is a display-only, seeded canopy symbol source clipped to park
polygons. Do not change routing, imported data or renderer to solve it.

Winter is recoloured canopy, not bare branches or snow. There is no shoreline edge pooling,
paper-screen filter, wetlands, rooftop wash or topography in this first implementation. No actual
mobile hardware, touch/pinch, GPU memory capture, formal FPS profiling or cross-browser matrix
was verified. PNG byte reproducibility was verified with the installed Bun 1.4.2/zlib; a different
compressor version may require regenerating the checked-in files despite identical raster pixels.

## Files and integration

Changed: `Makefile`, `assets/build.ts`, `assets/package.json`, `assets/tsconfig.json`, the two atlas
hooks, `atlas/season.ts`, `atlas/style.ts`, `atlas/tokens.ts`. Added: the two generator scripts,
`atlas/materials.ts`, `atlas/materials.test.ts`, twelve PNGs, this memo and browser evidence.
No new geographic files, migrations or Elixir modules.

After designer approval, inspect changes to the two hooks and the shared atlas files against
Claude's current work. Preserve both implementations if they diverged. On an integration branch
in a clean checkout, use `git cherry-pick feature/watercolor-atlas`, then `make assets` and the full
PostgreSQL-enabled `make check`. Do not run a merge or cherry-pick over the designer's current
uncommitted world work. No merge, push or deployment has been performed.

At final review, primary `main` had advanced to `0770c6b`. Its new commits modify `assets/src/app.ts`,
`PlayLive`, interaction tests and the revisions proposal; none overlap this experiment's changed
files. The primary checkout also has in-progress `PlayLive` and `atlas.css` edits. Those are
untouched; screenshots show the committed `867f01e` presentation plus this branch, so compare
the result with the designer's latest CSS before integration.
