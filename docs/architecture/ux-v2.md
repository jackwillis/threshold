# Threshold — UX and Story Architecture V2

**Status:** Approved product direction, 2026-10-12. Implementation details require milestone review.

## Product principle

**Studio exposes the authored world; Field Atlas reveals only what the player has encountered.** Places connect geographic position, traversable routes, interactions, discoveries, investigations, and playtesting. Keep the existing Phoenix/LiveView, MapLibre, Terra Draw, Elixir domain rules, PostgreSQL progress, and Classic Atlas aesthetic. Do not turn this into a generic game editor.

## Field Atlas

The designer approved a map-first redesign with a clear hierarchy: **Current Investigation**, current location, one contextual focus area, accessible one-hop movement, and Journal/Menu controls. Keep the map dominant on desktop; on mobile, prefer a compact/expanded sheet preserving usable map space.

A single focus area presents available interactions, open scenes, place descriptions, or recorded outcomes. Scenes open on deliberate player action, not automatically on arrival. Walking away closes a scene without completing it. Keep numbered shortcuts, map markers, touch-accessible movement buttons, validated server-side moves, route animation, and camera limits.

Move turn counts, visited statistics, graph mode, detailed GIS warnings, editor links, and less-used appearance controls out of the normal hierarchy. Preserve visible actionable errors. Correct New Walk confirmation to say that discoveries and completed interactions are also cleared.

Map markers should distinguish ordinary exits, places with authored notes, and available investigations; completed investigations should not look like unread content. Do not add note-read persistence merely to color a marker. Prevent spoilers: unavailable interactions should not be sent to the client.

The full-screen introduction remains a planned narrative feature: warm paper presentation, readable typography, keyboard/reduced-motion accessibility, begin action, new-walk-only lifecycle rather than repeating on reload. No cutscene engine.

## Cases and Journal

**Approved concept:** extend validated `interactions.json` with an optional `cases` collection containing stable IDs, opening text, visibility conditions, authored situation stages, journal entries, and outcomes. Current Investigation is a *summary of what is known*, not directions to the next objective. Derive case and journal views server-side from existing persistent discoveries and completed interactions. No separate quest progress table or rules duplication.

Example (illustrative, **not a final schema**):

```json
{
  "cases": [{
    "id": "case:quiet-hour",
    "title": "The Quiet Hour",
    "summary": "An unexplained signal repeats near the Square.",
    "opens_with": [],
    "stages": [
      {"when": [], "text": "Something is interrupting the receiver."},
      {"when": ["disc:conduit"], "text": "A municipal notice mentions a sealed conduit."}
    ],
    "entries": [{"discovery": "disc:pulse"}, {"discovery": "disc:conduit"}],
    "outcomes": [{"when": "disc:case-complete", "title": "Investigation concluded"}]
  }]
}
```

Select the last eligible stage in authored order and define unambiguous outcome precedence. **Important:** The Quiet Hour returns to the Square after the hatch decision; hatch choices alone must not prematurely mark the case complete. Decide whether to use final interaction completion or a dedicated ending discovery before implementation.

The read-only **Field Journal** should include Cases, Notes (earned clues/documents), and Carried (simple acquired objects). Initial carried items can be presentation metadata on permanent discoveries, but do not assume physical objects can always be modeled as knowledge: dropping, consuming, or trading requires a separate possession model. Initial-item semantics and multi-case pinning remain unapproved. Never serialize unseen stages, undiscovered clues, or endings to player clients.

## Studio

Target workspaces: **Map** (places and geography), **Story** (scenes, choices, discoveries, cases), **Playtest** (the actual game with isolated development state), and secondary **World Data** (import, regeneration, diagnostics). Use contextual validation and a Problems panel instead of a separate validation page.

**Approved: build the first structured Story editor in LiveView.** Reuse domain validation, form components, and player-facing preview. Consider Preact for rich client-owned geographic interactions only if a concrete problem justifies it; do not rewrite the whole frontend.

Target creator journey: select a place → author a two-scene clue chain → define case progression → validate → playtest safely → submit for review. Preserve the existing Map editor until this workflow succeeds.

## Cross-cutting requirements

Honor `AGENTS.md` and `docs/handoff.md`. No schema change or major gameplay system is authorized merely by this design. Preserve focus management, live announcements, Escape behavior, minimum touch targets and reduced-motion presentation. Avoid UI-driven regressions in persistence or movement. Browser-check desktop and narrow mobile layouts; real screen-reader usability needs an actual test. Keep world revisions and authoring save safety under separate explicit review.

## Sequence

1. Player-facing presentation-only Atlas redesign.
2. Approve precise case schema and implement Current Investigation, Journal, then introduction and map markers.
3. LiveView Story authoring and safe validation.
4. Integrated Map → Story → isolated Playtest.
5. Studio information architecture cleanup and World Data separation.

UX work can proceed in parallel with hosting preparation; do not start everything in one PR.
