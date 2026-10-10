# Threshold — Current Game Design Memo

**Date:** October 9, 2026  
**Status:** Working game design, pre-alpha  
**Setting:** A fictionalized Madison, Wisconsin  
**Genre:** Single-player geographic mystery, exploration, investigation, and cartography

## 1. Overview

**Threshold is a mystery game about exploring an ordinary city and discovering that its geography is incomplete.**

The player explores a stylized map of Madison, encounters strange events, investigates radio transmissions, speaks with unusual people, and gradually discovers hidden places and impossible connections.

The surface world is grounded in real streets, paths, buildings, parks, and lakes. The unusual elements emerge within that familiar environment.

A seemingly ordinary intersection might contain an unexplained radio signal. A service entrance might lead somewhere that does not correspond to the building above it. A familiar street might become inaccessible, or a passage might connect two locations that should be far apart.

The player's primary instrument is a map that serves as both a navigation interface and an evolving record of discoveries.

The central reward is not defeating enemies or accumulating equipment. It is **learning something about the world that changes how the world can be understood and explored**.

## 2. Design Pillars

### A believable city with impossible geography

Madison should feel recognizable, detailed, and inhabited.

Real geography provides the foundation, while carefully authored fictional locations, encounters, and connections introduce mystery.

Strange events should be relatively uncommon. The ordinary city gives them context and makes them more effective.

### Exploration produces knowledge

Discoveries are a central form of progression.

Learning something at one location may make a new investigation available elsewhere.

A place may become more interesting after the player finds a clue, meets a character, or understands a signal.

### The map is part of the game

The map is more than a background.

It is a navigation instrument, a record of exploration, and eventually a place where the player can annotate evidence and map hidden geography.

The distinction between **what exists** and **what the player knows exists** is important.

### Deliberate, geographic movement

The player moves between authored locations along real walking routes.

Movement is turn-based and currently one hop at a time.

This gives individual intersections, alleys, and entrances significance, and creates opportunities for location-based encounters.

### Narrative through places and people

The story should emerge through environmental descriptions, documents, conversations, radio transmissions, and discoveries.

Not every encounter needs to advance the main mystery.

The city should contain smaller stories, recurring characters, mundane details, and occasional humor.

### Curiosity is rewarded

The game should encourage investigation, revisiting locations, testing hypotheses, noticing small details, and exploring unusual routes.

Achievements and optional discoveries can reward these behaviors without reducing exploration to repetitive tasks.

## 3. The World

### Surface geography

The initial world is Madison's downtown and isthmus area.

The imported geographic dataset covers approximately 5.7 × 3.5 km, extending across much of the isthmus from the university area toward the east side.

This imported area is larger than the playable region.

The designer controls the playable boundary independently.

The real pedestrian network provides geographic walking routes, while the authored gameplay graph determines which locations the player can occupy and move between.

**The authored graph is the default gameplay graph.**

This distinction allows the game to maintain geographic accuracy without requiring the player to navigate every raw OpenStreetMap vertex.

### Authored locations

Authored locations represent the meaningful positions in the game.

They may correspond to:

- Street intersections.
- Mid-block positions.
- Building entrances.
- Alleys and courtyards.
- Public spaces.
- Fictional landmarks.
- Unusual or impossible locations.

An authored location has a stable identity independent of its geographic coordinates.

Its visual position can also differ from its pedestrian walking-access point.

This allows a location to appear in a building or courtyard while remaining accessible from a nearby street.

### Connections

Ordinary authored connections resolve to real walking paths over the underlying pedestrian network.

Future fictional connections may represent hidden passages, tunnels, anomalous transitions, or other forms of nonstandard movement.

Such transitions should be deliberate authored gameplay relationships, not accidental products of geographic proximity.

### Playable boundaries

The world designer chooses which region is available for ordinary movement.

Areas beyond the playable boundary may still appear as geographic context.

Future gameplay may change accessibility through flooding, construction, closures, anomalies, or discoveries, but those systems have not yet been implemented.

## 4. Current Navigation

Threshold currently uses **strict one-hop movement**.

The player sees adjacent legal destinations and chooses one.

The server validates the connection, advances the turn, and records progress.

Movement follows the actual geographic route associated with the connection.

### Controls

Reachable destinations are numbered clockwise around the player using `1` through `9`, then `0`.

The player may move by clicking an available destination or pressing its corresponding number key.

Movement choices are recomputed after each move.

### Camera

Field Atlas operates at close geographic zoom levels.

The current rules use:

- Minimum zoom: 17.
- Maximum zoom: 19.5.
- Maximum camera-center distance from the player: 200 meters.
- Camera following after movement.

The player can inspect the immediate surroundings without freely surveying the entire game world.

### Future travel convenience

Longer-distance travel or automatic traversal may eventually be appropriate for previously explored routes.

However, **multi-hop movement is not part of the current design**.

Any future convenience feature should preserve the significance of discoveries, interruptions, and individual locations.

## 5. Core Gameplay Loop

The intended long-term loop is:

1. **Move** through the city.
2. **Notice** an unusual feature, event, character, or signal.
3. **Investigate** by inspecting, listening, observing, or making a choice.
4. **Discover** information that becomes part of the player's persistent knowledge.
5. **Interpret** the discovery in relation to other places and clues.
6. **Return or continue** to locations where new opportunities have become available.
7. **Chart** the evolving understanding of the ordinary and hidden world.

The current implementation supports the first complete causal slice of this loop:

**Investigating Location A records a discovery that makes an interaction available at Location B.**

This is the foundation for more elaborate mysteries.

## 6. Interactions and Scenes

Interactions are authored opportunities to investigate or act at a location.

A scene is the narrative presentation of an interaction.

A discovery is a persistent piece of knowledge or evidence gained through a valid interaction.

A completed interaction records what the player has already resolved.

These concepts are intentionally separate.

### Current behavior

When the player reaches a location with an available interaction, Field Atlas indicates that something can be investigated.

The player chooses whether to open it.

Opening a scene does not itself grant a discovery.

The scene may contain descriptive text and explicit choices.

A choice is validated by the server. If accepted, it may grant a declared discovery and mark the interaction complete.

Discoveries persist in PostgreSQL across movement and reloads.

### Movement and investigation

Moving one connection consumes one turn.

Opening a scene, closing it, and choosing an option currently consume no movement turns.

An open scene does not prevent movement. Walking away closes the transient scene presentation.

### Conditional availability

For the first implementation, an interaction can require one or more previously recorded discoveries.

This supports simple causal mysteries without a general-purpose scripting language.

For example:

- At one location, the player records a strange transmission.
- At another, the recorded transmission lets them recognize a previously meaningless clue.
- That second interaction becomes available only after the first discovery.

### Future interaction forms

The architecture should eventually support:

- Character dialogue.
- Letters, signs, documents, and recordings.
- Environmental observations.
- Radio investigation.
- Multi-stage scenes.
- Conditional choices.
- Items and equipment.
- Puzzles.
- Changes to available routes.

These are future capabilities, not requirements for the first gameplay milestone.

## 7. Narrative and Atmosphere

Threshold should occupy a space between geographic investigation, small-town surrealism, analog mystery, and occasional horror.

Important tonal influences include:

- *Welcome to Night Vale*: the strange treated as part of ordinary civic life.
- *The Magnus Archives*: investigations, testimony, recurring details, and interconnected mysteries.
- *Silent Hill*: unsettling places, atmosphere, and distorted geography.
- *The Backrooms*: liminal environments and impossible spatial networks.
- *Ace Attorney* and *Pokémon*: approachable character interactions, expressive dialogue, and memorable encounters.

These are influences, not templates to reproduce.

### Preferred tone

The city should initially feel inviting and familiar.

A significant portion of the experience should be ordinary exploration, conversations, observations, and small discoveries.

Unsettling events become more powerful when they interrupt this normality.

The game can be eerie without being relentlessly dark.

Humor, municipal bureaucracy, local eccentricity, and seemingly trivial details can contribute to the atmosphere.

Not every mystery should be explained immediately.

## 8. Radio and Signal Investigation

Radio remains an important planned gameplay system.

The player may eventually carry a receiver capable of detecting unusual signals.

A signal could provide:

- A measurement suggesting a direction or location.
- A repeating tone or numbers transmission.
- A fragment of dialogue.
- Evidence of an unknown transmitter.
- A clue that changes an interaction elsewhere.
- An indication that ordinary geography is behaving strangely.

Radio should function primarily as an **investigative instrument**, not a conventional quest arrow.

Players should be able to compare readings, recognize patterns, and draw conclusions.

The radio interface may use sonar-like indicators, technical graphics, and signal overlays.

However, the radio aesthetic is secondary to the game's primary cartographic presentation.

A full radio-propagation simulation is not yet necessary.

## 9. Hidden Geography and Null Zones

The ordinary Madison map is not the whole world.

Some places may connect to a second, hidden geography.

These entrances are provisionally called **null zones**.

They might occur at service doors, stairwells, alleys, tunnels, unused buildings, or other apparently ordinary locations.

Three stages should remain distinct:

**Detection:** The player notices evidence that something unusual exists.

**Identification:** The player learns where the anomaly or entrance is.

**Access:** The player discovers how to enter.

Knowing that an entrance exists does not necessarily mean the player can use it.

### The Backrooms

The hidden world may contain rooms, corridors, repeated spaces, and unexpected connections.

Its topology need not correspond to real-world geometry.

It may eventually have its own map, explored and progressively revealed by the player.

The first implementation can be entirely two-dimensional, using descriptions, scenes, and authored connections.

First-person WebGL environments remain a possible future feature, not a current requirement.

Combat and survival systems are not central design priorities.

## 10. Cartography and Visual Identity

**Classic Atlas is Threshold's primary visual identity.**

The game should resemble a beautiful, carefully illustrated municipal atlas with understated investigative instrumentation.

### Primary palette

- Warm ivory and cream ground.
- Muted sage-green vegetation.
- Pale blue lakes and waterways.
- Fine blue-gray and slate street geometry.
- Detailed but restrained building footprints.
- Elegant geographic labels.
- Selective teal and amber gameplay accents.

The map should remain legible and geographically precise.

The objective is not a conventional commercial navigation map, nor a dark tactical surveillance screen.

### Seasons

The cartographic system supports four seasonal visual modes:

- Spring.
- Summer.
- Autumn.
- Winter.

Seasonal selection is presently a presentation feature.

It does not change gameplay topology, movement rules, or saved discoveries.

Future environmental simulation may connect seasons to gameplay, but that is a separate design decision.

### Watercolor direction

A future visual refinement is to make the atlas feel subtly hand-painted.

Promising treatments include:

- Fine paper grain.
- Soft watercolor pigment variation.
- Illustrated tree-canopy patterns.
- Meadow and lawn textures.
- Gentle water washes.
- Seasonal foliage variation.
- Selected terrain and wetland patterns.

The preferred initial approach is a reusable library of procedural, seamless cartographic materials applied to appropriate geographic features.

Streets, labels, buildings, and movement controls should remain crisp.

The watercolor effect should enhance the existing style, not replace it.

### Curved labels

Studio should eventually allow a designer to place geographic text along editable Bézier curves.

This supports carefully composed street, trail, neighborhood, and fictional-place labels.

Native MapLibre typography is preferred where sufficient, with custom rendering reserved for cases requiring greater artistic control.

### Special effects

Radio interference, unusual map markings, subtle distortion, and anomalous visual effects may appear when thematically justified.

They should be exceptional.

The normal atlas should be beautiful and trustworthy enough that deviations from it feel meaningful.

## 11. Field Atlas and HUD

The main gameplay interface is **Field Atlas**, the player-facing geographic map.

The map should dominate the screen.

The HUD supplies contextual information without overwhelming the cartography.

Important elements include:

- Current location and movement options.
- Numbered reachable destinations.
- Nearby investigations.
- Scene text and choices.
- Recorded outcomes.
- Recenter and map controls.
- Seasonal presentation controls.

### Scene presentation

Scenes should feel integrated with the Classic Atlas rather than appearing as generic web forms.

The preferred direction is a field notebook or restrained visual-novel-style panel.

Typography should be elegant and readable, with clear choices and a deliberate hierarchy.

The map remains visible when investigating.

The scene system must remain accessible through keyboard navigation, focus management, and appropriate announcements.

### Near-term additions (requested, not yet built)

- **Introduction:** a full-screen narrative introduction on a new walk that establishes setting and premise before Field Atlas appears (not on every reload).
- **Field Journal:** a persistent, read-only place for active investigations, recorded discoveries and completed cases, designed to help the player remember and reason without pointing the way.
- **Map indicators:** subtle marks distinguishing locations with notes, locations with available investigations, and completed investigations, without hiding movement numbers.

Requirements, constraints and the proposed smallest data model are in [near-term-features.md](near-term-features.md).

### Future presentation

Possible additions include:

- Character portraits.
- Simple character expressions.
- Dialogue-style presentation.
- Illustrated evidence.
- Field notes and case files.
- Radio instruments.
- Achievements and research records.

These features should be achievable with modest artistic resources.

Simple, expressive character art is preferred over expensive animation or photorealistic assets.

## 12. Knowledge, Discoveries, and the Journal

The game should distinguish between:

- Places the player can see.
- Places the player has visited.
- Interactions the player has completed.
- Facts the player has discovered.
- Hypotheses the player suspects.
- Hidden information not yet revealed.

Currently, visited places, completed interactions, and declared discoveries are the relevant persistent concepts.

### Field Notes

A future **Field Notes** or casebook interface could present discoveries as an investigative archive.

It might contain:

- Recorded signals.
- Evidence and documents.
- Notes about people and locations.
- Previously completed investigations.
- Unresolved questions.
- Personal map annotations.

A chronological journal is also a promising future feature, but has not yet been implemented as a separate gameplay system.

### Knowledge versus truth

The world can contain facts the player does not know.

The player may also hold incomplete or incorrect hypotheses.

Eventually, player-authored annotations should distinguish speculation from confirmed discoveries.

This distinction could become central to cartographic mystery solving.

## 13. Characters and Encounters

Characters should make the city feel inhabited.

Encounters may involve ordinary residents, municipal workers, amateur radio operators, shopkeepers, investigators, or people with unexplained connections to hidden places.

The preferred interaction style draws inspiration from approachable character-based games.

A character may have:

- A simple illustrated portrait.
- A small collection of expressions.
- Distinct dialogue.
- A recurring role in the world.
- New dialogue unlocked by discoveries.
- Personal mysteries or optional subplots.

The initial interaction model does not yet implement character dialogue trees.

A future system should build on its existing principles of authored scenes, validated choices, and persistent consequences rather than introducing a completely separate mechanism.

## 14. Achievements and Secondary Progression

Achievements remain an important long-term design goal.

They should reward curiosity and meaningful exploration rather than repetitive grinding.

Potential categories include:

- Geographic exploration.
- Radio investigation.
- Discovery and evidence.
- Cartographic accomplishments.
- Hidden passages and null zones.
- Unusual encounters.
- Backrooms exploration.
- Solving optional mysteries.
- Revisiting places under changed circumstances.

The game could eventually support dozens or hundreds of achievements.

Some should be visible, some hidden, and some part of progressive discovery chains.

They might be presented as field commendations, research distinctions, stamps, or unusual municipal records.

Achievements are not yet implemented.

## 15. World Authoring

Threshold includes a world editor, with a larger redesign planned as **Threshold Studio V2**.

The designer controls the authored navigation graph, locations, connections, boundary, spawns, and other world content.

The current editor supports the established geographic authoring workflow, while Studio V2 is intended to provide a more polished and flexible environment.

### Planned Studio V2

The design direction is:

- Preact for Studio's interactive interface.
- Phoenix/Elixir for authoritative validation and persistence.
- MapLibre for geographic rendering.
- Shared cartographic components with Field Atlas.
- Contextual editing panels.
- Richer geographic and narrative authoring tools.

Future Studio capabilities should include scene editing, curved labels, exact walking-access selection, decorative map materials, and visual previews.

World authoring should remain deterministic and reviewable.

The designer's geographic and narrative work must never be silently regenerated or rewritten.

## 16. Game Architecture Principles

The current architecture is organized around:

**World authoring → World compilation → World execution.**

World definitions are version-controlled data.

The runtime world is a compiled, validated representation of the geographic and authored content.

Player progress is stored in PostgreSQL.

Game rules are server-authoritative.

### Design principles

- Share immutable world data across player sessions.
- Keep each player's progress independent.
- Preserve transactional movement and interaction completion.
- Separate geographic movement from narrative effects.
- Validate discoveries and choices on the server.
- Avoid arbitrary executable scripts in early authored content.
- Prefer small declarative interactions.
- Keep game state distinct from frontend presentation state.

These principles allow the game to grow without immediately requiring a general-purpose scripting or simulation system.

### World revisions

The current save system uses a world-revision check to guard against incompatible geographic changes.

A revised compatibility model has been proposed but is not yet implemented.

The intended direction is to preserve exploration progress across harmless edits while explicitly handling cases where a saved player position is no longer valid.

Visited history and discoveries should not be silently discarded.

The detailed recovery policy remains subject to approval.

## 17. Current Implementation Status

As of this memo, the project has working implementations of:

- Madison geographic import and reproducible derived geography.
- A larger imported region and editable playable boundary.
- Manually authored locations and walking connections.
- Server-derived walking-access anchors.
- Atomic geographic snapshot publication.
- A fast immutable runtime-world cache.
- PostgreSQL-backed movement progress.
- Strict one-hop movement and numeric keyboard shortcuts.
- Constrained player camera.
- Classic Atlas cartography with seasonal modes.
- Native map typography.
- A declarative location-based interaction format.
- Declared persistent discoveries.
- Transactional interaction completion.
- Conditional interactions between different places.
- Field Atlas investigation scenes and choices.
- Keyboard focus and live-region accessibility improvements.

The two-location discovery scenario has been tested in a synthetic world.

It is a working gameplay demonstration, not yet a complete authored Madison mystery.

### Not yet implemented

Major planned features include:

- A full Madison storyline.
- Rich character dialogue and portraits.
- Radio measurement gameplay.
- Null-zone entrances and hidden geographic transitions.
- A playable Backrooms region.
- Player-authored map annotations.
- A field journal or casebook.
- Achievements.
- Procedural watercolor cartographic materials.
- Procedural vegetation.
- Studio V2 interaction authoring.
- A general scripting system.
- Multiplayer.

These should remain separate, incremental design efforts.

## 18. Recommended Next Milestone

The next product milestone should make Threshold feel like a small but complete mystery game.

### Phase A — Scene presentation

Polish the existing investigation panel within the Classic Atlas design.

Improve typography, pacing, choice presentation, and discovery feedback without changing interaction semantics.

Preserve keyboard accessibility and the map-first layout.

### Phase B — A short Madison mystery

Design a compact investigation involving approximately three or four nearby authored locations.

A possible structure:

**Location A — An unusual signal**

The player discovers evidence of a repeated transmission or an unexplained pattern.

**Location B — A physical clue**

Something in the built environment corresponds to the transmission.

**Location C — A witness or document**

A character, sign, or municipal record provides a conflicting account.

**Location D — An unsettling revelation**

A previously ordinary place reveals an impossible detail.

The precise story and locations should be reviewed before altering the real authored world.

### Phase C — Field Notes

Provide a simple way to revisit recorded discoveries.

Start with read-only presentation of existing persistent discovery data.

Avoid introducing a generalized journal or inventory system before it is necessary.

### Phase D — Further exploration mechanics

Once narrative investigation is compelling, introduce one additional mechanic that changes how the player explores.

Radio investigation or a single authored hidden transition are strong candidates.

Implement one at a time and evaluate how much each contributes to the game.

## 19. Longer-Term Vision

A more complete Threshold experience would allow a player to explore Madison, gather strange evidence, interact with recurring characters, triangulate an unusual signal, discover an entrance to hidden geography, and chart a small impossible spatial network.

Eventually, the player might emerge from that network somewhere unexpected in the city.

The surface map would remain familiar, but the player's understanding of it would be permanently changed.

This larger scenario could include:

- Six to twelve meaningful surface locations.
- Several narrative encounters.
- A radio investigation.
- One null-zone entrance.
- A small hidden network of rooms.
- One unexpected exit.
- Persistent discoveries.
- A personal cartographic record.
- A handful of achievements.

This is a longer-term target, not the immediate implementation scope.

The game should be developed through small, complete experiences that prove individual mechanics before expanding them.

## 20. Design Thesis

Threshold should feel like opening a beautiful illustrated atlas of a familiar city and discovering that some of its details cannot be explained.

The map invites exploration.

The city offers clues.

Conversations, signals, and observations change what the player knows.

What the player knows changes what becomes possible.

And over time, the player's map becomes a record of an extraordinary geography hidden within an ordinary place.

**Threshold is a game about discovering that the world is larger, stranger, and less certain than the map first suggests.**