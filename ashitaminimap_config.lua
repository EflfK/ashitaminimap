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
    map_opacity = 0.82,
    -- Re-renders the alpha map layer to strengthen faint extracted lines.
    map_visibility_boost = 4,
    -- Optional dark square behind the map; set to 0 for fully transparent.
    backdrop_opacity = 0.12,

    show_grid = true,
    show_coordinate = true,
    show_players = true,
    show_npcs = true,
    show_monsters = true,
    show_names = false,

    colors = {
        border = { 0.67, 0.47, 0.22, 0.90 },
        grid = { 0.48, 0.60, 0.61, 0.25 },
        grid_text = { 0.82, 0.71, 0.51, 0.88 },
        player = { 0.18, 0.88, 0.90, 1.00 },
        other_player = { 0.275, 0.553, 1.000, 0.96 },
        npc = { 0.000, 0.784, 0.176, 0.96 },
        monster = { 1.000, 0.275, 0.275, 0.96 },
        target = { 1.00, 0.71, 0.20, 1.00 },
        shadow = { 0.01, 0.02, 0.025, 0.94 },
        badge = { 0.025, 0.055, 0.070, 0.88 },
        backdrop = { 0.010, 0.030, 0.040, 1.00 },
    },
}
