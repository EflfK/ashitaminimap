# Map import and calibration

This document is the repeatable procedure for adding precision maps to
AshitaMinimap. Metalworks established the rendering transform; new maps should
reuse that transform with map-specific metadata rather than being manually
nudged until they look close.

Read `MAP_AUTHORING_PITFALLS.md` as well. It contains the source-reconstruction,
diagnostic, and live-deployment failures that are easy to repeat even when the
calibration formulas are correct.

## What is universal

AshitaMinimap is north-up. A calibrated map converts world coordinates to
source-image pixels with:

```text
image_x = origin_x + world_x * image_pixels_per_yalm
image_y = origin_y - world_y * image_pixels_per_yalm
```

The same transform must be used for:

- the optional vanilla layer;
- the structure layer;
- the player marker;
- entity and target markers;
- the Lua-rendered coordinate grid, using its own recorded grid anchor when the
  printed vanilla grid does not center on world `(0, 0)`.

Display size and user zoom are a later screen-space transform. They must never
be folded into the source-image calibration.

## What varies by map

Every zone or map variant can have different:

- DAT texture layout and horizontal wrapping;
- transparent padding or crop bounds;
- world-origin pixel;
- pixels per yalm;
- yalms per letter-number grid cell;
- floor, page, or map-variant selection.

For this reason, each entry in `ashitaminimap_maps.lua` owns its calibration.
Solving one zone proves the math but does not make its numeric constants valid
for another zone.

Required fields are:

```lua
[zone_id] = {
    name = 'Zone Name',
    vanilla_image = 'assets/maps/<zone>_vanilla.png',
    structure_image = 'assets/maps/<zone>_structure.png',
    width = 512,
    height = 512,
    view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
    origin_x = 253,
    origin_y = 253,
    grid_origin_x = 255,
    grid_origin_y = 255,
    grid_yalms = 40,
    image_pixels_per_yalm = 0.80,
},
```

A temporary flattened `image` is supported, but a production map should use
separate vanilla and walkable-structure layers when the source permits it.
`view_bounds` is optional. Use it when the source texture contains transparent
padding or an adjacent composite page. It defines the calibrated source-pixel
rectangle that the overview camera should keep visible; it does not crop or
recalibrate any layer.

`grid_origin_x` and `grid_origin_y` are optional source-image coordinates for
the center of vanilla cell H-8. When omitted, they default to `origin_x` and
`origin_y`. Record them separately when the printed grid and navigation
geometry use different origins; forcing the geometry origin onto the grid can
shift every displayed quadrant by a full row or column.

## Deterministic import procedure

1. Identify the exact vanilla DAT map page or variant for the zone. Do not
   assume the zone has only one floor or page.
2. Decode the DAT without resizing it. `tools/generate_vanilla_map.py` decodes
   the 512-by-512 palette texture, corrects its bottom-up scanlines, and can
   apply a horizontal wrap offset.
3. Unwrap and crop once. Record every offset. Apply the identical operation to
   every derived layer.
4. Prefer collision OBJ geometry for a new walkable-area structure. Use the
   matching Detour navmesh to exclude flat but unreachable collision surfaces
   such as roofs. Select the connected navmesh component from one verified
   walkable world-coordinate seed. Add another verified seed when a legitimate
   walkable region is separated by a model seam; never render every
   disconnected polygon island. If geometry is unavailable, derive a clean
   structure layer from another deterministic source without promoting static
   labels or landmark symbols into separate runtime layers. The vanilla and
   structure outputs must have identical dimensions and pixel coordinates.
   LandSandBoat OBJ/nav coordinates use X directly but use Z opposite Ashita's
   world Y: `world_x = nav_x` and `world_y = -nav_z`. Apply that conversion to
   both seed coordinates and rendered vertices.
   If collision geometry continues beyond a real zone-transition endpoint,
   record a narrow image-space exclusion rectangle that trims only the
   off-map tail. Never use broad exclusion boxes to reshape interior geometry.
5. Obtain the map's scale metadata. Minimap.dll's coordinate converter proves
   that `image_pixels_per_yalm = map_scale_byte / 5`. A 32-pixel vanilla grid
   cell therefore spans `grid_yalms = 160 / map_scale_byte`. Store both results
   per map; do not use a repository-wide default as calibration. The earlier
   `32 / (map_scale_byte * 10)` formula only agrees when the scale byte is `4`
   and mis-scales every other page.
6. Determine the image pixel represented by world `(0, 0)`. Read the signed
   `OffsetX` and `OffsetY` fields at `+0x0A` and `+0x0C` of the matching
   14-byte FFXiMain map-table record:

   ```text
   origin_x = -OffsetX
   origin_y = -OffsetY
   ```

   Minimap.dll's coordinate converter calculates
   `image_x = world_x * scale - OffsetX` and
   `image_y = -world_y * scale - OffsetY`, so these negations are the exact
   source-image origin. The earlier conclusion that the offsets were not final
   pixels came from combining them with an incorrect reciprocal scale. Upper
   Jeuno independently confirms record offsets `(-272,-304)` and source origin
   `(272,304)`.

   If the map record cannot be read, Minimap.dll's runtime doubles at
   `runtime + 0x18` and `runtime + 0x20` can provide a live fallback:

   ```text
   origin_x = runtime_map_x - world_x * image_pixels_per_yalm
   origin_y = runtime_map_y + world_y * image_pixels_per_yalm
   ```

   Separately record the printed H-8 cell center as `grid_origin_x`,
   `grid_origin_y` when it differs from world `(0, 0)`.
7. Derive `image_pixels_per_yalm` from source metadata or at least two verified,
   widely separated control points:

   ```text
   scale_x = (image_x2 - image_x1) / (world_x2 - world_x1)
   scale_y = -(image_y2 - image_y1) / (world_y2 - world_y1)
   ```

   For an ordinary north-up map, `scale_x` and `scale_y` should agree within
   pixel-measurement tolerance. A meaningful disagreement indicates a wrong
   crop, wrap, page, origin, or control point; do not hide it with separate
   arbitrary X and Y tuning.
8. Add the resulting values to `ashitaminimap_maps.lua`.

For a multi-page zone, use `structure_pages[page_id]` rather than one
`structure_image` when the stock pages do not share identical geometry. The
walkable-map generator accepts `--minimum-elevation` and
`--maximum-elevation` to isolate a verified Detour height band before
connectivity filtering and rendering. Detour elevation is the navmesh
vertex's second coordinate; record its bounds in the map provenance.

Metalworks is the reference example:

```text
origin                = (253, 255.5)
grid_yalms            = 40
image_pixels_per_yalm = 0.80
```

Its earlier `1.60` scale and global `20`-yalm grid produced a map that looked
plausible but expanded static geometry incorrectly relative to live markers.
This is why visual tuning alone is not an acceptable calibration method.

## Precision validation

Validate a new map before calling it complete:

1. Confirm vanilla and structure PNGs have the same dimensions.
2. Confirm transparent pixels have real zero alpha.
3. Before comparing static geometry, match the custom and stock zoom using
   several live entities as control points. Their screen-space offsets from the
   player must agree on both maps. If the entity pattern has a different
   spread, correct zoom first; an origin cannot be measured from mismatched
   scales.
4. At a known player position, compute the expected source pixel with the
   calibration formula and verify that the corresponding static location sits
   under the player marker.
5. Repeat at no fewer than three well-separated positions, preferably near
   different edges of the accessible area.
6. Compare several live entities against recognizable static geometry. Use
   exact live world coordinates, not coordinates guessed from a grid label.
7. Test at multiple user zoom levels. Static geometry, the player, entities,
   target rings, and the coordinate grid must scale around the same center.
8. Toggle vanilla and structure independently and confirm neither layer moves.
9. Check any additional floors or map variants separately.

Interpret mismatches by their pattern:

- A constant error everywhere is usually an origin or recorded crop offset.
- An error that grows with distance from the player or origin is usually scale.
- Correct X with incorrect Y, or vice versa, usually indicates an axis sign,
  crop, or unwrap error.
- A sudden regional mismatch usually means the wrong page, floor, or a
  discontinuous composite texture.
- Small marker-only motion can come from game update timing; do not compensate
  for it by distorting the static map transform.
- Entities from a different loaded floor can have valid X/Y coordinates but
  belong to another map page. Filter dynamic entities by elevation before
  judging scale or origin.

Record the source DAT/page, wrap or crop values, calibration derivation, and
validation positions in the map entry comments or an adjacent manifest when
adding the map. That provenance is part of the map asset.

## Current automation boundary

The repository provides deterministic DAT decoding and a collision/navmesh
walkable-mask generator. For vanilla fallback pages, the runtime now derives
page, scale, and world origin automatically from stock map state. Authored
assets still require deterministic wrap/crop metadata and multi-position
validation because their source coordinates may differ from the locally
imported stock page.

The desired future importer should:

1. identify the DAT map page;
2. decode and unwrap it;
3. extract the map scale;
4. calculate the post-crop world origin;
5. emit identically aligned vanilla and structure layers;
6. write or update the `ashitaminimap_maps.lua` entry;
7. produce a validation report from control points.

Even after automation, unusual multi-floor and composite maps must fail for
review instead of silently falling back to guessed constants.
