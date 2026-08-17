# AshitaMiniMap repository instructions

## Primary purpose

AshitaMiniMap is a display-only directional pathing addon for AshitaGuide,
custom waypoints, and other allowed attended destinations. It owns reusable
map-page navigation graphs, computes shortest paths, and renders directions.
AshitaGuide supplies destinations; it does not author or duplicate routes.

Keep the addon display-only. Never add movement automation, input simulation,
gameplay commands, packet injection, timers, unattended loops, multibox
routing, detection evasion, or any capability that acts on the player's behalf.

## MCP waypoint use

Use the AshitaMiniMap MCP waypoint instead of authoring an AshitaGuide guide
when the user needs directions to one exact destination and does not need
ordered instructions, completion tracking, reminders, or multiple guide steps.
The available tools are:

- `set_minimap_waypoint` to place or replace the session-only custom waypoint;
- `minimap_waypoint_status` to confirm how the addon handled the latest
  request; and
- `clear_minimap_waypoint` to remove it and restore AshitaGuide routing.

Supply an exact zone id and trustworthy world X/Y coordinates. Supply `mapId`
for every remote-zone destination and whenever a multi-page zone's correct map
or floor is known. Supply Z when trustworthy elevation evidence is available,
especially on overlapping floors. When Z is omitted, accept AshitaMiniMap's
floor resolution; never invent an elevation to force routing. Prefer exact
coordinates observed through live AshitaMCP `visible_entities` when the player
is in the relevant zone. Otherwise use verified local destination data or a
trustworthy source. Never derive world coordinates from a map-grid label.

After setting or clearing a waypoint, call `minimap_waypoint_status`. Treat
`routed` as a confirmed marker with a display-only path and `marker_only` as a
truthful destination without an available route. Report `rejected`, `expired`,
or persistently unacknowledged requests rather than claiming that the waypoint
is active. A pending acknowledgment may be checked again briefly, but do not
create an unattended polling loop. If the MCP server is newly installed and
its tools are unavailable, tell the user to start a new Codex task or restart
Codex. If the request remains unacknowledged, verify that AshitaMiniMap is
loaded and reload it through AshitaDevTools when lifecycle work is in scope.

Leave a requested waypoint active while the player is using it. Clear it when
the user asks, when live read-only position evidence confirms that the intended
destination has been reached, or after a temporary verification waypoint has
served its stated purpose. Setting a newer waypoint already replaces the older
one. Never use MCP waypoints to move the character, simulate input, target or
interact with an entity, send commands or packets, track hidden state, or build
timed/state-driven navigation automation.

## Required reading

Read `docs/MAP_CALIBRATION.md`, `docs/MAP_AUTHORING_PITFALLS.md`,
`docs/MAP_COMPONENT_AUDIT.md`, `docs/VANILLA_FALLBACKS.md`, and
`docs/PATH_GRAPHS.md` before adding or changing calibration, destinations, or a
map-owned graph. Read zone-specific provenance when it exists.

Structure-rendering code, assets, reports, and provenance are retained for
possible future restoration, but structure rendering is dormant during normal
addon operation. Do not generate, expand, replace, or recertify structure
images unless the user explicitly requests structure work.

## Production-map shorthand

When the user says `complete map <zone>`, finish that zone's routing and
destination support end to end:

1. Establish exact vanilla-map calibration for every relevant stock page.
   Derive page, origin, scale, grid anchor, crop, and wrap from deterministic
   source records plus well-separated live controls. Never eyeball calibration.
2. Generate a display-only graph from the pinned Detour navmesh using native
   `dtPoly.neis` topology and authored external tile portals. A production
   graph must not require a structure PNG. A retained structure mask may be
   used only as an optional diagnostic selector with independent routing
   evidence.
3. Analyze every component, elevation, overlapping floor, and nearby
   connection that could affect a normal guide destination. Include reachable
   public routes and required connectors. Exclude inaccessible roofs,
   decorative collision, isolated surfaces, false connections, private
   cutscene spaces, and irrelevant geometry with deterministic evidence.
4. Keep separate floors distinct in graph Z. Never join overlapping X/Y
   coordinates across elevations. Apply `--blocked-link` for a source edge
   proven impassable and `--transition` only for a real connection verified at
   its entrance, midpoint, and exit.
5. Publish the best graph supported by deterministic navmesh, collision,
   server data, and existing live evidence. Use Developer mode's **Show all
   pathing** web for an at-a-glance review. Do not create a long manual audit
   guide merely because a seam might be wrong. When the player reports a
   concrete defect, add only the focused attended checkpoints needed to
   capture that connection.
6. Add every active Home Point and Survival Guide, all verified Treasure Chest
   and Treasure Coffer locations, relevant notorious-monster references, zone
   exits, and other supported destinations from pinned trustworthy data.
   Treasure records must explicitly use `kind = 'chest'` or `kind = 'coffer'`.
   Record verified-empty categories instead of silently omitting them.
7. Test representative long routes, endpoint snapping, shortest-path output,
   off-route recovery, zone/page filtering, and cross-zone handoffs where
   relevant. Resolve defects revealed by deterministic analysis, the full
   graph web, or player reports. Focused live traversal remains required before
   authoring an exception edge, but speculative manual traversal of every
   plausible junction is not a publication gate.
8. Run `tools/validate_path_graphs.py` and `tools/audit_path_graphs.py`.
   Regenerate twice and compare hashes. Verify production/native parity except
   for documented live-verified `--transition` and `--blocked-link` exceptions.
9. Preserve the installed user configuration, sync the runtime and graph into
   CatsEyeXI, reload through AshitaDevTools, and verify the version, destination,
   computed route, and recovery behavior in game.
10. Commit only the intended request changes and push `main` to `origin/main`.
    If live evidence or trustworthy source data is unavailable, report the
    exact routing gap and keep the map partial rather than weakening the gate.

## Routing completeness invariant

Any authored calibration, navigation graph, or static destination triggers the
routing-first completion workflow for that zone or page. Completion means:

- accurate vanilla-map calibration;
- a complete display-only graph for all relevant reachable areas and floors;
- truthful handling of stairs, ramps, bridges, doors, elevators, zoning
  thresholds, and broken navmesh seams;
- trustworthy supported destinations and explicit verified-empty categories;
- representative long-route tests plus focused live tests for known defects or
  authored transition exceptions; and
- no unresolved component capable of affecting a normal guide destination.

Component analysis remains mandatory for routing quality, not for producing a
cyan overlay. Do not require exhaustive classification of decorative or
irrelevant components once deterministic evidence proves they cannot affect
allowed destinations or routes. Deterministically review components near a
supported destination, known route, zone exit, alternate floor, or plausible
connector. Escalate to a focused live audit when evidence or the developer
graph web exposes a concrete ambiguity; do not assume every nearby component
requires a manual walkthrough.

Prefer a zone's matching collision OBJ and Detour navmesh. The OBJ is useful
diagnostic geometry; Detour topology is the graph source. Neither source is
unquestionable player-route truth. Never use AI-generated or visually traced
geometry for routing.

Native adjacency is the production default. Inferred adjacency is audit-only.
Never connect components from two-dimensional proximity, an overview image, or
a shortest-route result. A missing connection remains marker-only until live
evidence proves the physical transition.

When the player and a same-zone destination snap to disconnected authored
components, AshitaMiniMap must attempt its world graph before returning a
marker-only result. A valid route may need to leave the zone and re-enter
through a different threshold. Keep that responsibility in AshitaMiniMap;
never require AshitaGuide to duplicate the transition sequence.

World-route costs must include a meaningful fixed penalty for each Home Point,
Survival Guide, or Warp transfer. A short route through adjacent physical zone
lines must outrank a geographically unrelated chain of unlocked fast-travel
menus; do not make AshitaGuide warn users away from a bad route choice.

## Missing-connection screenshot shorthand

All path-graph creation, correction, or connection work must be delegated to a
subagent so the primary agent remains available for live guidance and other
tasks. The graph subagent owns source inspection, deterministic graph
regeneration (including native/native/inferred comparison), validation,
provenance and version updates, deployment into the active CatsEyeXI install,
in-game reload, commit, and push. The primary agent may continue giving the
player attended directions while that work runs, but must not duplicate or
race the subagent's repository changes.

When the user attaches coordinate screenshots and says `fix connection` (or
equivalent), treat that as a request to repair one reported missing routing
link without requiring them to restate this workflow. The screenshots are an
ordered attended traversal record: the first is the start of the physical
transition, the last is its end, and every screenshot between them is an
intermediate checkpoint needed to describe the traversable path. Three
screenshots normally mean entrance, midpoint, and exit, but accept as many
intermediate checkpoints as the user supplies.

Extract the zone, page or floor, player X/Y/Z coordinates, and any visible
developer diagnostics from the screenshots. Locate both graph components and
the corresponding Detour/collision evidence, then determine why native routing
does not cross between them. Prefer correcting a genuine source-topology or
authored external-portal defect. If the game permits the traversal but the
Detour data has a seam, add the narrowest `--transition` supported by the
ordered checkpoints, including intermediate nodes where needed instead of
joining distant endpoints directly. Never create the link solely from visual
proximity, and do not collapse distinct elevations.

Treat a clear entrance/midpoint/exit capture sequence as the focused live
evidence required to attempt the repair. Ask for another screenshot only when
the zone, coordinates, elevation, checkpoint order, or physical continuity is
actually ambiguous. After changing the graph, run the normal graph validation,
audit, deterministic-regeneration, route, sync, reload, and in-game checks
required elsewhere in this file, then report exactly how the components were
connected.

The in-game Developer-mode Connection capture is the preferred equivalent when
available. Read its latest saved record through
`minimap_link_candidate_status`; its ordered points replace coordinate
screenshots as attended traversal evidence. Preserve the captured direction,
mechanism type, name, and forward/reverse instructions when authoring
`--transition`, `--one-way-transition`, and `--route-action` entries.
Treat the numbered magenta preview as a candidate only. Never promote it
directly into the runtime graph without the normal navmesh/collision review,
regeneration, validation, deployment, and in-game route verification. Clear
the saved candidate by exact id only after it has been successfully processed.

Path elevation is authoritative for floor-aware snapping. An exact guide
destination without Z may route only when the graph can resolve it to one
reachable floor; otherwise it remains marker-only as floor-ambiguous. An
explicitly approximate guide destination may omit Z when truthful elevation is
unavailable: resolve it using the shortest connected graph route from the
player's live three-dimensional position, then the player's current floor as a
fallback. Never apply that relaxation to exact guide destinations. Route
projection must remain three-dimensional so walking above or below a route
cannot count as following it.

FFXI/Ashita live Z is inverted for physical elevation: a more-negative live Z
is higher/up, and a more-positive live Z is lower/down. Any floor-transition
label or icon derived from converted live Z must therefore use
`destinationZ < sourceZ` for up and `destinationZ > sourceZ` for down. Raw
Detour graph elevation has the opposite sign and must be converted through
`state.path_node_live_z` before applying this rule.

## Dormant structure subsystem

Preserve all existing structure-rendering implementation, generated assets,
component reports, provenance, and map metadata. Do not delete or rewrite them
as part of routing work.

Normal operation must not load or render structure textures, and the config UI
must not expose structure enablement, opacity, inactive-floor opacity, or
visibility controls. The retained settings may continue to round-trip through
the config file for forward compatibility.

Structure masks remain optional internal diagnostics for
`generate_path_graph.py`; production pathing must be reproducible without
requiring a newly generated visible structure image. Structure audits and
structure-image provenance are required only when the user explicitly requests
structure work.

## Calibration and destination rules

- Treat calibration as zone-, page-, and variant-specific.
- Keep source calibration independent of display size and zoom.
- Keep the navigation origin and printed H-8 grid origin separate where the
  stock artwork requires it.
- Never assume a dark DAT seam is a page edge; test for cyclic continuation.
- Prefer exact live `visible_entities` coordinates for named destinations.
  Otherwise use pinned server data or another trustworthy source. Never guess
  coordinates from a printed grid label.
- Home Points use the cyan crystal symbol; Survival Guides use the open-book
  symbol; Treasure Chests use the wooden chest symbol; Treasure Coffers use the
  gold coffer symbol.
- Static references never inspect or report live chest, coffer, NM, or travel
  status beyond the read-only registration masks already used for routing.
- Preserve the user's installed `ashitaminimap_config.lua` when syncing.

## UI and privacy

Map-calibration controls remain hidden from normal configuration with
`SHOW_MAP_CALIBRATION = false`; expose them only for attended development.

Do not add entity-name labels or recover entity names solely for minimap
display. Dynamic entities remain anonymous dots, target styling, and the
player arrow.

Public repository content must not include personal paths, credentials,
private logs, account information, or screenshots containing private data.

## Windurst Walls

Preserve the existing partial Windurst Walls structure work as dormant
repository evidence. Do not expand its visible structure overlay unless the
user explicitly requests it. Complete Windurst Walls through its navigation
graph, exact stock calibration, three active Home Points, verified supported
markers and exits, truthful transitions, and live route verification.
