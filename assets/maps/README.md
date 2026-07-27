# Map assets

Files are named by FFXI zone ID.

- `107.png` — South Gustaberg
- `236.png` — Port Bastok
- `237_structure.png` — Metalworks calibrated geometry
- `237_labels.png` — Metalworks labels and map annotations
- `241_structure_source.png` — legacy Windurst Woods vanilla geometry mask
- `241_labels_source.png` — Windurst Woods immutable annotation mask
- `241_vanilla.png` — Windurst Woods optional vanilla parchment layer
- `241_structure.png` — Windurst Woods walkable-area mask
- `241_labels.png` — Windurst Woods place and exit labels
- `241_landmarks.png` — Windurst Woods service and landmark symbols

Every visible image must have real per-pixel alpha. Transparent pixels remain
invisible because AshitaMinimap draws the PNG directly through Direct3D instead
of asking the stock minimap DLL to render it.

Metalworks remains a linework-focused transparency prototype. Windurst Woods is
the production reference: `tools/generate_walkable_map.py` projects verified
collision/navigation data into a filled accessible-area layer. Labels and
landmarks remain optional vanilla-derived overlays. Every layer has identical
dimensions, origin, and world scale.

Windurst Woods is transparent everywhere outside the walkable polygon union.
Small collision details are intentionally suppressed; larger holes and
boundaries remain visible because they can constrain player movement.
