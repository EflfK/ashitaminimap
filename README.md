# AshitaMinimap

AshitaMinimap is a read-only Ashita v4 Lua addon focused on high-quality,
display-only directional pathing for AshitaGuide and attended custom
destinations. It renders a transparent calibrated vanilla minimap, supported
markers, and computed routes. Rendering does not require the stock
`Minimap.dll`; when available, the addon reads its active page and calibration
state to improve automatic page selection.

The first prototype includes:

- a transparent PNG map layer;
- a Lua-rendered player arrow;
- visible player, NPC, monster, current-target, and tracked Wide Scan markers;
- a north-up, zone-calibrated coordinate grid with edge labels;
- a live `H-8`-style coordinate badge;
- a compact Vana'diel environment card with time, elemental day, moon phase,
  moon illumination, and current weather;
- an in-game configuration window with persistent settings;
- a Developer tab with an optional full navigation-graph web;
- unlock-and-drag positioning;
- mouse-wheel zoom while the pointer is over the map;
- a searchable Atlas for browsing other zones and setting attended waypoints;
- calibrated vanilla-map rendering with dormant retained structure support;
- deterministic world-coordinate-to-image calibration;
- routing-first map definitions for the Windurst cities and surrounding
  Sarutabaruta, Horutoto, Giddeus, Tahrongi, Buburimu, and Shakhrami corridor,
  plus the authored Bastok, Jeuno, and dungeon maps documented below;
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
/aminimap atlas
/aminimap atlas 126
/aminimap atlas hide
/aminimap grid
/aminimap reload
```

`/ashitaminimap` is an alias for `/aminimap`.

## Configuration

Run `/aminimap config` to open the in-game configuration window. It controls:

- map visibility, position lock, size, and zoom;
- vanilla-map visibility and opacity;
- an optional dark translucent backdrop for bright game environments;
- coordinate grid and coordinate badge visibility, with optional live numeric
  X/Y/Z values in the badge;
- Vana'diel time, elemental day, moon phase/illumination, and weather card
  visibility, plus an independently visible compact weather badge;
- possible Treasure Chest or Coffer spawn references for authored zones;
- static NM spawn-range references for authored zones that provide them;
- player, NPC, and monster dot markers;
- a violet crosshair for the entity the player actively tracks through the
  native Wide Scan interface, including an edge-clamped direction marker when
  it is outside the current viewport;
- current AshitaGuide step destinations, including page filtering and
  edge-clamped off-map markers;
- optional map-owned shortest paths from the player to AshitaGuide's current
  destination when the zone provides a navigation graph;
- optionally zoom-scaled entity dots, target rings, and player arrow;
- independently adjustable entity-dot and target-ring size.
- per-zone, per-page X/Y origin calibration with live preview and explicit save.

Valkurm Dunes uses the dense-range presentation for every NM with multiple
server-defined positions: one padded translucent blob is drawn instead of one
circle per point. Single-position encounters remain point markers. This affects
only the static NM reference layer; AshitaGuide's explicit `14A` placeholder
remains a separate damselfly icon.

South Gustaberg uses separate padded blobs for Leaping Lizzy's lowland and
northwest-upland relocation regions. AshitaGuide's hunt handoff adds one small
lizard marker at each exact Rock Lizard placeholder; floor-aware rendering
keeps the disconnected elevations distinct.

Authored NM records may also carry an official CatsEyeXI monster-page URL.
AshitaGuide's attached NM Hunt drawer exposes those fixed links and sends
display-only per-NM visibility choices through handoff version 4. AshitaMiniMap
does not fetch URLs, run timers, issue gameplay commands, or inspect live NM
state.

The minimap temporarily uses its battle-safe vertical position while the
native player, magic, or ability command menu is open, including while the
player is not engaged. It returns to the configured position when the menu
closes.

While the native inventory is open, the minimap moves only far enough upward
to remain above the item-description preview, then returns to its configured
position when inventory closes.

The minimap also reads the current top edge of the vanilla chat frame and
temporarily shifts upward when its visible square would overlap the chat. The
position follows changes to the native chat height automatically and returns to
the configured position when there is enough room.

Temporary vertical layout changes animate with a short, non-overshooting
ease-out. If the target position changes mid-motion, the minimap redirects from
its current position instead of jumping or restarting.

The **Developer** tab is display-only and disabled by default. Enable
**Developer mode**, then **Show all pathing**, to draw every node and connection
from the active page's navigation graph. Connections on the player's current
floor are bright cyan; other floors are dim so overlapping elevations remain
distinguishable. The graph web is intended for fast visual review: publish the
best deterministic graph, inspect it in game, and report concrete defects for
targeted correction instead of requiring a manual checkpoint for every
possible seam.

Structure-rendering implementation, settings, assets, and provenance remain
preserved in the repository, but normal operation neither loads nor renders
structure textures and exposes no structure controls.

Dynamic entities are intentionally anonymous. AshitaMinimap does not render
entity-name labels and must not recover names solely for minimap display. That
capability was deliberately removed; dots, target styling, and the player
arrow are the supported dynamic representations. The tracked Wide Scan marker
reads only the native tracking updates already received by the game; it does
not search for entities, start tracking, target, claim, or interact. On
imported multi-page maps, the game's native coordinate selector also filters
live dots and unassigned static references to the active stock page.

## AshitaGuide marker handoff

AshitaGuide publishes the focused step's destination coordinates to
`config/addons/ashitaguide/ashitaminimap_markers.lua`. AshitaMiniMap polls this
versioned, display-only handoff and renders valid markers through its own live
camera transform. A marker is shown only in the matching zone and, when
specified, on the matching map page. Off-map destinations clamp to the viewport
edge, approximate destinations use a diamond, and handoffs older than three
seconds are discarded so a crashed or unloaded guide cannot leave stale
markers behind.

Version 2 of the handoff retains a destination in another zone. AshitaMiniMap
combines verified map-owned walking graphs with the generated physical
zone-line catalog and the player's read-only Home Point and Survival Guide
registration masks. It selects a shortest fully authored cross-zone route,
draws only the current-zone walking leg, names the next transition in the
status strip, and recalculates from the observed arrival position after zoning.
When a later destination-zone graph gap prevents an end-to-end route, it still
draws a truthful current-zone handoff as a clearly labeled partial route and
leaves the final destination marker-only after zoning.
Warp is eligible only when its exact authored landing anchor is unambiguous.
See [Cross-zone world routes](docs/WORLD_ROUTES.md).

Version 3 can apply a validated style to explicit guide markers. A marker-only
NM step can disable pathing and render small damselfly icons at verified
placeholder coordinates instead of gold guide dots. The separate static NM
relocation blob remains visible. Placeholder coordinates are never inferred
from the NM relocation catalog.

Version 4 adds a bounded, display-only NM visibility section. AshitaMiniMap
uses it to show or hide authored NM references selected in AshitaGuide's
attached drawer; commands, timers, links, and hunt state remain outside this
display-only addon.

The handoff contains no commands, routes, or player actions. AshitaGuide
remains the source of guide state and supplies only destination coordinates.
AshitaMinimap owns the reusable zone navigation graph, snaps the player and
destination to that graph, computes the shortest connected route with A*, and
renders the active cyan and traveled slate segments. Moving more than 12 yalms
away from the displayed route triggers a new shortest-path calculation. The
compact map status strip reports remaining route distance. Turning the
**AshitaGuide shortest path** setting off leaves the destination marker intact.

Right-click an empty location on the map to place a temporary cyan custom
waypoint. Its shortest path takes priority over the current AshitaGuide
destination. Right-click the custom waypoint again to remove it; when a guide
is active, its destination marker and path immediately regain priority. The
custom waypoint is session-only and remains display-only.

## AI / MCP waypoints

`AshitaMiniMap.Mcp` exposes the same temporary custom-waypoint state without
requiring a complete AshitaGuide guide:

- `set_minimap_waypoint` accepts an exact zone id and world X/Y coordinates,
  plus an optional map id and Z coordinate;
- `clear_minimap_waypoint` restores AshitaGuide routing; and
- `minimap_waypoint_status` reports whether the addon accepted a routed,
  marker-only, cleared, expired, or rejected request.

Remote destinations require `mapId`. When Z is omitted, AshitaMiniMap resolves
it only when the authored path graph identifies one truthful floor; otherwise
the waypoint remains marker-only. MCP waypoints use the same cyan marker,
route priority, floor handling, and session-only lifecycle as a right-clicked
waypoint.

The MCP process atomically replaces
`config/addons/ashitaminimap/mcp_waypoint_request.lua`. AshitaMiniMap validates
and consumes each request id once, ignores requests more than 60 seconds old,
and writes its display-only acknowledgment to `mcp_waypoint_status.json`.
Neither file can contain commands, routes, input instructions, or destination
paths. The addon never moves, targets, interacts, injects packets, or sends a
game command.

Build the stdio server before configuring an MCP client:

```powershell
dotnet build .\src\AshitaMiniMap.Mcp\AshitaMiniMap.Mcp.csproj
```

Configure the client to launch the built executable or DLL. The default Ashita
root is `C:\Games\CatsEyeXI\catseyexi-client\Ashita`. Set
`ASHITAMINIMAP_CONFIG_DIR` to the full persistent config directory or
`ASHITA_ROOT` to another Ashita installation when necessary. Neither value can
be supplied through an MCP tool.

## Atlas and remote waypoints

Use the small **ATLAS** button on the minimap, `/aminimap atlas`, or **Open
Atlas** in the configuration window to browse any imported vanilla map without
leaving the current zone. Search by zone name or ID, or narrow the catalog to
maps that support waypoint placement, have authored pathing, or contain
multiple pages. Filters can be combined, and the previous/next buttons move
through the alphabetized filtered results. Choose a page independently, drag
to pan, use the mouse wheel to zoom, and toggle **NM spawns** to show or hide
the selected map's authored notorious-monster spawn ranges. Hover a visible
range for its name and spawn details. Atlas browsing shows the full authored
catalog independently of any active AshitaGuide hunt filter.
`/aminimap atlas <zone-id>` opens a
zone directly, and `/aminimap atlas hide` closes the window. The minimap button
highlights while Atlas is open.

Right-click the Atlas map to set the same session-only custom waypoint used by
the live minimap. A remote waypoint takes priority over AshitaGuide and uses the
existing authored world-route catalog to show the current walking leg and next
truthful handoff. If the selected zone or destination is not covered by a
complete graph, the waypoint remains visible without inventing a route. Click
**Clear waypoint** in Atlas to restore AshitaGuide routing.

Atlas pages use their imported or authored stored calibration. They never use
the current zone's live map center, and dynamic entities are not projected onto
remote zones. Overlapping floors must resolve unambiguously on the selected
page; otherwise the waypoint is retained as marker-only. Placement is disabled
when an exact stored calibration is not available.

Navigation graphs are deterministic build artifacts generated directly from
verified Detour topology plus live-verified transition and blocked-link
exceptions. They do not require a visible structure image. They are
display-only and never move, target, interact, queue commands, or automate
gameplay. Multi-page zones select the graph for the active authored page. See
[Path graph authoring](docs/PATH_GRAPHS.md). The level-ordered production
campaign is tracked in [the level 1-60 map queue](docs/LEVEL_60_MAP_BACKLOG.md).

Kuftal Tunnel can optionally draw filled gold coffer icons at all authored
possible Treasure Coffer locations. These are fixed, page-filtered reference
points for manual searching. The addon does not inspect the live coffer,
identify which point is occupied, or mark its current location. A possible
spawn is always a fixed reference; it does not claim live presence.

Davoi provides display-only wooden chest references for its 12 possible
Treasure Chest locations. Treasure Coffers use a separate rounded gold symbol
on authored maps such as Kuftal Tunnel. Davoi also provides static spawn-area
references for the zone's verified notorious monsters. These references come
from CatsEyeXI's public treasure, mob-script, and SQL data; they never report
whether a chest or NM is currently present.

Kuftal Tunnel also provides an optional filled Amemet spawn-range veil on page
2. It is derived from the 50 authored initial-spawn positions and deliberately
draws no singular NM marker. Hover the veil for its compact static-reference
card. The overlay does not inspect Amemet, report its status, or draw its patrol
route.

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

Map-calibration controls are currently hidden from the configuration window.
Existing per-zone and per-page `origin_adjustments` remain active and are still
loaded and saved. The retained controls can be restored for development by
setting `SHOW_MAP_CALIBRATION` to `true` in `ashitaminimap.lua`.

**Dark backdrop** adds contrast behind the viewport and can be set back to
`0%` whenever a completely clear background is preferred.

## Layer model

The renderer draws map content in this order:

1. optional dark backdrop;
2. optional calibrated vanilla map;
3. static NM spawn-range veils, when enabled for an authored zone;
4. coordinate grid;
5. fixed possible Treasure Chest (wood) or Treasure Coffer (gold) references,
   when enabled;
6. live entities;
7. current AshitaGuide destinations and computed display path;
8. player arrow;
9. coordinate badge and unlocked-state hint.

Structure-rendering code, metadata, generated assets, and provenance are
retained but dormant. Normal operation does not load or draw structure
textures, and the configuration window does not expose structure controls.
This can be restored later without losing prior work, but new routing work must
not generate or expand structure images unless explicitly requested.

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

When the stock Minimap plugin is loaded, AshitaMinimap reads its current page,
map-scale byte, and computed map-space center. Together with the live player
position, those values determine the stock page's exact world origin
automatically. The renderer remains independent: if that plugin is unavailable,
the imported catalog's default page and safe provisional calibration are used.
Multi-page zones can always be changed manually with `/aminimap page next`,
`prev`, or a page number; `/aminimap page auto` restores automatic selection.

See [Map import and calibration](docs/MAP_CALIBRATION.md) for the required
source-data, page reconstruction, calibration, and multi-position validation
procedure. New maps must use deterministic calibration rather than visual
tuning.

Also read [Map authoring pitfalls and diagnostic
playbook](docs/MAP_AUTHORING_PITFALLS.md) before adding another zone. It records
the DAT-wrap, grid-origin, overview-boundary, navmesh, deployment, and mismatch
diagnostics learned while completing Windurst Woods.

For every authored graph, follow [Path graph authoring](docs/PATH_GRAPHS.md)
and the routing-first scope in [navmesh component and transition
analysis](docs/MAP_COMPONENT_AUDIT.md). Resolve every component and ambiguous
transition that can affect supported destinations or normal guide routes.

## Map asset status

Metalworks uses exact vanilla DAT pixels as its geometry source and is
horizontally unwrapped. Windurst Woods and Jeuno instead use LandSandBoat
collision and navigation geometry to render only the accessible-area fill and
its boundaries. Ru'Lude Gardens, Upper Jeuno, and Lower Jeuno also include
committed reference layers. Port Jeuno obtains its optional vanilla layer from
the local universal fallback import.
Davoi uses its exact stock page-0 calibration with deterministic collision and
Detour navigation geometry. Its static reference overlays include all 12
CatsEyeXI Treasure Chest possibilities and verified NM spawn areas.
Garlaige Citadel uses page-aware structure selection. Pages 1 and 16 have
authored layers generated from bounded Detour elevation bands; their
calibration is registered, but the zone remains partial pending complete
component and live-transition audits. Pages 2, 3, and 14 intentionally fall
back to vanilla only.
Batallia Downs, Toraimarai Canal, The Eldieme Necropolis, Bastok Markets, and
Mhaura now have deterministic destination-bearing graphs with exact stock
calibration. They remain partial where native components meet at stairs,
gates, drops, platforms, or thresholds that still require attended transition
captures; those cross-component legs deliberately remain marker-only.
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
