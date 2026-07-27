# AshitaMinimap repository instructions

## Adding or replacing maps

Read `docs/MAP_CALIBRATION.md` before adding, replacing, cropping, splitting, or
recalibrating a map.

- Navigation geometry must come from the vanilla DAT or another deterministic,
  verified source. Never use AI-generated or visually traced artwork for
  navigation geometry.
- Keep structure and labels as separate, identically sized layers whenever the
  source permits it. Both layers must use exactly the same crop, wrap, origin,
  and scale.
- Treat map calibration as zone- and map-variant-specific data. Do not reuse a
  global scale or grid-cell size.
- Derive `grid_yalms`, `origin_x`, `origin_y`, and
  `image_pixels_per_yalm` from source data and verified control points. Do not
  finish a map using eyeballed tuning.
- Keep source-image calibration independent of the user's display size and
  zoom.
- Validate at multiple well-separated world positions and compare static map
  geometry, the player marker, and entity markers before calling a map precise.
- Preserve the user's installed `ashitaminimap_config.lua` when syncing addon
  updates into the game installation.

