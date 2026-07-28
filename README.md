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
- independently composited vanilla and walkable-structure layers;
- deterministic world-coordinate-to-image calibration;
- map definitions for South Gustaberg (zone 107), Port Bastok (zone 236),
  Metalworks (zone 237), Windurst Woods (zone 241), and all four Jeuno city
  zones (zones 243–246).
- locally generated stock-map fallbacks for every map page found in the
  installed FFXI client.

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
/aminimap page auto
/aminimap page next
/aminimap page prev
/aminimap page 2
/aminimap grid
/aminimap names
/aminimap reload
```

`/ashitaminimap` is an alias for `/aminimap`.

## Configuration

Run `/aminimap config` to open the in-game configuration window. It controls:

- map visibility, position lock, size, and zoom;
- independent vanilla and structure visibility and opacity;
- adjustable structure line-strength boost;
- an optional dark translucent backdrop for bright game environments;
- coordinate grid and coordinate badge visibility;
- player, NPC, monster, and entity-name markers.
- optionally zoom-scaled entity dots, target rings, and player arrow;
- independently adjustable entity-dot and target-ring size.
- per-zone, per-page X/Y origin calibration with live preview and explicit save.

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
viewport size, map scale, and `view_bounds`, so maximum zoom-out is exactly the
complete vanilla map page, including its coordinate strips and border, and
never shrinks it into a thumbnail.
Grid labels outside FFXI's valid `A–Z / 1–16` range are not drawn.

At overview scales, the camera follows the player until centering them would
push part of the calibrated map page outside the viewport. It then shifts just
enough to keep the page visible. If the viewport is larger than a map axis, that
axis is centered as a whole. The player, entities, grid, and every static layer
share this camera transform.

Changes are saved automatically to `ashitaminimap_config.lua` after a short
delay. The **Save** button and `/aminimap save` command save immediately.
You can still edit the Lua configuration manually and run `/aminimap reload`.

For a stock fallback whose geometry is uniformly displaced, use the **Map
calibration** X/Y source-pixel controls. The adjustment is scoped to the
current zone and vanilla page. Slider changes move the map immediately but
remain session-only until **Save calibration** is selected. Reloading the addon
before saving restores the last persisted values.

If the transparent map linework is difficult to see, raise **Structure
visibility**. This composites its alpha layer more strongly than an ordinary
opacity control can. **Dark backdrop** adds
contrast behind the entire viewport and can be set back to `0%` whenever a
completely clear background is preferred.

## Layer model

The renderer draws map content in this order:

1. optional dark backdrop;
2. optional calibrated vanilla map;
3. calibrated map structure;
4. coordinate grid;
5. live entities and player arrow;
6. coordinate badge and unlocked-state hint.

Windurst Woods and the four Jeuno city zones use production dark-tactical
maps. Their structure layers are filled walkable-area masks generated from
collision geometry plus Detour traversability data; the background is truly
transparent. Optional vanilla parchment layers have independently adjustable
opacity. Authored layers share the same calibrated origin and scale. Port
Jeuno pairs its structure with the locally imported stock page; Metalworks
keeps its authored structure-focused presentation.
South Gustaberg and Port Bastok still use flattened prototype assets, so their
embedded labels remain part of those legacy images.

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

## Universal vanilla fallback

Run the local importer once against the game installation:

```text
python tools/import_vanilla_maps.py "<FFXI installation>/FINAL FANTASY XI"
```

It discovers embedded map page identifiers, decodes both indexed and DXT3
stock formats, and writes `assets/vanilla/*.png` plus
`ashitaminimap_vanilla_maps.lua`. These generated files are installed locally
but intentionally ignored by Git; the repository does not redistribute the
game's stock artwork.

An authored entry in `ashitaminimap_maps.lua` takes precedence. Missing fields
are filled from the matching stock page, so Port Jeuno can pair its authored
walkable structure with its vanilla page. A zone with no authored entry shows
the vanilla page by itself.

When the stock Minimap plugin is loaded, AshitaMinimap reads its current
page-record metadata for automatic page selection, per-page scale, and X/Y
world origin. The renderer remains independent: if that plugin is unavailable,
the imported catalog's default page and provisional fallback calibration are
used. Multi-page zones can always be changed manually with `/aminimap page
next`, `prev`, or a page number; `/aminimap page auto` restores automatic
selection.

See [Map import and calibration](docs/MAP_CALIBRATION.md) for the required
source-data, page reconstruction, calibration, and multi-position validation
procedure. New maps must use deterministic calibration rather than visual
tuning.

Also read [Map authoring pitfalls and diagnostic
playbook](docs/MAP_AUTHORING_PITFALLS.md) before adding another zone. It records
the DAT-wrap, grid-origin, overview-boundary, navmesh, deployment, and mismatch
diagnostics learned while completing Windurst Woods.

## Map asset status

Metalworks uses exact vanilla DAT pixels as its geometry source and is
horizontally unwrapped. Windurst Woods and Jeuno instead use LandSandBoat
collision and navigation geometry to render only the accessible-area fill and
its boundaries. Ru'Lude Gardens, Upper Jeuno, and Lower Jeuno also include
committed reference layers. Port Jeuno obtains its optional vanilla layer from
the local universal fallback import.
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
