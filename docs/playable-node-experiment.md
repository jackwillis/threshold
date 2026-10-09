# Playable-node experiment

Date: October 8, 2026. Script: `gis/analysis/playable_nodes.py` (exploratory; reads the committed Madison files, changes nothing; `--svg out.svg` draws a comparison of the Capitol Square area). This document records results and caveats; it does not select a production approach. Judgements about what "feels good" are **inferences**; nothing here was playtested.

## Question

The imported pedestrian graph has 5,757 nodes and 7,899 edges with sidewalks drawn separately from streets. The game needs far fewer, more meaningful player locations (working hypothesis: roughly 40-100 m between ordinary locations). Can a simple, deterministic rule produce a candidate network, without losing connectivity or erasing important features?

## Setup

**Core graph** (the input to every candidate): imported edges excluding `restricted` access and vehicle-oriented service ways (driveway, parking aisle, drive-through, emergency access): 5,066 nodes, 6,420 edges, 128.8 km, 20 connected components. 1,479 edges are excluded. Restricted ways are excluded for the experiment only; they remain in the data.

**Locations that must survive simplification:** dead ends (and entrances: dead ends within 3 m of a building footprint), alley endpoints, level changes (tunnel/bridge/layer transitions), and anything within 15 m of an elevator point.

**Candidates**
- **A, junctions:** contract only degree-2 pass-through nodes.
- **B, spatial 12 m:** merge nodes within 12 m by straight-line distance (single linkage). *Included as a cautionary example.*
- **G25, graph radius 25 m:** seed at the highest-degree node, absorb every node reachable along edges within 25 m, repeat. Clusters follow the network.
- **C, G25 + contract:** G25 followed by removing non-special degree-2 locations.

## Results

| | A junctions | B spatial 12 m | G25 | C (G25 + contract) |
|---|---|---|---|---|
| Locations | 2,807 | 1,010 | 1,467 | 968 |
| Connections | 4,151 | 1,507 | 2,091 | 1,592 |
| Components (core has 20) | 20 | 9 | 20 | 20 |
| Components wrongly joined | 0 | 1 | 0 | 0 |
| Source components erased | 0 | 7 | 0 | 0 |
| Median connection length | 10.5 m | 33.7 m | 34.3 m | 42.6 m |
| Connections < 40 m | 76.6% | 58.5% | 58.6% | 47.2% |
| Connections 40-100 m | 15.8% | 35.1% | 36.1% | 38.0% |
| Connections > 100 m | 7.6% | 6.4% | 5.3% | 14.8% |
| Dead-end locations | 623 | 158 | 237 | 237 |
| Connections with an alley edge | 59 | 30 | 26 | 26 |

Connection lengths are the shortest constituent edge between two clusters, an approximation. G25 clusters reach at most 47 m across (29 nodes).

**Radius sensitivity (G, before contraction):** R=15 m gives 2,103 locations (median 25 m, 27% in 40-100 m); R=25 m, 1,467 (34 m, 36%); R=40 m, 1,018 (42 m, 46%, but clusters up to 74 m across).

## What this showed

1. **A is far too fine.** Three quarters of connections are under 40 m; clusters of 4-6 locations sit at every street corner because sidewalk corners, curb ramps and crossings are separate nodes.
2. **Distance-based merging (B) is unsafe.** It chained a 100-node cluster, joined components that are not connected in the source, and erased seven. This is the "accidentally removes meaningful connectivity" failure the architecture memo warns about. Merging must follow the network.
3. **My first graph-based version also had a flaw:** components that fit inside one cluster vanished (13 of 20). Fixed by keeping one location per collapsed component. Any production approach needs an explicit check that disconnected components survive; the script reports it.
4. **G25 and C preserve connectivity** (20 of 20 components, 0 wrongly joined) and reach a median near the hypothesis (34 m and 43 m). Contraction (C) raises the share above 100 m to 15%, so a long connection may need splitting or a waypoint.
5. **Alleys are partly absorbed:** connections containing an alley edge fall from 59 to 26 because short alley mouths merge into intersection clusters. Alley locations are retained (43) but alley *connections* are not all visible. Needs attention if alleys are central to gameplay.
6. **Not addressed:** plaza gaps (footways ending at open plazas stay dead ends, 237 dead-end locations remain), whether dead ends at entrances should be kept, and any weighting for 'interesting' places. The visual crop shows C reading as a clean street grid with the Capitol Square octagon intact.

## Caveats

- One dataset, one area. No playtesting; "useful" is a hypothesis.
- The core graph choice (excluding restricted and vehicle service ways) strongly affects counts; it is an experimental assumption, not a decision.
- Only three radii and one special-location rule were tried.

## Suggested next steps (not yet decided)

1. If this direction is accepted, make graph-radius clustering a separate, deterministic pipeline step that writes a derived playable layer next to, not into, the imported graph, always reporting component integrity.
2. Add an editor view of the candidate locations so a designer can retain or suppress them.
3. Decide how alley connections and plaza crossings should be represented before fixing a radius.
