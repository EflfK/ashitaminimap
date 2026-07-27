# AshitaMinimap repository instructions

## Adding or replacing maps

Read both `docs/MAP_CALIBRATION.md` and `docs/MAP_AUTHORING_PITFALLS.md`
completely before adding, replacing, cropping, splitting, or recalibrating a
map. Treat their validation and deployment checklists as required work, not
optional background.

- Prefer a zone's intermediate collision OBJ plus matching Detour navmesh for
  accessible-area geometry. The OBJ preserves explicit triangles; the navmesh
  excludes flat but unreachable surfaces such as roofs. If those sources are
  unavailable, navigation geometry must come from the vanilla DAT or another
  deterministic, verified source. Never use AI-generated or visually traced
  artwork for navigation geometry.
- Production maps have only two static sources: an optional vanilla reference
  layer and a clean walkable-structure layer. Do not create separate static
  label or landmark layers. Both sources must use exactly the same crop, wrap,
  origin, and scale.
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
- Never assume a dark DAT seam is a page edge. Decode the complete texture and
  test for cyclic continuation before cropping.
- Keep the navigation origin and printed H-8 grid origin separate when the
  vanilla artwork requires it.
