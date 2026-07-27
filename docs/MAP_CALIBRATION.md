# Map import and calibration

This document is the repeatable procedure for adding precision maps to
AshitaMinimap. Metalworks established the rendering transform; new maps should
reuse that transform with map-specific metadata rather than being manually
nudged until they look close.

## What is universal

AshitaMinimap is north-up. A calibrated map converts world coordinates to
source-image pixels with:

```text
image_x = origin_x + world_x * image_pixels_per_yalm
image_y = origin_y - world_y * image_pixels_per_yalm
```

The same transform must be used for:

- the structure layer;
- the label layer;
- the static landmark and service-symbol layer;
- the player marker;
- entity and target markers;
- the Lua-rendered coordinate grid.

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
    structure_image = 'assets/maps/<zone>_structure.png',
    labels_image = 'assets/maps/<zone>_labels.png',
    landmarks_image = 'assets/maps/<zone>_landmarks.png',
    width = 512,
    height = 512,
    origin_x = 253,
    origin_y = 253,
    grid_yalms = 40,
    image_pixels_per_yalm = 0.80,
},
```

A temporary flattened `image` is supported, but a production map should use
separate structure, label, and landmark layers when the source permits it.

## Deterministic import procedure

1. Identify the exact vanilla DAT map page or variant for the zone. Do not
   assume the zone has only one floor or page.
2. Decode the DAT without resizing it. `tools/generate_vanilla_map.py` decodes
   the 512-by-512 palette texture, corrects its bottom-up scanlines, and can
   apply a horizontal wrap offset.
3. Unwrap and crop once. Record every offset. Apply the identical operation to
   every derived layer.
4. Split structure from labels with `tools/split_map_layers.py`, then split
   known static landmark symbols from ordinary text. The outputs must have
   identical dimensions and pixel coordinates.
5. Obtain the map's scale metadata. For known vanilla maps,
   `grid_yalms = map_scale_byte * 10`. Store the result per map; do not use a
   repository-wide default as calibration.
6. Determine the image pixel represented by world `(0, 0)`. That pixel becomes
   `origin_x`, `origin_y` after all wrap and crop operations.
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

1. Confirm structure and label PNGs have the same dimensions.
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
8. Toggle structure and labels independently and confirm neither layer moves.
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

Record the source DAT/page, wrap or crop values, calibration derivation, and
validation positions in the map entry comments or an adjacent manifest when
adding the map. That provenance is part of the map asset.

## Current automation boundary

The repository currently provides deterministic DAT decoding and layer
splitting, but it does not yet extract every calibration field automatically.
Until an importer generates the complete map entry, deriving and validating the
per-map metadata remains a required import step.

The desired future importer should:

1. identify the DAT map page;
2. decode and unwrap it;
3. extract the map scale;
4. calculate the post-crop world origin;
5. emit identically aligned structure and label layers;
6. write or update the `ashitaminimap_maps.lua` entry;
7. produce a validation report from control points.

Even after automation, unusual multi-floor and composite maps must fail for
review instead of silently falling back to guessed constants.
