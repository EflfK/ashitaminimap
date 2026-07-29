# Kuftal Tunnel map provenance

Kuftal Tunnel is the reference for a multi-page dungeon whose logical maps,
overlapping elevations, and transitional fragments must be authored together.
Do not replace these layers with one unioned texture.

## Stock records

The installed `FFXiMain.dll` map table contains four 14-byte records for zone
174. Page 0 artwork also exists in the DAT catalog, but it has no matching map
record and is not one of the four logical maps.

| Page | Scale byte | Source origin | Record offsets |
| --- | ---: | ---: | ---: |
| 1 | 4 | `(272, 96)` | `(-272, -96)` |
| 2 | 4 | `(208, 304)` | `(-208, -304)` |
| 15 | 4 | `(176, 160)` | `(-176, -160)` |
| 16 | 4 | `(216, 304)` | `(-216, -304)` |

All four pages therefore use `image_pixels_per_yalm = 0.8` and
`grid_yalms = 40`. The logical-page correspondence was cross-checked against
widely separated in-game coordinate references:

- page 1: southern Western Altepa route near `(1, -220)`;
- page 2: central map near `(1, -81)`;
- page 15: southern upper map near `(120, -60)`;
- page 16: northern upper map near `(110, 40)`.

## Geometry sources and classification

Sources:

- collision OBJ: LandSandBoat `Kuftal_Tunnel.obj`;
- Detour navmesh: `xiNavmeshes/Kuftal_Tunnel.nav`;
- stock page images: local FFXI DAT imports `174_01`, `174_02`, `174_15`,
  and `174_16`.

The navmesh contains 3,259 polygons and 260 seam-connected components at a
maximum step of `0.65`; 56 components contain at least five polygons. This is
not evidence that the zone has 260 floors. Most small components are slopes,
landings, narrow transition pieces, or collision fragments. The authored
layers deliberately use elevation bands for the overview page and verified
component seeds for the two upper pages.

Detour elevation has the opposite sign from the player's Ashita Z in this
zone. A player Z of about `-10` lies in raw Detour elevation `+7..+13`.
Always record both conventions and never choose a band by sign intuition.

| Page | Classification | Selection |
| --- | --- | --- |
| 1 | Current southern floor | raw elevation `<=15`, clipped to the recorded page extent, seam closure radius `1.25` |
| 1 | Descending/deeper route | raw elevation `>=15`, clipped to the recorded page extent |
| 1 | Verified floor transition | path-clipped transverse cyan/violet stripes centered at source pixel `(290, 252)` |
| 2 | Main central elevation | raw elevation `-6..6` |
| 2 | Upper alternate elevations | raw elevation `<=-6` |
| 2 | Lower alternate elevations | raw elevation `>=6` |
| 15 | Main upper component | seed `(126.245, -50.1)`, raw elevation `<=-17` |
| 15 | Higher southern continuation | seed `(40.112, -186.667)`, raw elevation `<=-25` |
| 15 | Lower north connector | seed `(64.112, 14.083)`, narrowly clipped to the stock connector |
| 16 | Main upper component | seed `(36.528, 140.083)`, raw elevation `-25..-15` |
| 16 | Higher room | seed `(56.112, 135.0)`, raw elevation `<=-25` |
| 16 | Lower west connector | seed `(-49.43, 101.0)`, clipped to the stock page |
| 16 | Lower east connector | seed `(179.695, 112.0)`, clipped to the stock page |

Page 2 is the broad overview and intentionally shows all verified elevation
bands. Cyan is the main map elevation; violet layers are alternate floors or
connectors. Drawing the cyan layer last keeps the current logical floor legible
where layers overlap.

Page 1 uses separately clipped cyan and violet floor assets. This prevents the
current cyan layer from remaining bright underneath the inactive violet floor.
The expanded seam closure prevents raw elevation thresholds from breaking
walkable slopes and tile seams into dots. Both geometry layers use
`--seam-closure-radius 1.25`; the default remains `0.25` for other maps. The
verified live position `(22.445, -195.267, -9.982)` maps to source pixel
`(290,252)`. A small geometry-clipped tapered threshold points southwest from
that position toward the violet lower route. The stripes cross the path
direction: cyan stripes widen toward the cyan floor, violet stripes widen
toward the violet floor, and both have equal width at the midpoint. The
path-aligned capsule avoids the previous circular sticker shape, and alpha is
feathered only at its two ends. Regenerate with the shared defaults: half
length `7`, half width `4.5`, stripe period `5`, end feather `1.5`, direction
`(-0.6,0.8)`, and alpha `190`. Its `floor_transition` runtime role uses one
visibility pass and fades from overview to close-zoom opacity.

Every Kuftal floor layer declares player-Z bounds. The matching floor uses
`structure_opacity`; all other floors use the independent
`inactive_floor_opacity` setting (default `0.14`). Page 1 switches at player Z
`-15`. Pages 2, 15, and 16 use the verified bands recorded in
`ashitaminimap_maps.lua`.

## Possible coffer spawn references

Kuftal has an optional marker overlay containing 13 fixed possible Treasure
Coffer locations. The positions come from CatsEyeXI's public
`scripts/globals/treasure.lua` Kuftal table and match the corresponding
LandSandBoat data. Its `setPos` tuples store
`(x, vertical, horizontal)`, so the last two values are converted to
AshitaMinimap's `(x, y, z)` convention.

Twelve locations belong to stock page 2. The deeper location at
`(-27.946, -183.709, -21.825)` belongs to page 1. Markers are filtered by the
active stock page and compared with the same authored elevation bands used by
the page's structure layers. A marker on the player's floor uses its configured
color opacity. A marker proven to be on another authored floor uses the
user-level `inactive_floor_opacity` setting, keeping it visible without
competing with current-floor possibilities. If either elevation cannot be
classified into an authored band, the marker remains fully visible rather than
implying an unverified floor relationship.

This overlay is static reference data. It does not inspect entities, locate the
currently spawned coffer, distinguish an occupied spawn point, or imply that a
coffer is present. Filled gold coffer icons distinguish these references from
the solid live entity dots.

## Amemet spawn-range reference

Kuftal page 2 has an optional filled range veil for Amemet. Its 50 points come
from the initial `spawnPoints` table in CatsEyeXI's public
`scripts/zones/Kuftal_Tunnel/mobs/Amemet.lua`; source tuples are converted from
`(x, vertical, horizontal)` to minimap `(x, y)`. The 13-entry `phList` supplies
the placeholder count shown in the hover card. The declared level is 66.

Each verified starting point contributes one small translucent disc. Their
overlap reads as a continuous area rather than 50 individual markers, while
remaining faithful to the non-convex distribution of the source positions.
The veil renders immediately above the vanilla and authored pathing layers.
The grid, coffers, live markers, player arrow, and hover card all remain above
it. The card stays fully readable even when the range itself uses other-floor
opacity. No singular Amemet marker is drawn.

This is intentionally static reference data. It neither checks whether Amemet
is alive nor selects a current placeholder or location. The separate patrol
paths in the source script are not included because they describe movement
after a spawn, not possible initial-spawn positions. The range is assigned to
page 2's `MAIN` floor and uses `inactive_floor_opacity` whenever the player is
on a different authored floor.

The west spur on page 15 is partly controlled by Kuftal's moving boulder. The
stock artwork remains visible there, while only navmesh-backed portions receive
the structure overlay. Do not invent a permanently walkable polygon across the
dynamic obstruction.

## Automatic page rules

When the stock Minimap plugin is not loaded, the DAT importer otherwise falls
back to unrecorded page 0. Kuftal therefore has authored page rules:

- player Z `>=15`, world Y `<-10`: page 15;
- player Z `>=15`, world Y `>=-10`: page 16;
- world Y `<=-175`, player Z `<=15`: page 1;
- remaining navigable space: page 2.

These rules are fallbacks as well as a guard against stale stock page state.
Validate them at the page transitions whenever a live traversal is available.

## Required regeneration audit

For any future Kuftal edit:

1. preserve all four recorded page transforms above;
2. regenerate every layer twice and compare SHA-256 hashes;
3. overlay each result on its exact stock page at source resolution;
4. confirm page 1 at the southern route before changing other pages;
5. check that page 1 renders as one connected cyan base and one connected
   violet route, and that its transition stripes remain centered on the
   live-verified connector at `(290,252)`;
6. cross every recorded Z boundary and confirm the player's floor uses
   **Current floor opacity** while every other floor uses **Other floors
   opacity**;
7. check the deep page-1 descent, page-15 boulder connector, page-16 west/east
   lower connectors, and every visible stair or ramp;
8. keep disconnected elevations in separate layer textures;
9. deploy without overwriting `ashitaminimap_config.lua`, reload the addon, and
   confirm the expected version and active page in the chat log.
