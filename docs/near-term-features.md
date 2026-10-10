# Near-term gameplay and UI features

Date: October 10, 2026. Status: **requirements recorded from the designer; nothing implemented, and no new gameplay system is authorized yet.** The next session begins with the designer's own playthrough of *The Quiet Hour* ([madison-mystery-proposal.md](madison-mystery-proposal.md)), then decides how the introduction and the Field Journal should work. Context: [current-design.md](current-design.md), [gameplay-interactions.md](gameplay-interactions.md), [handoff.md](handoff.md).

Shared constraints: classic Atlas look in all four seasons, keyboard and mobile accessibility, reduced-motion support, no change to movement or discovery semantics, the server stays authoritative, and the designer's authored world and existing saves are preserved.

## 1. Full-screen narrative introduction

A full-screen (or nearly full-screen) overlay shown when a player **begins a new walk**, before Field Atlas is revealed. It establishes setting, atmosphere and premise, like the opening passage of a mystery game or visual novel, and must not read as a tutorial pop-up.

- **For *The Quiet Hour*:** an ordinary afternoon in Madison; the player carrying an unfamiliar radio receiver; a strange recurring signal; a reason to begin at the Square.
- **Presentation:** warm Classic Atlas paper colors, readable serif typography, short paragraphs revealed at a deliberate pace, a clear Continue / Begin Investigation action, an optional subtle illustration or cartographic background, no elaborate animation.
- **Behaviour:** shown for a new walk, **not on every page reload**. Later chapter introductions and major story transitions may reuse the same presentation component. **No generalized cutscene engine.**
- **Accessibility:** focus moves into the overlay and returns to the map afterwards, Escape and the Continue button both proceed, the text is available at once to anyone who does not want the paced reveal (and with reduced motion), the overlay is a real labelled dialog on small screens, and the map is not reachable by keyboard behind it.
- **Open design questions for the designer:** where the text lives (a per-world authored `intro` in a new file or inside `interactions.json`), whether "has seen the introduction" is stored with the session (a boolean on the saved walk, cleared by New walk, so a reload does not repeat it) or only in the browser, and whether each walk or each case gets one.

## 2. Field Journal

A persistent place to understand what the player is investigating. The designer's term is **Field Journal**; investigations (cases) live inside it. This also replaces the earlier "Field Notes" idea.

It should eventually show:

- **Active investigations:** the current case, a short description of the situation, known leads, relevant locations once discovered, and a clear distinction between unresolved and completed.
- **Recorded discoveries:** clues, what characters said, documents and signals, all re-readable.
- **Completed cases:** investigations concluded, a short record of the outcome, possibly different endings depending on choices.

For *The Quiet Hour* an entry might begin **The Quiet Hour**: *A receiver has begun ticking at regular intervals near the Capitol Square. The source is unknown.* After the library the journal could record the 1974 works bulletin; after the hatch it could show the outcome that matches the player's decision.

**Principle:** the journal helps the player remember and reason; it does not tell them where to go next. No objective markers, no automatic route guidance, and nothing the player has not discovered.

**Scope rule:** derive content from existing saved state (declared discoveries and completed interactions) plus authored metadata. No quest scripting language, inventory engine or separate progression system. Discoveries alone may not be a complete quest model, so cases need their own small declarative definition, proposed below.

### Proposed smallest data model (for approval; not built)

Additive, in the existing `interactions.json` (one file, same strict validation and lint), a new optional top-level `cases` list; no database change, because progress is computed from the two existing tables.

```json
"cases": [
  {
    "id": "case:quiet-hour",
    "title": "The Quiet Hour",
    "summary": "A receiver has begun ticking at regular intervals near the Capitol Square. The source is unknown.",
    "opens_with": [],
    "entries": [
      { "discovery": "disc:pulse" },
      { "discovery": "disc:conduit" }
    ],
    "outcomes": [
      { "when": "disc:threshold", "title": "The hatch was opened", "text": "..." },
      { "when": "disc:marked",    "title": "The hatch was left shut", "text": "..." }
    ]
  }
]
```

- **`opens_with`** lists discoveries that must exist before the case appears (empty means it appears from the start of a walk). A case is **active** until one outcome's `when` discovery exists, then **completed** with that outcome's text, so different endings fall out of different discoveries.
- **`entries`** lists which declared discoveries belong to the case, in the order the author wants them shown; the journal shows only entries whose discovery is recorded, using the discovery's existing `label` (already written as a clue) and nothing else. Leads and locations come from the discoveries the author chooses to list, so unfound clues and places are never revealed. If an entry needs a richer re-readable text than the label (a document, a quoted line), a later optional `text` on the discovery is additive.
- **Derived, never stored:** the journal is a pure function of the saved discoveries and the file, computed server-side like `Interactions.at/4`. Removing or editing content therefore never corrupts a save (matching the rules in [world-revisions-proposal.md](world-revisions-proposal.md)).
- **Validation and lint:** case and discovery ids are declared; an outcome `when` or an entry that names an undeclared discovery is an error; a case whose outcomes can never be reached, or an entry no interaction can grant, is a warning.
- **Not in this model on purpose:** objectives, markers, ordering of what to do next, per-lead completion flags, items. If the designer later wants active player deduction ([handoff.md](handoff.md) decisions), that is a separate design built on this, not an extension of the journal.
- **UI:** a read-only panel (LiveView, field-notebook style) opened from a Journal control beside the Field Atlas panel; the map stays visible; same live-region and focus rules as the investigate panel.
- **Implementation size:** a pure `Interactions.journal/3`, the schema addition with tests, one panel, content for *The Quiet Hour*; one focused session.

## 3. Map indicators for locations with notes or investigations

On the Field Atlas map a location with an authored note gets a subtle indicator, distinct from an ordinary movement node; a location with an *available investigation* is distinct from both; a *completed* investigation must not look identical to unread content. The player should glance at the map and see where there is something to read or investigate.

- **Constraints:** ordinary movement nodes stay minimal; indicators never obscure the movement numbers or interfere with clicking or number-key movement; they work in all four seasons; no clutter where places are close; **no persistent note-read tracking** unless the designer later decides it is needed; no change to movement or discovery semantics.
- **Implementation note (deferred):** the full step-by-step note is in [handoff.md](handoff.md) ("Near-term UI feature"): per-destination `note` and `investigate` flags in the map state, a pure availability function that hides unmet interactions (no spoilers), seasonal token colors with contrast tests, two non-interactive circle layers beneath the move markers, tests, and a browser check on a scratch world.

## Order of work (proposed, for the designer to confirm)

1. The designer plays *The Quiet Hour* and gives feedback on story and pacing.
2. Decide the introduction and the Field Journal together (they share a presentation style and "new walk" lifecycle).
3. Then, one at a time and only when approved: the Field Journal, the introduction, the map indicators.
