# AshitaMinimap repository instructions

## Adding or replacing maps

Read `docs/MAP_CALIBRATION.md`, `docs/MAP_AUTHORING_PITFALLS.md`,
`docs/MAP_COMPONENT_AUDIT.md`, and `docs/VANILLA_FALLBACKS.md` completely
before adding, replacing, cropping, splitting, or recalibrating a map. Treat
their validation and deployment checklists as required work, not optional
background.

Also read a zone-specific provenance document when one exists. Kuftal Tunnel
work must read `docs/KUFTAL_TUNNEL.md` before changing its page rules,
calibration, component selection, elevation bands, or structure assets.

- Prefer a zone's intermediate collision OBJ plus matching Detour navmesh for
  accessible-area geometry. The OBJ preserves explicit triangles; the navmesh
  excludes flat but unreachable surfaces such as roofs. If those sources are
  unavailable, navigation geometry must come from the vanilla DAT or another
  deterministic, verified source. Never use AI-generated or visually traced
  artwork for navigation geometry.
- Production maps have only two static source categories: an optional vanilla
  reference and clean walkable structure. The structure category may contain
  multiple component textures when disconnected floors or connectors overlap
  in two dimensions. Do not create separate static label or landmark layers.
  Every texture must use exactly the same crop, wrap, origin, and scale.
- Treat map calibration as zone- and map-variant-specific data. Do not reuse a
  global scale or grid-cell size.
- Derive `grid_yalms`, `origin_x`, `origin_y`, and
  `image_pixels_per_yalm` from source data and verified control points. Do not
  finish a map using eyeballed tuning.
- Keep source-image calibration independent of the user's display size and
  zoom.
- Validate at multiple well-separated world positions and compare static map
  geometry, the player marker, and entity markers before calling a map precise.
- Never call a structure map complete until every plausible navmesh component
  has been classified as included main path, included alternate floor,
  included connector, or excluded with a recorded reason. Audit every stair,
  ramp, bridge, elevator landing, and other floor transition with live player
  coordinates; the player marker must remain over authored structure along the
  complete route.
- Never flatten disconnected overlapping floors into one PNG. Preserve their
  component boundaries with `structure_layers`; use cyan for the main
  connected network and violet for alternate floors and their connectors.
  When a verified transition remains ambiguous, use small path-clipped stripes
  perpendicular to travel: alternate cyan and violet, widen cyan toward the
  main floor, and widen violet toward the alternate floor. Do not blend the
  colors or place a stair glyph, opaque block, arrow, or inferred destination
  marker over the map.
- For multi-floor pages, give each floor layer truthful
  `minimum_player_z`/`maximum_player_z` bounds. Keep the matching current floor
  at full opacity and make nonmatching floors substantially fainter with
  `inactive_opacity`; do not rely on color alone to show the player's floor.
- A visually plausible overview is not coverage validation. Inspect close zoom
  and record live control points on every floor and at the entrance, middle,
  and exit of every transition. If full traversal is unavailable, document the
  map as partial rather than assuming omitted components are inaccessible.
- Preserve the user's installed `ashitaminimap_config.lua` when syncing addon
  updates into the game installation.
- Do not add entity-name labels or recover entity names solely for minimap
  display. AshitaMinimap intentionally limits dynamic entities to anonymous
  dots, target styling, and the player arrow. The former entity-name rendering
  capability was removed and must not be reintroduced.
- Never assume a dark DAT seam is a page edge. Decode the complete texture and
  test for cyclic continuation before cropping.
- Keep the navigation origin and printed H-8 grid origin separate when the
  vanilla artwork requires it.
- Treat the current asset-validation steps as manual completion gates. There
  is not yet an automated validator for page-to-asset references, PNG
  dimensions and alpha, deterministic regeneration, or prohibited
  entity-name rendering.
