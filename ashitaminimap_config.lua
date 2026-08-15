return {
    visible = true,
    locked = true,

    -- Screen placement and viewport size.
    x = 18,
    y = 128,
    size = 330,

    -- Lua renderer scale. Higher values zoom in.
    -- Matches the current stock Minimap configuration:
    -- 210 px mask * 0.70 zoom / 100 * 3.00 UI scale = 4.41.
    pixels_per_yalm = 4.41,

    -- Vanilla reference map. Structure settings below are retained only for
    -- forward compatibility while structure rendering is dormant.
    -- 'custom' uses a locally imported guide-map/Pivot catalog when the active
    -- page has one; the minimap button toggles this value at runtime.
    map_source = 'vanilla',
    show_map_vanilla = true,
    show_map_structure = false,
    vanilla_opacity = 0.35,
    -- Guide maps contain fine text and printed grids; keep them substantially
    -- more opaque than the sparse vanilla artwork.
    custom_map_opacity = 1.00,
    structure_opacity = 0.82,
    inactive_floor_opacity = 0.14,
    -- Re-render each alpha layer to strengthen faint extracted lines.
    structure_visibility_boost = 4,
    -- Optional dark square behind the map; set to 0 for fully transparent.
    backdrop_opacity = 0.12,

    show_grid = true,
    show_coordinate = true,
    show_numeric_coordinates = false,
    -- Compact Vana'diel time, elemental day, moon phase, and weather card.
    show_environment_clock = true,
    -- Show current weather in its own compact badge.
    show_weather_badge = true,
    -- Fixed authored references only; never indicates live treasure positions.
    show_coffer_spawns = true,
    -- Draw a map-owned shortest path to AshitaGuide's current destination.
    show_guide_paths = true,
    -- Display-only diagnostic features. Both are disabled by default.
    developer_mode = false,
    show_all_pathing = false,
    show_players = true,
    show_npcs = true,
    show_monsters = true,
    -- Highlight only the entity actively tracked through native Wide Scan.
    show_widescan_target = true,
    scale_markers_with_zoom = true,
    -- Scales entity dots and target rings independently of map zoom.
    marker_size = 1.00,

    colors = {
        border = { 0.67, 0.47, 0.22, 0.90 },
        grid = { 0.48, 0.60, 0.61, 0.25 },
        grid_text = { 0.82, 0.71, 0.51, 0.88 },
        chest_spawn = { 0.545, 0.306, 0.145, 0.98 },
        coffer_spawn = { 1.000, 0.820, 0.200, 0.98 },
        player = { 0.18, 0.88, 0.90, 1.00 },
        other_player = { 0.275, 0.553, 1.000, 0.96 },
        npc = { 0.000, 0.784, 0.176, 0.96 },
        monster = { 1.000, 0.275, 0.275, 0.96 },
        target = { 1.00, 0.71, 0.20, 1.00 },
        widescan_target = { 0.82, 0.48, 1.00, 1.00 },
        shadow = { 0.01, 0.02, 0.025, 0.94 },
        badge = { 0.025, 0.055, 0.070, 0.88 },
        backdrop = { 0.010, 0.030, 0.040, 1.00 },
    },
}
