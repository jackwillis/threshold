# Madison network review

Date: October 8, 2026. Data: the committed snapshot (retrieved 2026-10-08) and generated geography. Method: exploratory scripts in `gis/analysis/` (run from the repo root; they read files and change nothing). Numbers are for the first import and will change with a new snapshot. Items marked **inference** are heuristics, not verified facts.

## Summary

| Question | Finding | Recommendation |
|---|---|---|
| Does collapsing edges to undirected lose direction? | Not for pedestrians. | Keep undirected; do not use `oneway` for foot. |
| Is 96% `unknown` access a problem? | It conflates "OSM default says walkable" with "genuinely uncertain". | Decide whether to add a derived access basis (open question). |
| Are sidewalks and crossings usable? | Yes, well mapped and connected. | Retain the `footway` / `crossing` / `sidewalk` tags (currently dropped). |
| Are disconnected components bugs? | Mostly building-entrance walkways, not errors. | Keep and flag; treat as entrance/investigation candidates. |
| Are dead ends gaps? | About 27% end at pedestrian plazas (**inference**: a graph gap), 42% at buildings, 31% free (mostly driveways). | Handle plazas in the playable-node layer, not by editing the imported graph. |

## Direction

Of 3,957 graph-eligible ways, 371 are `oneway=yes`, but all are vehicular (residential, tertiary, service, primary, links) except 16 cycleways. Only one way has `oneway:foot` (`no`). Pedestrians may walk either way on a one-way street, so undirected edges are correct for walking. The importer already retains `oneway` for any later vehicle use.

`foot=no` appears on 18 cycleways and 7 primary roads/links. These are in the graph and classified `restricted`, which is the intended behaviour (inspect everything, never assume traversable). There are no `foot:conditional` or `access:conditional` tags in this extract, so the importer's lack of conditional interpretation does not matter yet.

## Access

Source ways with no `foot` or `access` tag: 3,642 of 3,957 (92%). Edges: 6,335 unknown, 417 restricted, 141 public.

- Restricted comes mostly from `access=private` (143 ways) and `access=no` (49), concentrated in `service` ways: 138 private and 48 no among 887, mostly driveways.
- `unknown` mixes cases with different meaning: footways, steps, residential and other streets where OSM's default is that walking is allowed, versus service ways, driveways, parking aisles and cycleways where it is genuinely unclear.

**Open question:** add a separate derived field (for example `access_basis`: explicit tag, default-allowed by highway type, or uncertain) without changing `access_status`? It would make the legend and the playable-node experiment far more informative. This is a design decision.

## Sidewalks and crossings

Edge counts by source subtype: sidewalk 1,865 (60 km); crossing 901; plain footway 689; driveway 924; residential 861; parking aisle 352; cycleway 212; steps 115; alley 63.

- 899 of 901 crossing edges connect at both ends, so the sidewalk-and-crossing network is largely connected. Crossing types: marked 542, traffic signals 235, uncontrolled 82, zebra 32.
- 520 streets are tagged `sidewalk=separate`, meaning their sidewalks are separate ways, which matches what we see.
- **Importer gap:** the `footway` (sidewalk / crossing), `crossing`, `crossing:markings`, `crossing:signals`, `sidewalk*` and `lit` tags are not retained, so generated edges cannot tell a sidewalk from a crossing from a plain path. The analysis above had to join back to the source XML. Recommend retaining them (requires regeneration).

## Disconnected components

Fourteen small components remain (6,873-edge main network, 14 pieces of 1-3 edges each). Only two touch the import-extent edge and lie outside the playable area (artifacts of truncation). Inside the playable area, every small component has endpoints at building footprints or pedestrian plazas (**inference**: walkways through or between buildings, skyways and bridges whose interiors are not mapped). Four are 1-edge `bridge=yes` pieces. They are retained and inspectable, as agreed.

## Dead ends and plazas

700 dead-end endpoints lie inside the playable area. Within about 3 m of: a building footprint 295 (42%), a pedestrian-area polygon 191 (27%), neither 214 (31%).

- Dead ends by type: plain footway 299, driveway 236, parking aisle 74, sidewalk 30, steps 12, alley 8.
- Footways ending at buildings are plausibly entrances; they are also candidate investigation points.
- Footways ending at plaza polygons are plausibly a **graph gap**: closed `area=yes` pedestrian ways became context polygons (decision 9), so paths that meet an open plaza have no connection across it. 227 of 458 plaza polygons touch at least one dangling footway end, and 146 touch two or more. Connecting them (for example with derived "plaza" edges) should live in the playable-node layer, not in the imported graph.
- Driveways and parking aisles dominate the free dead ends; they are vehicle-oriented and make poor playable locations.

## Layers, bridges and tunnels

71 edges are `tunnel=yes`, 4 `building_passage`, 17 `bridge=yes`; layers range from -1 to 3. 130 nodes join edges of different layer, bridge or tunnel status, which is consistent with ramps, stairs and portals. This review did not look for false joins; none were noticed.

## Recommended next actions

1. Retain the `footway`, `crossing*`, `sidewalk*`, `lit`, `level` and `indoor` tags in the importer and regenerate (small, mechanical, reviewable diff). Needs approval because it changes committed generated files.
2. Decide on a derived access basis (see Access).
3. Use the playable-node experiment to handle plazas (derived connections), building entrances (candidates), and driveways (deprioritized) rather than altering the imported graph.
4. Revisit this review after any new snapshot.
