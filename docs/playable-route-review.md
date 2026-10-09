# Playable route integrity review

Date: October 8, 2026. Scope: candidate navigation connections, not gameplay or real-world access certification.

## Finding

The original cluster contraction preserved component counts, but retained only the edges between clusters. It omitted the paths from cluster representatives to those edges. Contraction could also concatenate constituent edges in the wrong direction.

On the pinned Madison output, only 249 of 1,631 connections recorded edges connecting both displayed endpoint nodes. Another 152 recorded disconnected edge sets. Their displayed straight segments and reported lengths were therefore unsuitable as walking routes.

## Repair and verification

Each cluster now retains its network paths from the representative. A candidate connection includes the two internal paths and the selected connecting edge. Parallel candidates are compared using complete route length. Pass-through contraction orients both routes before concatenating them.

Each generated connection records:

- `edge_ids`: the complete, ordered source-edge walk.
- `route_nodes`: ordered routing nodes, from the `from` location to the `to` location.
- `geometry`: a continuous GeoJSON LineString using source polylines, reversed where necessary.
- `length_m`: the sum of constituent source-edge lengths, rounded once.
- `route_classes`: classifications actually traversed. Existing `classes` still describes the available parallel candidates.

The generator rejects mismatched route endpoints and gaps. The editor draws and highlights the route geometry; older outputs retain their legacy display until regenerated.

The Madison audit verified all 1,631 connections join their endpoint nodes through permitted core edges, with continuous source geometry. No routes revisit a node. All 58 selected alley connections remain. The 993 selected locations, 20 components and topology are unchanged. Corrected median connection length is 58.0 m; 42.4% are 40–100 m and 27.0% exceed 100 m. The original 42.3 m median underestimated travel by omitting internal segments.

Synthetic automated tests cover endpoint continuity, source-edge direction, retained polyline shape, exact length accumulation, restricted/vehicle-service exclusions and determinism at 25, 200 and 600 m clustering radii. Existing tests cover components, alley availability, dead ends and retain/suppress overrides.

## Limits before movement

- The core graph still includes unknown, mixed and conditional access. Gameplay needs an explicit access policy; these records do not establish real-world permission.
- Authored closures are annotations today. Movement must validate them according to agreed game rules; the derived graph does not enforce them.
- Boundary membership is metadata, not a traversal constraint. Decide whether routes may leave and re-enter the playable boundary.
- Cluster paths can pass through nodes assigned to other clusters. The routes are real network walks, but the abstraction is not guaranteed to offer globally optimal travel. Compare game routing with source-network shortest paths before committing to movement costs.
- Parallel route alternatives are summarized rather than exported individually. A blocked selected route may require recomputing an alternative on the source network.
- The available-map tests do not establish completeness of OSM entrances, crossings or elevator connectivity. No plaza gaps are bridged and no synthetic shortcuts are added.
- Retain overrides now seed clustering first, ensuring the exact retained source node survives rather than being absorbed by a neighboring representative. Synthetic tests cover absorption, component integrity and deterministic rebuilds.

These limits call for a small movement experiment and targeted route review, rather than more infrastructure. PostgreSQL-backed player state can follow once traversal rules are settled.
