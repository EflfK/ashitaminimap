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

## Page and scale selection

If `Minimap.dll` is loaded, its read-only current map-page record is used
automatically. The 14-byte record provides the page ID, scale byte, and signed
X/Y navigation-origin offsets. AshitaMinimap still performs all rendering
itself and does not require the plugin to draw.

Without that optional metadata source, the catalog default page is shown and a
40-yalm-cell fallback scale is used. Select another page with:

```text
/aminimap page next
/aminimap page prev
/aminimap page <number>
/aminimap page auto
```

Manual selections are stored per zone in `ashitaminimap_config.lua`. They are
useful for multi-floor zones and remain available whether or not the stock
plugin is loaded.

## Validation

After each import:

1. confirm the reported page and zone counts are plausible;
2. inspect at least one indexed and one DXT3 output;
3. rerun the importer and compare hashes for deterministic output;
4. preserve the installed user configuration while syncing;
5. reload AshitaMinimap and confirm the expected addon version;
6. test an authored zone, a structure-only zone, and an un-authored zone;
7. cycle a multi-page zone and restore automatic mode.

When stock metadata is available for the active page, fallback navigation
origin is:

```text
origin_x = -signed_int16(record + 0x0A)
origin_y = -signed_int16(record + 0x0C)
```

The scale byte at `record + 0x05` gives
`image_pixels_per_yalm = 32 / (scale_byte * 10)`. These fields vary by page;
do not replace them with a global center or scale. Without the optional
metadata source, origin `(255,256)` and a 40-yalm-cell scale remain provisional
fallbacks.

Authored map fields continue to override stock metadata. A production walkable
structure still requires the full calibration and multi-position validation in
`MAP_CALIBRATION.md`.

## Correcting a provisional fallback origin

Open `/aminimap config` while standing in the affected zone. The **Map
calibration** section exposes X and Y source-image pixel adjustments for the
active zone and active vanilla page. Ctrl-click either slider to type an exact
value. Slider changes preview immediately in the current session but do not
alter `ashitaminimap_config.lua`. Choose **Save calibration** to persist the
current values across addon reloads. Reloading before saving restores the last
saved calibration.

Adjustments are stored per zone and page because separate floors can use
different source origins. They change the navigation origin while leaving the
underlying PNG and its recorded printed-grid anchor unchanged. This lets the
Lua grid continue to align with the stock artwork as the world-to-image
calibration changes. Because the values are source-image pixels, they remain
valid across display sizes and user zoom levels.

The adjustment is a correction on top of the stock or authored base origin,
not a replacement for it. Set both adjustments to zero to use the page's
metadata-derived origin directly.

Use this as a user-level correction for a uniformly displaced fallback. An
error that grows with distance is a scale problem, and a regional mismatch is
usually a wrong floor/page; neither should be hidden with an origin adjustment.
