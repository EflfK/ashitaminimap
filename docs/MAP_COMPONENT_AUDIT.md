# Required navmesh component and transition audit

Read this document before creating, correcting, or declaring complete any
authored walkable-structure map. It records the coverage failures found while
correcting Ru'Lude Gardens and Upper Jeuno so they are not repeated without the
original chat context.

## Why seeded generation can silently omit real paths

`generate_walkable_map.py` deliberately does not render every Detour polygon.
Collision and navigation sources can contain roofs, inaccessible slabs,
off-map tails, residential-area circles, and unrelated islands. A verified
seed selects only its connected navmesh component.

That safe default also creates three omission risks:

1. Overlapping floors can contain the same world X/Y on different elevations.
   A two-dimensional seed can select only one polygon and can be ambiguous when
   multiple polygons contain that point.
2. Legitimate floors can be disconnected because of model or tile seams.
3. Stairs, ramps, and landings can be isolated into one or more tiny polygons.
   They may share no edge with either floor, so increasing `--maximum-step`
   cannot connect them.

The absence of a polygon from a seeded output does not prove that it is
inaccessible. Conversely, rendering every unselected polygon is not a safe
solution.

## Completion gate: classify components before publishing

Before calling a map complete, inventory the Detour components and classify
every component that is spatially near the stock map, selected geometry, a
named destination, or a known route:

| Classification | Required handling |
| --- | --- |
| Main path | Include with at least one verified seed |
| Alternate floor | Include as a separate `structure_layers` texture |
| Stair/ramp/connector | Include every fragment, normally with the floor it reaches |
| Excluded | Record the deterministic reason: roof, inaccessible slab, off-map tail, residential collision, or other verified cause |
| Unresolved | Do not call the map complete; document it as partial |

Record for each included or excluded component:

- seed or inspected interior point;
- polygon count;
- world X/Y bounds;
- world-elevation range;
- role or exclusion reason;
- live verification coordinates when accessible.

Do not infer accessibility solely from component size. Ru'Lude's missing east
staircase consisted of two isolated polygons, one of which contained the live
player. Tiny components can be essential route connectors.

## Seed rules for overlapping floors

The generator's seed is world X/Y only. Before using a seed in an overlapping
area, inspect every nav polygon containing that X/Y and its elevation.

- Prefer an interior point that belongs to exactly one polygon.
- If the point is ambiguous, choose another verified point or apply a verified
  elevation band before connectivity selection.
- Record the player's live Z and the selected Detour elevation in provenance.
- Never assume a `(0, 0)` seed represents every floor merely because the
  resulting overview looks plausible.

Ru'Lude's original `(0, 0)` seed selected only the main garden component.
Upper Jeuno's original `(0, 0)` seed omitted the Chocobo Stables component.
Both outputs looked coherent while remaining incomplete.

## Preserve topology when flattening to two dimensions

Disconnected floors must not be unioned into one PNG. A polygon union erases
interior component boundaries and can make an upper bridge appear to connect
to a lower path beneath it.

Use ordered `structure_layers` entries:

```lua
structure_layers = structure_layer_set({
    {
        image = 'assets/maps/<zone>_structure.png',
        maximum_player_z = <verified lower bound>,
    },
    {
        image = 'assets/maps/<zone>_stairs_structure.png',
        minimum_player_z = <verified upper bound>,
    },
    {
        image = 'assets/maps/<zone>_upper_structure.png',
        minimum_player_z = <verified upper bound>,
    },
})
```

Generate the main connected network with the standard cyan fill and edges.
Generate disconnected floors and their connector fragments with:

```text
--fill-rgb 42,30,66 --edge-rgb 181,132,255
```

Separate textures preserve each component's outline at crossings. Cyan denotes
the main network; violet denotes a disconnected alternate floor or the
connector leading to it. All component textures are still one logical
walkable-structure source category and must share identical dimensions,
calibration, crop, and wrap.

When a verified stair or ramp still reads as an unexplained color seam at
close zoom, add alternating floor-color stripes clipped to the actual path
geometry. Stripes cross the travel direction. Widen the main-floor color
toward the main floor, widen the alternate-floor color toward the alternate
floor, and use equal widths near the midpoint. The stripe field must be
centered on a live-verified connector and point toward the alternate floor.
First fix disconnected geometry and raster seam gaps. Do not blend the colors
or use an opaque block, glyph, arrow, or invented connector.

Use the shared tapered-threshold preset rather than a circular stripe field.
The threshold is a narrow path-aligned capsule with alpha feathering only at
its travel-direction ends. Declare its structure layer with
`role = 'floor_transition'`. The runtime renders this role in one pass and
fades it from subtle overview opacity to stronger close-zoom opacity so the
transition never becomes a pasted-on landmark:

```lua
{
    image = 'assets/maps/example_transition_structure.png',
    role = 'floor_transition',
}
```

Transition position, direction, and geometry remain map-specific verified
data. The role standardizes presentation; it does not infer or invent
transitions on maps that have not received a live route audit.

## Emphasize the player's current floor

Color is secondary to opacity. Give each floor layer verified
`minimum_player_z` and/or `maximum_player_z` bounds. The renderer keeps a
matching layer at the configured current-floor opacity and renders a
nonmatching layer at the independently configured
`inactive_floor_opacity`:

```lua
{
    image = 'assets/maps/example_lower.png',
    maximum_player_z = -15.0,
}
```

Use narrow nonoverlapping Z ranges derived from live transition samples. A
transition-only stripe layer may omit bounds and use a moderate fixed
`opacity`. The config UI exposes **Current floor opacity** and **Other floors
opacity** separately. Do not hardcode the inactive value in map metadata. Keep
inactive floors faint but visible so they still provide orientation and warn
about projected crossings.

Every multi-texture set in `ashitaminimap_maps.lua` must use
`structure_layer_set`. Each record must declare `minimum_player_z` and/or
`maximum_player_z`, use `role = 'floor_transition'`, or explicitly use
`floor_selection = 'always'` when live evidence proves that the component must
not participate in floor selection. The catalog loader also rejects an
unclassified set at runtime. Filenames such as `upper`, `lower`, `main`, or
`stairs` never imply floor behavior.

## Required live route audit

An overview screenshot and three generic calibration points are not sufficient
coverage validation. Perform a route audit after calibration:

1. Visit every known floor.
2. Visit every stair, ramp, bridge, elevator landing, drop, and other
   transition between floors.
3. Capture exact live X/Y/Z at the entrance, middle, and exit of each
   transition.
4. At close map zoom, confirm the player marker stays over the correct
   structure for the complete route.
5. At every projected crossing, confirm separate component outlines and colors
   do not imply a walkable junction.
6. Compare named stock-map destinations and visible entrances against the
   component inventory.
7. Repeat at overview zoom to confirm no legitimate component disappears and
   no excluded geometry was introduced.

If the player marker is outside every authored component at a known walkable
position, the map fails coverage validation. Capture that live position and
classify its nav polygon before publishing.

## Required provenance

Each multi-level map's `assets/maps/<zone>.md` must include:

- a component-classification table or equivalent complete list;
- every seed grouped by main floor, alternate floor, and connector;
- elevation ranges for overlapping components;
- generation commands for every component texture;
- exact live route-audit positions;
- explicit exclusions and reasons;
- any unresolved areas, with the map described as partial.

Do not replace missing evidence with language such as "the seeded component
appears to cover the zone." A coherent-looking mask is not proof of complete
walkable coverage.

## Review questions

Before committing, answer all of these with evidence:

- Did every named floor receive live or deterministic component review?
- Did every transition receive entrance, middle, and exit checks?
- Are any small nearby components still unclassified?
- Does any seed overlap polygons at multiple elevations?
- Were disconnected floors kept in separate textures?
- Do projected crossings retain visible boundaries and distinct colors?
- Is every exclusion recorded and justified?
- Was the installed addon reloaded and tested at close and overview zoom?

Any unanswered question blocks a claim that the map is complete.
