# Path graph authoring

AshitaMinimap owns reusable, display-only navigation graphs. AshitaGuide
continues to publish only the current destination. This prevents every guide
from duplicating routes and lets all guides benefit when a zone graph improves.

## Lessons from the Ru'Lude Gardens route audit

Ru'Lude Gardens exposed three distinct failure modes that a plausible-looking
route did not reveal:

1. The source Detour mesh contained a polygon adjacency across an impassable
   boundary. A* correctly followed the graph, but the graph was not truthful
   for a player, so the displayed route appeared to jump floors or cross a
   blocked passage.
2. Real staircases were split into disconnected navmesh components. Without
   explicit connections, valid nearby destinations produced no route or a
   longer route using a different staircase.
3. The generator originally selected seeded components before removing a
   verified blocked edge. The bad edge therefore pulled an unreachable
   16-node floor fragment into the output even though the edge itself was later
   deleted.

The durable fixes are:

- read native `dtPoly.neis` topology and resolve geometry only across Detour
  external tile portals rather than reconstructing every adjacency from
  similar-looking polygon edges;
- add `--transition` only for a connection verified from live entrance,
  middle, and exit coordinates;
- add `--blocked-link` for a source edge proven impassable in game;
- apply blocked links before seed-based component selection; and
- run the catalog auditor after every graph change.

Native Detour topology reduces invented connections, but it is not guaranteed
to describe player movement. The LandSandBoat meshes were built primarily for
server navigation use, and their absence or presence of an edge is not by
itself proof that a player can traverse it. The rendered structure, exact live
X/Y/Z samples, and an attended traversal remain authoritative for exceptions.

These rules apply to every existing graph when it is revisited and to every
future map. A shortest-path result is only accepted after its complete route
has been checked for walls, railings, floor changes, stairs, ramps, doors, and
other transitions.

## Routing-first topology

`generate_path_graph.py` reads native Detour topology directly. A production
graph must be explainable from verified seeds, elevation bounds, blocked links,
and transitions without requiring a visible structure PNG.

`--mask` remains available as an optional internal diagnostic selector for
retained legacy assets. It is not a routing-completion requirement, must not be
used as the only evidence that an area is reachable, and must never force the
author to generate or publish a structure image.

Native mode is the production default. Inferred mode is comparison-only.
Review every component that is near a supported destination, known route,
alternate floor, zone exit, or plausible connector. Decorative or irrelevant
components may be excluded once deterministic evidence proves that they cannot
affect a normal route; they do not require exhaustive structure-image
classification.

`tools/audit_structure_catalog.py` is retained only for an explicitly requested
structure audit. It is not part of the routing-first completion gate.

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
more than four yalms above or below the endpoint. For a custom waypoint whose
X/Y overlaps multiple floors, the map evaluates the nearby destination nodes
and selects the shortest connected graph route from the player's current
three-dimensional position. This allows a click on another floor to use the
nearest truthful staircase instead of forcing the destination onto the
player's present floor. The current floor remains the fallback when no
candidate route can be evaluated. If lower and upper nodes remain unresolved
near the click, the waypoint stays visible but marker-only. AshitaGuide
publishes `targetZ` when an authored destination supplies it or a named live
entity exposes it. On maps with authored elevation bands, a guide destination
without truthful Z likewise remains marker-only instead of selecting whichever
overlapping floor is closest in two dimensions.

Route projection is also three-dimensional. Walking above or below a route no
longer counts as remaining on it, and route recalculation cannot silently
attach the player to a projected path on another floor.

Maps explicitly certified with
`route_elevation_mode = 'continuous_surface'` retain that three-dimensional
snapping and projection while drawing the complete route across ordinary
terrain elevation changes. The first upcoming elevation-band boundary is
shown as an amber `UP` or `DN` required-passage marker. Do not apply this mode
solely because a zone has one stock page: a single image can still contain
overlapping floors that require the normal current-floor route clipping.

## Deterministic generation

Generate a graph from the pinned Detour `.nav` source:

```text
python tools/generate_path_graph.py <zone.nav> assets/paths/<zone-id>.lua \
  --zone-id <zone-id> --page-id <page-id> \
  --seed=<verified-world-x>,<verified-world-y>
```

Do not add `--mask` merely because an authored map previously displayed a
structure layer. Prefer truthful seeds and elevation bounds, then prove every
destination-affecting component through deterministic inspection and attended
route tests.

When a verified walkable staircase or ramp is split by source-navmesh gaps,
repeat `--transition` to join only the aligned polygons:

```text
--transition=<start-x>,<start-y>,<start-live-z>:<end-x>,<end-y>,<end-live-z>
```

Transition endpoints snap to polygon centroids within two yalms by default.
Every transition is bidirectional and must be backed by a verified physical
connection; it must never bridge unrelated surfaces that merely overlap on the
flattened map.

For a verified drop, gate, or other passage that can be crossed in only one
direction, use:

```text
--one-way-transition=<start-x>,<start-y>,<start-live-z>:<end-x>,<end-y>,<end-live-z>
```

The first endpoint is the allowed start and the second is the allowed
destination. Generated graphs record the resolved node pair in
`one_way_edges`; runtime A* follows only the forward adjacency. The validator
requires every asymmetric edge to have that declaration and rejects a declared
one-way edge if its reverse adjacency is present.

## Attended actions on a route

Every retained edge that requires a finite player action must declare that
action. This includes opening a door or gate, standing on a Dangruf Wadi
geyser, using an island Spatial Displacement, trading an item to activate a
portal, operating an elevator, and similar mechanisms. Ordinary walking edges,
stairs, ramps, drops, and automatic zone thresholds do not receive action
metadata.

Annotate an existing directed edge with `--route-action`:

```text
--route-action=<start-x>,<start-y>,<start-live-z>:<end-x>,<end-y>,<end-live-z>|<instruction>|<mechanism name>
```

The edge must already exist through native topology, `--transition`, or
`--one-way-transition`; the generator fails rather than allowing an action to
invent connectivity. Add one declaration per direction. This permits a portal
to say `Use the Spatial Displacement.` in one direction and `Trade one Giant
Scale to the Unstable Displacement.` in the other.

At runtime, AshitaMiniMap splits the path at each declared action. The panel
first routes to the mechanism, then shows the action as the next step, and
recalculates the remaining walking leg after the player crosses or uses it.
This applies to both same-zone and multi-zone destinations. AshitaMiniMap only
displays the instruction; it never interacts with the mechanism or supplies
input on the player's behalf.

Action metadata needs the same evidence as its edge and must be included when
reviewing doors, geysers, portals, elevators, and other route mechanisms. If a
mechanism's endpoints or directionality are unresolved, keep the connection
partial or marker-only until attended evidence proves it; do not add an action
label to a guessed edge.

When live verification proves that a source-navmesh adjacency crosses a wall,
door, railing, or other impassable boundary, remove only that edge with:

```text
--blocked-link=<start-x>,<start-y>,<start-live-z>:<end-x>,<end-y>,<end-live-z>
```

Blocked links use the same two-yalm centroid snap as authored transitions and
generation fails if the source edge does not exist.

Repeat `--seed` to retain multiple verified components without inventing edges
between them. Use repeated `--mask` arguments with the map's exact
`--origin-x`, `--origin-y`, and `--pixels-per-yalm` to constrain graph nodes to
the union of already-authored structure layers. Page/floor maps may also use
the same verified `--minimum-elevation` and `--maximum-elevation` bounds as
their structure generation.

The generator reads Detour's authored `dtPoly.neis` topology for neighbors
inside a tile and joins geometry only across edges Detour explicitly marks as
external tile portals. This avoids inventing same-floor or cross-floor links
between polygons that merely have similar edges. Portal height differences
must be no greater than `--maximum-step` (default `0.65` yalms). The
`--adjacency-mode inferred` compatibility option reconstructs all adjacency
geometrically and exists only for audits; completed maps use native topology.
The generator converts Detour's horizontal Z axis to the negated FFXI world-Y
convention used by the addon.

Blocked links are applied before seed-based component selection. As a result,
an inaccessible island is discarded unless another verified seed explicitly
retains it.

Register a single-page generated file directly in `ashitaminimap_paths.lua`.
For a multi-page zone, register a table keyed by active stock page. Generated
graph files must not be hand-edited.

Regenerate the complete current catalog with:

```text
python tools/generate_all_path_graphs.py <xiNavmeshes>
python tools/validate_path_graphs.py assets/paths/*.lua
python tools/audit_path_graphs.py <xiNavmeshes>
```

The catalog generation script records every source selector in one reviewable
place. `assets/paths/README.md` records the pinned source revision, hashes,
node/edge counts, and deterministic output hashes. The audit regenerates each
graph twice: once from native Detour topology and once with inferred adjacency.
It reports production drift, topology deltas, component health, stacked-floor
overlaps, and one closest review lead per pair of substantial disconnected
components. A suggested component pair is never proof of a staircase, door, or
other transition.

The auditor is a required completion gate, not an optional diagnostic. Its
production/native comparison must pass. Destination- or route-affecting
disconnected-component advisories must be reviewed against collision,
navmesh, existing live evidence, and the Developer mode graph web. They must
never be converted automatically into links. A focused live traversal is
required when adding an exception link or correcting a reported defect, not
merely because a nearby component exists. Traveling-salesman or nearest-neighbor
logic may choose an order among multiple destinations only after each leg has
a truthful graph route; it must never infer map connectivity.

## Validation checklist

- Record the source repository commit and SHA-256 in the zone provenance file.
- Use a verified live seed; never infer it from a map-grid label.
- Confirm graph node and edge counts are identical across two generations.
- Run the catalog audit and require production/native parity. Investigate every
  native/inferred delta and every destination- or route-affecting nearby
  component against collision/navmesh evidence and the full-graph overlay.
  Never add an edge from proximity alone; live-verify any authored exception.
- Confirm every linked node index exists and every edge is either
  bidirectional or explicitly declared one-way.
- Test endpoint snapping near the intended entrances, exits, and destination.
- Enable Developer mode and **Show all pathing** to inspect the complete graph
  web. Use focused attended checkpoints for concrete defects instead of a
  speculative walkthrough of every possible seam.
- Test overlapping X/Y points on different elevations and confirm each snaps
  only to its own floor.
- Test at least one connected route and one deliberately disconnected target.
- Compare the displayed route with close-zoom walkable structure.
- Traverse every relevant connector before describing the graph as complete.
- Record discovered blocked edges and verified transitions in the catalog job
  so the correction survives deterministic regeneration and benefits every
  guide using that map.
- Keep unresolved components marker-only rather than joining them by visual
  guesswork.

Graph data is navigation metadata for display. It must never be used to add
movement, input simulation, packet injection, timers, loops, command queuing,
unattended behavior, or detection evasion.
