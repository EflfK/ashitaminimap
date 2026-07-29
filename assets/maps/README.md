# Map assets

Files are named by FFXI zone ID.

- `107.png` — South Gustaberg
- `236.png` — Port Bastok
- `237_structure.png` — Metalworks calibrated geometry
- `241_structure_source.png` — legacy Windurst Woods vanilla geometry mask
- `241_vanilla.png` — Windurst Woods optional vanilla parchment layer
- `241_structure.png` — Windurst Woods walkable-area mask
- `243_vanilla.png` / `243_structure.png` / `243_stairs_structure.png` /
  `243_upper_structure.png` — Ru'Lude Gardens
- `244_vanilla.png` / `244_structure.png` /
  `244_stables_structure.png` — Upper Jeuno
- `200_01_structure.png` / `200_16_structure.png` — Garlaige Citadel,
  authored stock pages 1 and 16 (partial coverage audit)
- `245_vanilla.png` / `245_structure.png` — Lower Jeuno
- `246_structure.png` — Port Jeuno walkable-area mask

Every visible image must have real per-pixel alpha. Transparent pixels remain
invisible because AshitaMinimap draws the PNG directly through Direct3D instead
of asking the stock minimap DLL to render it.

Metalworks remains a linework-focused transparency prototype. Windurst Woods is
the production reference: `tools/generate_walkable_map.py` projects verified
collision/navigation data into a filled accessible-area layer. Labels and
landmarks are intentionally available only as part of the optional vanilla
layer. The vanilla and structure layers have identical dimensions, origin, and
world scale.

Production structure maps are transparent everywhere outside their walkable
polygon unions.
Small collision details are intentionally suppressed; larger holes and
