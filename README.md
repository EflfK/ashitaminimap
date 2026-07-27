# AshitaMinimap

AshitaMinimap is a read-only Ashita v4 Lua addon that renders its own transparent
minimap. It does not depend on the stock `Minimap.dll`.

The first prototype includes:

- a transparent PNG map layer;
- a Lua-rendered player arrow;
- visible player, NPC, monster, and current-target dots;
- a north-up, zone-calibrated coordinate grid with edge labels;
- a live `H-8`-style coordinate badge;
- an in-game configuration window with persistent settings;
- unlock-and-drag positioning;
- mouse-wheel zoom while the pointer is over the map;
- independently composited vanilla, structure, label, and landmark layers;
- deterministic world-coordinate-to-image calibration;
- map definitions for South Gustaberg (zone 107), Port Bastok (zone 236),
  Metalworks (zone 237), and Windurst Woods (zone 241).

## Commands

```text
/aminimap show
/aminimap hide
/aminimap toggle
/aminimap config
/aminimap lock
/aminimap unlock
/aminimap save
/aminimap zoomin
/aminimap zoomout
/aminimap grid
/aminimap names
/aminimap reload
```

`/ashitaminimap` is an alias for `/aminimap`.

## Configuration

Run `/aminimap config` to open the in-game configuration window. It controls:

- map visibility, position lock, size, and zoom;
- independent vanilla, structure, label, and landmark visibility and opacity;
- independent structure, label, and landmark line-strength boost;
- an optional dark translucent backdrop for bright game environments;
- coordinate grid and coordinate badge visibility;
- player, NPC, monster, and entity-name markers.
- optionally zoom-scaled entity dots, target rings, and player arrow;
- independently adjustable entity-dot and target-ring size.

Unlock the map in the configuration window or with `/aminimap unlock`, then
left-drag anywhere on the map to move it. Use `/aminimap lock` when finished.
Move the mouse over the map and scroll the wheel to zoom in or out.
Dynamic marker positions always follow the world zoom. By default their visual
size also scales relative to the original `4.41 px/yalm` zoom, clamped to a
usable range. Disable **Scale dynamic markers with zoom** if constant-size
icons are preferred. **Marker size** scales the dots and target rings
independently of map zoom; smaller values are useful for calibration
screenshots without making the player arrow harder to see.

Maximum zoom is `20.00 px/yalm`. The minimum is calculated from the current
viewport size, map scale, and `view_bounds`, so maximum zoom-out fits the full
calibrated page along its largest axis but never shrinks it into a thumbnail.
Grid labels outside FFXI's valid `A–Z / 1–16` range are not drawn.

At overview scales, the camera follows the player until centering them would
push part of the calibrated map page outside the viewport. It then shifts just
enough to keep the page visible. If the viewport is larger than a map axis, that
axis is centered as a whole. The player, entities, grid, and every static layer
share this camera transform.

Changes are saved automatically to `ashitaminimap_config.lua` after a short
delay. The **Save** button and `/aminimap save` command save immediately.
You can still edit the Lua configuration manually and run `/aminimap reload`.

If the transparent map linework is difficult to see, raise **Structure
visibility** or **Label visibility**. These composite their respective alpha
layers more strongly than ordinary opacity controls can. **Dark backdrop** adds
contrast behind the entire viewport and can be set back to `0%` whenever a
completely clear background is preferred.

## Layer model

The renderer draws map content in this order:

1. optional dark backdrop;
2. optional calibrated vanilla map;
3. calibrated map structure;
4. place names and exit labels;
5. static service and landmark symbols;
6. coordinate grid;
7. live entities and player arrow;
8. coordinate badge and unlocked-state hint.

Windurst Woods is the first production dark-tactical map. Its structure is a
filled walkable-area mask generated from collision geometry plus Detour
traversability data; the background is truly transparent. Place names and
static landmark symbols remain separate optional overlays. A fourth optional
layer reproduces the vanilla parchment map with independently adjustable
opacity. All four share the same verified origin and scale. Metalworks has
separate structure and
annotation layers. South Gustaberg and Port Bastok still use flattened
prototype assets, so their embedded labels cannot yet be hidden independently.

Map calibration lives in `ashitaminimap_maps.lua`. The image and world coordinate
systems are related by:

```text
image_x = origin_x + world_x * image_pixels_per_yalm
image_y = origin_y - world_y * image_pixels_per_yalm
```

This calibration is independent of the user's on-screen zoom.
`grid_yalms` is also stored per map because FFXI zones do not all use the same
world distance per coordinate cell. For example, Metalworks and Port Bastok use
40-yalm cells, while South Gustaberg uses 100-yalm cells.

See [Map import and calibration](docs/MAP_CALIBRATION.md) for the required
source-data, layer-splitting, calibration, and multi-position validation
procedure. New maps must use deterministic calibration rather than visual
tuning.

## Map asset status

Metalworks uses exact vanilla DAT pixels as its geometry source and is
horizontally unwrapped. Windurst Woods instead uses LandSandBoat collision and
navigation geometry to render only the accessible-area fill and its boundaries.
Its warm place labels and amber landmark symbols are independent optional
vanilla-derived layers.
The South Gustaberg and Port Bastok images remain flattened transparency and
calibration prototypes generated from locally installed reference maps. They
are not yet precision-traced walkable-area masks.

Production map packs should use hand-authored or deterministic vector masks tied
to verified map calibration. AI-generated artwork should never be used as the
source of navigation geometry.

## Install

Copy this directory to:

```text
Ashita/addons/ashitaminimap
```

Then load it in game:

```text
/addon load ashitaminimap
```
