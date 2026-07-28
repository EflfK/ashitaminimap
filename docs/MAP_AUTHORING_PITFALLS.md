# Map authoring pitfalls and diagnostic playbook

Read this with `MAP_CALIBRATION.md` before creating or correcting a map. This
document records the failure modes discovered while building the production
Windurst Woods map so a future task does not need the original chat history.

## Work in this order

1. Decode and reconstruct the complete vanilla page.
2. Establish one final source-image coordinate system.
3. Generate the walkable structure in that coordinate system.
4. Calibrate navigation geometry and the printed coordinate grid separately.
5. Set overview bounds from the complete vanilla page.
6. Validate with live player and entity coordinates at several positions.

Do not tune later stages to compensate for an error in an earlier stage.

## A dark seam may be a wrap boundary, not a crop boundary

Always inspect the entire decoded 512 × 512 DAT before choosing a crop.
Coordinate letters, row numbers, borders, and place names that stop at one
texture edge and continue at the opposite edge indicate a cyclic page.

Windurst Woods initially appeared to end at x=364 because x=364–365 is a dark
vertical seam. Cropping to `(0,0)-(364,512)` removed the wrapped A–D section and
made the left side look cut off. The correct reconstruction moves source x=366
to output x=0:

```text
x_offset = 512 - 366 = 146
new_x = (old_x + 146) mod 512
```

The resulting page runs continuously from A through O and retains all four
borders. Generate it with:

```text
python tools/generate_vanilla_layer.py \
  <FFXI>/ROM/18/72.DAT \
  assets/maps/241_vanilla.png \
  --x-offset 146 \
  --box 0,0,512,512
```

Before accepting a crop or unwrap, verify:

- the coordinate sequence is continuous;
- labels cut at one old texture edge resume at the other;
- the complete outer border is present;
- no neighboring or duplicate page is included;
- the output remains at its original resolution.

## Do not assume every vanilla DAT uses the paletted layout

The ordinary Jeuno city pages for zones 243–245 use the same paletted layout
and `+146 px` cyclic reconstruction as Windurst Woods. Port Jeuno's installed
`ROM/18/78.DAT`, however, identifies a DXT3 texture and is shorter than the
paletted files.

The DXT3 payload does not begin at a fixed round file offset. Locate the
`0xA1`/`0xB1` image header, read the type at header `+0x39`, payload size at
`+0x3D`, and compressed blocks at `+0x45`. Starting at `0x70`, `0x110`, or
another guessed boundary shifts the 16-byte blocks and produces
plausible-looking cyan/magenta noise. DXT pages are already top-to-bottom and
must not receive the indexed format's vertical flip or `+146 px` unwrap.

Fail closed when a decoder does not support the exact format. Do not substitute
an unlicensed map pack or a guessed decode merely to fill the slot.

## Apply every spatial transform to every source

Once an unwrap, crop, or offset is chosen, it defines the map's source-image
coordinate system. Apply it identically to:

- the vanilla image;
- the generated structure;
- `origin_x` and `origin_y`;
- `grid_origin_x` and `grid_origin_y`;
- `view_bounds`;
- image-space exclusions and other recorded pixel rectangles.

For Windurst, the +146 px unwrap changed the verified geometry origin from
`x=108.5` to `x=254.5`. Its western transition exclusion changed from
`(0,360)-(61,371)` to `(146,360)-(207,371)`. Moving only the vanilla image
would make correctly related entity markers appear displaced from the
structure.

If an offset causes a rectangle to cross the texture boundary, split that
rectangle into two non-wrapping rectangles instead of silently clipping it.

## Navigation origin and printed-grid origin are different concepts

`origin_x` and `origin_y` identify the image pixel for navigation world
coordinate `(0,0)`. They control the structure, player, and entity transform.

`grid_origin_x` and `grid_origin_y` identify the image pixel at the center of
printed vanilla cell H-8. They control Lua grid lines, edge labels, and the
coordinate badge. They default to the navigation origin only when the two
origins genuinely coincide.

Windurst Woods uses:

```text
navigation origin = (254.5, 288.0)
H-8 grid origin   = (255.0, 256.0)
```

Using `(254.5,288)` for both made every Lua row appear one complete 32 px cell
below the vanilla row and made the coordinate badge one quadrant row wrong.
Do not move the navigation origin to fix this; record the separate grid origin.

## Overview bounds belong to the complete vanilla page

`view_bounds` controls the minimum zoom and the camera's overview clamping. It
must describe the final complete vanilla page, including coordinate strips and
outer borders. It is not:

- the structure layer's alpha bounding box;
- a convenient crop around current walkable geometry;
- a way to hide an incorrectly decoded texture region.

For the unwrapped Windurst page:

```lua
view_bounds = { left = 0, top = 0, right = 512, bottom = 512 }
```

At maximum zoom-out, the page should fit without cropping. Near a page edge,
the camera may move the player off-center to keep the opposite edge visible.
Lua grid lines and edge labels must be clipped to the projected `view_bounds`
rectangle so letters or numbers never continue through transparent space
outside the vanilla page.

## Build walkable structure from collision plus navigation data

Collision OBJ geometry alone contains roofs, decorative surfaces, and other
flat but inaccessible polygons. Use the matching Detour navmesh to select
traversable polygons, then retain the connected component containing a verified
walkable world-coordinate seed.

Common symptoms:

| Symptom | Likely cause | Correction |
| --- | --- | --- |
| Large blocky protrusions | Collision geometry rendered without sufficient navmesh filtering | Select only the seeded Detour-connected component |
| Real walkable region missing | Model seam separates valid navmesh components | Add another verified walkable seed for that region |
| Long straight tail at a zone exit | Collision continues past the useful transition endpoint | Add one narrow image-space exclusion at the tail |
| Interior paths disappear | Exclusion is too broad | Remove it and trim only the proven off-map segment |
| Roofs or platforms appear playable | All flat collision polygons were accepted | Require matching navmesh traversability |

LandSandBoat axes require:

```text
world_x = nav_x
world_y = -nav_z
```

Apply that conversion to both vertices and seed coordinates.

## Diagnose alignment from the mismatch pattern

First match custom and stock zoom by comparing several live entity markers.
Their relative spread is more reliable than marker centers or decorative map
lines.

| Observation | Interpretation |
| --- | --- |
| Entity dots have different spread | Scale is wrong |
| Entity dots match each other, but all static geometry is uniformly shifted | Origin, crop, or unwrap is wrong |
| Error grows with distance | Scale is wrong |
| X is correct but Y is uniformly wrong | Y origin, crop, or axis sign is wrong |
| Grid rows differ by exactly one cell while entities align | Printed-grid origin is wrong; do not change geometry calibration |
| Only one region disagrees | Wrong page/floor or discontinuous composite texture |
| Tiny marker-only motion changes between screenshots | Game update timing; do not distort the map |

Temporarily shrinking both minimaps' entity dots makes center-to-center
comparison easier. Restore normal marker size after calibration.

For stock fallback pages, use the DLL's actual source-pixel scale:

```text
image_pixels_per_yalm = map_scale_byte / 5
grid_yalms             = 160 / map_scale_byte
```

Do not restore the older reciprocal formula. It accidentally matches scale
byte `4`, making initial maps look correct, but changes entity spread on every
other scale. Also compare entity elevation with the player before rendering;
loaded enemies on another floor can have plausible X/Y coordinates while
belonging to a different active page.

Use exact world coordinates from live game state. Never derive calibration
coordinates from an `H-8` label or from an approximate screenshot.

## Runtime layer rules

Production maps have only two independently controlled static layers:

1. optional vanilla reference;
2. clean walkable structure.

Do not create separate static place-label or landmark layers. Labels and
symbols remain available only through the optional vanilla layer. Dynamic
players, NPCs, monsters, targets, the player arrow, coordinate grid, and badge
remain Lua-rendered.

Both PNGs must have identical dimensions and real per-pixel alpha. Pixels
outside the walkable structure must have alpha zero; a dark RGB value with
nonzero alpha is not transparent.

## Live verification and deployment

After changing addon code or assets:

1. preserve the installed `ashitaminimap_config.lua`;
2. sync every changed runtime file and asset into the Ashita addon directory;
3. reload `ashitaminimap` through AshitaDevTools;
4. confirm the chat log reports the expected addon version;
5. test overview zoom, an ordinary zoom, and a close zoom;
6. test at multiple well-separated player positions;
7. toggle vanilla and structure independently;
8. confirm the coordinate badge agrees with the printed vanilla cell.

Copying files without reloading leaves old Lua metadata and texture handles in
memory. A screenshot taken before a confirmed reload does not validate the new
build.

## Determinism and completion checklist

Before publishing a map:

- record the source DAT, internal page or variant, wrap offset, crop, and
  exclusions;
- record navigation origin, printed H-8 grid origin, scale, and grid size;
- regenerate each asset twice and compare hashes;
- confirm all outputs are the expected dimensions;
- inspect each output's alpha bounding box;
- run `git diff --check`;
- reload the installed addon and confirm its version in the game log;
- document any zone-specific exception next to the map asset;
- commit and push the verified repository state.

For Windurst Woods, `assets/maps/241.md` is the concrete provenance example.
