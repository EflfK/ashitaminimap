# Universal vanilla-map fallbacks

AshitaMinimap can render every stock map page from the local FFXI installation
while authored walkable structures are completed incrementally.

## Ownership and repository boundary

`tools/import_vanilla_maps.py` is committed. The stock PNGs it generates and
`ashitaminimap_vanilla_maps.lua` are gitignored because they are derived from
the user's installed game files. Do not commit, publish, or package those
generated assets.

Run:

```text
python tools/import_vanilla_maps.py "<FFXI installation>/FINAL FANTASY XI"
```

The importer scans all `ROM*` directories for embedded `m_ZZZ_PP` page
identifiers. When duplicate zone/page candidates exist, it prefers the current
DXT3 form and then the later ROM directory. The generated catalog records every
page and chooses page `00`, then `01`, then the lowest available page as its
default.

## Supported stock layouts

Legacy indexed pages contain a 256-entry palette and bottom-up pixel indices.
They require a vertical flip and the common `+146 px` cyclic horizontal
reconstruction.

Newer pages have an `0xA1` or `0xB1` image header:

```text
type         header + 0x39  ("3TXD")
payload size header + 0x3D
DXT3 blocks  header + 0x45
```

DXT3 pages are already top-to-bottom and do not use the indexed page's cyclic
offset. Both formats are exported with fully opaque alpha so the addon's
vanilla opacity setting remains the sole transparency control.

## Runtime precedence

The runtime builds the current definition in this order:

1. imported vanilla fallback page;
2. authored `ashitaminimap_maps.lua` fields overlaid on it.

Therefore:

- an un-authored zone displays vanilla only;
- an authored structure-only zone displays vanilla plus structure;
- a committed/authored vanilla layer overrides the generated fallback;
- no generated file is loaded until its zone and page are actually active.

## Page, scale, and origin selection

If `Minimap.dll` is loaded, its read-only current map page, scale byte, and
computed map-space center are used automatically. AshitaMinimap still performs
all rendering itself and does not require the plugin to draw.

Without that optional metadata source, the catalog default page is shown and a
40-yalm-cell fallback scale plus provisional `(255,256)` origin are used.
Select another page with:

```text
/aminimap page next
/aminimap page prev
/aminimap page <number>
/aminimap page auto
```

Manual selections are stored per zone in `ashitaminimap_config.lua`. They are
useful for multi-floor zones and remain available whether or not the stock
plugin is loaded.

In automatic mode, AshitaMiniMap asks FFXiMain's read-only coordinate selector
for the stock page at the player's current position before consulting authored
page rules or cached Minimap.dll state. FFXiMain expects its position tuple in
`X, vertical Z, horizontal Y` order. This native lookup handles irregular page
boundaries such as Garlaige Citadel's Banishing Gates and works even when the
stock Minimap plugin is not loaded. A zero/no-page result falls through to the
authored and default-page safeguards.

An authored multi-page zone may define `page_rules` to avoid an unrecorded
overview page when live page metadata is unavailable. If its recorded detail
pages use different transforms, `page_calibrations[page_id]` supplies an exact
per-page fallback origin, scale, and grid anchor. These values are used only
when neither the stock record nor Minimap.dll provides the corresponding live
metadata; live calibration remains authoritative.

For an irregular dungeon whose pages cannot be separated truthfully with
rectangular X/Y/Z rules, `page_graph_seeds` can assign retained navigation
components to stock pages. Each record supplies a page and one exact point on
that component:

```lua
page_graph_seeds = {
    { page_id = 15, x = 100.0, y = 20.0, z = -32.0 },
}
```

In automatic mode, the runtime snaps the live player to the shared graph and
uses the seed assigned to that connected component. Every retained component
that should select a page needs exactly one non-conflicting seed. Areas absent
from a partial graph deliberately fall through to the normal stock/default
selection instead of borrowing a nearby page.

## Validation

After each import:

1. confirm the reported page and zone counts are plausible;
2. inspect at least one indexed and one DXT3 output;
3. rerun the importer and compare hashes for deterministic output;
4. preserve the installed user configuration while syncing;
5. reload AshitaMinimap and confirm the expected addon version;
6. test an authored zone, a structure-only zone, and an un-authored zone;
7. cycle a multi-page zone and restore automatic mode.

The scale byte at page-record offset `+0x05` gives
`image_pixels_per_yalm = scale_byte / 5`; a 32-pixel grid cell therefore spans
`grid_yalms = 160 / scale_byte`. Minimap.dll's own coordinate-conversion
routine performs this multiplication directly. The older
`32 / (scale_byte * 10)` expression only produced the same result for scale
byte `4` and caused live entities to spread incorrectly on every other scale.
The matching 14-byte FFXiMain map-table record stores signed `OffsetX` and
`OffsetY` values at `+0x0A` and `+0x0C`. Minimap.dll's own converter uses:

```text
image_x = world_x * image_pixels_per_yalm - OffsetX
image_y = -world_y * image_pixels_per_yalm - OffsetY
```

The exact source origin is therefore `(-OffsetX,-OffsetY)`. AshitaMinimap looks
up the active zone and page in this table before using Minimap.dll's live player
map-space doubles as a fallback. This is stable while the player moves and is
available for every imported stock page, including maps that have no authored
layers.

The stock renderer also rejects entities assigned to a different active map
page. AshitaMinimap applies a zone-independent elevation tolerance before
drawing live entities so monsters loaded from floors above or below do not
pollute the current page. This same filter is used for every authored and
fallback map; it is not a Castle-specific correction.

The former warning against using the signed offsets was based on the obsolete
reciprocal scale formula. The offsets were correct; the scale paired with them
was not.

An authored map that shares the imported stock page's coordinate system can set
`stock_calibration = true`. Its custom layers will then use the exact live
record origin and scale rather than masking those values with provisional
authored defaults. Regenerate every geometry-derived structure layer using the
same record origin before enabling this flag.

## Correcting a provisional fallback origin

The map-calibration controls are currently hidden from `/aminimap config`
because normal play does not need them. Existing adjustments continue to load
and render. For attended development calibration, temporarily set
`SHOW_MAP_CALIBRATION` to `true` in `ashitaminimap.lua`; the restored section
provides X and Y source-image pixel adjustments for the active zone and vanilla
page. Slider changes preview immediately, and **Save calibration** persists
them across addon reloads.

Adjustments are stored per zone and page because separate floors can use
different source origins. They change the navigation origin while leaving the
underlying PNG and its recorded printed-grid anchor unchanged. This lets the
Lua grid continue to align with the stock artwork as the world-to-image
calibration changes. Because the values are source-image pixels, they remain
valid across display sizes and user zoom levels.

The adjustment is a correction on top of the live-derived, provisional, or
authored base origin, not a replacement for it. A saved correction should
normally be unnecessary when the stock page matches the selected page; clear
obsolete corrections created before live origin derivation was available.

Use this as a user-level correction for a uniformly displaced fallback. An
error that grows with distance is a scale problem, and a regional mismatch is
usually a wrong floor/page; neither should be hidden with an origin adjustment.
