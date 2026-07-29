# Path graph authoring

AshitaMinimap owns reusable, display-only navigation graphs. AshitaGuide
continues to publish only the current destination. This prevents every guide
from duplicating routes and lets all guides benefit when a zone graph improves.

## Runtime behavior

For a fresh destination, AshitaMinimap:

1. loads the graph registered for the current zone;
2. rejects a graph or destination for another map page;
3. snaps the player and destination to graph nodes within `snap_radius`;
4. runs A* across graph edges using world distance as both edge cost and
   heuristic;
5. draws the route without issuing any command or player action;
6. projects the player onto the retained route to distinguish traveled and
   active segments; and
7. recalculates only when the destination changes or the player moves more
   than 12 yalms away from the route.

If either endpoint cannot be snapped or no connected route exists, the normal
AshitaGuide destination marker remains visible and no path is drawn.

## Deterministic generation

Generate a graph from the same pinned Detour `.nav` source used by the map:

```text
python tools/generate_path_graph.py <zone.nav> assets/paths/<zone-id>.lua \
  --zone-id <zone-id> --page-id <page-id> \
  --seed=<verified-world-x>,<verified-world-y>
```

`--seed` limits the artifact to the connected component containing that
verified walkable point. The generator recognizes exact shared polygon edges
and split axis-aligned tile seams whose interpolated vertical difference is no
greater than `--maximum-step` (default `0.65` yalms). It converts Detour's
horizontal Z axis to the negated FFXI world-Y convention used by the addon.

Register the generated file in `ashitaminimap_paths.lua`. Generated graph files
must not be hand-edited.

## Validation checklist

- Record the source repository commit and SHA-256 in the zone provenance file.
- Use a verified live seed; never infer it from a map-grid label.
- Confirm graph node and edge counts are identical across two generations.
- Confirm every linked node index exists and every edge is bidirectional.
- Test endpoint snapping near the intended entrances, exits, and destination.
- Test at least one connected route and one deliberately disconnected target.
- Compare the displayed route with close-zoom walkable structure.
- Traverse every relevant connector before describing the graph as complete.
- Keep unresolved components marker-only rather than joining them by visual
  guesswork.

Graph data is navigation metadata for display. It must never be used to add
movement, input simulation, packet injection, timers, loops, command queuing,
unattended behavior, or detection evasion.
