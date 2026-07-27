# Map assets

Files are named by FFXI zone ID.

- `107.png` — South Gustaberg
- `236.png` — Port Bastok
- `237_structure.png` — Metalworks calibrated geometry
- `237_labels.png` — Metalworks labels and map annotations
- `241_structure_source.png` — Windurst Woods immutable geometry mask
- `241_labels_source.png` — Windurst Woods immutable annotation mask
- `241_structure.png` — Windurst Woods dark-tactical geometry
- `241_labels.png` — Windurst Woods place and exit labels
- `241_landmarks.png` — Windurst Woods service and landmark symbols

Every visible image must have real per-pixel alpha. Transparent pixels remain
invisible because AshitaMinimap draws the PNG directly through Direct3D instead
of asking the stock minimap DLL to render it.

Metalworks remains a linework-focused transparency prototype. Windurst Woods is
the production reference: `tools/style_dark_tactical_layers.py` generates its
visible structure, label, and landmark layers from the immutable source masks.
Every generated layer has identical dimensions, origin, and world scale.

The assets are intentionally not filled walkable-area masks. The vanilla source
does not encode a trustworthy closed walkability polygon, so adding one by
visual inference would weaken map precision.
