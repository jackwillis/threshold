# Threshold — Game Design Memo

**Date:** October 8, 2026  
**Status:** Working design, pre-alpha  
**Genre:** Single-player geographic exploration, mystery, and cartography  
**Setting:** A fictionalized Madison, Wisconsin

## 1. Concept

*Threshold* is a location-based mystery game about discovering that an ordinary city contains an extraordinary geography.

The player explores a detailed map of Madison, investigates strange radio transmissions, encounters characters, and discovers places where the normal rules of space break down.

Some locations are **null zones**: places where the player can enter an alternate spatial network inspired by the Backrooms. These hidden spaces contain passages, clues, artifacts, and unexpected connections to the surface world.

As players investigate, they gradually construct their own maps of the hidden geography, documenting discoveries, observations, and hypotheses.

**The central idea is that making the map is part of playing the game.**

## 2. Design Pillars

### An ordinary city with extraordinary properties

The world should feel grounded in real geography. Streets, alleys, intersections, and buildings create a recognizable environment.

The strange elements should be relatively sparse and mysterious. Much of the atmosphere comes from encountering something impossible in an otherwise ordinary setting.

### Exploration produces knowledge

Progress comes primarily from discovering locations, gathering evidence, understanding anomalies, and learning how places connect.

The player becomes a better investigator by developing knowledge of the world.

### The map is an instrument

The map is simultaneously a navigation tool, research notebook, record of discoveries, and interface to the game world.

It should support observations, routes, measurements, and eventually player-created annotations.

### Convenient travel, deliberate investigation

Routine travel should not require excessive clicking.

Players can choose destinations and follow routes, but movement should stop when an event, discovery, or obstacle deserves attention.

### Narrative through exploration

Characters, dialogue, unusual encounters, and environmental clues contribute to the larger mystery.

Not every encounter needs to be part of the main plot. Small subplots and unexplained incidents help make the world feel strange and inhabited.

### Curiosity should be rewarded

Achievements, discoveries, hidden locations, unusual interactions, and cartographic accomplishments provide reasons to explore.

The game should reward experimentation as well as completing explicit objectives.

## 3. Core Gameplay Loop

The player repeatedly:

1. **Explores** streets, alleys, buildings, and hidden spaces.
2. **Investigates** using radio measurements, observations, and dialogue.
3. **Interprets** clues and forms hypotheses about the world.
4. **Discovers** anomalies, hidden entrances, and new connections.
5. **Charts** those discoveries on a personal map.
6. **Progresses** to new investigations using accumulated knowledge.

The loop should be interesting even in a small, mostly deterministic world.

The player should have reasons to revisit familiar locations as new information or equipment becomes available.

## 4. The Surface World

The initial surface world is a small area of downtown Madison, beginning near First Settlement.

The world is based on real geographic data, but game locations are selected and simplified to produce enjoyable navigation.

### Movement granularity

The player should not have to visit every geographic vertex.

An ordinary block may represent one movement connection, while an alley, unusual entrance, or important intersection may justify additional locations.

For initial experiments, ordinary playable locations may be approximately 40–100 meters apart, with density increased around interesting features.

This is a playtesting hypothesis, not a permanent rule.

### Navigation

Movement is initially virtual and turn-based.

The preferred interaction is:

- Select a visible destination.
- Preview an available walking route.
- Confirm travel.
- Automatically traverse ordinary intermediate locations.
- Stop when a meaningful event or obstacle occurs.

Players should also be able to make individual movements when investigating closely.

Physical GPS-based movement may eventually become an additional play mode, but is not required initially.

### Boundaries and disruptions

The initial world occupies a small, defined geographic area.

Later, environmental events may make streets inaccessible or create new routes. Flooding, temporary closures, and anomalous passages are possible examples.

The player's movement network may therefore differ from the ordinary geographic street network.

## 5. Radio Investigation

The player carries a radio receiver used to detect strange transmissions and investigate anomalies.

At different locations, the player can take measurements and compare signal strength.

Readings should provide useful evidence without simply revealing the correct destination.

Early signal behavior can be predictable. More complicated interference and anomalies may be introduced later.

Radio signals can also carry narrative content:

- Fragments of conversations.
- Unidentified broadcasts.
- Numbers stations.
- Repeating tones.
- Transmissions apparently originating from impossible locations.

The radio should feel like an investigative instrument rather than a conventional objective pointer.

Initially, scans do not need ammunition, charges, or arbitrary usage limits.

## 6. Null Zones

Null zones are locations where ordinary geography connects to the hidden world.

They may appear at familiar places such as alleys, service entrances, stairwells, tunnels, or buildings.

Three concepts should remain distinct:

**Detection:** The player observes evidence of an anomaly.

**Identification:** The player determines where the entrance is.

**Access:** The player discovers how to enter.

An entrance may be known but temporarily inaccessible.

Future null zones might appear only under certain conditions, change over time, or connect to different destinations.

The first scenario needs only one fixed entrance.

## 7. The Backrooms

The Backrooms are a separate network of rooms, corridors, and passages.

They need not obey real-world geography.

The player gradually charts the network by moving through it, discovering rooms, documenting connections, and finding exits.

### Reasons to enter

The hidden spaces should offer meaningful rewards:

- Clues about surface-world mysteries.
- Artifacts or equipment.
- Unusual radio transmissions.
- Missing-person investigations.
- Shortcuts between distant surface locations.
- Discoveries that reveal the hidden world's structure.

The Backrooms should feel eerie, repetitive, and unsettling without requiring constant danger.

The initial experience can be entirely 2D, using room maps, descriptions, dialogue, and encounters.

First-person WebGL environments may be added for significant locations later.

Combat, monsters, and survival systems are not currently central to the design.

## 8. Cartography and Discovery

The game distinguishes between the world as it exists and the world as the player understands it.

### Ordinary geography

Most ordinary Madison streets and public paths should be visible from the beginning.

The player should not have to discover the existence of familiar city blocks through conventional fog of war.

### Explored geography

Visited locations and traversed routes are recorded.

Surveyed locations may gain measurements, observations, and encounter histories.

### Hidden geography

Null zones, impossible passages, undiscovered entrances, and Backrooms rooms remain hidden until discovered.

The Backrooms should use progressive map revelation.

### Knowledge and uncertainty

The personal map should eventually distinguish:

- Known locations.
- Visited locations.
- Surveyed locations.
- Confirmed discoveries.
- Suspected anomalies.
- Player-authored hypotheses.
- Unknown or unverified connections.

Players should be able to make incorrect inferences.

A hypothesis is not the same as a confirmed fact.

This distinction can become central to investigative gameplay.

### Personal annotations

Eventually, players should be able to mark suspected beacon locations, annotate measurements, draw possible connections, and record notes.

The first version only needs visited-location and discovered-connection tracking.

## 9. Encounters and Narrative

Encounters can occur when the player:

- Enters a location.
- Investigates a geographic feature.
- Takes a particular measurement.
- Discovers an item or clue.
- Revisits a location after learning something.
- Satisfies a narrative condition.

Encounters may include dialogue, decisions, environmental descriptions, and observations.

Some may initiate small subplots across multiple locations.

### Narrative tone

The game should balance mystery and unease with occasional mundane or absurd details.

The setting can draw from analog horror, the Backrooms, municipal infrastructure, amateur radio, and investigative fieldwork.

Ordinary environments and bureaucratic language may help make supernatural events more unsettling.

Not every mystery needs an immediate explanation.

## 10. Visual and Interface Design

The primary interface is a custom-styled 2D geographic map.

The aesthetic combines:

- Municipal cartography and technical atlases.
- Digital field-investigation software.
- Radio-surveillance terminals.
- Restrained analog-horror elements.

### Visual direction

Use dark navy and charcoal backgrounds, fine cyan and muted green street geometry, subdued labels, gridlines, and technical annotations.

Amber and red may indicate unusual signals, warnings, or anomalies.

Individual buildings, alleys, and street features should remain legible at close zoom.

The map should look like a specialized piece of investigative software, not a conventional fantasy map or generic GIS application.

Visual disturbances should be used sparingly.

### Interface

The player should be able to:

- Pan and zoom the map.
- Recenter on their location.
- Select a destination and preview travel.
- Inspect nearby features.
- Take radio readings.
- Open encounters and dialogue.
- Consult discoveries, notes, and achievements.

The map should remain readable and useful throughout.

The world editor and player interface may share rendering technology, but they should not expose the same controls.

## 11. Achievements and Progression

Achievements should be a substantial part of the game.

We envision dozens of achievements initially, potentially growing to hundreds as more content is added.

### Categories

| Category | Example |
|---|---|
| Exploration | **Surveyor** — Visit 25 locations |
| Cartography | **Here Be Dragons** — Chart an unknown passage |
| Radio | **Numbers Station** — Receive an unidentified broadcast |
| Investigation | **Triangulation** — Locate a beacon using measurements |
| Null zones | **Out of Bounds** — Enter your first null zone |
| Backrooms | **Wrong Turn** — Discover a hidden room |
| Navigation | **The Long Way Around** — Find an alternate exit |
| Encounters | **Familiar Stranger** — Meet a character twice |
| Collection | **Evidence Locker** — Recover 10 artifacts |
| Mastery | **Field Researcher** — Solve an investigation without hints |

Include visible achievements, hidden achievements, and progressive achievement chains.

Achievements should emphasize curiosity, unusual actions, discoveries, and meaningful accomplishments rather than repetitive grinding.

### Presentation

Achievements should fit the field-investigation theme.

They might appear as research distinctions, field commendations, stamped certificates, or unusual municipal records.

A field journal may eventually collect achievements, notes, discoveries, and exploration statistics.

Achievements are not the primary narrative objective, but should provide a rewarding secondary progression system.

## 12. First Playable Scenario: The Beacon

The first complete scenario should be short, roughly five to ten minutes.

### Premise

The player begins in Madison with a radio receiver.

An unidentified transmission has been detected nearby.

The player explores several streets, takes signal measurements, and encounters someone who recognizes the broadcast.

The investigation leads to a null zone.

Entering it reveals a small network of unfamiliar rooms and corridors.

The player discovers an artifact or clue and eventually finds a second exit.

They emerge somewhere else in Madison, carrying evidence of an impossible geographic connection.

Their map is updated with the newly discovered rooms and passage.

### Minimum scope

- Approximately 6–12 surface locations.
- One radio beacon.
- One null-zone entrance.
- Three to five Backrooms rooms.
- One alternate surface exit.
- Two narrative encounters.
- One branching conversation.
- One discoverable clue or artifact.
- Basic visited-location and connection tracking.
- A clear scenario-completion condition.

The scenario should be hand-authored and mostly deterministic.

Its purpose is to test whether exploration, investigation, and discovery are compelling.

## 13. Future Possibilities

Potential later systems include:

- Dynamic null zones.
- Temporally evolving anomalies.
- Environmental disruptions and blocked routes.
- More sophisticated radio propagation.
- Equipment upgrades.
- Larger Backrooms regions.
- Unstable or changing room topology.
- Procedurally generated encounters or spaces.
- First-person environments.
- GPS-based physical exploration.
- Player-authored cartography.
- Shared investigations or multiplayer.

These are possibilities, not commitments.

The game should remain playable as a single-player experience without depending on any of them.

## 14. Open Design Questions

We still need to test:

- How many playable locations make an interesting neighborhood?
- When should a street have multiple player positions?
- How much travel should one click represent?
- How frequently should travel be interrupted?
- What makes radio signal investigation genuinely interesting?
- How much information should the map automatically reveal?
- When should players make their own annotations?
- How dangerous or disorienting should Backrooms exploration be?
- What incentives make players revisit familiar locations?
- How should achievements affect long-term progression?
- How should we balance authored mysteries with systemic world behavior?

These questions should be answered through small playable experiments.

## 15. Design Thesis

*Threshold* is about exploring a familiar city and discovering that its map is incomplete.

The player collects evidence, encounters unexplained events, and gradually discovers a second geography hidden beneath the ordinary one.

The central reward is understanding.

**The map is the player's principal instrument, record of discovery, and one of the game's most important accomplishments.**
