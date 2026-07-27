# Map assets

Files are named by FFXI zone ID.

- `107.png` — South Gustaberg
- `236.png` — Port Bastok
- `237_structure.png` — Metalworks calibrated geometry
- `237_labels.png` — Metalworks labels and map annotations
- `241_structure.png` — Windurst Woods calibrated geometry
- `241_labels.png` — Windurst Woods labels and map annotations

Every image must have real per-pixel alpha. Transparent pixels remain invisible
because AshitaMinimap draws the PNG directly through Direct3D instead of asking
the stock minimap DLL to render it.

The current files are linework-focused transparency prototypes. Metalworks and
Windurst Woods use vanilla map pixels and deterministic grid calibration. Each
zone's structure and label layers share identical dimensions, origin, and world
scale, so they can be composited or hidden independently without changing
alignment. Their alpha masks are not yet filled walkable-area masks.
