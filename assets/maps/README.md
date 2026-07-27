# Map assets

Files are named by FFXI zone ID.

- `107.png` — South Gustaberg
- `236.png` — Port Bastok
- `237.png` — Metalworks, decoded from the exact vanilla zone DAT

Every image must have real per-pixel alpha. Transparent pixels remain invisible
because AshitaMinimap draws the PNG directly through Direct3D instead of asking
the stock minimap DLL to render it.

The current files are linework-focused transparency prototypes. Metalworks uses
the vanilla map pixels and verified grid calibration; its alpha mask is not yet
a filled walkable-area mask. Replace the prototype alpha masks with verified
walkable-area masks before treating their filled shapes as navigation data.
