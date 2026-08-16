# Cross-zone world routes

AshitaMiniMap layers a display-only world router above its map-owned walking
graphs. The world router never moves the player, interacts with an NPC, selects
a menu option, issues a command, or sends a packet.

## Catalog sources

CatsEyeXI commit `314deaf03465f2b24b6a1e4e73a016ca036f1084` is
authoritative for the server's zone-line destination zone, arrival position,
and rotation. Its `sql/zonelines.sql` contains 844 records but does not contain
the departure coordinate.

LandSandBoat commit `bf838f7c4d52903d99bbb4baff9726ff2c66d797`
contains an enriched `sql/zonelines.sql` whose source coordinates were decoded
with `xiregiondump`. The generator joins records by zone-line ID and publishes
a connection only when both sources agree on the source and destination zone.
CatsEyeXI's arrival position remains authoritative even when the newer source
differs.

Run:

```text
python tools/generate_world_connections.py
```

The generated catalog contains 820 candidate connections. Twenty-five records
remain in the audit report: 23 shared IDs whose zone pairs differ, one
CatsEyeXI-only ID, and one LandSandBoat-only ID. Never silently promote an
unresolved record.

## Runtime behavior

For a destination in another zone, the router:

1. snaps the player and destination to authored map-owned path graphs;
2. snaps compatible physical zone-line endpoints to those graphs;
3. adds exact walking costs only when the relevant endpoints share a connected
   authored graph;
4. adds directed physical transition edges;
5. adds Home Point and Survival Guide edges only to destinations whose
   read-only registration bit is set;
6. adds Warp only when AshitaCore reports the respawn zone and that zone has
   exactly one authored Home Point candidate, avoiding an invented landing
   position; and
7. applies a fixed fast-travel penalty so short routes through adjacent physical
   zone lines outrank unrelated Home Point and Survival Guide transfer chains;
   and
8. runs Dijkstra across the combined walking and travel graph.

Only the current-zone walking leg is drawn. After zoning, the route is rebuilt
from the player's actual arrival position. When the destination cannot be
reached because of a later graph gap, the router may draw only a fully authored
handoff into the destination zone. The footer labels that result `PARTIAL
ROUTE` and warns that the destination remains marker-only after zoning. A route
is still withheld when the current endpoint or handoff cannot snap truthfully.

The footer names the endpoint of the current cyan walking leg and the exact
action to take there. Home Point and Survival Guide instructions use the
in-game **By Region Name** hierarchy: one line names the region group and the
next names the destination. Home Point destinations also include the numbered
crystal. This keeps both nested travel menus and same-zone transfers
unambiguous.

Home Point and Survival Guide endpoints currently come from each authored map's
audited `travel_references`. Expanding travel coverage therefore follows the
normal complete-map and provenance requirements.

## Validation

- Regenerate twice and require identical catalog and audit hashes.
- Require exactly 844 records from each pinned source, 820 published
  connections, and 25 unresolved records.
- Validate every published coordinate as finite and bounded.
- Preserve directionality. Never infer a reverse zone line.
- Treat same-zone transitions as distinct records; they may connect separate
  stock pages.
- Verify source and arrival endpoint snapping before a connection is eligible
  at runtime.
- Keep destinations marker-only when no fully authored route exists.
