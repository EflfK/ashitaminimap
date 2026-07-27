# AshitaMinimap

AshitaMinimap is a read-only Ashita v4 Lua addon that renders its own transparent
minimap. It does not depend on the stock `Minimap.dll`.

The first prototype includes:

- a transparent PNG map layer;
- a Lua-rendered player arrow;
- visible player, NPC, monster, and current-target dots;
- a north-up 20-yalm coordinate grid with edge labels;
- a live `H-8`-style coordinate badge;
- an in-game configuration window with persistent settings;
- unlock-and-drag positioning;
- mouse-wheel zoom while the pointer is over the map;
- deterministic world-coordinate-to-image calibration;
- initial map definitions for South Gustaberg (zone 107), Port Bastok (zone 236),
  and Metalworks (zone 237).

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

- map visibility, position lock, size, zoom, opacity, and line-strength boost;
- an optional dark translucent backdrop for bright game environments;
- coordinate grid and coordinate badge visibility;
- player, NPC, monster, and entity-name markers.

Unlock the map in the configuration window or with `/aminimap unlock`, then
left-drag anywhere on the map to move it. Use `/aminimap lock` when finished.
Move the mouse over the map and scroll the wheel to zoom in or out.

Changes are saved automatically to `ashitaminimap_config.lua` after a short
delay. The **Save** button and `/aminimap save` command save immediately.
You can still edit the Lua configuration manually and run `/aminimap reload`.

If the transparent map linework is difficult to see, raise **Map visibility**.
This composites the alpha layer more strongly than the ordinary opacity control
can. **Dark backdrop** adds contrast behind the entire viewport and can be set
back to `0%` whenever a completely clear background is preferred.

Map calibration lives in `ashitaminimap_maps.lua`. The image and world coordinate
systems are related by:

```text
image_x = origin_x + world_x * image_pixels_per_yalm
image_y = origin_y - world_y * image_pixels_per_yalm
```

This calibration is independent of the user's on-screen zoom.

## Map asset status

Metalworks now uses the exact vanilla DAT pixels, unwrapped into north-up map
space before transparency is applied. The other bundled images remain
transparency and calibration prototypes generated from locally installed
reference maps. All currently keep only the strongest map linework and suppress
most of the parchment background. They are not yet precision-traced walkable-area
masks.

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
