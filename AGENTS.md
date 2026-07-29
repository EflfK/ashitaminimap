# AshitaMinimap repository instructions

## Adding or replacing maps

Read `docs/MAP_CALIBRATION.md`, `docs/MAP_AUTHORING_PITFALLS.md`,
`docs/MAP_COMPONENT_AUDIT.md`, and `docs/VANILLA_FALLBACKS.md` completely
before adding, replacing, cropping, splitting, or recalibrating a map. Also
read `docs/PATH_GRAPHS.md` before creating or changing a map-owned navigation
graph. Treat their validation and deployment checklists as required work, not
optional background.

Also read a zone-specific provenance document when one exists. Kuftal Tunnel
work must read `docs/KUFTAL_TUNNEL.md` before changing its page rules,
calibration, component selection, elevation bands, or structure assets.

## Production-map shorthand

When the user says `complete map <zone>`, treat it as a request to finish that
zone's production map end to end and make it visible in game without requiring
the user to restate the workflow:

1. Follow every map-authoring document and use exact stock calibration plus
   deterministic collision/navigation sources.
2. Generate, inventory, and classify every plausible component as main path,
   alternate floor, connector, excluded with evidence, or unresolved. Preserve
   overlapping floors as separate cyan/violet layers with verified player-Z
   bounds and transition treatments.
3. Conduct the required attended live route audit. Give the user concise
   destinations to visit, capture entrance/middle/exit positions for every
   floor transition, and continue when live evidence arrives. Never substitute
   an overview image for traversal evidence or call unresolved work complete.
4. Add display-only static references for all verified Treasure Chest or
   Treasure Coffer locations and relevant notorious-monster spawn points or
   ranges available from trustworthy CatsEyeXI-compatible data. Every treasure
   record must declare `kind = 'chest'` or `kind = 'coffer'`: Treasure Chests
   use the wooden chest symbol and Treasure Coffers use the gold coffer symbol.
   Never combine or relabel the two types. Record their provenance and
   page/floor metadata. Do not add live detection, status reporting,
   entity-name recovery, commands, movement, or automation.
5. Generate the map-owned display-path graph from the same pinned deterministic
   Detour source, and register it in `ashitaminimap_paths.lua`. AshitaGuide must
   continue to supply only destination coordinates; do not duplicate routes in
   guides. Validate node and edge integrity, bidirectional links, connected and
   deliberately disconnected destinations, endpoint snapping, shortest-path
   output, off-route recovery, page/floor filtering, and close-zoom alignment
   with verified walkable structure. Do not join disconnected components
   without live transition evidence; leave those destinations marker-only and
   the graph partial.
6. Register every finished asset and overlay in `ashitaminimap_maps.lua`,
   document complete provenance, regenerate twice, and verify deterministic
   hashes for both map and path artifacts, referenced paths, dimensions, alpha,
   calibration, floor/page filtering, overview zoom, close zoom, marker
   placement, and rendered guide paths.
7. Preserve the installed user configuration, sync the finished addon into the
   game installation, reload it through AshitaDevTools, and verify the expected
   version, map layers, destination marker, and computed path behavior in the
   live log and game.
8. Finish the repository workflow: update relevant documentation, commit only
   the intended work in one request-specific commit, and push `main` to
   `origin/main`. If required live traversal or authoritative source data is
   unavailable, clearly leave the map partial and report the exact remaining
   audit rather than lowering the completion standard.

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
  marker over the map. Generate the shared tapered-threshold treatment and
  declare its structure layer with `role = 'floor_transition'` so overview
  opacity, close-zoom opacity, and single-pass visibility are consistent on
  every authored map.
- For multi-floor pages, give each floor layer truthful
  `minimum_player_z`/`maximum_player_z` bounds. Keep the matching current floor
  at full opacity and make nonmatching floors substantially fainter with
  the user-level `inactive_floor_opacity` setting; do not hardcode inactive
  opacity per map or rely on color alone to show the player's floor.
- Map-calibration controls are intentionally hidden from the normal config UI
  with `SHOW_MAP_CALIBRATION = false`. Existing origin adjustments remain
  active; only expose the controls temporarily for attended development.
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
