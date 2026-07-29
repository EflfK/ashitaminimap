# Path graph authoring

AshitaMinimap owns reusable, display-only navigation graphs. AshitaGuide
continues to publish only the current destination. This prevents every guide
from duplicating routes and lets all guides benefit when a zone graph improves.

## Runtime behavior

For a fresh destination, AshitaMinimap:

1. loads the graph registered for the current zone and active authored page;
2. rejects a graph or destination for another map page;
3. snaps the player and destination to graph nodes within `snap_radius` and,
   when Z is available, within the graph's floor tolerance;
4. runs A* across graph edges using world distance as both edge cost and
   heuristic;
5. draws the route without issuing any command or player action;
6. projects the player onto the retained route to distinguish traveled and
   active segments; and
7. recalculates only when the destination changes or the player moves more
   than 12 yalms away from the route.

If either endpoint cannot be snapped or no connected route exists, the normal
AshitaGuide destination marker remains visible and no path is drawn.

Generated Detour elevation has the opposite sign from Ashita's live player Z.
Runtime snapping converts graph elevation back to live Z and rejects nodes
more than four yalms above or below the endpoint. A custom waypoint adopts an
unambiguous graph elevation only when nearby candidates belong to one floor.
If lower and upper nodes overlap near the click, the waypoint remains visible
but marker-only. AshitaGuide publishes `targetZ` when an authored destination
supplies it or a named live entity exposes it. On maps with authored elevation
bands, a guide destination without truthful Z likewise remains marker-only
instead of selecting whichever overlapping floor is closest in two
dimensions.

Route projection is also three-dimensional. Walking above or below a route no
longer counts as remaining on it, and route recalculation cannot silently
attach the player to a projected path on another floor.

## Deterministic generation

Generate a graph from the same pinned Detour `.nav` source used by the map:

```text
python tools/generate_path_graph.py <zone.nav> assets/paths/<zone-id>.lua \
  --zone-id <zone-id> --page-id <page-id> \
  --seed=<verified-world-x>,<verified-world-y>
```

Repeat `--seed` to retain multiple verified components without inventing edges
between them. Use repeated `--mask` arguments with the map's exact
`--origin-x`, `--origin-y`, and `--pixels-per-yalm` to constrain graph nodes to
the union of already-authored structure layers. Page/floor maps may also use
the same verified `--minimum-elevation` and `--maximum-elevation` bounds as
their structure generation.

The generator recognizes exact shared polygon edges and split axis-aligned tile
seams whose interpolated vertical difference is no greater than
`--maximum-step` (default `0.65` yalms). It converts Detour's horizontal Z axis
to the negated FFXI world-Y convention used by the addon.

Register a single-page generated file directly in `ashitaminimap_paths.lua`.
For a multi-page zone, register a table keyed by active stock page. Generated
graph files must not be hand-edited.

Regenerate the complete current catalog with:

```text
python tools/generate_all_path_graphs.py <xiNavmeshes>
python tools/validate_path_graphs.py assets/paths/*.lua
```

The catalog generation script records every source selector in one reviewable
place. `assets/paths/README.md` records the pinned source revision, hashes,
node/edge counts, and deterministic output hashes.

## Validation checklist

- Record the source repository commit and SHA-256 in the zone provenance file.
- Use a verified live seed; never infer it from a map-grid label.
- Confirm graph node and edge counts are identical across two generations.
- Confirm every linked node index exists and every edge is bidirectional.
- Test endpoint snapping near the intended entrances, exits, and destination.
- Test overlapping X/Y points on different elevations and confirm each snaps
  only to its own floor.
- Test at least one connected route and one deliberately disconnected target.
- Compare the displayed route with close-zoom walkable structure.
- Traverse every relevant connector before describing the graph as complete.
- Keep unresolved components marker-only rather than joining them by visual
  guesswork.

Graph data is navigation metadata for display. It must never be used to add
movement, input simulation, packet injection, timers, loops, command queuing,
unattended behavior, or detection evasion.
