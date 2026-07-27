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

If `Minimap.dll` is loaded, its read-only current map page and scale byte are
used automatically. AshitaMinimap still performs all rendering itself and does
not require the plugin to draw.

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

Fallback origin `(255,256)` is intentionally provisional. A production
walkable structure still requires the full calibration and multi-position
validation in `MAP_CALIBRATION.md`.
