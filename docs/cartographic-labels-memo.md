# Threshold Studio V2 — Curved Street Labels

**Status:** Additional frontend V2 design requirement  
**Area:** Cartographic authoring and typography  
**Priority:** After the core Studio editing workflow is functional

Add a dedicated **Cartographic Labels** layer to Threshold Studio V2.

The designer should be able to create custom text labels for streets, alleys, paths, and other geographic features using editable Bézier curves.

### Requirements

- Create, select, edit, and delete custom geographic labels.
- Enter arbitrary label text.
- Draw and adjust a Bézier baseline with draggable endpoints and control handles.
- Store control points as geographic coordinates.
- Provide an optional **Follow street** action that initializes a label from existing geographic geometry.
- Configure text size, spacing, color, and optional capitalization.
- Configure minimum and maximum display zoom.
- Keep labels legible and correctly oriented.
- Display labels in both Studio and Field Atlas.
- Support hiding and showing the label layer in Studio.
- Preserve authored labels when the underlying generated street graph changes.
- Never modify movement topology when editing a label.

Keep cartographic labels separate from authored game locations and navigation connections.

For the first implementation, evaluate sampling the Bézier curve into a GeoJSON LineString and using MapLibre line-placement text.

Test whether MapLibre's label collision handling, glyph rendering, and placement behavior offer sufficient artistic control.

If precise typography cannot be achieved through MapLibre alone, document the limitation before introducing a custom renderer.

Prefer designer-controlled placement over automatic relabeling.

Keep the data schema simple and versioned, and make sure existing authored worlds continue to load without requiring destructive migration.

**Design goal:** Let the creator produce beautiful, carefully composed street labels that feel like part of a hand-crafted municipal atlas rather than a generic navigation map.
