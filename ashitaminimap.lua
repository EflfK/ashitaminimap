addon.name      = 'ashitaminimap';
addon.author    = 'EflfK';
addon.version   = '1.31.1';
addon.desc      = 'Display-only directional minimap and guide pathing for Ashita v4.';

require('common');

local bit = require('bit');
local d3d8 = require('d3d8');
local ffi = require('ffi');
local imgui = require('imgui');
local spectralfocus_modal = require('spectralfocus_modal');

local commands = T{
    ['/aminimap'] = true,
    ['/ashitaminimap'] = true,
};

local ZOOM_MIN = 0.25;
local ZOOM_MAX = 20.00;
local ZOOM_STEP = 1.12;
local TRANSITION_OVERVIEW_OPACITY = 0.28;
local TRANSITION_CLOSE_OPACITY = 0.64;
local TRANSITION_CLOSE_ZOOM_RATIO = 3.00;
local MARKER_REFERENCE_ZOOM = 4.41;
local ENTITY_FLOOR_TOLERANCE = 8.0;
local PATH_FLOOR_TOLERANCE = 4.0;
local MAP_CORNER_RADIUS = 7.0;
local HUD_INSET = 6;
local HUD_CONTROL_GAP = 4;
local HUD_CONTROL_HEIGHT = 22;
local DECISION_SELECTOR_TOP = 1230;
local DECISION_SELECTOR_GUTTER = 16;
local COMBAT_SELECTOR_TOP = 1130;
local COMBAT_SELECTOR_GUTTER = 16;
local INVENTORY_PREVIEW_TOP = 1290;
local INVENTORY_PREVIEW_GUTTER = 16;
local POSITION_ANIMATION_RESPONSE = 22;
local HOVER_FADE_IN_SECONDS = 0.30;
local HOVER_FADE_OUT_SECONDS = 0.45;
local SHOW_MAP_CALIBRATION = false;
local VANA_TIME_SIGNATURE = 'B0015EC390518B4C24088D4424005068';
local WEATHER_SIGNATURE = '66A1????????663D????72';
-- General structure rendering is intentionally dormant. Keep the
-- implementation, metadata, and assets intact so attended development can
-- restore it later. A map may force one narrowly authored correction overlay
-- after live traversal proves that the stock artwork omits walkable geometry.
local STRUCTURE_RENDERING_ENABLED = false;

local DEFAULTS = {
    visible = true,
    locked = true,
    x = 18,
    y = 128,
    size = 330,
    pixels_per_yalm = 4.41,
    show_map_vanilla = true,
    show_map_structure = false,
    vanilla_opacity = 0.35,
    structure_opacity = 0.82,
    inactive_floor_opacity = 0.14,
    structure_visibility_boost = 4,
    backdrop_opacity = 0.12,
    show_grid = true,
    show_coordinate = true,
    show_numeric_coordinates = false,
    show_environment_clock = true,
    show_weather_badge = true,
    show_coffer_spawns = true,
    show_travel_references = true,
    show_nm_spawn_ranges = true,
    show_guide_paths = true,
    developer_mode = false,
    show_all_pathing = false,
    show_players = true,
    show_npcs = true,
    show_monsters = true,
    show_widescan_target = true,
    scale_markers_with_zoom = true,
    marker_size = 1.00,
    map_pages = {},
    origin_adjustments = {},
    colors = {
        border = { 0.67, 0.47, 0.22, 0.90 },
        grid = { 0.48, 0.60, 0.61, 0.25 },
        grid_text = { 0.82, 0.71, 0.51, 0.88 },
        chest_spawn = { 0.545, 0.306, 0.145, 0.98 },
        coffer_spawn = { 1.000, 0.820, 0.200, 0.98 },
        home_point = { 0.310, 0.900, 1.000, 0.98 },
        survival_guide = { 0.690, 0.420, 0.180, 0.98 },
        nm_spawn_range = { 0.690, 0.145, 0.190, 0.075 },
        nm_spawn_border = { 0.890, 0.660, 0.260, 0.78 },
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
};

local state = {
    settings = DEFAULTS,
    native_chat = require('native_chat'),
    maps = {},
    path_catalog = {},
    path_graphs = {},
    world_catalog = {},
    vanilla_maps = {},
    textures = {},
    device = nil,
    warned_zones = {},
    stock_minimap_pointer_address = 0,
    stock_minimap_checked_at = 0,
    stock_map_table_address = 0,
    stock_map_table_checked_at = 0,
    stock_map_records = {},
    stock_page_selector_address = 0,
    stock_page_context_pointer_address = 0,
    stock_page_selector_checked_at = 0,
    stock_page_by_zone = {},
    stock_position_pages = {},
    stock_page_selector_warning = nil,
    widescan_target = nil,
    environment = {
        time_signature_address = 0,
        weather_signature_address = 0,
        checked_at = 0,
        snapshot = nil,
        snapshot_at = 0,
    },
    config_visible = { false },
    config_dirty = false,
    config_changed_at = 0,
    dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
    hover_focus = 0,
    hover_focus_updated_at = 0,
    window_y = nil,
    window_y_updated_at = 0,
    origin_editor = {
        zone_id = nil,
        page_key = nil,
        x = 0,
        y = 0,
    },
    guide_markers = {
        payload = nil,
        last_poll = 0,
        last_error = nil,
    },
    mcp_waypoint = {
        pending = nil,
        last_poll = 0,
        last_request_id = nil,
        last_error = nil,
    },
    guide_path = {
        route = nil,
        last_attempt = 0,
        last_error = nil,
    },
    world_path = {
        route = nil,
        last_attempt = 0,
        last_error = nil,
    },
    world_topology = nil,
    -- Retail Home Point destination counts for currently authored zones.
    -- Warp is withheld unless both the complete zone count and the authored
    -- anchor count prove one unambiguous landing point.
    world_home_point_zone_counts = {
        [236] = 3,
        [237] = 2,
        [241] = 5,
        [243] = 3,
        [244] = 3,
        [245] = 2,
        [246] = 2,
    },
    custom_waypoint = nil,
    atlas = {
        visible = { false },
        zone_id = nil,
        page_id = nil,
        camera_x = nil,
        camera_y = nil,
        pixels_per_yalm = nil,
        dragging = false,
        drag_mouse_x = 0,
        drag_mouse_y = 0,
        show_nm_spawn_ranges = true,
        search = { '' },
        filters = {
            waypoint_ready = false,
            has_pathing = false,
            multiple_pages = false,
        },
        filter_metadata = {},
        window_x = nil,
        window_y = nil,
        window_width = nil,
        window_height = nil,
        toggle_x = nil,
        toggle_y = nil,
        toggle_width = nil,
        toggle_height = nil,
    },
};

local function safe_read(callback, fallback)
    local ok, value = pcall(callback);
    if (ok and value ~= nil) then
        return value;
    end
    return fallback;
end

local function log(message)
    print(string.format('[%s] %s', addon.name, tostring(message)));
end

local function copy_table(value)
    if (type(value) ~= 'table') then
        return value;
    end
    local result = {};
    for key, child in pairs(value) do
        result[key] = copy_table(child);
    end
    return result;
end

local function merge_table(target, source)
    if (type(source) ~= 'table') then
        return target;
    end
    for key, value in pairs(source) do
        if (type(value) == 'table' and type(target[key]) == 'table') then
            merge_table(target[key], value);
        else
            target[key] = value;
        end
    end
    return target;
end

local function bool_text(value)
    return value == true and 'true' or 'false';
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum));
end

local function color_text(value, fallback)
    value = type(value) == 'table' and value or fallback;
    return string.format(
        '{ %.3f, %.3f, %.3f, %.3f }',
        tonumber(value[1]) or fallback[1],
        tonumber(value[2]) or fallback[2],
        tonumber(value[3]) or fallback[3],
        tonumber(value[4]) or fallback[4]);
end

local function colors_match(left, right)
    if (type(left) ~= 'table' or type(right) ~= 'table') then
        return false;
    end
    for index = 1, 4 do
        if (math.abs((tonumber(left[index]) or -1) - right[index]) > 0.0005) then
            return false;
        end
    end
    return true;
end

local function number_map_text(value)
    local entries = {};
    if (type(value) == 'table') then
        for key, item in pairs(value) do
            local numeric_key = tonumber(key);
            local numeric_value = tonumber(item);
            if (numeric_key ~= nil and numeric_value ~= nil) then
                entries[#entries + 1] = {
                    key = math.floor(numeric_key),
                    value = math.floor(numeric_value),
                };
            end
        end
    end
    table.sort(entries, function (left, right) return left.key < right.key; end);
    local parts = {};
    for _, entry in ipairs(entries) do
        parts[#parts + 1] = string.format('[%d] = %d', entry.key, entry.value);
    end
    return '{ ' .. table.concat(parts, ', ') .. ' }';
end

local function origin_adjustments_text(value)
    local zones = {};
    if (type(value) == 'table') then
        for zone_key, pages in pairs(value) do
            local zone_id = tonumber(zone_key);
            if (zone_id ~= nil and type(pages) == 'table') then
                local page_entries = {};
                for page_key, adjustment in pairs(pages) do
                    local page_id = tonumber(page_key);
                    local x = type(adjustment) == 'table' and tonumber(adjustment.x) or nil;
                    local y = type(adjustment) == 'table' and tonumber(adjustment.y) or nil;
                    if (page_id ~= nil and x ~= nil and y ~= nil) then
                        page_entries[#page_entries + 1] = {
                            page_id = math.floor(page_id),
                            x = x,
                            y = y,
                        };
                    end
                end
                table.sort(page_entries, function (left, right)
                    return left.page_id < right.page_id;
                end);
                if (#page_entries > 0) then
                    zones[#zones + 1] = {
                        zone_id = math.floor(zone_id),
                        pages = page_entries,
                    };
                end
            end
        end
    end
    table.sort(zones, function (left, right) return left.zone_id < right.zone_id; end);

    local zone_parts = {};
    for _, zone in ipairs(zones) do
        local page_parts = {};
        for _, page in ipairs(zone.pages) do
            page_parts[#page_parts + 1] = string.format(
                '[%d] = { x = %.3f, y = %.3f }',
                page.page_id,
                page.x,
                page.y);
        end
        zone_parts[#zone_parts + 1] = string.format(
            '[%d] = { %s }',
            zone.zone_id,
            table.concat(page_parts, ', '));
    end
    return '{ ' .. table.concat(zone_parts, ', ') .. ' }';
end

local function config_text()
    local settings = state.settings;
    local colors = settings.colors or DEFAULTS.colors;
    local lines = {
        'return {',
        string.format('    visible = %s,', bool_text(settings.visible)),
        string.format('    locked = %s,', bool_text(settings.locked)),
        '',
        '    -- Screen placement and viewport size.',
        string.format('    x = %d,', math.floor((tonumber(settings.x) or DEFAULTS.x) + 0.5)),
        string.format('    y = %d,', math.floor((tonumber(settings.y) or DEFAULTS.y) + 0.5)),
        string.format('    size = %d,', math.floor(clamp(settings.size, 120, 700) + 0.5)),
        '',
        '    -- Lua renderer scale. Higher values zoom in.',
        string.format('    pixels_per_yalm = %.4f,', clamp(settings.pixels_per_yalm, ZOOM_MIN, ZOOM_MAX)),
        '',
        '    -- Independently composited map layers.',
        string.format('    show_map_vanilla = %s,', bool_text(settings.show_map_vanilla)),
        string.format('    show_map_structure = %s,', bool_text(settings.show_map_structure)),
        string.format('    vanilla_opacity = %.3f,', clamp(settings.vanilla_opacity, 0, 1)),
        string.format('    structure_opacity = %.3f,', clamp(settings.structure_opacity, 0, 1)),
        string.format(
            '    inactive_floor_opacity = %.3f,',
            clamp(settings.inactive_floor_opacity, 0, 1)),
        string.format(
            '    structure_visibility_boost = %d,',
            math.floor(clamp(settings.structure_visibility_boost, 1, 12) + 0.5)),
        string.format('    backdrop_opacity = %.3f,', clamp(settings.backdrop_opacity, 0, 0.75)),
        '',
        string.format('    show_grid = %s,', bool_text(settings.show_grid)),
        string.format('    show_coordinate = %s,', bool_text(settings.show_coordinate)),
        string.format(
            '    show_numeric_coordinates = %s,',
            bool_text(settings.show_numeric_coordinates)),
        string.format(
            '    show_environment_clock = %s,',
            bool_text(settings.show_environment_clock)),
        string.format(
            '    show_weather_badge = %s,',
            bool_text(settings.show_weather_badge)),
        string.format('    show_coffer_spawns = %s,', bool_text(settings.show_coffer_spawns)),
        string.format('    show_travel_references = %s,', bool_text(settings.show_travel_references)),
        string.format('    show_nm_spawn_ranges = %s,', bool_text(settings.show_nm_spawn_ranges)),
        string.format('    show_guide_paths = %s,', bool_text(settings.show_guide_paths)),
        string.format('    developer_mode = %s,', bool_text(settings.developer_mode)),
        string.format('    show_all_pathing = %s,', bool_text(settings.show_all_pathing)),
        string.format('    show_players = %s,', bool_text(settings.show_players)),
        string.format('    show_npcs = %s,', bool_text(settings.show_npcs)),
        string.format('    show_monsters = %s,', bool_text(settings.show_monsters)),
        string.format(
            '    show_widescan_target = %s,',
            bool_text(settings.show_widescan_target)),
        string.format('    scale_markers_with_zoom = %s,', bool_text(settings.scale_markers_with_zoom)),
        string.format('    marker_size = %.2f,', clamp(settings.marker_size, 0.25, 2.00)),
        string.format('    map_pages = %s,', number_map_text(settings.map_pages)),
        '',
        '    -- Per-zone and per-page source-image calibration offsets, in pixels.',
        string.format(
            '    origin_adjustments = %s,',
            origin_adjustments_text(settings.origin_adjustments)),
        '',
        '    colors = {',
        string.format('        border = %s,', color_text(colors.border, DEFAULTS.colors.border)),
        string.format('        grid = %s,', color_text(colors.grid, DEFAULTS.colors.grid)),
        string.format('        grid_text = %s,', color_text(colors.grid_text, DEFAULTS.colors.grid_text)),
        string.format('        chest_spawn = %s,', color_text(colors.chest_spawn, DEFAULTS.colors.chest_spawn)),
        string.format('        coffer_spawn = %s,', color_text(colors.coffer_spawn, DEFAULTS.colors.coffer_spawn)),
        string.format('        home_point = %s,', color_text(colors.home_point, DEFAULTS.colors.home_point)),
        string.format('        survival_guide = %s,', color_text(colors.survival_guide, DEFAULTS.colors.survival_guide)),
        string.format('        nm_spawn_range = %s,', color_text(colors.nm_spawn_range, DEFAULTS.colors.nm_spawn_range)),
        string.format('        nm_spawn_border = %s,', color_text(colors.nm_spawn_border, DEFAULTS.colors.nm_spawn_border)),
        string.format('        player = %s,', color_text(colors.player, DEFAULTS.colors.player)),
        string.format('        other_player = %s,', color_text(colors.other_player, DEFAULTS.colors.other_player)),
        string.format('        npc = %s,', color_text(colors.npc, DEFAULTS.colors.npc)),
        string.format('        monster = %s,', color_text(colors.monster, DEFAULTS.colors.monster)),
        string.format('        target = %s,', color_text(colors.target, DEFAULTS.colors.target)),
        string.format(
            '        widescan_target = %s,',
            color_text(colors.widescan_target, DEFAULTS.colors.widescan_target)),
        string.format('        shadow = %s,', color_text(colors.shadow, DEFAULTS.colors.shadow)),
        string.format('        badge = %s,', color_text(colors.badge, DEFAULTS.colors.badge)),
        string.format('        backdrop = %s,', color_text(colors.backdrop, DEFAULTS.colors.backdrop)),
        '    },',
        '}',
        '',
    };
    return table.concat(lines, '\n');
end

local function save_configuration()
    local path = string.format('%s%s', addon.path, 'ashitaminimap_config.lua');
    local file, error_message = io.open(path, 'w');
    if (file == nil) then
        return false, tostring(error_message or 'open failed');
    end
    file:write(config_text());
    file:close();
    state.config_dirty = false;
    return true, path;
end

local function mark_configuration_changed()
    state.config_dirty = true;
    state.config_changed_at = os.clock();
end

local function save_configuration_if_due(force)
    if (state.config_dirty ~= true) then
        return;
    end
    if (force ~= true and (os.clock() - state.config_changed_at) < 0.75) then
        return;
    end
    local ok, message = save_configuration();
    if (not ok) then
        log('Could not save configuration: ' .. message);
    end
end

local function load_module_file(filename)
    local path = string.format('%s%s', addon.path, filename);
    local chunk, error_message = loadfile(path);
    if (chunk == nil) then
        return nil, error_message;
    end
    local ok, value = pcall(chunk);
    if (not ok) then
        return nil, value;
    end
    return value, nil;
end

local function validate_structure_layer_set(layers, context)
    if (type(layers) ~= 'table') then
        return true;
    end
    for index, layer in ipairs(layers) do
        local minimum_z = type(layer) == 'table'
            and tonumber(layer.minimum_player_z)
            or nil;
        local maximum_z = type(layer) == 'table'
            and tonumber(layer.maximum_player_z)
            or nil;
        local has_floor_bounds = minimum_z ~= nil or maximum_z ~= nil;
        local is_transition = type(layer) == 'table'
            and layer.role == 'floor_transition';
        local is_always_visible = type(layer) == 'table'
            and layer.floor_selection == 'always';
        if (type(layer) ~= 'table'
                or not (has_floor_bounds
                    or is_transition
                    or is_always_visible)
                or (minimum_z ~= nil
                    and maximum_z ~= nil
                    and minimum_z > maximum_z)) then
            log(string.format(
                'Map calibration warning: %s layer %d (%s) has no valid '
                    .. 'floor selection metadata; skipping this layer set.',
                context,
                index,
                tostring(type(layer) == 'table' and layer.image or layer)));
            return false;
        end
    end
    return true;
end

local function validate_structure_layers(maps)
    for zone_id, map in pairs(maps) do
        if (type(map) == 'table') then
            if (type(map.structure_layers) == 'table'
                    and not validate_structure_layer_set(
                        map.structure_layers,
                        string.format('zone %s', tostring(zone_id)))) then
                map.structure_layers = nil;
            end
            if (type(map.structure_pages) == 'table') then
                for page_id, layers in pairs(map.structure_pages) do
                    if (type(layers) == 'table'
                            and not validate_structure_layer_set(
                                layers,
                                string.format(
                                    'zone %s page %s',
                                    tostring(zone_id),
                                    tostring(page_id)))) then
                        map.structure_pages[page_id] = nil;
                    end
                end
            end
        end
    end
end

local function load_configuration()
    local settings, settings_error = load_module_file('ashitaminimap_config.lua');
    settings = type(settings) == 'table' and settings or {};
    state.settings = merge_table(copy_table(DEFAULTS), settings);
    -- Migrate the original flattened-layer settings without overwriting newer
    -- per-layer values when they are already present.
    if (settings.structure_opacity == nil and settings.map_opacity ~= nil) then
        state.settings.structure_opacity = settings.map_opacity;
    end
    if (settings.structure_visibility_boost == nil and settings.map_visibility_boost ~= nil) then
        state.settings.structure_visibility_boost = settings.map_visibility_boost;
    end
    local obsolete_layer_settings = settings.show_map_labels ~= nil
        or settings.show_map_landmarks ~= nil
        or settings.label_opacity ~= nil
        or settings.landmark_opacity ~= nil
        or settings.label_visibility_boost ~= nil
        or settings.landmark_visibility_boost ~= nil;
    local legacy_coffer_color = type(settings.colors) == 'table'
        and colors_match(
            settings.colors.coffer_spawn,
            { 1.000, 0.314, 0.686, 0.98 });
    if (legacy_coffer_color) then
        state.settings.colors.coffer_spawn =
            copy_table(DEFAULTS.colors.coffer_spawn);
    end
    state.settings.size = clamp(state.settings.size, 120, 700);
    local loaded_zoom = tonumber(state.settings.pixels_per_yalm) or DEFAULTS.pixels_per_yalm;
    state.settings.pixels_per_yalm = clamp(loaded_zoom, ZOOM_MIN, ZOOM_MAX);
    state.settings.vanilla_opacity = clamp(state.settings.vanilla_opacity, 0, 1);
    state.settings.structure_opacity = clamp(state.settings.structure_opacity, 0, 1);
    state.settings.inactive_floor_opacity =
        clamp(state.settings.inactive_floor_opacity, 0, 1);
    state.settings.structure_visibility_boost =
        math.floor(clamp(state.settings.structure_visibility_boost, 1, 12) + 0.5);
    state.settings.backdrop_opacity = clamp(state.settings.backdrop_opacity, 0, 0.75);
    state.settings.marker_size = clamp(state.settings.marker_size, 0.25, 2.00);
    state.settings.map_pages = type(state.settings.map_pages) == 'table'
        and state.settings.map_pages
        or {};
    state.settings.origin_adjustments = type(state.settings.origin_adjustments) == 'table'
        and state.settings.origin_adjustments
        or {};
    state.config_dirty = loaded_zoom ~= state.settings.pixels_per_yalm
        or obsolete_layer_settings
        or legacy_coffer_color;
    state.config_changed_at = 0;
    state.dragging = false;
    state.origin_editor.zone_id = nil;
    state.origin_editor.page_key = nil;
    if (settings_error ~= nil) then
        log('Config warning: ' .. tostring(settings_error));
    end

    local maps, maps_error = load_module_file('ashitaminimap_maps.lua');
    state.maps = type(maps) == 'table' and maps or {};
    if (STRUCTURE_RENDERING_ENABLED) then
        validate_structure_layers(state.maps);
    end
    if (maps_error ~= nil) then
        log('Map calibration warning: ' .. tostring(maps_error));
    end

    local path_catalog, path_catalog_error =
        load_module_file('ashitaminimap_paths.lua');
    state.path_catalog = type(path_catalog) == 'table' and path_catalog or {};
    state.path_graphs = {};
    state.guide_path.route = nil;
    state.guide_path.last_attempt = 0;
    state.guide_path.last_error = nil;
    if (path_catalog_error ~= nil) then
        log('Path graph catalog unavailable: ' .. tostring(path_catalog_error));
    end

    local world_catalog, world_catalog_error =
        load_module_file('assets/world/connections.lua');
    state.world_catalog = type(world_catalog) == 'table'
        and world_catalog
        or {};
    state.world_path.route = nil;
    state.world_path.last_attempt = 0;
    state.world_path.last_error = nil;
    state.world_topology = nil;
    if (world_catalog_error ~= nil) then
        log('World connection catalog unavailable: '
            .. tostring(world_catalog_error));
    end

    local vanilla_maps, vanilla_error =
        load_module_file('ashitaminimap_vanilla_maps.lua');
    state.vanilla_maps = type(vanilla_maps) == 'table' and vanilla_maps or {};
    if (vanilla_error ~= nil) then
        log('Vanilla fallback catalog unavailable; run tools/import_vanilla_maps.py.');
    end
end

local function color(name, fallback)
    local colors = state.settings.colors or {};
    return imgui.GetColorU32(colors[name] or fallback);
end

local function color_with_opacity(name, fallback, opacity)
    local colors = state.settings.colors or {};
    local value = type(colors[name]) == 'table' and colors[name] or fallback;
    return imgui.GetColorU32({
        tonumber(value[1]) or fallback[1],
        tonumber(value[2]) or fallback[2],
        tonumber(value[3]) or fallback[3],
        (tonumber(value[4]) or fallback[4]) * clamp(opacity, 0, 1),
    });
end

state.guide_marker_file_path = function ()
    local install_path = tostring(safe_read(function ()
        return AshitaCore:GetInstallPath();
    end, '') or '');
    if (install_path == '') then
        return nil;
    end
    local last = install_path:sub(#install_path);
    if (last ~= '\\' and last ~= '/') then
        install_path = install_path .. '\\';
    end
    return install_path .. 'config\\addons\\ashitaguide\\ashitaminimap_markers.lua';
end

state.poll_guide_markers = function (force)
    local now_clock = os.clock();
    if (force ~= true and now_clock - state.guide_markers.last_poll < 0.25) then
        return;
    end
    state.guide_markers.last_poll = now_clock;

    local path = state.guide_marker_file_path();
    local chunk = nil;
    local load_error = nil;
    if (path ~= nil) then
        chunk, load_error = loadfile(path);
    end
    if (chunk == nil) then
        if (load_error ~= nil
                and state.guide_markers.last_error ~= tostring(load_error)) then
            state.guide_markers.last_error = tostring(load_error);
        end
        return;
    end

    local ok, value = pcall(chunk);
    local version = type(value) == 'table' and tonumber(value.version) or nil;
    if (not ok or type(value) ~= 'table'
            or (version ~= 1 and version ~= 2 and version ~= 3 and version ~= 4)
            or value.source ~= 'ashitaguide') then
        state.guide_markers.last_error = 'invalid marker handoff';
        return;
    end

    local zone_id = tonumber(
        version >= 2 and value.destination_zone_id or value.zone_id);
    local player_zone_id = tonumber(
        version >= 2 and value.player_zone_id or value.zone_id);
    local updated_at = tonumber(value.updated_at);
    local normalized = {
        zone_id = zone_id ~= nil and math.floor(zone_id) or nil,
        player_zone_id = player_zone_id ~= nil
            and math.floor(player_zone_id)
            or nil,
        updated_at = updated_at,
        path_enabled = version < 3 or value.path_enabled ~= false,
        markers = {},
    };
    if (version >= 4 and type(value.nm_hunt) == 'table') then
        local hunt_zone_id = tonumber(value.nm_hunt.zone_id);
        local hidden = {};
        local hidden_count = 0;
        for name, is_hidden in pairs(
                type(value.nm_hunt.hidden) == 'table' and value.nm_hunt.hidden or {}) do
            local clean_name = type(name) == 'string'
                and name:gsub('^%s+', ''):gsub('%s+$', '')
                or '';
            if (is_hidden == true and clean_name ~= '' and #clean_name <= 96 and hidden_count < 64) then
                hidden[clean_name:lower()] = true;
                hidden_count = hidden_count + 1;
            end
        end
        if (hunt_zone_id ~= nil and hunt_zone_id >= 0 and hunt_zone_id <= 999) then
            normalized.nm_hunt = {
                zone_id = math.floor(hunt_zone_id),
                visible = value.nm_hunt.visible == true,
                hidden = hidden,
                markers = {},
            };
            for _, marker in ipairs(type(value.nm_hunt.markers) == 'table'
                    and value.nm_hunt.markers or {}) do
                local x = type(marker) == 'table' and tonumber(marker.x) or nil;
                local y = type(marker) == 'table' and tonumber(marker.y) or nil;
                local style = type(marker) == 'table' and tostring(marker.style or ''):lower() or '';
                if (x ~= nil and y ~= nil
                        and math.abs(x) <= 100000 and math.abs(y) <= 100000
                        and (style == 'damselfly' or style == 'lizard')
                        and #normalized.nm_hunt.markers < 20) then
                    normalized.nm_hunt.markers[#normalized.nm_hunt.markers + 1] = {
                        x = x,
                        y = y,
                        z = tonumber(marker.z),
                        style = style,
                    };
                end
            end
        end
    end
    if (version >= 3 and type(value.marker_reference) == 'table') then
        local kind = tostring(value.marker_reference.kind or '');
        local name = tostring(value.marker_reference.name or '')
            :gsub('^%s+', '')
            :gsub('%s+$', '');
        if (kind == 'nm_spawn_range'
                and name ~= ''
                and #name <= 96) then
            normalized.marker_reference = {
                kind = kind,
                name = name,
            };
        end
    end
    for _, marker in ipairs(type(value.markers) == 'table' and value.markers or {}) do
        local x = type(marker) == 'table' and tonumber(marker.x) or nil;
        local y = type(marker) == 'table' and tonumber(marker.y) or nil;
        local map_id = type(marker) == 'table' and tonumber(marker.map_id) or nil;
        if (x ~= nil and y ~= nil
                and math.abs(x) <= 100000
                and math.abs(y) <= 100000
                and #normalized.markers < 20) then
            normalized.markers[#normalized.markers + 1] = {
                x = x,
                y = y,
                z = type(marker) == 'table' and tonumber(marker.z) or nil,
                map_id = map_id ~= nil and math.floor(map_id) or nil,
                approximate = marker.approximate == true,
                style = tostring(marker.style or ''):lower() == 'damselfly'
                    and 'damselfly'
                    or '',
            };
        end
    end
    state.guide_markers.payload = normalized;
    state.guide_markers.last_error = nil;
end

state.mcp_waypoint_file_path = function (filename)
    local install_path = tostring(safe_read(function ()
        return AshitaCore:GetInstallPath();
    end, '') or '');
    if (install_path == '') then
        return nil;
    end
    local last = install_path:sub(#install_path);
    if (last ~= '\\' and last ~= '/') then
        install_path = install_path .. '\\';
    end
    return install_path
        .. 'config\\addons\\ashitaminimap\\'
        .. tostring(filename or '');
end

local function json_quoted(value)
    local text = tostring(value or '')
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\r', '\\r')
        :gsub('\n', '\\n')
        :gsub('\t', '\\t');
    return '"' .. text .. '"';
end

state.write_mcp_waypoint_status = function (
        request_id,
        status,
        message,
        waypoint,
        acknowledged)
    local path = state.mcp_waypoint_file_path('mcp_waypoint_status.json');
    if (path == nil) then
        return;
    end
    local parts = {
        '"ok":true',
        '"acknowledged":' .. bool_text(acknowledged == true),
        '"requestId":' .. json_quoted(request_id),
        '"state":' .. json_quoted(status),
        '"message":' .. json_quoted(message),
        '"updatedAt":' .. tostring(os.time()),
        '"active":' .. bool_text(type(waypoint) == 'table'),
    };
    if (type(waypoint) == 'table') then
        parts[#parts + 1] = '"zoneId":' .. tostring(waypoint.zone_id);
        parts[#parts + 1] = '"mapId":'
            .. (waypoint.map_id ~= nil and tostring(waypoint.map_id) or 'null');
        parts[#parts + 1] = '"x":' .. string.format('%.6f', waypoint.x);
        parts[#parts + 1] = '"y":' .. string.format('%.6f', waypoint.y);
        parts[#parts + 1] = '"z":'
            .. (waypoint.z ~= nil and string.format('%.6f', waypoint.z) or 'null');
        parts[#parts + 1] = '"floorAmbiguous":'
            .. bool_text(waypoint.floor_ambiguous == true);
    end
    local file = io.open(path, 'w');
    if (file ~= nil) then
        file:write('{' .. table.concat(parts, ',') .. '}');
        file:close();
    end
end

state.note_manual_waypoint_change = function (active)
    state.write_mcp_waypoint_status(
        state.mcp_waypoint.last_request_id or '',
        active == true and 'manual_waypoint' or 'cleared_manually',
        active == true
            and 'The player replaced the MCP waypoint by right-clicking the map.'
            or 'The player cleared the waypoint manually.',
        active == true and state.custom_waypoint or nil,
        state.mcp_waypoint.last_request_id ~= nil);
end

state.poll_mcp_waypoint = function (force)
    local now_clock = os.clock();
    if (force ~= true and now_clock - state.mcp_waypoint.last_poll < 0.25) then
        return;
    end
    state.mcp_waypoint.last_poll = now_clock;

    local path = state.mcp_waypoint_file_path('mcp_waypoint_request.lua');
    local chunk = path ~= nil and loadfile(path) or nil;
    if (chunk == nil) then
        return;
    end
    local ok, value = pcall(chunk);
    local request_id = type(value) == 'table'
        and tostring(value.request_id or '')
        or '';
    if (not ok
            or type(value) ~= 'table'
            or tonumber(value.version) ~= 1
            or value.source ~= 'ashitaminimap_mcp'
            or request_id == ''
            or #request_id > 64
            or request_id:match('^[%w%-]+$') == nil) then
        state.mcp_waypoint.last_error = 'invalid MCP waypoint request';
        return;
    end
    if (state.mcp_waypoint.last_request_id == request_id) then
        return;
    end
    state.mcp_waypoint.last_request_id = request_id;

    local issued_at = tonumber(value.issued_at);
    local expires_at = tonumber(value.expires_at);
    local now = os.time();
    if (issued_at == nil
            or expires_at == nil
            or expires_at < issued_at
            or expires_at - issued_at > 120
            or now < issued_at - 5
            or now > expires_at) then
        state.mcp_waypoint.last_error = 'expired MCP waypoint request';
        state.write_mcp_waypoint_status(
            request_id,
            'expired',
            'The waypoint request expired before AshitaMiniMap could consume it.',
            nil,
            true);
        return;
    end

    local action = tostring(value.action or ''):lower();
    if (action ~= 'set' and action ~= 'clear') then
        state.mcp_waypoint.last_error = 'invalid MCP waypoint action';
        state.write_mcp_waypoint_status(
            request_id,
            'rejected',
            'The waypoint action must be set or clear.',
            nil,
            true);
        return;
    end
    state.mcp_waypoint.pending = {
        request_id = request_id,
        action = action,
        waypoint = value.waypoint,
        expires_at = expires_at,
    };
    state.mcp_waypoint.last_error = nil;
end

state.active_guide_payload = function ()
    local payload = state.guide_markers.payload;
    if (type(payload) ~= 'table'
            or payload.zone_id == nil
            or tonumber(payload.updated_at) == nil
            or math.abs(os.time() - payload.updated_at) > 3) then
        return nil;
    end
    return payload;
end

state.active_guide_markers = function (player)
    local payload = state.active_guide_payload();
    if (payload == nil or payload.zone_id ~= player.zone_id) then
        return {};
    end
    return payload.markers;
end

state.active_guide_nm_reference = function (player, map)
    local payload = state.active_guide_payload();
    local requested = payload ~= nil and payload.marker_reference or nil;
    if (requested == nil
            or payload.zone_id ~= player.zone_id
            or type(map.nm_spawn_ranges) ~= 'table') then
        return nil;
    end
    local requested_name = requested.name:lower();
    local current_page = tonumber(map.page_id);
    for _, reference in ipairs(map.nm_spawn_ranges) do
        local reference_page = type(reference) == 'table'
            and tonumber(reference.page_id)
            or nil;
        if (type(reference) == 'table'
                and tostring(reference.name or ''):lower() == requested_name
                and (reference_page == nil or reference_page == current_page)) then
            return reference;
        end
    end
    return nil;
end

state.nm_hunt_reference_visible = function (player, reference)
    local payload = state.active_guide_payload();
    local hunt = payload ~= nil and payload.nm_hunt or nil;
    if (hunt == nil or hunt.zone_id ~= player.zone_id) then
        return true;
    end
    if (hunt.visible ~= true) then
        return false;
    end
    return hunt.hidden[tostring(reference.name or ''):lower()] ~= true;
end

state.active_nm_hunt_markers = function (player)
    local payload = state.active_guide_payload();
    local hunt = payload ~= nil and payload.nm_hunt or nil;
    if (hunt == nil or hunt.zone_id ~= player.zone_id or hunt.visible ~= true) then
        return {};
    end
    return hunt.markers or {};
end

state.active_custom_waypoint = function (player, map)
    local waypoint = state.custom_waypoint;
    if (type(waypoint) ~= 'table'
            or waypoint.zone_id ~= player.zone_id
            or (waypoint.page_id ~= nil
                and tonumber(map.page_id) ~= waypoint.page_id)) then
        return nil;
    end
    return waypoint;
end

state.path_graph_for = function (zone_id, page_id)
    local page_key = tonumber(page_id) ~= nil
        and math.floor(tonumber(page_id))
        or -1;
    local cache_key = string.format('%d:%d', zone_id, page_key);
    if (state.path_graphs[cache_key] ~= nil) then
        return state.path_graphs[cache_key] ~= false
            and state.path_graphs[cache_key]
            or nil;
    end
    local catalog_entry = state.path_catalog[zone_id];
    local filename = type(catalog_entry) == 'table'
        and (catalog_entry[page_key] or catalog_entry.default)
        or catalog_entry;
    if (type(filename) ~= 'string' or filename == '') then
        state.path_graphs[cache_key] = false;
        return nil;
    end
    local graph, error_message = load_module_file(filename);
    if (type(graph) ~= 'table'
            or tonumber(graph.zone_id) ~= zone_id
            or type(graph.nodes) ~= 'table'
            or #graph.nodes < 2) then
        state.path_graphs[cache_key] = false;
        log(string.format(
            'Invalid path graph for zone %d: %s',
            zone_id,
            tostring(error_message or filename)));
        return nil;
    end
    state.path_graphs[cache_key] = graph;
    return graph;
end

state.path_node_live_z = function (graph, node)
    local graph_z = type(node) == 'table' and tonumber(node[3]) or nil;
    if (graph_z == nil) then
        return nil;
    end
    -- Generated Detour elevation has the opposite sign from Ashita's live Z.
    return graph_z * (tonumber(graph.live_z_sign) or -1);
end

state.path_nearest_node = function (graph, x, y, live_z)
    local best_index = nil;
    local best_distance_squared = nil;
    local best_planar_distance_squared = nil;
    local floor_tolerance = tonumber(graph.floor_tolerance)
        or PATH_FLOOR_TOLERANCE;
    for index, node in ipairs(graph.nodes) do
        local delta_x = (tonumber(node[1]) or 0) - x;
        local delta_y = (tonumber(node[2]) or 0) - y;
        local node_z = state.path_node_live_z(graph, node);
        local delta_z = live_z ~= nil and node_z ~= nil
            and (node_z - live_z)
            or 0;
        local same_floor = live_z == nil
            or node_z == nil
            or math.abs(delta_z) <= floor_tolerance;
        local planar_distance_squared =
            (delta_x * delta_x) + (delta_y * delta_y);
        local distance_squared = planar_distance_squared + (delta_z * delta_z);
        if (same_floor
                and (best_distance_squared == nil
                    or distance_squared < best_distance_squared)) then
            best_index = index;
            best_distance_squared = distance_squared;
            best_planar_distance_squared = planar_distance_squared;
        end
    end
    local distance = best_planar_distance_squared ~= nil
        and math.sqrt(best_planar_distance_squared)
        or math.huge;
    if (distance > (tonumber(graph.snap_radius) or 24)) then
        return nil, distance;
    end
    return best_index, distance;
end

state.path_component_ids = function (graph)
    if (type(graph) ~= 'table' or type(graph.nodes) ~= 'table') then
        return nil;
    end
    if (type(graph._component_ids) == 'table') then
        return graph._component_ids;
    end
    local component_ids = {};
    local component_id = 0;
    for start_index = 1, #graph.nodes do
        if (component_ids[start_index] == nil) then
            component_id = component_id + 1;
            component_ids[start_index] = component_id;
            local pending = { start_index };
            while (#pending > 0) do
                local index = pending[#pending];
                pending[#pending] = nil;
                local node = graph.nodes[index];
                local neighbors = type(node) == 'table' and node[4] or nil;
                if (type(neighbors) == 'table') then
                    for _, raw_neighbor in ipairs(neighbors) do
                        local neighbor = tonumber(raw_neighbor);
                        if (neighbor ~= nil) then
                            neighbor = math.floor(neighbor);
                        end
                        if (neighbor ~= nil
                                and neighbor >= 1
                                and neighbor <= #graph.nodes
                                and component_ids[neighbor] == nil) then
                            component_ids[neighbor] = component_id;
                            pending[#pending + 1] = neighbor;
                        end
                    end
                end
            end
        end
    end
    graph._component_ids = component_ids;
    return component_ids;
end

state.path_waypoint_z = function (
        graph,
        x,
        y,
        player_x,
        player_y,
        player_z,
        require_unambiguous_floor)
    if (type(graph) ~= 'table' or type(graph.nodes) ~= 'table') then
        return nil, false;
    end
    local candidates = {};
    local nearest_distance = math.huge;
    local snap_radius = tonumber(graph.snap_radius) or 24;
    for index, node in ipairs(graph.nodes) do
        local delta_x = (tonumber(node[1]) or 0) - x;
        local delta_y = (tonumber(node[2]) or 0) - y;
        local distance = math.sqrt(
            (delta_x * delta_x) + (delta_y * delta_y));
        local node_z = state.path_node_live_z(graph, node);
        if (node_z ~= nil and distance <= snap_radius) then
            candidates[#candidates + 1] = {
                distance = distance,
                index = index,
                z = node_z,
            };
            nearest_distance = math.min(nearest_distance, distance);
        end
    end
    local selected_z = nil;
    local ambiguity_radius = nearest_distance + PATH_FLOOR_TOLERANCE;
    local nearest_candidate = nil;
    local first_floor_z = nil;
    local multiple_floors = false;
    for _, candidate in ipairs(candidates) do
        if (candidate.distance <= ambiguity_radius) then
            if (nearest_candidate == nil
                    or candidate.distance < nearest_candidate.distance) then
                nearest_candidate = candidate;
            end
            if (first_floor_z == nil) then
                first_floor_z = candidate.z;
            elseif math.abs(candidate.z - first_floor_z)
                    > PATH_FLOOR_TOLERANCE then
                multiple_floors = true;
            end
        end
    end
    if (nearest_candidate ~= nil and not multiple_floors) then
        return nearest_candidate.z, false;
    end
    if (multiple_floors and require_unambiguous_floor == true) then
        return nil, true;
    end

    local start_index = player_x ~= nil
        and player_y ~= nil
        and state.path_nearest_node(
            graph,
            player_x,
            player_y,
            player_z)
        or nil;
    if (start_index ~= nil and type(state.path_find) == 'function') then
        local best_score = math.huge;
        for _, candidate in ipairs(candidates) do
            if (candidate.distance <= ambiguity_radius) then
                local indices = state.path_find(
                    graph,
                    start_index,
                    candidate.index);
                if (indices ~= nil) then
                    local route_length = candidate.distance;
                    for route_index = 1, #indices - 1 do
                        local start = graph.nodes[indices[route_index]];
                        local finish = graph.nodes[indices[route_index + 1]];
                        local delta_x = start[1] - finish[1];
                        local delta_y = start[2] - finish[2];
                        local delta_z = (tonumber(start[3]) or 0)
                            - (tonumber(finish[3]) or 0);
                        route_length = route_length + math.sqrt(
                            (delta_x * delta_x)
                                + (delta_y * delta_y)
                                + (delta_z * delta_z));
                    end
                    if (route_length < best_score) then
                        best_score = route_length;
                        selected_z = candidate.z;
                    end
                end
            end
        end
        if (selected_z ~= nil) then
            return selected_z, false;
        end
    end

    if (player_z ~= nil) then
        local preferred_distance = math.huge;
        for _, candidate in ipairs(candidates) do
            if (math.abs(candidate.z - player_z)
                    <= PATH_FLOOR_TOLERANCE
                    and candidate.distance <= ambiguity_radius
                    and candidate.distance < preferred_distance) then
                selected_z = candidate.z;
                preferred_distance = candidate.distance;
            end
        end
        if (selected_z ~= nil) then
            return selected_z, false;
        end
    end

    for _, candidate in ipairs(candidates) do
        if (candidate.distance <= ambiguity_radius) then
            if (selected_z == nil) then
                selected_z = candidate.z;
            elseif math.abs(candidate.z - selected_z)
                    > PATH_FLOOR_TOLERANCE then
                return nil, true;
            end
        end
    end
    return selected_z, false;
end

state.path_find = function (graph, start_index, target_index)
    if (start_index == target_index) then
        return { start_index };
    end

    local nodes = graph.nodes;
    local open = {};
    local open_count = 0;
    local previous = {};
    local cost = { [start_index] = 0 };
    local closed = {};

    local function heuristic(index)
        local node = nodes[index];
        local target = nodes[target_index];
        local delta_x = node[1] - target[1];
        local delta_y = node[2] - target[2];
        local delta_z = (tonumber(node[3]) or 0)
            - (tonumber(target[3]) or 0);
        return math.sqrt(
            (delta_x * delta_x)
                + (delta_y * delta_y)
                + (delta_z * delta_z));
    end

    local function push(index, score)
        open_count = open_count + 1;
        local position = open_count;
        while position > 1 do
            local parent = math.floor(position / 2);
            if (open[parent].score <= score) then
                break;
            end
            open[position] = open[parent];
            position = parent;
        end
        open[position] = { index = index, score = score };
    end

    local function pop()
        if (open_count == 0) then
            return nil;
        end
        local result = open[1];
        local tail = open[open_count];
        open[open_count] = nil;
        open_count = open_count - 1;
        if (open_count > 0) then
            local position = 1;
            while true do
                local left = position * 2;
                if (left > open_count) then
                    break;
                end
                local right = left + 1;
                local child = right <= open_count
                    and open[right].score < open[left].score
                    and right
                    or left;
                if (open[child].score >= tail.score) then
                    break;
                end
                open[position] = open[child];
                position = child;
            end
            open[position] = tail;
        end
        return result;
    end

    push(start_index, heuristic(start_index));
    while open_count > 0 do
        local current = pop();
        local current_index = current.index;
        if (not closed[current_index]) then
            if (current_index == target_index) then
                local result = { target_index };
                while result[1] ~= start_index do
                    local parent = previous[result[1]];
                    if (parent == nil) then
                        return nil;
                    end
                    table.insert(result, 1, parent);
                end
                return result;
            end
            closed[current_index] = true;
            local current_node = nodes[current_index];
            for _, neighbor_index in ipairs(current_node[4] or {}) do
                local neighbor = nodes[neighbor_index];
                if (neighbor ~= nil and not closed[neighbor_index]) then
                    local delta_x = current_node[1] - neighbor[1];
                    local delta_y = current_node[2] - neighbor[2];
                    local delta_z = (tonumber(current_node[3]) or 0)
                        - (tonumber(neighbor[3]) or 0);
                    local edge_cost = math.sqrt(
                        (delta_x * delta_x)
                            + (delta_y * delta_y)
                            + (delta_z * delta_z));
                    local candidate = cost[current_index] + edge_cost;
                    if (cost[neighbor_index] == nil
                            or candidate < cost[neighbor_index]) then
                        cost[neighbor_index] = candidate;
                        previous[neighbor_index] = current_index;
                        push(neighbor_index, candidate + heuristic(neighbor_index));
                    end
                end
            end
        end
    end
    return nil;
end

state.path_projection = function (route, x, y, z)
    local best = nil;
    local traveled = 0;
    for index = 1, #route.points - 1 do
        local start = route.points[index];
        local finish = route.points[index + 1];
        local segment_x = finish.x - start.x;
        local segment_y = finish.y - start.y;
        local segment_z = (tonumber(finish.z) or 0)
            - (tonumber(start.z) or 0);
        local length_squared = (segment_x * segment_x)
            + (segment_y * segment_y)
            + (segment_z * segment_z);
        local ratio = length_squared > 0
            and clamp(
                (((x - start.x) * segment_x)
                    + ((y - start.y) * segment_y)
                    + (((tonumber(z) or 0) - (tonumber(start.z) or 0))
                        * segment_z))
                    / length_squared,
                0,
                1)
            or 0;
        local projected_x = start.x + (segment_x * ratio);
        local projected_y = start.y + (segment_y * ratio);
        local projected_z = (tonumber(start.z) or 0) + (segment_z * ratio);
        local delta_x = x - projected_x;
        local delta_y = y - projected_y;
        local delta_z = (tonumber(z) or 0) - projected_z;
        local distance_squared = (delta_x * delta_x)
            + (delta_y * delta_y)
            + (delta_z * delta_z);
        local segment_length = math.sqrt(length_squared);
        if (best == nil or distance_squared < best.distance_squared) then
            best = {
                index = index,
                ratio = ratio,
                x = projected_x,
                y = projected_y,
                z = projected_z,
                distance_squared = distance_squared,
                traveled = traveled + (segment_length * ratio),
            };
        end
        traveled = traveled + segment_length;
    end
    if (best ~= nil) then
        best.distance = math.sqrt(best.distance_squared);
        best.remaining = math.max(0, traveled - best.traveled);
    end
    return best;
end

state.path_graph_options = function (zone_id)
    local result = {};
    local seen = {};
    local catalog_entry = state.path_catalog[zone_id];
    local function append(page_id)
        local graph = state.path_graph_for(zone_id, page_id);
        if (graph ~= nil and seen[graph] ~= true) then
            seen[graph] = true;
            result[#result + 1] = {
                graph = graph,
                page_id = tonumber(graph.page_id) or tonumber(page_id),
            };
        end
    end
    if (type(catalog_entry) == 'table') then
        for page_id in pairs(catalog_entry) do
            if (tonumber(page_id) ~= nil) then
                append(math.floor(tonumber(page_id)));
            end
        end
        if (catalog_entry.default ~= nil) then
            append(nil);
        end
    elseif (type(catalog_entry) == 'string') then
        append(nil);
    end
    return result;
end

state.world_snap = function (zone_id, x, y, z, page_id)
    local best = nil;
    for _, option in ipairs(state.path_graph_options(zone_id)) do
        if (page_id == nil
                or option.page_id == nil
                or tonumber(page_id) == tonumber(option.page_id)) then
            local index, distance =
                state.path_nearest_node(option.graph, x, y, z);
            if (index ~= nil and (best == nil or distance < best.distance)) then
                best = {
                    graph = option.graph,
                    page_id = option.page_id,
                    index = index,
                    distance = distance,
                };
            end
        end
    end
    return best;
end

state.world_local_leg = function (left, right)
    if (left == nil or right == nil or left.graph ~= right.graph) then
        return nil;
    end
    local indices = state.path_find(
        left.graph,
        left.graph_index,
        right.graph_index);
    if (indices == nil) then
        return nil;
    end
    local points = {};
    local distance = 0;
    for position, index in ipairs(indices) do
        local node = left.graph.nodes[index];
        local point = {
            x = node[1],
            y = node[2],
            z = state.path_node_live_z(left.graph, node),
        };
        if (position > 1) then
            local previous = points[#points];
            local delta_x = point.x - previous.x;
            local delta_y = point.y - previous.y;
            local delta_z = (tonumber(point.z) or 0)
                - (tonumber(previous.z) or 0);
            distance = distance + math.sqrt(
                (delta_x * delta_x)
                    + (delta_y * delta_y)
                    + (delta_z * delta_z));
        end
        points[#points + 1] = point;
    end
    return {
        kind = 'walk',
        cost = distance,
        distance = distance,
        points = points,
    };
end

state.world_mask_bit = function (kind, index)
    index = tonumber(index);
    if (index == nil or index < 0) then
        return nil;
    end
    local memory = safe_read(function ()
        return AshitaCore:GetMemoryManager();
    end, nil);
    local player = memory ~= nil and safe_read(function ()
        return memory:GetPlayer();
    end, nil) or nil;
    local masks = player ~= nil and safe_read(function ()
        return player:GetHomepointMasks();
    end, nil) or nil;
    if (masks == nil) then
        return nil;
    end
    local byte_offset = kind == 'survival_guide' and 16 or 0;
    local byte_index = byte_offset + math.floor(index / 8);
    local value = safe_read(function ()
        return tonumber(masks[byte_index + 1]);
    end, nil);
    if (value == nil) then
        value = safe_read(function ()
            local pointer = ffi.cast('const uint8_t*', masks);
            return tonumber(pointer[byte_index]);
        end, nil);
    end
    if (value == nil) then
        return nil;
    end
    return bit.band(value, bit.lshift(1, index % 8)) ~= 0;
end

state.world_static_topology = function ()
    if (state.world_topology ~= nil) then
        return state.world_topology;
    end

    -- Keep world endpoints lightweight until a search reaches their zone.
    -- Snapping every endpoint and precomputing every same-zone pair inside
    -- d3d_present made off-route recalculation stall the render thread.
    local topology = {
        nodes = {},
        adjacency = {},
        by_zone = {},
        travel_nodes = {
            home_point = {},
            survival_guide = {},
        },
        walk_cache = {},
    };
    local function add_node(value)
        local index = #topology.nodes + 1;
        topology.nodes[index] = value;
        topology.adjacency[index] = {};
        topology.by_zone[value.zone_id] =
            topology.by_zone[value.zone_id] or {};
        topology.by_zone[value.zone_id][
            #topology.by_zone[value.zone_id] + 1] = index;
        return index;
    end
    local function add_edge(from_index, to_index, edge)
        edge.to = to_index;
        topology.adjacency[from_index][
            #topology.adjacency[from_index] + 1] = edge;
    end

    for _, connection in ipairs(
            type(state.world_catalog.connections) == 'table'
                and state.world_catalog.connections
                or {}) do
        if (state.path_catalog[connection.from_zone] ~= nil
                and state.path_catalog[connection.to_zone] ~= nil) then
            local from_index = add_node({
                zone_id = connection.from_zone,
                x = connection.from_x,
                y = connection.from_y,
                z = connection.from_z,
                kind = 'zone_line',
                metadata = connection,
            });
            local to_index = add_node({
                zone_id = connection.to_zone,
                x = connection.to_x,
                y = connection.to_y,
                z = connection.to_z,
                kind = 'zone_arrival',
                metadata = connection,
            });
            add_edge(from_index, to_index, {
                kind = 'zone_line',
                cost = 40,
                connection = connection,
            });
        end
    end

    for zone_id, map_definition in pairs(state.maps) do
        if (state.path_catalog[zone_id] ~= nil
                and type(map_definition.travel_references) == 'table') then
            for _, marker in ipairs(map_definition.travel_references) do
                if (topology.travel_nodes[marker.kind] ~= nil) then
                    local index = add_node({
                        zone_id = zone_id,
                        x = marker.x,
                        y = marker.y,
                        z = marker.z,
                        requested_page_id = marker.page_id,
                        kind = marker.kind,
                        metadata = marker,
                    });
                    topology.travel_nodes[marker.kind][
                        #topology.travel_nodes[marker.kind] + 1] = index;
                end
            end
        end
    end

    state.world_topology = topology;
    return topology;
end

state.world_prepare_node = function (node)
    if (node.snap_attempted == true) then
        return node.graph ~= nil;
    end
    node.snap_attempted = true;
    local snap = state.world_snap(
        node.zone_id,
        node.x,
        node.y,
        node.z,
        node.requested_page_id);
    if (snap == nil) then
        return false;
    end
    node.graph = snap.graph;
    node.page_id = snap.page_id;
    node.graph_index = snap.index;
    return true;
end

state.world_route_local_leg = function (
        topology,
        route_walk_cache,
        nodes,
        static_node_count,
        left_index,
        right_index)
    -- Static endpoint pairs survive player-position recalculations. Legs that
    -- touch the moving start or target stay scoped to the current search.
    local cache = left_index <= static_node_count
        and right_index <= static_node_count
        and topology.walk_cache
        or route_walk_cache;
    cache[left_index] = cache[left_index] or {};
    local cached = cache[left_index][right_index];
    if (cached ~= nil) then
        return cached ~= false and cached or nil;
    end

    local left = nodes[left_index];
    local right = nodes[right_index];
    local leg = nil;
    if (state.world_prepare_node(left)
            and state.world_prepare_node(right)
            and left.graph == right.graph) then
        leg = state.world_local_leg(left, right);
    end
    cache[left_index][right_index] = leg or false;
    return leg;
end

state.ensure_world_path = function (player, destination)
    local now = os.clock();
    local cached = state.world_path.route;
    local destination_source = destination.source == 'custom'
        and 'custom'
        or 'guide';
    local same_destination = cached ~= nil
        and cached.start_zone == player.zone_id
        and cached.destination_zone == destination.zone_id
        and cached.destination_page == tonumber(destination.map_id)
        and cached.destination_source == destination_source
        and math.abs(cached.destination_x - destination.x) < 0.1
        and math.abs(cached.destination_y - destination.y) < 0.1
        and ((cached.destination_z == nil and destination.z == nil)
            or (cached.destination_z ~= nil
                and destination.z ~= nil
                and math.abs(cached.destination_z - destination.z) < 0.1));
    if (same_destination) then
        local leg = cached.world_steps[1];
        if (leg ~= nil and leg.kind == 'walk') then
            local projection = state.path_projection(
                cached,
                player.x,
                player.y,
                player.z);
            if (projection ~= nil and projection.distance <= 12) then
                cached.projection = projection;
                return cached;
            end
        elseif (leg ~= nil) then
            return cached;
        end
    end
    if (now - state.world_path.last_attempt < 0.75) then
        return same_destination and cached or nil;
    end
    state.world_path.last_attempt = now;

    local start_snap = state.world_snap(
        player.zone_id,
        player.x,
        player.y,
        player.z,
        nil);
    local target_snap = state.world_snap(
        destination.zone_id,
        destination.x,
        destination.y,
        destination.z,
        destination.map_id);
    if (start_snap == nil or target_snap == nil) then
        state.world_path.route = nil;
        state.world_path.last_error = 'world endpoint outside authored graph';
        return nil;
    end

    local topology = state.world_static_topology();
    local static_node_count = #topology.nodes;
    local nodes = {};
    for index, node in ipairs(topology.nodes) do
        nodes[index] = node;
    end
    local start_index = static_node_count + 1;
    nodes[start_index] = {
        zone_id = player.zone_id,
        x = player.x,
        y = player.y,
        z = player.z,
        graph = start_snap.graph,
        page_id = start_snap.page_id,
        graph_index = start_snap.index,
        kind = 'start',
        snap_attempted = true,
    };
    local target_index = start_index + 1;
    nodes[target_index] = {
        zone_id = destination.zone_id,
        x = destination.x,
        y = destination.y,
        z = destination.z,
        graph = target_snap.graph,
        page_id = target_snap.page_id,
        graph_index = target_snap.index,
        kind = 'target',
        snap_attempted = true,
    };

    local route_walk_cache = {};
    local unlocked = {};
    local function is_unlocked(kind, index)
        local key = string.format('%s:%s', kind, tostring(index));
        if (unlocked[key] == nil) then
            unlocked[key] = state.world_mask_bit(kind, index) == true;
        end
        return unlocked[key];
    end
    local route_zone_indexes = {};
    local function zone_indexes(zone_id)
        if (route_zone_indexes[zone_id] ~= nil) then
            return route_zone_indexes[zone_id];
        end
        local result = {};
        for _, index in ipairs(topology.by_zone[zone_id] or {}) do
            result[#result + 1] = index;
        end
        if nodes[start_index].zone_id == zone_id then
            result[#result + 1] = start_index;
        end
        if nodes[target_index].zone_id == zone_id then
            result[#result + 1] = target_index;
        end
        route_zone_indexes[zone_id] = result;
        return result;
    end

    local respawn_target = nil;
    local memory = safe_read(function ()
        return AshitaCore:GetMemoryManager();
    end, nil);
    local memory_player = memory ~= nil and safe_read(function ()
        return memory:GetPlayer();
    end, nil) or nil;
    local respawn_zone = memory_player ~= nil and tonumber(safe_read(function ()
        return memory_player:GetHomepoint();
    end, nil)) or nil;
    if (respawn_zone ~= nil) then
        local respawn_candidates = {};
        for _, index in ipairs(topology.travel_nodes.home_point) do
            if (nodes[index].zone_id == respawn_zone) then
                respawn_candidates[#respawn_candidates + 1] = index;
            end
        end
        if (state.world_home_point_zone_counts[respawn_zone] == 1
                and #respawn_candidates == 1) then
            respawn_target = respawn_candidates[1];
        end
    end

    local costs = { [start_index] = 0 };
    local previous = {};
    local previous_edge = {};
    local visited = {};
    local function relax(current, current_cost, edge)
        local target = nodes[edge.to];
        if (target == nil or not state.world_prepare_node(target)) then
            return;
        end
        local candidate = current_cost + edge.cost;
        if (costs[edge.to] == nil or candidate < costs[edge.to]) then
            costs[edge.to] = candidate;
            previous[edge.to] = current;
            previous_edge[edge.to] = edge;
        end
    end
    while true do
        local current = nil;
        local current_cost = math.huge;
        for index, cost_value in pairs(costs) do
            if (visited[index] ~= true and cost_value < current_cost) then
                current = index;
                current_cost = cost_value;
            end
        end
        if (current == nil or current == target_index) then
            break;
        end
        visited[current] = true;
        local current_node = nodes[current];
        if (state.world_prepare_node(current_node)) then
            for _, edge in ipairs(topology.adjacency[current] or {}) do
                relax(current, current_cost, edge);
            end
            for _, right_index in ipairs(zone_indexes(current_node.zone_id)) do
                if (right_index ~= current) then
                    local leg = state.world_route_local_leg(
                        topology,
                        route_walk_cache,
                        nodes,
                        static_node_count,
                        current,
                        right_index);
                    if (leg ~= nil) then
                        relax(current, current_cost, {
                            to = right_index,
                            kind = leg.kind,
                            cost = leg.cost,
                            distance = leg.distance,
                            points = leg.points,
                        });
                    end
                end
            end
            local travel_indexes =
                topology.travel_nodes[current_node.kind];
            if (travel_indexes ~= nil) then
                for _, right_index in ipairs(travel_indexes) do
                    if (right_index ~= current) then
                        local marker = nodes[right_index].metadata;
                        local unlock_index = current_node.kind == 'home_point'
                            and marker.unlock_index
                            or marker.unlock_bit;
                        if (is_unlocked(
                                current_node.kind,
                                unlock_index)) then
                            relax(current, current_cost, {
                                to = right_index,
                                kind = current_node.kind,
                                cost = 55,
                                destination_zone =
                                    nodes[right_index].zone_id,
                                destination_name = marker.name,
                            });
                        end
                    end
                end
            end
            if (current == start_index and respawn_target ~= nil) then
                relax(current, current_cost, {
                    to = respawn_target,
                    kind = 'warp',
                    cost = 70,
                    destination_zone = respawn_zone,
                });
            end
        end
    end
    local route_target_index = target_index;
    local partial = false;
    if (costs[target_index] == nil) then
        -- A downstream graph gap should not suppress an already-authored
        -- current-zone handoff. Prefer the reachable arrival in the
        -- destination zone that leaves the smallest remaining straight-line
        -- gap, then rebuild normally after zoning. The destination marker
        -- remains marker-only until a complete local graph is available.
        local best_partial_score = nil;
        for _, index in ipairs(zone_indexes(destination.zone_id)) do
            local node = nodes[index];
            local arrival = previous_edge[index];
            if index ~= target_index
                    and costs[index] ~= nil
                    and node ~= nil
                    and arrival ~= nil
                    and arrival.kind ~= 'walk' then
                local delta_x = node.x - destination.x;
                local delta_y = node.y - destination.y;
                local score = costs[index]
                    + math.sqrt((delta_x * delta_x) + (delta_y * delta_y));
                if best_partial_score == nil or score < best_partial_score then
                    best_partial_score = score;
                    route_target_index = index;
                end
            end
        end
        if best_partial_score == nil then
            state.world_path.route = nil;
            state.world_path.last_error = 'no authored cross-zone handoff';
            return nil;
        end
        partial = true;
    end

    local steps = {};
    local cursor = route_target_index;
    while cursor ~= start_index do
        local edge = previous_edge[cursor];
        local parent = previous[cursor];
        if (edge == nil or parent == nil) then
            state.world_path.route = nil;
            state.world_path.last_error = 'invalid world route reconstruction';
            return nil;
        end
        local step = {};
        for key, value in pairs(edge) do
            step[key] = value;
        end
        step.from_node = nodes[parent];
        step.to_node = nodes[cursor];
        table.insert(steps, 1, step);
        cursor = parent;
    end
    local first = steps[1];
    local points = first ~= nil and first.kind == 'walk'
        and first.points
        or {};
    local route = {
        world = true,
        start_zone = player.zone_id,
        destination_zone = destination.zone_id,
        destination_page = tonumber(destination.map_id),
        destination_x = destination.x,
        destination_y = destination.y,
        destination_z = destination.z,
        destination_source = destination_source,
        world_steps = steps,
        total_cost = costs[route_target_index],
        partial = partial,
        points = points,
    };
    if (#points > 1) then
        route.projection = state.path_projection(
            route,
            player.x,
            player.y,
            player.z);
    end
    state.world_path.route = route;
    state.world_path.last_error = nil;
    return route;
end

state.ensure_guide_path = function (player, map)
    if (state.settings.show_guide_paths ~= true) then
        state.guide_path.route = nil;
        return nil;
    end
    local custom_destination = type(state.custom_waypoint) == 'table'
        and state.custom_waypoint
        or nil;
    local custom_waypoint = state.active_custom_waypoint(player, map);
    local payload = state.active_guide_payload();
    if (custom_destination ~= nil
            and custom_destination.floor_ambiguous == true) then
        state.guide_path.route = nil;
        state.world_path.route = nil;
        return nil;
    end
    if (custom_destination == nil
            and payload ~= nil
            and payload.path_enabled == false) then
        state.guide_path.route = nil;
        state.world_path.route = nil;
        return nil;
    end
    if (custom_destination ~= nil and custom_waypoint == nil) then
        return state.ensure_world_path(player, custom_destination);
    end
    local markers = state.active_guide_markers(player);
    local destination = custom_waypoint
        or (payload ~= nil and payload.markers[1] or nil);
    if (custom_destination == nil
            and payload ~= nil
            and payload.zone_id ~= player.zone_id
            and destination ~= nil) then
        destination.zone_id = payload.zone_id;
        return state.ensure_world_path(player, destination);
    end
    destination = custom_waypoint or markers[1];
    if (destination == nil
            or (destination.map_id ~= nil
                and tonumber(map.page_id) ~= destination.map_id)) then
        state.guide_path.route = nil;
        return nil;
    end

    local graph = state.path_graph_for(player.zone_id, map.page_id);
    if (graph == nil
            or (graph.page_id ~= nil
                and tonumber(map.page_id) ~= tonumber(graph.page_id))) then
        state.guide_path.route = nil;
        return nil;
    end
    local destination_z = tonumber(destination.z);
    if (destination_z == nil) then
        local floor_ambiguous = false;
        destination_z, floor_ambiguous = state.path_waypoint_z(
            graph,
            destination.x,
            destination.y,
            player.x,
            player.y,
            player.z,
            custom_waypoint == nil);
        if (floor_ambiguous) then
            state.guide_path.route = nil;
            state.guide_path.last_error = 'destination floor ambiguous';
            return nil;
        end
    end

    local route = state.guide_path.route;
    local same_destination = route ~= nil
        and route.zone_id == player.zone_id
        and route.page_id == tonumber(map.page_id)
        and route.destination_source == (custom_waypoint ~= nil and 'custom' or 'guide')
        and math.abs(route.destination_x - destination.x) < 0.1
        and math.abs(route.destination_y - destination.y) < 0.1
        and ((route.destination_z == nil and destination_z == nil)
            or (route.destination_z ~= nil
                and destination_z ~= nil
                and math.abs(route.destination_z - destination_z) < 0.1));
    if (same_destination) then
        local projection = state.path_projection(
            route,
            player.x,
            player.y,
            player.z);
        if (projection ~= nil and projection.distance <= 12) then
            route.projection = projection;
            return route;
        end
    end

    local now = os.clock();
    if (now - state.guide_path.last_attempt < 0.5) then
        return same_destination and route or nil;
    end
    state.guide_path.last_attempt = now;

    local start_index, start_distance =
        state.path_nearest_node(graph, player.x, player.y, player.z);
    local target_index, target_distance =
        state.path_nearest_node(
            graph,
            destination.x,
            destination.y,
            destination_z);
    if (start_index == nil or target_index == nil) then
        state.guide_path.route = nil;
        state.guide_path.last_error = string.format(
            'endpoint outside graph (player %.1fy, destination %.1fy)',
            start_distance,
            target_distance);
        return nil;
    end

    local indices = state.path_find(graph, start_index, target_index);
    if (indices == nil) then
        state.guide_path.route = nil;
        state.guide_path.last_error = 'no connected path';
        return nil;
    end
    local points = {};
    for _, index in ipairs(indices) do
        local node = graph.nodes[index];
        points[#points + 1] = {
            x = node[1],
            y = node[2],
            z = state.path_node_live_z(graph, node),
        };
    end
    route = {
        zone_id = player.zone_id,
        page_id = tonumber(map.page_id),
        destination_x = destination.x,
        destination_y = destination.y,
        destination_z = destination_z,
        destination_source = custom_waypoint ~= nil and 'custom' or 'guide',
        points = points,
    };
    route.projection = state.path_projection(
        route,
        player.x,
        player.y,
        player.z);
    state.guide_path.route = route;
    state.guide_path.last_error = nil;
    return route;
end

local function ensure_device()
    if (state.device == nil) then
        state.device = safe_read(function () return d3d8.get_device(); end, nil);
    end
    return state.device;
end

local function texture_for(image)
    if (image == nil or image == '') then
        return nil;
    end
    if (state.textures[image] ~= nil) then
        return state.textures[image] ~= false and state.textures[image] or nil;
    end

    local device = ensure_device();
    if (device == nil) then
        return nil;
    end

    local path = string.format('%s%s', addon.path, image);
    if (not ashita.fs.exists(path)) then
        state.textures[image] = false;
        log('Missing map asset: ' .. path);
        return nil;
    end

    local pointer = ffi.new('IDirect3DTexture8*[1]');
    local result = safe_read(function ()
        return ffi.C.D3DXCreateTextureFromFileA(device, path, pointer);
    end, -1);
    if (result ~= 0 or pointer[0] == nil) then
        state.textures[image] = false;
        log('Could not load map asset: ' .. path);
        return nil;
    end

    local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    local entry = {
        texture = texture,
        handle = tonumber(ffi.cast('uint32_t', texture)),
    };
    state.textures[image] = entry;
    return entry;
end

local function current_player()
    local memory = safe_read(function () return AshitaCore:GetMemoryManager(); end, nil);
    if (memory == nil) then
        return nil;
    end

    local party = safe_read(function () return memory:GetParty(); end, nil);
    local entity = safe_read(function () return memory:GetEntity(); end, nil);
    if (party == nil or entity == nil) then
        return nil;
    end

    local index = tonumber(safe_read(function () return party:GetMemberTargetIndex(0); end, 0)) or 0;
    local player = safe_read(function () return GetPlayerEntity(); end, nil);
    local position = player ~= nil and safe_read(function () return player.Movement.LocalPosition; end, nil) or nil;
    local x = position ~= nil and tonumber(safe_read(function () return position.X; end, nil)) or nil;
    local y = position ~= nil and tonumber(safe_read(function () return position.Y; end, nil)) or nil;
    local z = position ~= nil and tonumber(safe_read(function () return position.Z; end, nil)) or nil;
    local yaw = position ~= nil and tonumber(safe_read(function () return position.Yaw; end, nil)) or nil;

    if (index > 0) then
        x = x or tonumber(safe_read(function () return entity:GetLocalPositionX(index); end, nil));
        y = y or tonumber(safe_read(function () return entity:GetLocalPositionY(index); end, nil));
        z = z or tonumber(safe_read(function () return entity:GetLocalPositionZ(index); end, nil));
        yaw = yaw or tonumber(safe_read(function () return entity:GetLocalPositionYaw(index); end, nil));
        yaw = yaw or tonumber(safe_read(function () return entity:GetHeading(index); end, nil));
    end
    if (x == nil or y == nil or z == nil or yaw == nil) then
        return nil;
    end

    return {
        x = x,
        y = y,
        z = z,
        yaw = yaw,
        index = index,
        zone_id = tonumber(safe_read(function () return party:GetMemberZone(0); end, 0)) or 0,
        entity = entity,
        memory = memory,
    };
end

local function player_is_engaged(player)
    return player ~= nil
        and player.entity ~= nil
        and (tonumber(player.index) or 0) > 0
        and tonumber(safe_read(function ()
            return player.entity:GetStatus(player.index);
        end, 0)) == 1;
end

local letters = {
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z',
};

local STOCK_MINIMAP_SIGNATURE =
    'A1????????F30F104044C3CCCCCCCCCCA1????????F30F10402C';
local STOCK_MAP_TABLE_SIGNATURE =
    '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9';
local STOCK_MAP_SELECTOR_SIGNATURE =
    '8B542408568D4424108BF18B4C2410508B44240C';
local STOCK_MAP_CONTEXT_SIGNATURE =
    '8B7424148B4424108B7C240C8B0D';
local STOCK_MAP_ENTRY_SIZE = 0x0E;
-- LuaJIT interns string declarations passed to ffi.cast. Re-parsing this
-- signature every frame eventually exhausts its ctype table and disables
-- automatic stock-page selection with a "table overflow" error.
local STOCK_MAP_SELECTOR_CTYPE =
    ffi.typeof('int32_t (__thiscall *)(void*, float, float, float)');

local function signed_uint16(value)
    value = tonumber(value);
    if (value == nil) then
        return nil;
    end
    return value >= 0x8000 and (value - 0x10000) or value;
end

local function stock_map_record(zone_id, page_id)
    zone_id = tonumber(zone_id);
    page_id = tonumber(page_id);
    local cache_key = tostring(zone_id) .. ':' .. tostring(page_id);
    local cached = state.stock_map_records[cache_key];
    if (cached ~= nil) then
        return cached;
    end

    local now = os.clock();
    if (state.stock_map_table_address == 0
            and now - state.stock_map_table_checked_at >= 1.0) then
        state.stock_map_table_checked_at = now;
        local signature = tonumber(safe_read(function ()
            return ashita.memory.find(
                'FFXiMain.dll',
                0,
                STOCK_MAP_TABLE_SIGNATURE,
                0,
                0);
        end, 0)) or 0;
        if (signature ~= 0) then
            state.stock_map_table_address = tonumber(safe_read(function ()
                return ashita.memory.read_uint32(signature + 0x1C);
            end, 0)) or 0;
        end
    end

    local table_address = state.stock_map_table_address;
    if (table_address == 0) then
        return nil;
    end
    for index = 0, 999 do
        local entry = table_address + (index * STOCK_MAP_ENTRY_SIZE);
        local entry_zone = tonumber(safe_read(function ()
            return ashita.memory.read_uint16(entry + 0x00);
        end, 0)) or 0;
        local entry_page = tonumber(safe_read(function ()
            return ashita.memory.read_uint8(entry + 0x02);
        end, 0)) or 0;
        if (entry_zone == zone_id and entry_page == page_id) then
            local scale_raw = tonumber(safe_read(function ()
                return ashita.memory.read_uint8(entry + 0x05);
            end, nil));
            local offset_x = signed_uint16(safe_read(function ()
                return ashita.memory.read_uint16(entry + 0x0A);
            end, nil));
            local offset_y = signed_uint16(safe_read(function ()
                return ashita.memory.read_uint16(entry + 0x0C);
            end, nil));
            if (scale_raw ~= nil and offset_x ~= nil and offset_y ~= nil) then
                local record = {
                    scale_raw = scale_raw,
                    offset_x = offset_x,
                    offset_y = offset_y,
                };
                state.stock_map_records[cache_key] = record;
                return record;
            end
            return nil;
        end
    end
    return nil;
end

local function stock_minimap_runtime()
    local now = os.clock();
    if (state.stock_minimap_pointer_address == 0
            and now - state.stock_minimap_checked_at >= 1.0) then
        state.stock_minimap_checked_at = now;
        local signature = tonumber(safe_read(function ()
            return ashita.memory.find(
                'Minimap.dll',
                0,
                STOCK_MINIMAP_SIGNATURE,
                0,
                0);
        end, 0)) or 0;
        if (signature ~= 0) then
            state.stock_minimap_pointer_address = tonumber(safe_read(function ()
                return ashita.memory.read_uint32(signature + 0x01);
            end, 0)) or 0;
        end
    end

    local pointer_address = state.stock_minimap_pointer_address;
    if (pointer_address == 0) then
        return 0;
    end
    return tonumber(safe_read(function ()
        return ashita.memory.read_uint32(pointer_address);
    end, 0)) or 0;
end

local function stock_minimap_info()
    local runtime = stock_minimap_runtime();
    local map_info = runtime ~= 0 and tonumber(safe_read(function ()
        return ashita.memory.read_uint32(runtime + 0x14);
    end, 0)) or 0;
    if (map_info == 0) then
        return nil;
    end
    local page_id = tonumber(safe_read(function ()
        return ashita.memory.read_uint8(map_info + 0x02);
    end, nil));
    local scale_raw = tonumber(safe_read(function ()
        return ashita.memory.read_uint8(map_info + 0x05);
    end, nil));
    local map_x = tonumber(safe_read(function ()
        return ashita.memory.read_double(runtime + 0x18);
    end, nil));
    local map_y = tonumber(safe_read(function ()
        return ashita.memory.read_double(runtime + 0x20);
    end, nil));
    return {
        page_id = page_id,
        scale_raw = scale_raw,
        map_x = map_x,
        map_y = map_y,
    };
end

local function stock_page_id_for_position(player)
    if (player == nil) then
        return nil;
    end
    local x = tonumber(player.x);
    local y = tonumber(player.y);
    local z = tonumber(player.z);
    if (x == nil or y == nil or z == nil) then
        return nil;
    end

    -- The stock plugin resolves its active map through FFXiMain's native
    -- coordinate selector. Its cached map record can lag behind a physical
    -- page boundary (notably Garlaige Citadel's Banishing Gates), so invoke
    -- the same read-only selector for the current position instead. Resolve
    -- it directly from FFXiMain because the stock plugin need not be loaded.
    local now = os.clock();
    if ((state.stock_page_selector_address == 0
                or state.stock_page_context_pointer_address == 0)
            and now - state.stock_page_selector_checked_at >= 1.0) then
        state.stock_page_selector_checked_at = now;
        state.stock_page_selector_address = tonumber(safe_read(function ()
            return ashita.memory.find(
                'FFXiMain.dll',
                0,
                STOCK_MAP_SELECTOR_SIGNATURE,
                0,
                0);
        end, 0)) or 0;
        local context_signature = tonumber(safe_read(function ()
            return ashita.memory.find(
                'FFXiMain.dll',
                0,
                STOCK_MAP_CONTEXT_SIGNATURE,
                0,
                0);
        end, 0)) or 0;
        if (context_signature ~= 0) then
            state.stock_page_context_pointer_address =
                tonumber(safe_read(function ()
                    return ashita.memory.read_uint32(context_signature + 0x0E);
                end, 0)) or 0;
        end
    end
    local selector_address = state.stock_page_selector_address;
    local context_pointer_address = state.stock_page_context_pointer_address;
    local context = context_pointer_address ~= 0 and tonumber(safe_read(function ()
        return ashita.memory.read_uint32(context_pointer_address);
    end, 0)) or 0;
    if (selector_address == 0 or context == 0) then
        return nil, 'native selector or context is unavailable';
    end

    local succeeded, result = pcall(function ()
        local selector = ffi.cast(STOCK_MAP_SELECTOR_CTYPE, selector_address);
        -- FFXiMain's position tuple is ordered X, vertical Z, horizontal Y.
        return selector(ffi.cast('void*', context), x, z, y);
    end);
    if (not succeeded) then
        return nil, 'native selector call failed: ' .. tostring(result);
    end
    local page_id = tonumber(result);
    if (page_id == nil or page_id < 0 or page_id > 255) then
        return nil, 'native selector returned no stock page';
    end
    if (page_id == 0) then
        return nil, nil;
    end
    return math.floor(page_id), nil;
end

local function position_matches_active_stock_page(
        zone_id,
        map,
        position,
        explicit_page,
        cache_position)
    local active_page = type(map) == 'table' and tonumber(map.page_id) or nil;
    explicit_page = tonumber(explicit_page);
    if (explicit_page ~= nil) then
        return active_page == explicit_page;
    end

    local zone = state.vanilla_maps[zone_id];
    if (active_page == nil
            or type(zone) ~= 'table'
            or type(zone.pages) ~= 'table'
            or type(position) ~= 'table') then
        return true;
    end

    local page_count = 0;
    for _ in pairs(zone.pages) do
        page_count = page_count + 1;
        if (page_count > 1) then
            break;
        end
    end
    if (page_count <= 1
            or tonumber(position.x) == nil
            or tonumber(position.y) == nil
            or tonumber(position.z) == nil) then
        return true;
    end

    local cache_key = nil;
    if (cache_position == true) then
        cache_key = string.format(
            '%d:%s:%s:%s',
            tonumber(zone_id) or -1,
            tostring(position.x),
            tostring(position.y),
            tostring(position.z));
    end
    local resolved_page = cache_key ~= nil
        and state.stock_position_pages[cache_key]
        or nil;
    if (resolved_page == nil) then
        resolved_page = stock_page_id_for_position(position);
        if (cache_key ~= nil and resolved_page ~= nil) then
            state.stock_position_pages[cache_key] = resolved_page;
        end
    end
    -- Fail open when the native selector is unavailable or reports no page.
    -- Exact page membership is still preferred whenever FFXiMain provides it.
    return resolved_page == nil or resolved_page == active_page;
end

local function zone_name(zone_id)
    local resources = safe_read(function ()
        return AshitaCore:GetResourceManager();
    end, nil);
    local name = resources ~= nil and safe_read(function ()
        return resources:GetString('zones.names', zone_id);
    end, nil) or nil;
    if (type(name) == 'string' and name ~= '') then
        return name;
    end
    return 'Zone ' .. tostring(zone_id);
end

local function authored_page_for_player(zone_id, player)
    local authored = state.maps[zone_id];
    local rules = type(authored) == 'table' and authored.page_rules or nil;
    if (type(authored) ~= 'table' or player == nil) then
        return nil;
    end
    local player_x = tonumber(player.x);
    local player_y = tonumber(player.y);
    local player_z = tonumber(player.z);
    if (type(rules) == 'table') then
        for _, rule in ipairs(rules) do
            local page_id = tonumber(rule.page_id);
            local matches = page_id ~= nil and player_z ~= nil
                and player_z >= (tonumber(rule.minimum_z) or -math.huge)
                and player_z <= (tonumber(rule.maximum_z) or math.huge)
                and (rule.minimum_x == nil
                    or (player_x ~= nil and player_x >= tonumber(rule.minimum_x)))
                and (rule.maximum_x == nil
                    or (player_x ~= nil and player_x <= tonumber(rule.maximum_x)))
                and (rule.minimum_y == nil
                    or (player_y ~= nil and player_y >= tonumber(rule.minimum_y)))
                and (rule.maximum_y == nil
                    or (player_y ~= nil and player_y <= tonumber(rule.maximum_y)));
            if (matches) then
                return math.floor(page_id);
            end
        end
    end
    local seeds = authored.page_graph_seeds;
    if (type(seeds) ~= 'table'
            or player_x == nil
            or player_y == nil) then
        return nil;
    end
    local graph = state.path_graph_for(zone_id, nil);
    if (graph == nil) then
        return nil;
    end
    local component_ids = state.path_component_ids(graph);
    if (component_ids == nil) then
        return nil;
    end
    if (type(graph._authored_page_ids_by_component) ~= 'table') then
        local pages_by_component = {};
        local conflicts = {};
        for _, seed in ipairs(seeds) do
            local page_id = tonumber(seed.page_id);
            local seed_x = tonumber(seed.x);
            local seed_y = tonumber(seed.y);
            local seed_z = tonumber(seed.z);
            if (page_id ~= nil and seed_x ~= nil and seed_y ~= nil) then
                local node_index = state.path_nearest_node(
                    graph,
                    seed_x,
                    seed_y,
                    seed_z);
                local component_id = node_index ~= nil
                    and component_ids[node_index]
                    or nil;
                if (component_id ~= nil) then
                    page_id = math.floor(page_id);
                    local previous = pages_by_component[component_id];
                    if (previous == nil or previous == page_id) then
                        pages_by_component[component_id] = page_id;
                    else
                        pages_by_component[component_id] = false;
                        conflicts[component_id] = true;
                    end
                end
            end
        end
        for component_id in pairs(conflicts) do
            log(string.format(
                'Conflicting authored map pages for zone %d graph component %d.',
                zone_id,
                component_id));
        end
        graph._authored_page_ids_by_component = pages_by_component;
    end
    local node_index = state.path_nearest_node(
        graph,
        player_x,
        player_y,
        player_z);
    local component_id = node_index ~= nil
        and component_ids[node_index]
        or nil;
    local page_id = component_id ~= nil
        and graph._authored_page_ids_by_component[component_id]
        or nil;
    return tonumber(page_id) ~= nil and math.floor(page_id) or nil;
end

local function fallback_page(
        zone_id,
        player,
        requested_page_id,
        allow_runtime_stock)
    local zone = state.vanilla_maps[zone_id];
    if (type(zone) ~= 'table' or type(zone.pages) ~= 'table') then
        return nil;
    end
    local manual_page = tonumber(requested_page_id)
        or tonumber(state.settings.map_pages[zone_id]);
    local page_id = manual_page;
    local stock = allow_runtime_stock ~= false and stock_minimap_info() or nil;
    local authored = state.maps[zone_id];
    local prefer_authored_page = type(authored) == 'table'
        and authored.prefer_authored_page_selection == true;
    if (page_id == nil and prefer_authored_page) then
        local authored_page = authored_page_for_player(zone_id, player);
        if (authored_page ~= nil and zone.pages[authored_page] ~= nil) then
            page_id = authored_page;
        end
    end
    if (page_id == nil) then
        local native_page, selector_warning = stock_page_id_for_position(player);
        if (state.settings.developer_mode == true
                and selector_warning ~= nil
                and state.stock_page_selector_warning ~= selector_warning) then
            state.stock_page_selector_warning = selector_warning;
            log('Native stock-page selection unavailable: '
                .. selector_warning .. '.');
        end
        if (state.settings.developer_mode == true
                and native_page ~= nil
                and state.stock_page_by_zone[zone_id] ~= native_page) then
            state.stock_page_by_zone[zone_id] = native_page;
            log(string.format(
                'Native stock page for zone %d changed to %d.',
                zone_id,
                native_page));
        end
        if (native_page ~= nil and zone.pages[native_page] ~= nil) then
            page_id = native_page;
        end
    end
    if (page_id == nil) then
        local authored_page = authored_page_for_player(zone_id, player);
        if (authored_page ~= nil and zone.pages[authored_page] ~= nil) then
            page_id = authored_page;
        end
    end
    if (page_id == nil and stock ~= nil
            and zone.pages[tonumber(stock.page_id)] ~= nil) then
        page_id = tonumber(stock.page_id);
    end
    if (page_id == nil or zone.pages[page_id] == nil) then
        page_id = tonumber(zone.default_page);
    end
    if (page_id == nil or zone.pages[page_id] == nil) then
        for candidate in pairs(zone.pages) do
            page_id = tonumber(candidate);
            break;
        end
    end
    local image = page_id ~= nil and zone.pages[page_id] or nil;
    if (type(image) ~= 'string' or image == '') then
        return nil;
    end

    local stock_matches_page = stock ~= nil
        and tonumber(stock.page_id) == page_id;
    local record = stock_map_record(zone_id, page_id);
    local scale_raw = record ~= nil and tonumber(record.scale_raw)
        or (stock_matches_page and tonumber(stock.scale_raw) or nil);
    local has_live_scale = scale_raw ~= nil and scale_raw > 0;
    if (scale_raw == nil or scale_raw <= 0) then
        scale_raw = 4;
    end
    -- Minimap.dll converts world coordinates to source pixels with
    -- (scale_raw / 5), not 32 / (scale_raw * 10). The formulas only agree
    -- when scale_raw is 4, which hid the error on the first maps.
    local image_scale = scale_raw / 5;
    local grid_yalms = 32 / image_scale;
    local record_origin = record ~= nil
        and tonumber(record.offset_x) ~= nil
        and tonumber(record.offset_y) ~= nil;
    local map_x = stock_matches_page and tonumber(stock.map_x) or nil;
    local map_y = stock_matches_page and tonumber(stock.map_y) or nil;
    local has_runtime_origin = player ~= nil
        and map_x ~= nil
        and map_y ~= nil
        and map_x == map_x
        and map_y == map_y
        and math.abs(map_x) < 1000000
        and math.abs(map_y) < 1000000;
    local origin_x = record_origin and -record.offset_x
        or (has_runtime_origin
            and (map_x - ((tonumber(player.x) or 0) * image_scale))
            or 255.0);
    local origin_y = record_origin and -record.offset_y
        or (has_runtime_origin
            and (map_y + ((tonumber(player.y) or 0) * image_scale))
            or 256.0);
    local has_live_origin = record_origin or has_runtime_origin;
    return {
        name = zone_name(zone_id),
        vanilla_image = image,
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        origin_x = origin_x,
        origin_y = origin_y,
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = grid_yalms,
        image_pixels_per_yalm = image_scale,
        page_id = page_id,
        fallback = true,
        live_scale = has_live_scale,
        live_origin = has_live_origin,
        stock_scale_raw = scale_raw,
        stock_offset_x = record ~= nil and record.offset_x or nil,
        stock_offset_y = record ~= nil and record.offset_y or nil,
        stock_record_origin = record_origin,
        waypoint_calibrated = record_origin,
    };
end

local function map_page_key(map)
    local page_id = map ~= nil and tonumber(map.page_id) or nil;
    return page_id ~= nil and math.floor(page_id) or -1;
end

local function saved_origin_adjustment(zone_id, page_key)
    local zones = state.settings.origin_adjustments;
    local pages = type(zones) == 'table' and zones[zone_id] or nil;
    local adjustment = type(pages) == 'table' and pages[page_key] or nil;
    return {
        x = type(adjustment) == 'table' and tonumber(adjustment.x) or 0,
        y = type(adjustment) == 'table' and tonumber(adjustment.y) or 0,
    };
end

local function runtime_origin_adjustment(zone_id, page_key)
    if (state.origin_editor.zone_id == zone_id
            and state.origin_editor.page_key == page_key) then
        return {
            x = tonumber(state.origin_editor.x) or 0,
            y = tonumber(state.origin_editor.y) or 0,
        };
    end
    return saved_origin_adjustment(zone_id, page_key);
end

local function apply_origin_adjustment(map, zone_id)
    if (map == nil) then
        return nil;
    end
    local page_key = map_page_key(map);
    local adjustment = runtime_origin_adjustment(zone_id, page_key);
    map.base_origin_x = tonumber(map.origin_x) or 0;
    map.base_origin_y = tonumber(map.origin_y) or 0;
    map.origin_adjustment_x = adjustment.x;
    map.origin_adjustment_y = adjustment.y;
    map.origin_x = map.base_origin_x + adjustment.x;
    map.origin_y = map.base_origin_y + adjustment.y;
    return map;
end

local function merge_authored_map(zone_id, fallback)
    local authored = state.maps[zone_id];
    if (authored == nil) then
        return apply_origin_adjustment(fallback, zone_id);
    end
    if (fallback == nil) then
        return apply_origin_adjustment(copy_table(authored), zone_id);
    end
    local merged = merge_table(copy_table(fallback), authored);
    if (authored.stock_calibration == true
            and fallback.stock_record_origin == true) then
        merged.origin_x = fallback.origin_x;
        merged.origin_y = fallback.origin_y;
        merged.image_pixels_per_yalm = fallback.image_pixels_per_yalm;
        merged.grid_yalms = fallback.grid_yalms;
        merged.live_origin = fallback.live_origin;
        merged.live_scale = fallback.live_scale;
        merged.stock_scale_raw = fallback.stock_scale_raw;
        merged.stock_offset_x = fallback.stock_offset_x;
        merged.stock_offset_y = fallback.stock_offset_y;
        merged.stock_record_origin = true;
    elseif (authored.origin_x ~= nil or authored.origin_y ~= nil) then
        merged.live_origin = false;
    end
    if (authored.stock_calibration ~= true
            and (authored.image_pixels_per_yalm ~= nil
                or authored.grid_yalms ~= nil)) then
        merged.live_scale = false;
    end
    local page_calibrations = authored.page_calibrations;
    local page_calibration = type(page_calibrations) == 'table'
        and page_calibrations[map_page_key(merged)]
        or nil;
    if (type(page_calibration) == 'table') then
        if (fallback.live_origin ~= true) then
            merged.origin_x = tonumber(page_calibration.origin_x)
                or merged.origin_x;
            merged.origin_y = tonumber(page_calibration.origin_y)
                or merged.origin_y;
            merged.live_origin = false;
        end
        if (fallback.live_scale ~= true) then
            merged.image_pixels_per_yalm =
                tonumber(page_calibration.image_pixels_per_yalm)
                or merged.image_pixels_per_yalm;
            merged.grid_yalms = tonumber(page_calibration.grid_yalms)
                or merged.grid_yalms;
            merged.live_scale = false;
        end
        merged.grid_origin_x = tonumber(page_calibration.grid_origin_x)
            or merged.grid_origin_x;
        merged.grid_origin_y = tonumber(page_calibration.grid_origin_y)
            or merged.grid_origin_y;
    end
    local authored_base_calibration = authored.stock_calibration ~= true
        and tonumber(authored.origin_x) ~= nil
        and tonumber(authored.origin_y) ~= nil
        and (tonumber(authored.image_pixels_per_yalm) ~= nil
            or tonumber(authored.grid_yalms) ~= nil);
    local authored_page_calibration = type(page_calibration) == 'table'
        and tonumber(page_calibration.origin_x) ~= nil
        and tonumber(page_calibration.origin_y) ~= nil
        and (tonumber(page_calibration.image_pixels_per_yalm) ~= nil
            or tonumber(page_calibration.grid_yalms) ~= nil);
    merged.waypoint_calibrated = merged.waypoint_calibrated == true
        or authored_base_calibration
        or authored_page_calibration;
    if (type(authored.structure_pages) == 'table') then
        local page_structure = authored.structure_pages[map_page_key(merged)];
        if (type(page_structure) == 'table') then
            merged.structure_image = nil;
            merged.structure_layers = page_structure;
        else
            merged.structure_image = page_structure;
            merged.structure_layers = nil;
        end
    end
    return apply_origin_adjustment(merged, zone_id);
end

local function map_for_player(player)
    if (player == nil) then
        return nil;
    end
    return merge_authored_map(
        player.zone_id,
        fallback_page(player.zone_id, player, nil, true));
end

local function map_for_catalog_page(zone_id, page_id)
    zone_id = tonumber(zone_id);
    page_id = tonumber(page_id);
    if (zone_id == nil or page_id == nil) then
        return nil;
    end
    return merge_authored_map(
        math.floor(zone_id),
        fallback_page(
            math.floor(zone_id),
            nil,
            math.floor(page_id),
            false));
end

state.apply_mcp_waypoint = function ()
    local request = state.mcp_waypoint.pending;
    if (type(request) ~= 'table') then
        return;
    end
    if (tonumber(request.expires_at) ~= nil
            and os.time() > tonumber(request.expires_at)) then
        state.mcp_waypoint.pending = nil;
        state.write_mcp_waypoint_status(
            request.request_id,
            'expired',
            'The waypoint request expired before player map state became available.',
            nil,
            true);
        return;
    end
    state.mcp_waypoint.pending = nil;

    if (request.action == 'clear') then
        state.custom_waypoint = nil;
        state.guide_path.route = nil;
        state.guide_path.last_attempt = 0;
        state.world_path.route = nil;
        state.world_path.last_attempt = 0;
        state.write_mcp_waypoint_status(
            request.request_id,
            'cleared',
            'The custom waypoint is clear and AshitaGuide routing is restored.',
            nil,
            true);
        log('MCP waypoint cleared; AshitaGuide routing restored.');
        return;
    end

    local source = type(request.waypoint) == 'table'
        and request.waypoint
        or {};
    local zone_id = tonumber(source.zone_id);
    local map_id = tonumber(source.map_id);
    local x = tonumber(source.x);
    local y = tonumber(source.y);
    local z = tonumber(source.z);
    local function finite_coordinate(value)
        return value ~= nil
            and value == value
            and math.abs(value) <= 100000;
    end
    local valid = zone_id ~= nil
        and zone_id >= 0
        and zone_id <= 999
        and zone_id == math.floor(zone_id)
        and finite_coordinate(x)
        and finite_coordinate(y)
        and (map_id == nil
            or (map_id >= 0
                and map_id <= 255
                and map_id == math.floor(map_id)))
        and (z == nil or finite_coordinate(z));
    if (not valid) then
        state.mcp_waypoint.last_error = 'invalid MCP waypoint coordinates';
        state.write_mcp_waypoint_status(
            request.request_id,
            'rejected',
            'The waypoint coordinates or identifiers are outside the supported bounds.',
            nil,
            true);
        return;
    end

    zone_id = math.floor(zone_id);
    map_id = map_id ~= nil and math.floor(map_id) or nil;
    local player = current_player();
    local live_map = player ~= nil and map_for_player(player) or nil;
    if (map_id == nil) then
        if (player == nil or live_map == nil) then
            state.mcp_waypoint.pending = request;
            return;
        end
        if (player.zone_id ~= zone_id) then
            state.mcp_waypoint.last_error = 'remote MCP waypoint missing map id';
            state.write_mcp_waypoint_status(
                request.request_id,
                'rejected',
                'mapId is required when the waypoint is outside the current zone.',
                nil,
                true);
            return;
        end
        map_id = tonumber(live_map.page_id);
    end

    local destination_map = map_for_catalog_page(zone_id, map_id);
    if (destination_map == nil) then
        state.mcp_waypoint.last_error = 'MCP waypoint map unavailable';
        state.write_mcp_waypoint_status(
            request.request_id,
            'rejected',
            'AshitaMiniMap has no map record for the requested zone and mapId.',
            nil,
            true);
        return;
    end
    if ((player == nil or player.zone_id ~= zone_id)
            and destination_map.waypoint_calibrated ~= true) then
        state.mcp_waypoint.last_error = 'remote MCP waypoint map uncalibrated';
        state.write_mcp_waypoint_status(
            request.request_id,
            'rejected',
            'The remote map does not have exact waypoint calibration.',
            nil,
            true);
        return;
    end

    local graph = state.path_graph_for(zone_id, map_id);
    local floor_ambiguous = false;
    if (z == nil) then
        local player_on_destination_page = player ~= nil
            and player.zone_id == zone_id
            and live_map ~= nil
            and tonumber(live_map.page_id) == map_id;
        z, floor_ambiguous = state.path_waypoint_z(
            graph,
            x,
            y,
            player_on_destination_page and player.x or nil,
            player_on_destination_page and player.y or nil,
            player_on_destination_page and player.z or nil,
            not player_on_destination_page);
    end

    state.custom_waypoint = {
        zone_id = zone_id,
        page_id = map_id,
        map_id = map_id,
        x = x,
        y = y,
        z = z,
        floor_ambiguous = floor_ambiguous,
        source = 'custom',
        origin = 'mcp',
    };
    state.guide_path.route = nil;
    state.guide_path.last_attempt = 0;
    state.world_path.route = nil;
    state.world_path.last_attempt = 0;

    local route = player ~= nil and live_map ~= nil
        and state.ensure_guide_path(player, live_map)
        or nil;
    local status = route ~= nil and 'routed' or 'marker_only';
    local reason = floor_ambiguous
        and 'The waypoint is active, but overlapping floors are ambiguous.'
        or route ~= nil
            and 'The waypoint is active with a display-only route.'
            or state.world_path.last_error ~= nil
                and ('The waypoint is active without a route: '
                    .. tostring(state.world_path.last_error) .. '.')
                or state.guide_path.last_error ~= nil
                    and ('The waypoint is active without a route: '
                        .. tostring(state.guide_path.last_error) .. '.')
                    or 'The waypoint is active as a marker; no route is currently available.';
    state.write_mcp_waypoint_status(
        request.request_id,
        status,
        reason,
        state.custom_waypoint,
        true);
    log(string.format(
        'MCP waypoint set at %.1f, %.1f in zone %d page %d (%s).',
        x,
        y,
        zone_id,
        map_id,
        status));
end

local function map_grid_yalms(map)
    return clamp(map ~= nil and map.grid_yalms or 40, 10, 1000);
end

local function map_grid_origin_world(map)
    local width = tonumber(map ~= nil and map.width) or 0;
    local height = tonumber(map ~= nil and map.height) or 0;
    local image_scale = tonumber(map ~= nil and map.image_pixels_per_yalm) or 0;
    if (image_scale <= 0) then
        return 0, 0;
    end
    local origin_x = tonumber(map.origin_x) or (width / 2);
    local origin_y = tonumber(map.origin_y) or (height / 2);
    local grid_origin_x = tonumber(map.grid_origin_x) or origin_x;
    local grid_origin_y = tonumber(map.grid_origin_y) or origin_y;
    return
        (grid_origin_x - origin_x) / image_scale,
        (origin_y - grid_origin_y) / image_scale;
end

local function zoom_minimum_for_map(map, size)
    local image_scale = tonumber(map ~= nil and map.image_pixels_per_yalm) or 0;
    local width = tonumber(map ~= nil and map.width) or 0;
    local height = tonumber(map ~= nil and map.height) or 0;
    if (image_scale <= 0 or width <= 0 or height <= 0) then
        return ZOOM_MIN;
    end

    local bounds = type(map.view_bounds) == 'table' and map.view_bounds or {};
    local left = clamp(bounds.left or 0, 0, width);
    local top = clamp(bounds.top or 0, 0, height);
    local right = clamp(bounds.right or width, left, width);
    local bottom = clamp(bounds.bottom or height, top, height);
    local maximum_span = math.max(right - left, bottom - top);
    if (maximum_span <= 0) then
        return ZOOM_MIN;
    end
    return clamp((size * image_scale) / maximum_span, ZOOM_MIN, ZOOM_MAX);
end

local function grid_coordinate(x, y, map)
    local grid_yalms = map_grid_yalms(map);
    local half_cell = grid_yalms / 2;
    local grid_origin_x, grid_origin_y = map_grid_origin_world(map);
    local local_x = (tonumber(x) or 0) - grid_origin_x;
    local local_y = (tonumber(y) or 0) - grid_origin_y;
    local column = math.floor((local_x + half_cell) / grid_yalms) + 8;
    local row = math.floor((-local_y + half_cell) / grid_yalms) + 8;
    return string.format('%s-%d', letters[column] or '?', row);
end

local function camera_for_map(player, map, size, scale)
    local image_scale = tonumber(map.image_pixels_per_yalm) or 0;
    local width = tonumber(map.width) or 0;
    local height = tonumber(map.height) or 0;
    local bounds = type(map.view_bounds) == 'table' and map.view_bounds or nil;
    if (bounds == nil or image_scale <= 0 or width <= 0 or height <= 0) then
        return { x = player.x, y = player.y };
    end

    local left = clamp(bounds.left, 0, width);
    local top = clamp(bounds.top, 0, height);
    local right = clamp(bounds.right, left, width);
    local bottom = clamp(bounds.bottom, top, height);
    local half_source = ((size / 2) / scale) * image_scale;
    local player_image_x = (tonumber(map.origin_x) or (width / 2)) + (player.x * image_scale);
    local player_image_y = (tonumber(map.origin_y) or (height / 2)) - (player.y * image_scale);

    local function clamp_axis(value, minimum, maximum)
        if ((half_source * 2) >= (maximum - minimum)) then
            return (minimum + maximum) / 2;
        end
        return clamp(value, minimum + half_source, maximum - half_source);
    end

    local image_x = clamp_axis(player_image_x, left, right);
    local image_y = clamp_axis(player_image_y, top, bottom);
    return {
        x = (image_x - (tonumber(map.origin_x) or (width / 2))) / image_scale,
        y = ((tonumber(map.origin_y) or (height / 2)) - image_y) / image_scale,
    };
end

local function draw_grid(draw_list, left, top, size, camera, map, scale)
    if (state.settings.show_grid ~= true) then
        return;
    end

    local viewport_right = left + size;
    local viewport_bottom = top + size;
    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local line_color = color('grid', { 0.48, 0.60, 0.61, 0.25 });
    local text_color = color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    local shadow = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local world_radius = (size / 2) / scale;
    local grid_yalms = map_grid_yalms(map);
    local grid_origin_x, grid_origin_y = map_grid_origin_world(map);
    local image_scale = tonumber(map.image_pixels_per_yalm) or 0;
    local width = tonumber(map.width) or 0;
    local height = tonumber(map.height) or 0;
    local bounds = type(map.view_bounds) == 'table' and map.view_bounds or {};
    local bounds_left = clamp(bounds.left or 0, 0, width);
    local bounds_top = clamp(bounds.top or 0, 0, height);
    local bounds_right = clamp(bounds.right or width, bounds_left, width);
    local bounds_bottom = clamp(bounds.bottom or height, bounds_top, height);
    local camera_image_x = (tonumber(map.origin_x) or (width / 2)) + (camera.x * image_scale);
    local camera_image_y = (tonumber(map.origin_y) or (height / 2)) - (camera.y * image_scale);
    local screen_per_image_pixel = image_scale > 0 and (scale / image_scale) or 0;
    local grid_left = math.max(
        left,
        center_x + ((bounds_left - camera_image_x) * screen_per_image_pixel));
    local grid_top = math.max(
        top,
        center_y + ((bounds_top - camera_image_y) * screen_per_image_pixel));
    local grid_right = math.min(
        viewport_right,
        center_x + ((bounds_right - camera_image_x) * screen_per_image_pixel));
    local grid_bottom = math.min(
        viewport_bottom,
        center_y + ((bounds_bottom - camera_image_y) * screen_per_image_pixel));
    if (grid_right <= grid_left or grid_bottom <= grid_top) then
        return;
    end

    local half_cell = grid_yalms / 2;
    local first_column = math.floor(
        (camera.x - world_radius - grid_origin_x + half_cell) / grid_yalms) + 8;
    local last_column = math.floor(
        (camera.x + world_radius - grid_origin_x + half_cell) / grid_yalms) + 8;
    for column = first_column, last_column do
        local boundary_world_x =
            grid_origin_x + ((column - 8) * grid_yalms) - half_cell;
        local screen_x = center_x + ((boundary_world_x - camera.x) * scale);
        if (screen_x >= grid_left and screen_x <= grid_right) then
            draw_list:AddLine(
                { screen_x, grid_top },
                { screen_x, grid_bottom },
                line_color,
                1.0);
        end

        local cell_center_world_x = grid_origin_x + ((column - 8) * grid_yalms);
        local label_x = center_x + ((cell_center_world_x - camera.x) * scale);
        local label = letters[column];
        if (label ~= nil and label_x >= grid_left + 9 and label_x <= grid_right - 9) then
            draw_list:AddText({ label_x - 3, grid_top + 4 }, shadow, label);
            draw_list:AddText({ label_x - 4, grid_top + 3 }, text_color, label);
        end
    end

    local first_row = math.floor(
        (-(camera.y + world_radius - grid_origin_y) + half_cell) / grid_yalms) + 8;
    local last_row = math.floor(
        (-(camera.y - world_radius - grid_origin_y) + half_cell) / grid_yalms) + 8;
    for row = first_row, last_row do
        local boundary_world_y =
            grid_origin_y + half_cell - ((row - 8) * grid_yalms);
        local screen_y = center_y - ((boundary_world_y - camera.y) * scale);
        if (screen_y >= grid_top and screen_y <= grid_bottom) then
            draw_list:AddLine(
                { grid_left, screen_y },
                { grid_right, screen_y },
                line_color,
                1.0);
        end

        local cell_center_world_y = grid_origin_y - ((row - 8) * grid_yalms);
        local label_y = center_y - ((cell_center_world_y - camera.y) * scale);
        if (row >= 1 and row <= 16
                and label_y >= grid_top + 9 and label_y <= grid_bottom - 9) then
            local label = tostring(row);
            draw_list:AddText({ grid_left + 5, label_y - 6 }, shadow, label);
            draw_list:AddText({ grid_left + 4, label_y - 7 }, text_color, label);
        end
    end
end

local function current_target_index(memory)
    local target = memory ~= nil and safe_read(function () return memory:GetTarget(); end, nil) or nil;
    if (target == nil) then
        return 0;
    end
    local primary = tonumber(safe_read(function () return target:GetTargetIndex(0); end, 0)) or 0;
    local sub = tonumber(safe_read(function () return target:GetTargetIndex(1); end, 0)) or 0;
    local sub_active = safe_read(function () return target:GetIsSubTargetActive(); end, false) == true;
    return sub_active and sub or primary;
end

local function widescan_target_position()
    return state.widescan_target;
end

local function draw_widescan_target(
        draw_list,
        left,
        top,
        size,
        player,
        camera,
        map,
        scale,
        visual_scale)
    if (state.settings.show_widescan_target ~= true) then
        return;
    end
    local tracked = widescan_target_position();
    if (tracked == nil) then
        return;
    end
    local same_floor = tracked.z == nil
        or player.z == nil
        or math.abs(tracked.z - player.z) <= ENTITY_FLOOR_TOLERANCE;
    if (not same_floor
            or not position_matches_active_stock_page(player.zone_id, map, tracked)) then
        return;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local screen_x = center_x + ((tracked.x - camera.x) * scale);
    local screen_y = center_y - ((tracked.y - camera.y) * scale);
    local margin = math.max(12, 11 * visual_scale);
    local marker_x = clamp(screen_x, left + margin, left + size - margin);
    local marker_y = clamp(screen_y, top + margin, top + size - margin);
    local offscreen = marker_x ~= screen_x or marker_y ~= screen_y;
    local marker_color = color(
        'widescan_target',
        { 0.82, 0.48, 1.00, 1.00 });
    local shadow = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local radius = (offscreen and 9.0 or 8.0) * visual_scale;
    local line_width = math.max(1.5, 1.8 * visual_scale);

    draw_list:AddCircleFilled(
        { marker_x, marker_y },
        3.2 * visual_scale,
        shadow,
        16);
    draw_list:AddCircleFilled(
        { marker_x, marker_y },
        2.0 * visual_scale,
        marker_color,
        16);
    draw_list:AddCircle(
        { marker_x, marker_y },
        radius,
        shadow,
        20,
        math.max(3.0, 3.0 * visual_scale));
    draw_list:AddCircle(
        { marker_x, marker_y },
        radius,
        marker_color,
        20,
        line_width);
    draw_list:AddLine(
        { marker_x - (radius + 3), marker_y },
        { marker_x - (radius - 2), marker_y },
        marker_color,
        line_width);
    draw_list:AddLine(
        { marker_x + (radius - 2), marker_y },
        { marker_x + (radius + 3), marker_y },
        marker_color,
        line_width);
    draw_list:AddLine(
        { marker_x, marker_y - (radius + 3) },
        { marker_x, marker_y - (radius - 2) },
        marker_color,
        line_width);
    draw_list:AddLine(
        { marker_x, marker_y + (radius - 2) },
        { marker_x, marker_y + (radius + 3) },
        marker_color,
        line_width);
end

local function entity_kind(entity, index)
    local spawn_flags = tonumber(safe_read(function () return entity:GetSpawnFlags(index); end, 0)) or 0;
    local entity_type = tonumber(safe_read(function () return entity:GetType(index); end, -1)) or -1;
    if (bit.band(spawn_flags, 0x10) == 0x10) then
        return 'monster';
    end
    if (entity_type == 0 or bit.band(spawn_flags, 0x01) == 0x01) then
        return 'player';
    end
    return 'npc';
end

local function marker_zoom_scale(world_scale)
    if (state.settings.scale_markers_with_zoom ~= true) then
        return 1.0;
    end
    return clamp(world_scale / MARKER_REFERENCE_ZOOM, 0.50, 2.50);
end

local function draw_entities(
        draw_list,
        left,
        top,
        size,
        player,
        camera,
        map,
        scale,
        visual_scale)
    local entity = player.entity;
    local count = math.min(tonumber(safe_read(function () return entity:GetEntityMapSize(); end, 0)) or 0, 0x8FF);
    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local target_index = current_target_index(player.memory);
    local shadow = color('shadow', { 0.01, 0.02, 0.025, 0.94 });

    for index = 0, count - 1 do
        if (index ~= player.index) then
            local render_flags = tonumber(safe_read(function () return entity:GetRenderFlags0(index); end, 0)) or 0;
            if (bit.band(render_flags, 0x200) == 0x200 and bit.band(render_flags, 0x4000) == 0) then
                local x = tonumber(safe_read(function () return entity:GetLocalPositionX(index); end, nil));
                local y = tonumber(safe_read(function () return entity:GetLocalPositionY(index); end, nil));
                local z = tonumber(safe_read(function () return entity:GetLocalPositionZ(index); end, nil));
                local same_floor = z ~= nil
                    and math.abs(z - player.z) <= ENTITY_FLOOR_TOLERANCE;
                local same_page = position_matches_active_stock_page(
                    player.zone_id,
                    map,
                    { x = x, y = y, z = z });
                if (x ~= nil and y ~= nil and same_floor and same_page) then
                    local kind = entity_kind(entity, index);
                    local enabled = (kind == 'player' and state.settings.show_players == true)
                        or (kind == 'npc' and state.settings.show_npcs == true)
                        or (kind == 'monster' and state.settings.show_monsters == true);
                    local screen_x = center_x + ((x - camera.x) * scale);
                    local screen_y = center_y - ((y - camera.y) * scale);
                    if (enabled and screen_x >= left + 3 and screen_x <= left + size - 3
                            and screen_y >= top + 3 and screen_y <= top + size - 3) then
                        local dot_color = color(kind == 'player' and 'other_player' or kind,
                            { 0.88, 0.82, 0.62, 0.90 });
                        draw_list:AddCircleFilled(
                            { screen_x, screen_y },
                            6.0 * visual_scale,
                            shadow,
                            16);
                        draw_list:AddCircleFilled(
                            { screen_x, screen_y },
                            4.5 * visual_scale,
                            dot_color,
                            16);
                        if (index == target_index) then
                            draw_list:AddCircle(
                                { screen_x, screen_y },
                                7.0 * visual_scale,
                                color('target', { 1.00, 0.71, 0.20, 1.00 }),
                                20,
                                math.max(1.0, 2.0 * visual_scale));
                        end
                    end
                end
            end
        end
    end
end

local function floor_layer_matches_z(layer, z)
    if (type(layer) ~= 'table' or z == nil) then
        return false, false;
    end

    local minimum_z = tonumber(layer.minimum_player_z);
    local maximum_z = tonumber(layer.maximum_player_z);
    if (minimum_z == nil and maximum_z == nil) then
        return false, false;
    end

    return true,
        (minimum_z == nil or z >= minimum_z)
        and (maximum_z == nil or z <= maximum_z);
end

local function shares_authored_floor(map, player_z, marker_z)
    if (not STRUCTURE_RENDERING_ENABLED) then
        player_z = tonumber(player_z);
        marker_z = tonumber(marker_z);
        return player_z == nil
            or marker_z == nil
            or math.abs(player_z - marker_z) <= ENTITY_FLOOR_TOLERANCE;
    end
    player_z = tonumber(player_z);
    marker_z = tonumber(marker_z);
    local layers = type(map) == 'table' and map.structure_layers or nil;
    if (player_z == nil or marker_z == nil or type(layers) ~= 'table') then
        return true;
    end

    local player_has_floor = false;
    local marker_has_floor = false;
    for _, layer in ipairs(layers) do
        local is_bounded, player_matches = floor_layer_matches_z(
            layer,
            player_z);
        local _, marker_matches = floor_layer_matches_z(layer, marker_z);
        if (is_bounded) then
            player_has_floor = player_has_floor or player_matches;
            marker_has_floor = marker_has_floor or marker_matches;
            if (player_matches and marker_matches) then
                return true;
            end
        end
    end

    -- Only dim a marker when both elevations map unambiguously to authored
    -- floor bands. Unknown elevations remain fully visible rather than
    -- implying a floor relationship the map does not prove.
    return not (player_has_floor and marker_has_floor);
end

local function draw_treasure_spawns(
        draw_list,
        left,
        top,
        size,
        camera,
        map,
        scale,
        player_z,
        zone_id)
    local marker_sets = {
        {
            markers = map.treasure_spawns,
            default_kind = nil,
        },
        {
            markers = map.coffer_spawns,
            default_kind = 'coffer',
        },
    };
    if (state.settings.show_coffer_spawns ~= true
            or (type(map.treasure_spawns) ~= 'table'
                and type(map.coffer_spawns) ~= 'table')) then
        return;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    for _, marker_set in ipairs(marker_sets) do
        for _, marker in ipairs(
                type(marker_set.markers) == 'table'
                    and marker_set.markers
                    or {}) do
        local marker_page = type(marker) == 'table'
            and tonumber(marker.page_id)
            or nil;
        local marker_kind = type(marker) == 'table'
            and marker.kind
            or nil;
        marker_kind = marker_kind or marker_set.default_kind;
        local x = type(marker) == 'table' and tonumber(marker.x) or nil;
        local y = type(marker) == 'table' and tonumber(marker.y) or nil;
        if ((marker_kind == 'chest' or marker_kind == 'coffer')
                and x ~= nil and y ~= nil
                and position_matches_active_stock_page(
                    zone_id,
                    map,
                    marker,
                    marker_page,
                    true)) then
            local screen_x = center_x + ((x - camera.x) * scale);
            local screen_y = center_y - ((y - camera.y) * scale);
            if (screen_x >= left + 8 and screen_x <= left + size - 8
                    and screen_y >= top + 7 and screen_y <= top + size - 7) then
                local marker_opacity = shares_authored_floor(
                    map,
                    player_z,
                    marker.z)
                    and 1
                    or state.settings.inactive_floor_opacity;
                local shadow = color_with_opacity(
                    'shadow',
                    { 0.01, 0.02, 0.025, 0.94 },
                    marker_opacity);
                local marker_color = color_with_opacity(
                    marker_kind == 'chest'
                        and 'chest_spawn'
                        or 'coffer_spawn',
                    marker_kind == 'chest'
                        and { 0.545, 0.306, 0.145, 0.98 }
                        or { 1.000, 0.820, 0.200, 0.98 },
                    marker_opacity);
                if (marker_kind == 'chest') then
                    -- Wooden plank chest: square lid, crossed front boards,
                    -- and a small gold latch. This must remain visibly
                    -- different from the rounded gold coffer silhouette.
                    draw_list:AddRectFilled(
                        { screen_x - 9, screen_y - 7 },
                        { screen_x + 9, screen_y + 7 },
                        shadow,
                        1.0);
                    draw_list:AddRectFilled(
                        { screen_x - 8, screen_y - 6 },
                        { screen_x + 8, screen_y + 6 },
                        marker_color,
                        0.5);
                    draw_list:AddLine(
                        { screen_x - 8, screen_y - 1 },
                        { screen_x + 8, screen_y - 1 },
                        shadow,
                        2.0);
                    draw_list:AddLine(
                        { screen_x - 6, screen_y },
                        { screen_x + 5, screen_y + 6 },
                        shadow,
                        1.5);
                    draw_list:AddLine(
                        { screen_x + 6, screen_y },
                        { screen_x - 5, screen_y + 6 },
                        shadow,
                        1.5);
                    draw_list:AddRectFilled(
                        { screen_x - 2, screen_y - 2 },
                        { screen_x + 2, screen_y + 2 },
                        color_with_opacity(
                            'coffer_spawn',
                            { 1.000, 0.820, 0.200, 0.98 },
                            marker_opacity),
                        0.5);
                else
                    -- Rounded gold coffer silhouette.
                    draw_list:AddRectFilled(
                        { screen_x - 8, screen_y - 7 },
                        { screen_x + 8, screen_y + 1 },
                        shadow,
                        3.0);
                    draw_list:AddRectFilled(
                        { screen_x - 8, screen_y - 1 },
                        { screen_x + 8, screen_y + 7 },
                        shadow,
                        1.5);
                    draw_list:AddRectFilled(
                        { screen_x - 7, screen_y - 6 },
                        { screen_x + 7, screen_y },
                        marker_color,
                        2.5);
                    draw_list:AddRectFilled(
                        { screen_x - 7, screen_y - 0.5 },
                        { screen_x + 7, screen_y + 6 },
                        marker_color,
                        1.0);
                    draw_list:AddRectFilled(
                        { screen_x - 7, screen_y - 1 },
                        { screen_x + 7, screen_y + 1 },
                        shadow);
                    draw_list:AddRectFilled(
                        { screen_x - 2, screen_y - 2 },
                        { screen_x + 2, screen_y + 3 },
                        shadow,
                        0.8);
                    draw_list:AddCircleFilled(
                        { screen_x, screen_y + 0.5 },
                        0.9,
                        marker_color,
                        8);
                end
            end
        end
        end
    end
end

local function draw_travel_references(
        draw_list,
        left,
        top,
        size,
        camera,
        map,
        scale,
        player_z,
        zone_id)
    if (state.settings.show_travel_references ~= true
            or type(map.travel_references) ~= 'table') then
        return;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local player = safe_read(function ()
        return AshitaCore:GetMemoryManager():GetPlayer();
    end, nil);
    local travel_masks = player ~= nil and safe_read(function ()
        return player:GetHomepointMasks();
    end, nil) or nil;

    local function read_mask_byte(byte_index)
        if (travel_masks == nil or byte_index == nil) then
            return nil;
        end
        local direct = safe_read(function ()
            return tonumber(travel_masks[byte_index + 1]);
        end, nil);
        if (direct ~= nil) then
            return direct;
        end
        return safe_read(function ()
            local pointer = ffi.cast('const uint8_t*', travel_masks);
            return tonumber(pointer[byte_index]);
        end, nil);
    end

    local function is_unlocked(marker, kind)
        local bit_index = kind == 'home_point'
            and tonumber(marker.unlock_index)
            or tonumber(marker.unlock_bit);
        if (bit_index == nil) then
            return nil;
        end
        local byte_offset = kind == 'survival_guide' and 16 or 0;
        local value = read_mask_byte(
            byte_offset + math.floor(bit_index / 8));
        if (value == nil) then
            return nil;
        end
        return bit.band(
            value,
            bit.lshift(1, bit_index % 8)) ~= 0;
    end

    local function draw_home_point_icon(
            screen_x,
            screen_y,
            crystal,
            shine,
            shadow,
            icon_scale)
        local s = icon_scale or 1;
        draw_list:AddTriangleFilled(
            { screen_x, screen_y - (10 * s) },
            { screen_x - (8 * s), screen_y + (2 * s) },
            { screen_x + (8 * s), screen_y + (2 * s) },
            shadow);
        draw_list:AddTriangleFilled(
            { screen_x - (8 * s), screen_y + (1 * s) },
            { screen_x, screen_y + (10 * s) },
            { screen_x + (8 * s), screen_y + (1 * s) },
            shadow);
        draw_list:AddTriangleFilled(
            { screen_x, screen_y - (8 * s) },
            { screen_x - (6 * s), screen_y + (1 * s) },
            { screen_x + (6 * s), screen_y + (1 * s) },
            crystal);
        draw_list:AddTriangleFilled(
            { screen_x - (6 * s), screen_y + (1 * s) },
            { screen_x, screen_y + (8 * s) },
            { screen_x + (6 * s), screen_y + (1 * s) },
            crystal);
        draw_list:AddTriangleFilled(
            { screen_x, screen_y - (7 * s) },
            { screen_x - (4 * s), screen_y },
            { screen_x, screen_y + (6 * s) },
            shine);
    end

    local function draw_survival_guide_icon(
            screen_x,
            screen_y,
            cover,
            page,
            shadow,
            icon_scale)
        local s = icon_scale or 1;
        draw_list:AddRectFilled(
            { screen_x - (10 * s), screen_y - (7 * s) },
            { screen_x + (10 * s), screen_y + (8 * s) },
            shadow,
            2.0 * s);
        draw_list:AddRectFilled(
            { screen_x - (9 * s), screen_y - (6 * s) },
            { screen_x + (9 * s), screen_y + (7 * s) },
            cover,
            1.5 * s);
        draw_list:AddTriangleFilled(
            { screen_x - (7 * s), screen_y - (5 * s) },
            { screen_x - (1 * s), screen_y - (3 * s) },
            { screen_x - (1 * s), screen_y + (6 * s) },
            page);
        draw_list:AddTriangleFilled(
            { screen_x + (7 * s), screen_y - (5 * s) },
            { screen_x + (1 * s), screen_y - (3 * s) },
            { screen_x + (1 * s), screen_y + (6 * s) },
            page);
        draw_list:AddLine(
            { screen_x, screen_y - (3 * s) },
            { screen_x, screen_y + (6 * s) },
            shadow,
            1.5 * s);
    end

    for _, marker in ipairs(map.travel_references) do
        local kind = type(marker) == 'table' and marker.kind or nil;
        local marker_page = type(marker) == 'table'
            and tonumber(marker.page_id)
            or nil;
        local x = type(marker) == 'table' and tonumber(marker.x) or nil;
        local y = type(marker) == 'table' and tonumber(marker.y) or nil;
        if ((kind == 'home_point' or kind == 'survival_guide')
                and x ~= nil and y ~= nil
                and position_matches_active_stock_page(
                    zone_id,
                    map,
                    marker,
                    marker_page,
                    true)) then
            local screen_x = center_x + ((x - camera.x) * scale);
            local screen_y = center_y - ((y - camera.y) * scale);
            if (screen_x >= left + 9 and screen_x <= left + size - 9
                    and screen_y >= top + 9
                    and screen_y <= top + size - 9) then
                local marker_opacity = shares_authored_floor(
                    map,
                    player_z,
                    marker.z)
                    and 1
                    or state.settings.inactive_floor_opacity;
                local shadow = color_with_opacity(
                    'shadow',
                    { 0.01, 0.02, 0.025, 0.94 },
                    marker_opacity);
                local unlocked = is_unlocked(marker, kind);
                local pulse = 0.5 + (0.5 * math.sin(os.clock() * 4.5));
                local glow = nil;
                if (unlocked == false) then
                    glow = kind == 'home_point'
                        and imgui.GetColorU32({
                            0.310,
                            0.900,
                            1.000,
                            (0.16 + (pulse * 0.24)) * marker_opacity,
                        })
                        or imgui.GetColorU32({
                            0.940,
                            0.720,
                            0.300,
                            (0.16 + (pulse * 0.24)) * marker_opacity,
                        });
                end
                if (kind == 'home_point') then
                    local crystal = color_with_opacity(
                        'home_point',
                        { 0.310, 0.900, 1.000, 0.98 },
                        marker_opacity);
                    local shine = imgui.GetColorU32({
                        0.84,
                        0.98,
                        1.00,
                        0.95 * marker_opacity,
                    });
                    -- Draw the same crystal silhouette larger and translucent
                    -- behind locked Home Points so they read as collectible.
                    if (glow ~= nil) then
                        draw_home_point_icon(
                            screen_x,
                            screen_y,
                            glow,
                            glow,
                            glow,
                            1.25 + (pulse * 0.18));
                    end
                    draw_home_point_icon(
                        screen_x,
                        screen_y,
                        crystal,
                        shine,
                        shadow,
                        1);
                else
                    local cover = color_with_opacity(
                        'survival_guide',
                        { 0.690, 0.420, 0.180, 0.98 },
                        marker_opacity);
                    local page = imgui.GetColorU32({
                        0.94,
                        0.83,
                        0.58,
                        0.98 * marker_opacity,
                    });
                    -- Locked books pulse as a larger copy of the same icon.
                    if (glow ~= nil) then
                        draw_survival_guide_icon(
                            screen_x,
                            screen_y,
                            glow,
                            glow,
                            glow,
                            1.18 + (pulse * 0.15));
                    end
                    draw_survival_guide_icon(
                        screen_x,
                        screen_y,
                        cover,
                        page,
                        shadow,
                        1);
                end
            end
        end
    end
end

local function draw_nm_spawn_range_card(
        draw_list,
        left,
        top,
        size,
        anchor_x,
        anchor_y,
        reference,
        opacity)
    local width = 236;
    local height = 82;
    local card_left = clamp(anchor_x + 14, left + 8, left + size - width - 8);
    local card_top = clamp(anchor_y - (height / 2), top + 38, top + size - height - 8);
    local card_right = card_left + width;
    local card_bottom = card_top + height;
    local background = color_with_opacity(
        'badge',
        { 0.025, 0.055, 0.070, 0.88 },
        opacity);
    local border = color_with_opacity(
        'nm_spawn_border',
        { 0.890, 0.660, 0.260, 0.78 },
        opacity);
    local heading = color_with_opacity(
        'grid_text',
        { 0.82, 0.71, 0.51, 0.88 },
        opacity);
    local body = color_with_opacity(
        'text',
        { 0.86, 0.90, 0.88, 0.92 },
        opacity);
    local muted = color_with_opacity(
        'grid_text',
        { 0.82, 0.71, 0.51, 0.88 },
        opacity * 0.75);
    local points = type(reference.points) == 'table'
        and #reference.points
        or 0;
    local placeholders = tonumber(reference.placeholder_count) or 0;
    local floor = tostring(reference.floor or 'UNKNOWN');
    local spawn_type = tostring(reference.spawn_type or 'Spawn');
    local level = tostring(reference.level or '?');

    draw_list:AddRectFilled(
        { card_left, card_top },
        { card_right, card_bottom },
        background,
        4.0);
    draw_list:AddRect(
        { card_left, card_top },
        { card_right, card_bottom },
        border,
        4.0,
        0,
        1.0);
    draw_list:AddText(
        { card_left + 10, card_top + 7 },
        heading,
        string.upper(tostring(reference.name or 'NM')));
    draw_list:AddText(
        { card_left + 10, card_top + 24 },
        body,
        string.format(
            'Static spawn range  |  %d starts / %d PHs',
            points,
            placeholders));
    draw_list:AddText(
        { card_left + 10, card_top + 41 },
        body,
        string.format('%s  |  Lv. %s  |  %s floor', spawn_type, level, floor));
    draw_list:AddText(
        { card_left + 10, card_top + 58 },
        muted,
        'Reference only - no live tracking');
end

state.nm_blob_hull = function (points)
    local sorted = {};
    for _, point in ipairs(points or {}) do
        if (type(point) == 'table'
                and tonumber(point.x) ~= nil
                and tonumber(point.y) ~= nil) then
            sorted[#sorted + 1] = { x = tonumber(point.x), y = tonumber(point.y) };
        end
    end
    table.sort(sorted, function (a, b)
        return a.x < b.x or (a.x == b.x and a.y < b.y);
    end);
    if (#sorted <= 2) then
        return sorted;
    end
    local function cross(origin, a, b)
        return ((a.x - origin.x) * (b.y - origin.y))
            - ((a.y - origin.y) * (b.x - origin.x));
    end
    local lower = {};
    for _, point in ipairs(sorted) do
        while (#lower >= 2
                and cross(lower[#lower - 1], lower[#lower], point) <= 0) do
            table.remove(lower);
        end
        lower[#lower + 1] = point;
    end
    local upper = {};
    for index = #sorted, 1, -1 do
        local point = sorted[index];
        while (#upper >= 2
                and cross(upper[#upper - 1], upper[#upper], point) <= 0) do
            table.remove(upper);
        end
        upper[#upper + 1] = point;
    end
    table.remove(lower);
    table.remove(upper);
    for _, point in ipairs(upper) do
        lower[#lower + 1] = point;
    end
    return lower;
end

state.draw_nm_spawn_blob = function (
        draw_list,
        reference,
        center_x,
        center_y,
        camera,
        scale,
        fill,
        border,
        mouse_x,
        mouse_y)
    local hull = state.nm_blob_hull(reference.points);
    if (#hull < 3) then
        return nil;
    end
    local centroid_x = 0;
    local centroid_y = 0;
    for _, point in ipairs(hull) do
        centroid_x = centroid_x + point.x;
        centroid_y = centroid_y + point.y;
    end
    centroid_x = centroid_x / #hull;
    centroid_y = centroid_y / #hull;
    local padding = tonumber(reference.blob_padding_yalms) or 8;
    local screen_points = {};
    for _, point in ipairs(hull) do
        local offset_x = point.x - centroid_x;
        local offset_y = point.y - centroid_y;
        local length = math.sqrt((offset_x * offset_x) + (offset_y * offset_y));
        local expansion = length > 0 and padding / length or 0;
        local expanded_x = point.x + (offset_x * expansion);
        local expanded_y = point.y + (offset_y * expansion);
        screen_points[#screen_points + 1] = {
            center_x + ((expanded_x - camera.x) * scale),
            center_y - ((expanded_y - camera.y) * scale),
        };
    end
    local screen_centroid = { 0, 0 };
    for _, point in ipairs(screen_points) do
        screen_centroid[1] = screen_centroid[1] + point[1];
        screen_centroid[2] = screen_centroid[2] + point[2];
    end
    screen_centroid[1] = screen_centroid[1] / #screen_points;
    screen_centroid[2] = screen_centroid[2] / #screen_points;
    for index, point in ipairs(screen_points) do
        local next_point = screen_points[(index % #screen_points) + 1];
        draw_list:AddTriangleFilled(screen_centroid, point, next_point, fill);
        draw_list:AddLine(point, next_point, border, 2.0);
    end
    local inside = false;
    local previous = #screen_points;
    for index, point in ipairs(screen_points) do
        local other = screen_points[previous];
        if (((point[2] > mouse_y) ~= (other[2] > mouse_y))
                and mouse_x < ((other[1] - point[1])
                    * (mouse_y - point[2])
                    / (other[2] - point[2])
                    + point[1])) then
            inside = not inside;
        end
        previous = index;
    end
    return inside and screen_centroid or nil;
end

local function draw_nm_spawn_ranges(
        draw_list,
        left,
        top,
        size,
        camera,
        map,
        scale,
        player,
        visible,
        apply_hunt_filter)
    if (visible ~= true or type(map.nm_spawn_ranges) ~= 'table') then
        return;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local mouse_x, mouse_y = imgui.GetMousePos();
    for _, reference in ipairs(map.nm_spawn_ranges) do
        local reference_page = type(reference) == 'table'
            and tonumber(reference.page_id)
            or nil;
        local points = type(reference) == 'table'
            and reference.points
            or nil;
        local first_point = type(points) == 'table' and points[1] or nil;
        local reference_position = {
            x = type(first_point) == 'table' and first_point.x or nil,
            y = type(first_point) == 'table' and first_point.y or nil,
            z = type(reference) == 'table' and reference.z or nil,
        };
        if (type(points) == 'table'
                and (apply_hunt_filter ~= true
                    or state.nm_hunt_reference_visible(player, reference))
                and position_matches_active_stock_page(
                    player.zone_id,
                    map,
                    reference_position,
                    reference_page,
                    true)) then
            local floor_opacity = shares_authored_floor(
                map,
                player.z,
                reference.z)
                and 1
                or state.settings.inactive_floor_opacity;
            local fill = color_with_opacity(
                'nm_spawn_range',
                { 0.820, 0.080, 0.130, 0.280 },
                floor_opacity);
            local border = color_with_opacity(
                'nm_spawn_border',
                { 1.000, 0.300, 0.340, 0.900 },
                floor_opacity);
            local radius = clamp(
                (tonumber(reference.radius_yalms) or 4.5) * scale,
                5.0,
                18.0);
            local hovered = false;
            local hover_x = nil;
            local hover_y = nil;
            if (reference.render_mode == 'blob') then
                local blob_hover = state.draw_nm_spawn_blob(
                    draw_list,
                    reference,
                    center_x,
                    center_y,
                    camera,
                    scale,
                    fill,
                    border,
                    mouse_x,
                    mouse_y);
                if (blob_hover ~= nil) then
                    hovered = true;
                    hover_x = blob_hover[1];
                    hover_y = blob_hover[2];
                end
            else
            for _, point in ipairs(points) do
                local x = type(point) == 'table' and tonumber(point.x) or nil;
                local y = type(point) == 'table' and tonumber(point.y) or nil;
                if (x ~= nil and y ~= nil) then
                    local screen_x = center_x + ((x - camera.x) * scale);
                    local screen_y = center_y - ((y - camera.y) * scale);
                    if (screen_x >= left - radius
                            and screen_x <= left + size + radius
                            and screen_y >= top - radius
                            and screen_y <= top + size + radius) then
                        -- Overlapping translucent discs turn the verified
                        -- initial-spawn points into one readable range veil.
                        -- No disc represents Amemet's current position.
                        draw_list:AddCircleFilled(
                            { screen_x, screen_y },
                            radius,
                            fill,
                            20);
                        draw_list:AddCircle(
                            { screen_x, screen_y },
                            radius,
                            border,
                            20,
                            1.5);
                        local dx = mouse_x - screen_x;
                        local dy = mouse_y - screen_y;
                        if ((dx * dx) + (dy * dy)) <= (radius * radius) then
                            hovered = true;
                            hover_x = screen_x;
                            hover_y = screen_y;
                        end
                    end
                end
            end
            end
            if (hovered) then
                return {
                    x = hover_x,
                    y = hover_y,
                    reference = reference,
                    opacity = floor_opacity,
                };
            end
        end
    end
end

local function draw_player(draw_list, center_x, center_y, yaw, visual_scale)
    local heading_x = math.cos(yaw);
    local heading_y = math.sin(yaw);
    local side_x = -heading_y;
    local side_y = heading_x;
    local tip_length = 13 * visual_scale;
    local back_length = 7 * visual_scale;
    local half_width = 7 * visual_scale;
    local tip = { center_x + (heading_x * tip_length), center_y + (heading_y * tip_length) };
    local back_x = center_x - (heading_x * back_length);
    local back_y = center_y - (heading_y * back_length);
    local left = { back_x + (side_x * half_width), back_y + (side_y * half_width) };
    local right = { back_x - (side_x * half_width), back_y - (side_y * half_width) };
    local shadow = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local player_color = color('player', { 0.18, 0.88, 0.90, 1.00 });
    draw_list:AddTriangleFilled(
        { tip[1] + 1, tip[2] + 1 },
        { left[1] + 1, left[2] + 1 },
        { right[1] + 1, right[2] + 1 },
        shadow);
    draw_list:AddTriangleFilled(tip, left, right, player_color);
    draw_list:AddCircle(
        { center_x, center_y },
        4.0 * visual_scale,
        player_color,
        16,
        math.max(1.0, 1.5 * visual_scale));
end

state.draw_all_pathing = function (
        draw_list,
        left,
        top,
        size,
        player,
        camera,
        map,
        scale)
    if (state.settings.developer_mode ~= true
            or state.settings.show_all_pathing ~= true) then
        return nil;
    end
    local graph = state.path_graph_for(player.zone_id, map.page_id);
    if (graph == nil) then
        return nil;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local floor_tolerance = tonumber(graph.floor_tolerance)
        or PATH_FLOOR_TOLERANCE;
    local active_edge = imgui.GetColorU32({ 0.05, 0.94, 1.00, 0.70 });
    local inactive_edge = imgui.GetColorU32({ 0.12, 0.55, 0.66, 0.28 });
    local active_node = imgui.GetColorU32({ 0.45, 0.98, 1.00, 0.90 });
    local inactive_node = imgui.GetColorU32({ 0.22, 0.62, 0.70, 0.42 });

    local function screen(node)
        return {
            center_x + (((tonumber(node[1]) or 0) - camera.x) * scale),
            center_y - (((tonumber(node[2]) or 0) - camera.y) * scale),
        };
    end

    local function on_player_floor(node)
        local live_z = state.path_node_live_z(graph, node);
        return player.z == nil
            or live_z == nil
            or math.abs(live_z - player.z) <= floor_tolerance;
    end

    local function segment_might_be_visible(a, b)
        return not ((a[1] < left and b[1] < left)
            or (a[1] > left + size and b[1] > left + size)
            or (a[2] < top and b[2] < top)
            or (a[2] > top + size and b[2] > top + size));
    end

    local edge_count = 0;
    local seen_edges = {};
    for index, node in ipairs(graph.nodes) do
        local start = screen(node);
        for _, neighbor_index in ipairs(node[4] or {}) do
            local neighbor = graph.nodes[tonumber(neighbor_index) or 0];
            local edge_key = neighbor ~= nil
                and string.format(
                    '%d:%d',
                    math.min(index, neighbor_index),
                    math.max(index, neighbor_index))
                or nil;
            if (neighbor ~= nil and seen_edges[edge_key] ~= true) then
                seen_edges[edge_key] = true;
                edge_count = edge_count + 1;
                local finish = screen(neighbor);
                if (segment_might_be_visible(start, finish)) then
                    local active = on_player_floor(node)
                        and on_player_floor(neighbor);
                    draw_list:AddLine(
                        start,
                        finish,
                        active and active_edge or inactive_edge,
                        active and 1.4 or 1.0);
                end
            end
        end
    end

    for _, node in ipairs(graph.nodes) do
        local point = screen(node);
        if (point[1] >= left and point[1] <= left + size
                and point[2] >= top and point[2] <= top + size) then
            local active = on_player_floor(node);
            draw_list:AddCircleFilled(
                point,
                active and 1.7 or 1.2,
                active and active_node or inactive_node,
                6);
        end
    end
    return {
        nodes = #graph.nodes,
        edges = edge_count,
    };
end

state.draw_guide_path = function (
        draw_list,
        left,
        top,
        size,
        player,
        camera,
        map,
        scale)
    local route = state.ensure_guide_path(player, map);
    local projection = route ~= nil and route.projection or nil;
    if (route == nil) then
        return nil;
    end
    if (projection == nil) then
        return route.world == true and route or nil;
    end
    route.floor_transition_direction = nil;
    route.elevation_passage_direction = nil;

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local outline = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local active = imgui.GetColorU32({ 0.10, 0.86, 1.00, 0.96 });
    local traveled = imgui.GetColorU32({ 0.34, 0.40, 0.44, 0.88 });
    local floor_tolerance = PATH_FLOOR_TOLERANCE;

    local function screen(point)
        return {
            center_x + ((point.x - camera.x) * scale),
            center_y - ((point.y - camera.y) * scale),
        };
    end

    local function segment(start, finish, fill)
        local screen_start = screen(start);
        local screen_finish = screen(finish);
        draw_list:AddLine(screen_start, screen_finish, outline, 5.5);
        draw_list:AddLine(screen_start, screen_finish, fill, 2.8);
    end

    local function segment_on_player_floor(start, finish)
        if (player.z == nil) then
            return true;
        end
        local start_z = tonumber(start.z);
        local finish_z = tonumber(finish.z);
        return start_z == nil
            or finish_z == nil
            or math.abs(start_z - player.z) <= floor_tolerance
            or math.abs(finish_z - player.z) <= floor_tolerance;
    end

    -- A shared dungeon graph can span several stock map pages. Only draw the
    -- contiguous portion around the player projection that belongs to the
    -- current floor; flattening later floors onto this page produces false
    -- corridors even though the three-dimensional route itself is valid.
    local visible_first = projection.index;
    while (visible_first > 1
            and segment_on_player_floor(
                route.points[visible_first - 1],
                route.points[visible_first])) do
        visible_first = visible_first - 1;
    end
    local visible_last = projection.index;
    while (visible_last < #route.points
            and segment_on_player_floor(
                route.points[visible_last],
                route.points[visible_last + 1])) do
        visible_last = visible_last + 1;
    end
    local elevation_marker_index = visible_last < #route.points
        and visible_last
        or nil;
    local continuous_surface = map.route_elevation_mode
        == 'continuous_surface';
    if (continuous_surface) then
        -- Outdoor and other explicitly certified single-surface maps use Z
        -- for truthful snapping and projection, but elevation does not change
        -- the stock artwork. Keep the complete route visible and retain the
        -- first elevation-band boundary as a required passage marker.
        visible_first = 1;
        visible_last = #route.points;
    end

    local projected_point = { x = projection.x, y = projection.y };
    for index = visible_first, visible_last - 1 do
        local start = route.points[index];
        local finish = route.points[index + 1];
        if (index < projection.index) then
            segment(start, finish, traveled);
        elseif (index == projection.index) then
            if (projection.ratio > 0.01) then
                segment(start, projected_point, traveled);
            end
            if (projection.ratio < 0.99) then
                segment(projected_point, finish, active);
            end
        else
            segment(start, finish, active);
        end
    end

    if (projection.distance > 2) then
        local player_point = { x = player.x, y = player.y };
        local start = screen(player_point);
        local finish = screen(projected_point);
        local delta_x = finish[1] - start[1];
        local delta_y = finish[2] - start[2];
        local distance = math.sqrt((delta_x * delta_x) + (delta_y * delta_y));
        local dots = math.floor(distance / 8);
        for index = 1, dots do
            local ratio = index / (dots + 1);
            draw_list:AddCircleFilled(
                {
                    start[1] + (delta_x * ratio),
                    start[2] + (delta_y * ratio),
                },
                1.8,
                active,
                8);
        end
    end

    local arrow_spacing = 58;
    local since_arrow = 0;
    for index = projection.index, visible_last - 1 do
        local start = index == projection.index
            and projected_point
            or route.points[index];
        local finish = route.points[index + 1];
        local screen_start = screen(start);
        local screen_finish = screen(finish);
        local delta_x = screen_finish[1] - screen_start[1];
        local delta_y = screen_finish[2] - screen_start[2];
        local distance = math.sqrt((delta_x * delta_x) + (delta_y * delta_y));
        if (distance > 0.01) then
            local offset = arrow_spacing - since_arrow;
            while offset < distance do
                local ratio = offset / distance;
                local x = screen_start[1] + (delta_x * ratio);
                local y = screen_start[2] + (delta_y * ratio);
                local direction_x = delta_x / distance;
                local direction_y = delta_y / distance;
                local side_x = -direction_y;
                local side_y = direction_x;
                draw_list:AddTriangleFilled(
                    { x + (direction_x * 6), y + (direction_y * 6) },
                    { x - (direction_x * 4) + (side_x * 4), y - (direction_y * 4) + (side_y * 4) },
                    { x - (direction_x * 4) - (side_x * 4), y - (direction_y * 4) - (side_y * 4) },
                    active);
                offset = offset + arrow_spacing;
            end
            since_arrow = (since_arrow + distance) % arrow_spacing;
        end
    end
    if (elevation_marker_index ~= nil) then
        local transition = route.points[elevation_marker_index];
        local next_point = route.points[elevation_marker_index + 1];
        local transition_screen = screen(transition);
        local minimum_x = left + 13;
        local maximum_x = left + size - 13;
        local minimum_y = top + 13;
        local maximum_y = top + size - 51;
        local transition_x = clamp(transition_screen[1], minimum_x, maximum_x);
        local transition_y = clamp(transition_screen[2], minimum_y, maximum_y);
        for index = projection.index, elevation_marker_index - 1 do
            local start = index == projection.index
                and projected_point
                or route.points[index];
            local finish = route.points[index + 1];
            local screen_start = screen(start);
            local screen_finish = screen(finish);
            local start_inside = screen_start[1] >= minimum_x
                and screen_start[1] <= maximum_x
                and screen_start[2] >= minimum_y
                and screen_start[2] <= maximum_y;
            local finish_inside = screen_finish[1] >= minimum_x
                and screen_finish[1] <= maximum_x
                and screen_finish[2] >= minimum_y
                and screen_finish[2] <= maximum_y;
            if (start_inside and not finish_inside) then
                local delta_x = screen_finish[1] - screen_start[1];
                local delta_y = screen_finish[2] - screen_start[2];
                local ratio = 1.0;
                if (screen_finish[1] < minimum_x and delta_x ~= 0) then
                    ratio = math.min(ratio, (minimum_x - screen_start[1]) / delta_x);
                elseif (screen_finish[1] > maximum_x and delta_x ~= 0) then
                    ratio = math.min(ratio, (maximum_x - screen_start[1]) / delta_x);
                end
                if (screen_finish[2] < minimum_y and delta_y ~= 0) then
                    ratio = math.min(ratio, (minimum_y - screen_start[2]) / delta_y);
                elseif (screen_finish[2] > maximum_y and delta_y ~= 0) then
                    ratio = math.min(ratio, (maximum_y - screen_start[2]) / delta_y);
                end
                transition_x = screen_start[1] + (delta_x * ratio);
                transition_y = screen_start[2] + (delta_y * ratio);
                break;
            end
        end
        local direction = (tonumber(next_point.z) or 0)
                > (tonumber(transition.z) or 0)
            and 'UP'
            or 'DN';
        local marker_fill = continuous_surface
            and imgui.GetColorU32({ 1.00, 0.68, 0.05, 1.00 })
            or active;
        draw_list:AddCircleFilled(
            { transition_x, transition_y },
            10.0,
            outline,
            20);
        draw_list:AddCircleFilled(
            { transition_x, transition_y },
            8.0,
            marker_fill,
            20);
        draw_list:AddText(
            { transition_x - 7, transition_y - 6 },
            outline,
            direction);
        if (continuous_surface) then
            route.elevation_passage_direction = direction;
        else
            route.floor_transition_direction = direction;
        end
    end
    return route;
end

local function world_step_target_name(step, next_action)
    local node = step ~= nil and step.to_node or nil;
    local metadata = node ~= nil and node.metadata or nil;
    if (metadata ~= nil
            and type(metadata.name) == 'string'
            and metadata.name ~= '') then
        return metadata.name;
    end
    if (next_action ~= nil and next_action.kind == 'zone_line') then
        return 'zone exit';
    elseif (next_action ~= nil and next_action.kind == 'home_point') then
        return 'Home Point';
    elseif (next_action ~= nil
            and next_action.kind == 'survival_guide') then
        return 'Survival Guide';
    end
    return 'guide destination';
end

-- Travel menus can be sorted by region or by expansion. World-route
-- instructions use the in-game "By Region Name" hierarchy so every route
-- supplies a stable group followed by the exact destination. Only zones with
-- an authored Home Point or Survival Guide endpoint are retained here.
local WORLD_TRAVEL_MENU_GROUPS = {
    { name = 'Republic of Bastok', zones = { 235, 236, 237 } },
    { name = 'Federation of Windurst', zones = { 238, 239, 240, 241 } },
    { name = 'Grand Duchy of Jeuno', zones = { 243, 244, 245, 246 } },
    { name = 'Ronfaure', zones = { 100, 140, 141, 167, 190 } },
    { name = 'Zulkheim', zones = { 102, 103, 108, 196 } },
    { name = 'Norvallen', zones = { 2, 104, 105, 149, 195 } },
    { name = 'Gustaberg', zones = { 106, 143, 172, 173, 191 } },
    { name = 'Derfland', zones = { 109, 110, 147, 197 } },
    { name = 'Sarutabaruta', zones = { 115, 145, 169, 192 } },
    { name = 'Kolshushu', zones = { 4, 117, 118, 198, 213, 249 } },
    { name = 'Aragoneu', zones = { 119, 120, 151, 200 } },
    { name = 'Fauregandi', zones = { 9, 111, 166, 204 } },
    { name = 'Valdeaunia', zones = { 5, 112, 161, 162 } },
    { name = 'Qufim', zones = { 126, 127, 158, 184 } },
    { name = 'Li\'Telor', zones = { 121, 122, 153, 154 } },
    { name = 'Kuzotz', zones = { 114, 125, 208 } },
    { name = 'Vollbow', zones = { 113, 128, 174, 212 } },
    { name = 'Elshimo Lowlands', zones = { 123, 176 } },
    { name = 'Elshimo Uplands', zones = { 124, 159, 160, 205 } },
    { name = 'Tu\'Lia', zones = { 130, 178 } },
    { name = 'Movalpolos', zones = { 11, 12 } },
    { name = 'Tavnazian Archipelago', zones = { 24, 25, 26, 27, 28, 29, 30 } },
    { name = 'Lumoria', zones = { 33, 34, 35 } },
    { name = 'West Aht Urhgan', zones = { 52 } },
    { name = 'Mamool Ja Savagelands', zones = { 51, 65, 68 } },
    { name = 'Halvung Territory', zones = { 61, 62 } },
    { name = 'Arrapago Islands', zones = { 54, 79 } },
    { name = 'Ronfaure Front', zones = { 81 } },
    { name = 'Norvallen Front', zones = { 82, 84, 175 } },
    { name = 'Gustaberg Front', zones = { 88, 89 } },
    { name = 'Derfland Front', zones = { 83, 90, 91, 171 } },
    { name = 'Sarutabaruta Front', zones = { 95, 96 } },
    { name = 'Aragoneu Front', zones = { 97, 98 } },
    { name = 'Fauregandi Front', zones = { 136 } },
    { name = 'Dark Kindred', zones = { 138, 155 } },
    { name = 'East Ulbuka Territory', zones = { 261, 263, 265, 267 } },
    { name = 'Ra\'Kaznar', zones = { 276 } },
};
local WORLD_TRAVEL_MENU_GROUP_BY_ZONE = {};
for _, group in ipairs(WORLD_TRAVEL_MENU_GROUPS) do
    for _, zone_id in ipairs(group.zones) do
        WORLD_TRAVEL_MENU_GROUP_BY_ZONE[zone_id] = group.name;
    end
end

local function world_action_menu_group(action)
    if (action == nil
            or (action.kind ~= 'home_point'
                and action.kind ~= 'survival_guide')) then
        return nil;
    end
    return WORLD_TRAVEL_MENU_GROUP_BY_ZONE[
        tonumber(action.destination_zone)];
end

local function world_action_instruction(action)
    if (action == nil) then
        return nil;
    elseif (action.kind == 'zone_line') then
        return string.format(
            'enter %s',
            zone_name(action.connection.to_zone));
    elseif (action.kind == 'home_point') then
        local destination = zone_name(action.destination_zone);
        if (type(action.destination_name) == 'string'
                and action.destination_name ~= '') then
            destination = string.format(
                '%s %s',
                destination,
                action.destination_name);
        end
        return string.format('select %s', destination);
    elseif (action.kind == 'survival_guide') then
        return string.format(
            'select %s',
            zone_name(action.destination_zone));
    elseif (action.kind == 'warp') then
        return string.format(
            'use Warp to return to %s',
            zone_name(action.destination_zone));
    end
    return 'follow the highlighted walking leg';
end

local function capitalize_instruction(value)
    if (type(value) ~= 'string' or value == '') then
        return value;
    end
    return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2);
end

state.draw_guide_path_status = function (draw_list, left, top, size, route)
    if (route == nil or size < 180
            or (route.world ~= true and route.projection == nil)) then
        return;
    end
    local height = route.world == true and 54 or 38;
    local panel_top = top + size - height;
    local background = imgui.GetColorU32({ 0.015, 0.025, 0.030, 0.88 });
    local border = color('border', { 0.67, 0.47, 0.22, 0.90 });
    local text_color = imgui.GetColorU32({ 0.88, 0.79, 0.61, 1.00 });
    local accent = imgui.GetColorU32({ 0.10, 0.86, 1.00, 1.00 });
    draw_list:AddRectFilled(
        { left + 1, panel_top },
        { left + size - 1, top + size - 1 },
        background,
        MAP_CORNER_RADIUS,
        ImDrawCornerFlags_All);
    draw_list:AddLine(
        { left + 1, panel_top },
        { left + size - 1, panel_top },
        border,
        1.0);
    local title = nil;
    local instruction = nil;
    local instruction_detail = nil;
    if (route.world == true) then
        local first = route.world_steps[1];
        if (first ~= nil and first.kind == 'walk') then
            local action = route.world_steps[2];
            local target_name = world_step_target_name(first, action);
            local leg_remaining = route.projection ~= nil
                and route.projection.remaining
                or first.distance
                or 0;
            title = string.format(
                '%s   %.0fy to %s',
                route.partial == true
                    and 'PARTIAL ROUTE'
                    or (route.destination_source == 'custom'
                        and 'ATLAS WAYPOINT'
                        or 'WORLD ROUTE'),
                leg_remaining,
                target_name);
            local next_instruction = world_action_instruction(action);
            if (next_instruction ~= nil) then
                local menu_group = world_action_menu_group(action);
                if (menu_group ~= nil) then
                    instruction = 'Region: ' .. menu_group;
                    instruction_detail = capitalize_instruction(
                        next_instruction);
                else
                    instruction = capitalize_instruction(next_instruction);
                end
            else
                instruction = route.destination_source == 'custom'
                    and 'Follow cyan line toward the custom waypoint'
                    or 'Follow cyan line to the guide destination';
            end
            if route.partial == true and instruction_detail == nil then
                instruction_detail = 'Destination remains marker-only after zoning';
            end
        elseif (first ~= nil) then
            title = route.destination_source == 'custom'
                and 'ATLAS WAYPOINT   next action'
                or 'WORLD ROUTE   next action';
            local menu_group = world_action_menu_group(first);
            if (menu_group ~= nil) then
                instruction = 'Region: ' .. menu_group;
                instruction_detail = capitalize_instruction(
                    world_action_instruction(first));
            else
                instruction = capitalize_instruction(
                    world_action_instruction(first));
            end
        else
            title = route.destination_source == 'custom'
                and 'ATLAS WAYPOINT'
                or 'WORLD ROUTE';
            instruction = route.destination_source == 'custom'
                and 'Custom waypoint reached'
                or 'Guide destination reached';
        end
    else
        title = string.format(
            '%s   %.0fy remaining',
            route.destination_source == 'custom'
                and 'CUSTOM WAYPOINT'
                or 'GUIDE PATH',
            route.projection.remaining);
        instruction = route.destination_source == 'custom'
            and 'Right-click waypoint to clear'
            or 'Shortest route from map navigation graph';
        if (route.elevation_passage_direction ~= nil) then
            instruction = string.format(
                'Full route; amber %s point is required',
                route.elevation_passage_direction);
        elseif (route.floor_transition_direction ~= nil) then
            instruction = string.format(
                'Follow cyan route to %s floor change',
                route.floor_transition_direction);
        end
    end
    draw_list:AddText(
        { left + 10, panel_top + 5 },
        text_color,
        title);
    draw_list:AddText(
        { left + 10, panel_top + 21 },
        accent,
        instruction);
    if (instruction_detail ~= nil) then
        draw_list:AddText(
            { left + 10, panel_top + 37 },
            accent,
            instruction_detail);
    end
    if (route.world ~= true) then
        draw_list:AddText(
            { left + size - 63, panel_top + 21 },
            accent,
            'PATH ON');
    end
end

local function draw_waypoint_marker(
        draw_list,
        left,
        top,
        size,
        camera,
        scale,
        waypoint)
    local marker_x, marker_y, offscreen = state.custom_waypoint_screen(
        left,
        top,
        size,
        camera,
        scale,
        waypoint);
    local outline = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local fill = imgui.GetColorU32({ 0.10, 0.86, 1.00, 1.00 });
    local radius = offscreen and 9 or 8;
    draw_list:AddCircleFilled({ marker_x, marker_y }, radius + 2, outline, 20);
    draw_list:AddCircleFilled({ marker_x, marker_y }, radius, fill, 20);
    draw_list:AddCircle({ marker_x, marker_y }, radius + 4, fill, 20, 2.0);
    draw_list:AddLine(
        { marker_x - 4, marker_y },
        { marker_x + 4, marker_y },
        outline,
        2.0);
    draw_list:AddLine(
        { marker_x, marker_y - 4 },
        { marker_x, marker_y + 4 },
        outline,
        2.0);
end

state.draw_custom_waypoint = function (
        draw_list,
        left,
        top,
        size,
        player,
        camera,
        map,
        scale)
    local waypoint = state.active_custom_waypoint(player, map);
    if (waypoint ~= nil) then
        draw_waypoint_marker(
            draw_list,
            left,
            top,
            size,
            camera,
            scale,
            waypoint);
    end
end

local function draw_damselfly_marker(draw_list, x, y, opacity)
    local shadow = color_with_opacity(
        'shadow',
        { 0.01, 0.02, 0.025, 0.94 },
        opacity);
    local wing = imgui.GetColorU32({ 0.52, 0.92, 1.00, 0.82 * opacity });
    local body = imgui.GetColorU32({ 0.98, 0.67, 0.18, opacity });
    local wing_tips = {
        { x - 7.0, y - 5.0 },
        { x + 7.0, y - 5.0 },
        { x - 6.0, y + 4.0 },
        { x + 6.0, y + 4.0 },
    };
    for _, tip in ipairs(wing_tips) do
        local root_y = tip[2] < y and y - 1.5 or y + 1.5;
        draw_list:AddLine({ x, root_y }, tip, shadow, 4.0);
        draw_list:AddLine({ x, root_y }, tip, wing, 2.4);
        draw_list:AddCircleFilled(tip, 1.7, wing, 10);
    end
    draw_list:AddLine({ x, y - 5.5 }, { x, y + 6.5 }, shadow, 4.0);
    draw_list:AddLine({ x, y - 5.5 }, { x, y + 6.5 }, body, 2.2);
    draw_list:AddCircleFilled({ x, y - 6.2 }, 2.3, shadow, 12);
    draw_list:AddCircleFilled({ x, y - 6.2 }, 1.5, body, 12);
end

local function draw_lizard_marker(draw_list, x, y, opacity)
    local shadow = color_with_opacity('shadow', { 0.01, 0.02, 0.025, 0.94 }, opacity);
    local body = imgui.GetColorU32({ 0.96, 0.68, 0.20, opacity });
    local accent = imgui.GetColorU32({ 0.25, 0.88, 0.84, opacity });
    draw_list:AddCircleFilled({ x - 1, y }, 5.0, shadow, 16);
    draw_list:AddCircleFilled({ x - 1, y }, 3.8, body, 16);
    draw_list:AddCircleFilled({ x + 4, y - 2 }, 3.2, shadow, 12);
    draw_list:AddCircleFilled({ x + 4, y - 2 }, 2.2, body, 12);
    draw_list:AddLine({ x - 4, y + 1 }, { x - 9, y + 6 }, shadow, 4.0);
    draw_list:AddLine({ x - 4, y + 1 }, { x - 9, y + 6 }, accent, 2.0);
    draw_list:AddLine({ x - 2, y + 3 }, { x - 5, y + 7 }, body, 1.8);
    draw_list:AddLine({ x + 1, y + 3 }, { x + 5, y + 6 }, body, 1.8);
    draw_list:AddCircleFilled({ x + 5, y - 3 }, 0.8, shadow, 6);
end

state.draw_guide_markers = function (
        draw_list,
        left,
        top,
        size,
        player,
        camera,
        map,
        scale)
    local custom_waypoint_active = type(state.custom_waypoint) == 'table';
    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local minimum_x = left + 10;
    local maximum_x = left + size - 10;
    local minimum_y = top + 10;
    local maximum_y = top + size - 10;
    local outline = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local pulse = 0.82 + ((math.sin(os.clock() * 5) + 1) * 0.09);
    local display_markers = {};
    if (not custom_waypoint_active) then
        for _, marker in ipairs(state.active_guide_markers(player)) do
            display_markers[#display_markers + 1] = marker;
        end
    end
    for _, marker in ipairs(state.active_nm_hunt_markers(player)) do
        display_markers[#display_markers + 1] = marker;
    end
    for _, marker in ipairs(display_markers) do
        local marker_on_player_floor = marker.z == nil
            or player.z == nil
            or math.abs(marker.z - player.z) <= PATH_FLOOR_TOLERANCE;
        if (position_matches_active_stock_page(
                    player.zone_id,
                    map,
                    marker,
                    marker.map_id)
                and marker_on_player_floor) then
            local screen_x = center_x + ((marker.x - camera.x) * scale);
            local screen_y = center_y - ((marker.y - camera.y) * scale);
            local clamped_x = clamp(screen_x, minimum_x, maximum_x);
            local clamped_y = clamp(screen_y, minimum_y, maximum_y);
            local offscreen = clamped_x ~= screen_x or clamped_y ~= screen_y;
            local distance_x = marker.x - player.x;
            local distance_y = marker.y - player.y;
            local distance = math.sqrt(
                (distance_x * distance_x) + (distance_y * distance_y));
            local fill = distance <= 2.5
                and color('player', { 0.18, 0.88, 0.90, 1.00 })
                or imgui.GetColorU32({ 1.00, 0.71, 0.20, pulse });
            if (marker.style == 'damselfly') then
                draw_damselfly_marker(draw_list, clamped_x, clamped_y, 1);
            elseif (marker.style == 'lizard') then
                draw_lizard_marker(draw_list, clamped_x, clamped_y, 1);
            elseif (marker.approximate == true) then
                local radius = offscreen and 9.0 or 8.0;
                draw_list:AddLine(
                    { clamped_x, clamped_y - radius },
                    { clamped_x + radius, clamped_y },
                    outline,
                    5.0);
                draw_list:AddLine(
                    { clamped_x + radius, clamped_y },
                    { clamped_x, clamped_y + radius },
                    outline,
                    5.0);
                draw_list:AddLine(
                    { clamped_x, clamped_y + radius },
                    { clamped_x - radius, clamped_y },
                    outline,
                    5.0);
                draw_list:AddLine(
                    { clamped_x - radius, clamped_y },
                    { clamped_x, clamped_y - radius },
                    outline,
                    5.0);
                draw_list:AddLine(
                    { clamped_x, clamped_y - radius },
                    { clamped_x + radius, clamped_y },
                    fill,
                    2.0);
                draw_list:AddLine(
                    { clamped_x + radius, clamped_y },
                    { clamped_x, clamped_y + radius },
                    fill,
                    2.0);
                draw_list:AddLine(
                    { clamped_x, clamped_y + radius },
                    { clamped_x - radius, clamped_y },
                    fill,
                    2.0);
                draw_list:AddLine(
                    { clamped_x - radius, clamped_y },
                    { clamped_x, clamped_y - radius },
                    fill,
                    2.0);
            else
                draw_list:AddCircleFilled(
                    { clamped_x, clamped_y },
                    6.0,
                    outline,
                    20);
                draw_list:AddCircleFilled(
                    { clamped_x, clamped_y },
                    4.0,
                    fill,
                    20);
                draw_list:AddCircle(
                    { clamped_x, clamped_y },
                    offscreen and 9.0 or 8.0,
                    fill,
                    20,
                    2.0);
            end
        end
    end
end

local VANA_WEEKDAYS = {
    [0] = { name = 'Firesday', color = { 0.95, 0.35, 0.18, 1.00 } },
    [1] = { name = 'Earthsday', color = { 0.78, 0.62, 0.28, 1.00 } },
    [2] = { name = 'Watersday', color = { 0.30, 0.52, 0.95, 1.00 } },
    [3] = { name = 'Windsday', color = { 0.35, 0.82, 0.40, 1.00 } },
    [4] = { name = 'Iceday', color = { 0.55, 0.85, 0.98, 1.00 } },
    [5] = { name = 'Lightningday', color = { 0.72, 0.45, 0.95, 1.00 } },
    [6] = { name = 'Lightsday', color = { 0.96, 0.94, 0.70, 1.00 } },
    [7] = { name = 'Darksday', color = { 0.35, 0.28, 0.48, 1.00 } },
};

local WEATHER_NAMES = {
    [0] = 'Clear',
    [1] = 'Sunshine',
    [2] = 'Clouds',
    [3] = 'Fog',
    [4] = 'Hot Spells',
    [5] = 'Heat Waves',
    [6] = 'Rain',
    [7] = 'Squalls',
    [8] = 'Dust Storms',
    [9] = 'Sandstorms',
    [10] = 'Winds',
    [11] = 'Gales',
    [12] = 'Snow',
    [13] = 'Blizzards',
    [14] = 'Thunder',
    [15] = 'Thunderstorms',
    [16] = 'Auroras',
    [17] = 'Stellar Glare',
    [18] = 'Gloom',
    [19] = 'Darkness',
};

local WEATHER_COLORS = {
    [0] = { 0.86, 0.84, 0.70, 1.00 },
    [1] = { 1.00, 0.86, 0.42, 1.00 },
    [2] = { 0.68, 0.72, 0.76, 1.00 },
    [3] = { 0.72, 0.76, 0.80, 1.00 },
    [4] = { 0.95, 0.38, 0.18, 1.00 },
    [5] = { 1.00, 0.28, 0.10, 1.00 },
    [6] = { 0.30, 0.58, 0.96, 1.00 },
    [7] = { 0.20, 0.48, 0.92, 1.00 },
    [8] = { 0.72, 0.54, 0.27, 1.00 },
    [9] = { 0.84, 0.62, 0.28, 1.00 },
    [10] = { 0.38, 0.82, 0.48, 1.00 },
    [11] = { 0.26, 0.72, 0.36, 1.00 },
    [12] = { 0.62, 0.88, 1.00, 1.00 },
    [13] = { 0.48, 0.80, 1.00, 1.00 },
    [14] = { 0.78, 0.52, 1.00, 1.00 },
    [15] = { 0.66, 0.38, 0.96, 1.00 },
    [16] = { 1.00, 0.96, 0.62, 1.00 },
    [17] = { 0.96, 0.88, 0.48, 1.00 },
    [18] = { 0.48, 0.38, 0.62, 1.00 },
    [19] = { 0.34, 0.26, 0.48, 1.00 },
};

local WEATHER_SHORT_NAMES = {
    [0] = 'Clear',
    [1] = 'Sun',
    [2] = 'Clouds',
    [3] = 'Fog',
    [4] = 'Hot',
    [5] = 'Heat',
    [6] = 'Rain',
    [7] = 'Squalls',
    [8] = 'Dust',
    [9] = 'Sand',
    [10] = 'Wind',
    [11] = 'Gales',
    [12] = 'Snow',
    [13] = 'Blizzard',
    [14] = 'Thunder',
    [15] = 'Storm',
    [16] = 'Aurora',
    [17] = 'Glare',
    [18] = 'Gloom',
    [19] = 'Dark',
};

local function ensure_environment_addresses()
    local environment = state.environment;
    local now = os.clock();
    if (environment.time_signature_address ~= 0
            and environment.weather_signature_address ~= 0) then
        return;
    end
    if (now - environment.checked_at < 5.0) then
        return;
    end
    environment.checked_at = now;
    if (environment.time_signature_address == 0) then
        environment.time_signature_address = tonumber(safe_read(function ()
            return ashita.memory.find(
                'FFXiMain.dll',
                0,
                VANA_TIME_SIGNATURE,
                0,
                0);
        end, 0)) or 0;
    end
    if (environment.weather_signature_address == 0) then
        environment.weather_signature_address = tonumber(safe_read(function ()
            return ashita.memory.find(
                'FFXiMain.dll',
                0,
                WEATHER_SIGNATURE,
                0,
                0);
        end, 0)) or 0;
    end
end

local function current_environment()
    local now = os.clock();
    if (state.environment.snapshot ~= nil
            and now - state.environment.snapshot_at < 0.5) then
        return state.environment.snapshot;
    end
    ensure_environment_addresses();
    local environment = state.environment;
    if (environment.time_signature_address == 0) then
        return nil;
    end
    local time_pointer = tonumber(safe_read(function ()
        return ashita.memory.read_uint32(
            environment.time_signature_address + 0x34);
    end, 0)) or 0;
    if (time_pointer == 0) then
        return nil;
    end
    local raw_time = tonumber(safe_read(function ()
        return ashita.memory.read_uint32(time_pointer + 0x0C);
    end, nil));
    if (raw_time == nil) then
        return nil;
    end
    raw_time = raw_time + 92514960;
    local day_number = math.floor(raw_time / 3456);
    local weekday_index = day_number % 8;
    local weekday = VANA_WEEKDAYS[weekday_index] or VANA_WEEKDAYS[0];
    local moon_day = (day_number + 26) % 84;
    local moon_direction = moon_day < 42 and 'Waning' or 'Waxing';
    local moon_percent = moon_day >= 42
        and math.floor(100 * ((moon_day - 42) / 42) + 0.5)
        or math.floor(100 * (1 - (moon_day / 42)) + 0.5);
    local moon_name = nil;
    if (moon_percent <= 5) then
        moon_name = 'New Moon';
    elseif (moon_percent <= 25) then
        moon_name = moon_direction .. ' Crescent';
    elseif (moon_percent <= 40) then
        moon_name = moon_direction == 'Waning'
            and 'Last Quarter'
            or 'First Quarter';
    elseif (moon_percent <= 90) then
        moon_name = moon_direction .. ' Gibbous';
    else
        moon_name = 'Full Moon';
    end
    local weather_id = nil;
    if (environment.weather_signature_address ~= 0) then
        local weather_pointer = tonumber(safe_read(function ()
            return ashita.memory.read_uint32(
                environment.weather_signature_address + 0x02);
        end, 0)) or 0;
        if (weather_pointer ~= 0) then
            weather_id = tonumber(safe_read(function ()
                return ashita.memory.read_uint8(weather_pointer);
            end, nil));
        end
    end
    local snapshot = {
        time = string.format(
            '%02d:%02d',
            math.floor(raw_time / 144) % 24,
            math.floor((raw_time % 144) / 2.4)),
        weekday = weekday,
        moon_name = moon_name,
        moon_percent = moon_percent,
        weather_id = weather_id,
        weather = WEATHER_NAMES[weather_id] or 'Weather unknown',
    };
    environment.snapshot = snapshot;
    environment.snapshot_at = now;
    return snapshot;
end

local function draw_environment_clock(draw_list, left, top, size)
    if (state.settings.show_environment_clock ~= true or size < 260) then
        return;
    end
    local environment = current_environment();
    if (environment == nil) then
        return;
    end
    local time_label = string.format(
        '%s  %s',
        environment.time,
        environment.weekday.name);
    local detail_label = string.format(
        '%s %d%%',
        environment.moon_name,
        environment.moon_percent);
    if (state.settings.show_weather_badge ~= true) then
        detail_label = string.format(
            '%s  |  %s',
            detail_label,
            environment.weather);
    end
    local time_width = select(1, imgui.CalcTextSize(time_label));
    local detail_width = select(1, imgui.CalcTextSize(detail_label));
    local panel_width = math.min(
        size - (HUD_INSET * 2),
        math.max(time_width + 36, detail_width + 16, 150));
    local panel_height = 41;
    local panel_left = left + size - panel_width - HUD_INSET;
    local panel_top = top + HUD_INSET;
    local badge_color = color('badge', { 0.025, 0.055, 0.070, 0.88 });
    local border = color('border', { 0.67, 0.47, 0.22, 0.90 });
    local text_color = color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    draw_list:AddRectFilled(
        { panel_left, panel_top },
        { panel_left + panel_width, panel_top + panel_height },
        badge_color,
        3.0);
    draw_list:AddRect(
        { panel_left, panel_top },
        { panel_left + panel_width, panel_top + panel_height },
        border,
        3.0,
        0,
        1.0);
    draw_list:AddCircleFilled(
        { panel_left + 11, panel_top + 12 },
        5.0,
        imgui.GetColorU32(environment.weekday.color),
        18);
    draw_list:AddCircle(
        { panel_left + 11, panel_top + 12 },
        5.0,
        color('shadow', { 0.01, 0.02, 0.025, 0.94 }),
        18,
        1.0);
    draw_list:AddText(
        { panel_left + 22, panel_top + 5 },
        text_color,
        time_label);
    draw_list:AddText(
        { panel_left + 8, panel_top + 22 },
        text_color,
        detail_label);
end

local function compact_weather_visible(size)
    return state.settings.show_weather_badge == true;
end

local function hud_toolbar_top(top, size)
    local full_environment_card = state.settings.show_environment_clock == true
        and size >= 260;
    return top + (full_environment_card and 52 or HUD_INSET);
end

local function atlas_toggle_width()
    local text_width = select(1, imgui.CalcTextSize('ATLAS'));
    return math.max(68, math.ceil(text_width + 31));
end

local function weather_badge_layout(left, top, size)
    if (not compact_weather_visible(size)) then
        return nil;
    end
    local environment = current_environment();
    if (environment == nil) then
        return nil;
    end
    local label = size < 180
        and (WEATHER_SHORT_NAMES[environment.weather_id] or 'Unknown')
        or environment.weather;
    local text_width = select(1, imgui.CalcTextSize(label));
    local atlas_width = atlas_toggle_width();
    local available_width = math.max(
        0,
        size - (HUD_INSET * 2) - atlas_width - HUD_CONTROL_GAP);
    local width = math.min(available_width, math.max(64, text_width + 30));
    if (width < 64) then
        label = nil;
        width = math.min(available_width, HUD_CONTROL_HEIGHT);
    end
    if (width <= 0) then
        return nil;
    end
    local x = left + size - HUD_INSET - atlas_width - HUD_CONTROL_GAP - width;
    local y = hud_toolbar_top(top, size);
    return {
        environment = environment,
        label = label,
        x = x,
        y = y,
        width = width,
        height = HUD_CONTROL_HEIGHT,
    };
end

local function draw_weather_badge(draw_list, left, top, size)
    local layout = weather_badge_layout(left, top, size);
    if (layout == nil) then
        return;
    end
    local environment = layout.environment;
    local x = layout.x;
    local y = layout.y;
    local width = layout.width;
    local height = layout.height;
    local badge_color = color('badge', { 0.025, 0.055, 0.070, 0.88 });
    local border = color('border', { 0.67, 0.47, 0.22, 0.90 });
    local text_color = color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    local weather_color = WEATHER_COLORS[environment.weather_id]
        or { 0.70, 0.74, 0.78, 1.00 };
    draw_list:AddRectFilled(
        { x, y },
        { x + width, y + height },
        badge_color,
        3.0);
    draw_list:AddRect(
        { x, y },
        { x + width, y + height },
        border,
        3.0,
        0,
        1.0);
    draw_list:AddCircleFilled(
        { x + 11, y + (height / 2) },
        4.0,
        imgui.GetColorU32(weather_color),
        14);
    draw_list:AddCircle(
        { x + 11, y + (height / 2) },
        4.0,
        color('shadow', { 0.01, 0.02, 0.025, 0.94 }),
        14,
        1.0);
    if (layout.label ~= nil) then
        draw_list:AddText({ x + 21, y + 3 }, text_color, layout.label);
    end
end

local function draw_badge(draw_list, left, top, player, map)
    local show_grid_coordinate = state.settings.show_coordinate == true;
    local show_numeric_coordinates =
        state.settings.show_numeric_coordinates == true;
    if (not show_grid_coordinate and not show_numeric_coordinates) then
        return;
    end
    local name = map.name or ('Zone ' .. tostring(player.zone_id));
    local label = name;
    if (show_grid_coordinate) then
        label = string.format(
            '%s  %s',
            grid_coordinate(player.x, player.y, map),
            name);
    end
    local numeric_label = nil;
    if (show_numeric_coordinates) then
        numeric_label = string.format(
            'X %.1f  Y %.1f  Z %.1f',
            tonumber(player.x) or 0,
            tonumber(player.y) or 0,
            tonumber(player.z) or 0);
    end
    local width = math.max(
        66,
        (#label * 7) + 16,
        numeric_label ~= nil and ((#numeric_label * 7) + 16) or 0);
    local height = numeric_label ~= nil and 41 or 23;
    local badge_color = color('badge', { 0.025, 0.055, 0.070, 0.88 });
    local border = color('border', { 0.67, 0.47, 0.22, 0.90 });
    local text_color = color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    draw_list:AddRectFilled(
        { left + 6, top + 6 },
        { left + 6 + width, top + 6 + height },
        badge_color,
        3.0);
    draw_list:AddRect(
        { left + 6, top + 6 },
        { left + 6 + width, top + 6 + height },
        border,
        3.0,
        0,
        1.0);
    draw_list:AddText({ left + 14, top + 10 }, text_color, label);
    if (numeric_label ~= nil) then
        draw_list:AddText(
            { left + 14, top + 28 },
            text_color,
            numeric_label);
    end
end

local function draw_map_layer(
        draw_list,
        left,
        top,
        size,
        camera,
        map,
        texture,
        scale,
        opacity,
        visibility_boost)
    local image_scale = tonumber(map.image_pixels_per_yalm) or 0;
    local width = tonumber(map.width) or 0;
    local height = tonumber(map.height) or 0;
    if (image_scale <= 0 or width <= 0 or height <= 0) then
        return;
    end

    local camera_image_x = (tonumber(map.origin_x) or (width / 2)) + (camera.x * image_scale);
    local camera_image_y = (tonumber(map.origin_y) or (height / 2)) - (camera.y * image_scale);
    local source_half_pixels = ((size / 2) / scale) * image_scale;
    local source_left = camera_image_x - source_half_pixels;
    local source_top = camera_image_y - source_half_pixels;
    local source_right = camera_image_x + source_half_pixels;
    local source_bottom = camera_image_y + source_half_pixels;
    local clipped_left = clamp(source_left, 0, width);
    local clipped_top = clamp(source_top, 0, height);
    local clipped_right = clamp(source_right, 0, width);
    local clipped_bottom = clamp(source_bottom, 0, height);
    if (clipped_right <= clipped_left or clipped_bottom <= clipped_top) then
        return;
    end

    local source_span = source_half_pixels * 2;
    local destination_left = left + (((clipped_left - source_left) / source_span) * size);
    local destination_top = top + (((clipped_top - source_top) / source_span) * size);
    local destination_right = left + (((clipped_right - source_left) / source_span) * size);
    local destination_bottom = top + (((clipped_bottom - source_top) / source_span) * size);
    local u0 = clipped_left / width;
    local v0 = clipped_top / height;
    local u1 = clipped_right / width;
    local v1 = clipped_bottom / height;
    opacity = clamp(opacity, 0, 1);
    local passes = math.floor(clamp(visibility_boost, 1, 12) + 0.5);
    local tint = imgui.GetColorU32({ 1, 1, 1, opacity });
    for _ = 1, passes do
        draw_list:AddImageRounded(
            texture.handle,
            { destination_left, destination_top },
            { destination_right, destination_bottom },
            { u0, v0 },
            { u1, v1 },
            tint,
            MAP_CORNER_RADIUS,
            ImDrawCornerFlags_All);
    end
end

local function focused_opacity(configured, focus)
    configured = clamp(configured, 0, 1);
    return configured + ((1 - configured) * clamp(focus, 0, 1));
end

local function update_hover_focus(hovered)
    local now = os.clock();
    local elapsed = state.hover_focus_updated_at > 0
        and clamp(now - state.hover_focus_updated_at, 0, 0.10)
        or 0;
    state.hover_focus_updated_at = now;
    local duration = hovered and HOVER_FADE_IN_SECONDS or HOVER_FADE_OUT_SECONDS;
    local direction = hovered and 1 or -1;
    state.hover_focus = clamp(
        state.hover_focus + (direction * elapsed / duration),
        0,
        1);
    return state.hover_focus;
end

local function animated_window_y(target)
    target = tonumber(target) or DEFAULTS.y;
    local now = os.clock();
    if (state.settings.locked ~= true or state.window_y == nil) then
        state.window_y = target;
        state.window_y_updated_at = now;
        return target;
    end

    local elapsed = clamp(now - state.window_y_updated_at, 0, 0.10);
    state.window_y_updated_at = now;
    local blend = 1 - math.exp(-POSITION_ANIMATION_RESPONSE * elapsed);
    state.window_y = state.window_y + ((target - state.window_y) * blend);
    if (math.abs(target - state.window_y) < 0.5) then
        state.window_y = target;
    end
    return state.window_y;
end

local function draw_map_backdrop(draw_list, left, top, size, focus)
    local opacity = focused_opacity(
        clamp(state.settings.backdrop_opacity, 0, 0.75),
        focus);
    if (opacity <= 0) then
        return;
    end
    local configured = state.settings.colors and state.settings.colors.backdrop or DEFAULTS.colors.backdrop;
    draw_list:AddRectFilled(
        { left, top },
        { left + size, top + size },
        imgui.GetColorU32({
            tonumber(configured[1]) or DEFAULTS.colors.backdrop[1],
            tonumber(configured[2]) or DEFAULTS.colors.backdrop[2],
            tonumber(configured[3]) or DEFAULTS.colors.backdrop[3],
            opacity,
        }),
        MAP_CORNER_RADIUS);
end

local function layer_zoom_opacity(layer, scale, minimum_zoom)
    if (type(layer) ~= 'table' or layer.role ~= 'floor_transition') then
        return 1;
    end

    local overview_opacity = clamp(
        layer.overview_opacity or TRANSITION_OVERVIEW_OPACITY,
        0,
        1);
    local close_opacity = clamp(
        layer.close_opacity or TRANSITION_CLOSE_OPACITY,
        0,
        1);
    local close_zoom_ratio = math.max(
        1.01,
        tonumber(layer.close_zoom_ratio) or TRANSITION_CLOSE_ZOOM_RATIO);
    local zoom_ratio = minimum_zoom > 0 and (scale / minimum_zoom) or 1;
    local progress = clamp(
        (zoom_ratio - 1) / (close_zoom_ratio - 1),
        0,
        1);
    progress = progress * progress * (3 - (2 * progress));
    return overview_opacity
        + ((close_opacity - overview_opacity) * progress);
end

local function mouse_over_map(left, top, size)
    local mouse_x, mouse_y = imgui.GetMousePos();
    mouse_x = tonumber(mouse_x);
    mouse_y = tonumber(mouse_y);
    if (mouse_x == nil or mouse_y == nil) then
        return false, 0, 0;
    end
    return mouse_x >= left and mouse_x <= left + size
        and mouse_y >= top and mouse_y <= top + size,
        mouse_x,
        mouse_y;
end

local function atlas_toggle_bounds(left, top, size)
    local width = atlas_toggle_width();
    local height = HUD_CONTROL_HEIGHT;
    local x = left + size - width - HUD_INSET;
    local y = hud_toolbar_top(top, size);
    return x, y, width, height;
end

local function update_atlas_toggle_hover(left, top, size)
    local x, y, width, height = atlas_toggle_bounds(left, top, size);
    state.atlas.toggle_x = x;
    state.atlas.toggle_y = y;
    state.atlas.toggle_width = width;
    state.atlas.toggle_height = height;
    local mouse_x, mouse_y = imgui.GetMousePos();
    mouse_x = tonumber(mouse_x);
    mouse_y = tonumber(mouse_y);
    local hovered = mouse_x ~= nil
        and mouse_y ~= nil
        and mouse_x >= x
        and mouse_x <= x + width
        and mouse_y >= y
        and mouse_y <= y + height;
    local atlas = state.atlas;
    if (hovered
            and atlas.visible[1] == true
            and atlas.window_x ~= nil
            and mouse_x >= atlas.window_x
            and mouse_x <= atlas.window_x + atlas.window_width
            and mouse_y >= atlas.window_y
            and mouse_y <= atlas.window_y + atlas.window_height) then
        hovered = false;
    end
    return hovered;
end

local function render_atlas_toggle_capture()
    local atlas = state.atlas;
    local x = tonumber(atlas.toggle_x);
    local y = tonumber(atlas.toggle_y);
    local width = tonumber(atlas.toggle_width);
    local height = tonumber(atlas.toggle_height);
    if (x == nil or y == nil or width == nil or height == nil) then
        return;
    end
    if (atlas.visible[1] == true
            and atlas.window_x ~= nil
            and x < atlas.window_x + atlas.window_width
            and x + width > atlas.window_x
            and y < atlas.window_y + atlas.window_height
            and y + height > atlas.window_y) then
        return;
    end

    local flags = bit.bor(
        bit.lshift(1, 0),  -- NoTitleBar
        bit.lshift(1, 1),  -- NoResize
        bit.lshift(1, 2),  -- NoMove
        bit.lshift(1, 3),  -- NoScrollbar
        bit.lshift(1, 7),  -- NoBackground
        bit.lshift(1, 8),  -- NoSavedSettings
        bit.lshift(1, 12), -- NoFocusOnAppearing
        bit.lshift(1, 13), -- NoBringToFrontOnFocus
        bit.lshift(1, 18), -- NoNavInputs
        bit.lshift(1, 19));-- NoNavFocus
    imgui.SetNextWindowPos({ x, y }, 0);
    imgui.SetNextWindowSize({ width, height }, 0);
    if (type(imgui.SetNextWindowBgAlpha) == 'function') then
        imgui.SetNextWindowBgAlpha(0.0);
    end
    if (imgui.Begin(
            '##ashitaminimap_atlas_toggle_capture',
            true,
            flags)) then
        imgui.SetCursorScreenPos({ x, y });
        if (imgui.InvisibleButton(
                '##ashitaminimap_atlas_toggle_button',
                { width, height })) then
            atlas.visible[1] = not atlas.visible[1];
            state.dragging = false;
        end
    end
    imgui.End();
end

local function draw_atlas_toggle_button(draw_list, left, top, size, hovered)
    local x, y, width, height = atlas_toggle_bounds(left, top, size);
    local active = state.atlas.visible[1] == true;
    local fill = active
        and imgui.GetColorU32({ 0.06, 0.48, 0.58, hovered and 1.00 or 0.92 })
        or imgui.GetColorU32({
            0.025,
            0.055,
            0.070,
            hovered and 0.98 or 0.88,
        });
    local border = active
        and imgui.GetColorU32({ 0.10, 0.86, 1.00, 1.00 })
        or color('border', { 0.67, 0.47, 0.22, 0.90 });
    draw_list:AddRectFilled(
        { x, y },
        { x + width, y + height },
        fill,
        3.0);
    draw_list:AddRect(
        { x, y },
        { x + width, y + height },
        border,
        3.0,
        0,
        1.0);
    local icon_x = x + 12;
    local icon_y = y + (height / 2);
    local icon_color = active
        and imgui.GetColorU32({ 0.92, 1.00, 1.00, 1.00 })
        or color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    draw_list:AddCircle(
        { icon_x, icon_y },
        6.0,
        icon_color,
        16,
        1.0);
    draw_list:AddTriangleFilled(
        { icon_x, icon_y - 5 },
        { icon_x - 2.5, icon_y + 2 },
        { icon_x + 2.5, icon_y + 2 },
        icon_color);
    draw_list:AddText(
        { x + 24, y + 3 },
        icon_color,
        'ATLAS');
end

state.custom_waypoint_screen = function (
        left,
        top,
        size,
        camera,
        scale,
        waypoint)
    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local screen_x = center_x + ((waypoint.x - camera.x) * scale);
    local screen_y = center_y - ((waypoint.y - camera.y) * scale);
    local margin = 12;
    return clamp(screen_x, left + margin, left + size - margin),
        clamp(screen_y, top + margin, top + size - margin),
        screen_x ~= clamp(screen_x, left + margin, left + size - margin)
            or screen_y ~= clamp(screen_y, top + margin, top + size - margin);
end

local function handle_custom_waypoint_input(
        left,
        top,
        size,
        player,
        map,
        camera,
        scale,
        suppress_input)
    local hovered, mouse_x, mouse_y = mouse_over_map(left, top, size);
    if (suppress_input == true
            or not hovered
            or safe_read(function () return imgui.IsMouseClicked(1); end, false)
                ~= true) then
        return;
    end

    local waypoint = state.active_custom_waypoint(player, map);
    if (waypoint ~= nil) then
        local marker_x, marker_y = state.custom_waypoint_screen(
            left,
            top,
            size,
            camera,
            scale,
            waypoint);
        local delta_x = mouse_x - marker_x;
        local delta_y = mouse_y - marker_y;
        if ((delta_x * delta_x) + (delta_y * delta_y)) <= (14 * 14) then
            state.custom_waypoint = nil;
            state.guide_path.route = nil;
            state.guide_path.last_attempt = 0;
            state.world_path.route = nil;
            state.world_path.last_attempt = 0;
            state.note_manual_waypoint_change(false);
            log('Custom waypoint cleared; AshitaGuide routing restored.');
            return;
        end
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local waypoint_x = camera.x + ((mouse_x - center_x) / scale);
    local waypoint_y = camera.y - ((mouse_y - center_y) / scale);
    local graph = state.path_graph_for(player.zone_id, map.page_id);
    local waypoint_z, floor_ambiguous = state.path_waypoint_z(
        graph,
        waypoint_x,
        waypoint_y,
        player.x,
        player.y,
        player.z);
    state.custom_waypoint = {
        zone_id = player.zone_id,
        page_id = tonumber(map.page_id),
        map_id = tonumber(map.page_id),
        x = waypoint_x,
        y = waypoint_y,
        z = waypoint_z,
        floor_ambiguous = floor_ambiguous,
        source = 'custom',
    };
    state.guide_path.route = nil;
    state.guide_path.last_attempt = 0;
    state.world_path.route = nil;
    state.world_path.last_attempt = 0;
    state.note_manual_waypoint_change(true);
    log(string.format(
        floor_ambiguous
            and 'Custom waypoint set at %.1f, %.1f; overlapping floors are ambiguous, so no path will be drawn.'
            or 'Custom waypoint set at %.1f, %.1f (z %s); it overrides AshitaGuide routing.',
        state.custom_waypoint.x,
        state.custom_waypoint.y,
        state.custom_waypoint.z ~= nil
            and string.format('%.1f', state.custom_waypoint.z)
            or 'unknown'));
end

local function handle_map_input(left, top, size, map, suppress_input)
    local hovered, mouse_x, mouse_y = mouse_over_map(left, top, size);
    local wheel = hovered and suppress_input ~= true
        and safe_read(function () return tonumber(imgui.GetIO().MouseWheel) or 0; end, 0)
        or 0;
    if (wheel ~= 0) then
        local factor = ZOOM_STEP ^ math.abs(wheel);
        local minimum_zoom = zoom_minimum_for_map(map, size);
        local current = clamp(state.settings.pixels_per_yalm, minimum_zoom, ZOOM_MAX);
        state.settings.pixels_per_yalm = clamp(
            wheel > 0 and (current * factor) or (current / factor),
            minimum_zoom,
            ZOOM_MAX);
        mark_configuration_changed();
    end

    if (state.settings.locked == true) then
        state.dragging = false;
        return hovered;
    end

    if (hovered
            and suppress_input ~= true
            and safe_read(function ()
                return imgui.IsMouseClicked(0);
            end, false) == true) then
        state.dragging = true;
        state.drag_offset_x = mouse_x - (tonumber(state.settings.x) or DEFAULTS.x);
        state.drag_offset_y = mouse_y - (tonumber(state.settings.y) or DEFAULTS.y);
    end

    if (state.dragging == true) then
        if (safe_read(function () return imgui.IsMouseDown(0); end, false) == true) then
            local next_x = math.floor((mouse_x - state.drag_offset_x) + 0.5);
            local next_y = math.floor((mouse_y - state.drag_offset_y) + 0.5);
            if (next_x ~= state.settings.x or next_y ~= state.settings.y) then
                state.settings.x = next_x;
                state.settings.y = next_y;
                mark_configuration_changed();
            end
        else
            state.dragging = false;
        end
    end

    return hovered;
end

local function draw_unlocked_hint(draw_list, left, top, size)
    if (state.settings.locked == true) then
        return;
    end
    local label = 'UNLOCKED - DRAG TO MOVE';
    local width = 174;
    local x = left + ((size - width) / 2);
    local y = top + size - 27;
    draw_list:AddRectFilled(
        { x, y },
        { x + width, y + 21 },
        color('badge', { 0.025, 0.055, 0.070, 0.88 }),
        3.0);
    draw_list:AddRect(
        { x, y },
        { x + width, y + 21 },
        color('border', { 0.67, 0.47, 0.22, 0.90 }),
        3.0,
        0,
        1.0);
    draw_list:AddText(
        { x + 10, y + 3 },
        color('grid_text', { 0.82, 0.71, 0.51, 0.88 }),
        label);
end

local function render_minimap()
    if (state.settings.visible ~= true or spectralfocus_modal.is_equipment()) then
        return;
    end
    local player = current_player();
    if (player == nil) then
        return;
    end

    local map = map_for_player(player);
    if (map == nil) then
        if (state.warned_zones[player.zone_id] ~= true) then
            state.warned_zones[player.zone_id] = true;
            log(string.format(
                'No authored or imported vanilla map for zone %d.',
                player.zone_id));
        end
        return;
    end
    local vanilla_image = map.vanilla_image;
    local vanilla_texture = state.settings.show_map_vanilla == true
        and texture_for(vanilla_image)
        or nil;
    local structure_layers = {};
    local force_structure_overlay = map.force_structure_overlay == true;
    local draw_structure = force_structure_overlay
        or (STRUCTURE_RENDERING_ENABLED
            and state.settings.show_map_structure == true);
    local structure_opacity = force_structure_overlay
        and clamp(map.force_structure_opacity or 0.72, 0, 1)
        or state.settings.structure_opacity;
    local inactive_structure_opacity = force_structure_overlay
        and clamp(map.force_inactive_structure_opacity
            or structure_opacity, 0, 1)
        or state.settings.inactive_floor_opacity;
    if (draw_structure) then
        if (type(map.structure_layers) == 'table') then
            for _, layer in ipairs(map.structure_layers) do
                local image = type(layer) == 'table' and layer.image or layer;
                local texture = type(image) == 'string'
                    and texture_for(image)
                    or nil;
                if (texture ~= nil) then
                    local opacity = type(layer) == 'table'
                        and clamp(layer.opacity or 1, 0, 1)
                        or 1;
                    if (type(layer) == 'table') then
                        local player_z = tonumber(player.z);
                        local is_bounded, is_current_floor =
                            floor_layer_matches_z(layer, player_z);
                        if (is_bounded and player_z ~= nil) then
                            opacity = opacity * (is_current_floor
                                and structure_opacity
                                or inactive_structure_opacity);
                        else
                            opacity = opacity * structure_opacity;
                        end
                    else
                        opacity = opacity * structure_opacity;
                    end
                    structure_layers[#structure_layers + 1] = {
                        texture = texture,
                        opacity = opacity,
                        role = type(layer) == 'table' and layer.role or nil,
                        overview_opacity = type(layer) == 'table'
                            and layer.overview_opacity
                            or nil,
                        close_opacity = type(layer) == 'table'
                            and layer.close_opacity
                            or nil,
                        close_zoom_ratio = type(layer) == 'table'
                            and layer.close_zoom_ratio
                            or nil,
                        visibility_boost = type(layer) == 'table'
                            and layer.visibility_boost
                            or nil,
                    };
                end
            end
        else
            local texture = texture_for(map.structure_image or map.image);
            if (texture ~= nil) then
                structure_layers[1] = {
                    texture = texture,
                    opacity = structure_opacity,
                };
            end
        end
    end

    local size = clamp(state.settings.size, 120, 700);
    local minimum_zoom = zoom_minimum_for_map(map, size);
    local scale = clamp(state.settings.pixels_per_yalm, minimum_zoom, ZOOM_MAX);
    local window_flags = bit.bor(
        bit.lshift(1, 0),  -- NoTitleBar
        bit.lshift(1, 1),  -- NoResize
        bit.lshift(1, 2),  -- NoMove (movement is handled explicitly)
        bit.lshift(1, 3),  -- NoScrollbar
        bit.lshift(1, 7),  -- NoBackground
        bit.lshift(1, 8),  -- NoSavedSettings
        bit.lshift(1, 9),  -- NoMouseInputs (read hover/wheel without blocking the game)
        bit.lshift(1, 12), -- NoFocusOnAppearing
        bit.lshift(1, 13), -- NoBringToFrontOnFocus
        bit.lshift(1, 18), -- NoNavInputs
        bit.lshift(1, 19));-- NoNavFocus

    local window_x = tonumber(state.settings.x) or 18;
    local window_y = tonumber(state.settings.y) or 128;
    if (spectralfocus_modal.is_decision()) then
        window_y = math.max(
            tonumber(state.settings.x) or 10,
            DECISION_SELECTOR_TOP - DECISION_SELECTOR_GUTTER - (size + 16));
    elseif (spectralfocus_modal.is_inventory()) then
        window_y = math.min(
            window_y,
            math.max(
                tonumber(state.settings.x) or 10,
                INVENTORY_PREVIEW_TOP - INVENTORY_PREVIEW_GUTTER - (size + 16)));
    elseif (player_is_engaged(player) or spectralfocus_modal.is_command_menu()) then
        window_y = math.max(
            tonumber(state.settings.x) or 10,
            COMBAT_SELECTOR_TOP - COMBAT_SELECTOR_GUTTER - (size + 16));
    end
    local display_size = safe_read(function () return imgui.GetIO().DisplaySize; end, nil);
    local display_height = display_size ~= nil and tonumber(display_size.y) or nil;
    local native_chat_top = safe_read(function ()
        return state.native_chat.top_screen_y(display_height);
    end, nil);
    if (native_chat_top ~= nil) then
        window_y = math.max(
            10,
            math.min(window_y, native_chat_top - 8 - (size + 8)));
    end
    window_y = animated_window_y(window_y);
    imgui.SetNextWindowPos({ window_x, window_y }, 0);
    -- The Ashita ImGui binding applies 8 px of default window padding. Account
    -- for it so the requested map square is not clipped on the right or bottom.
    imgui.SetNextWindowSize({ size + 16, size + 16 }, 0);
    if (type(imgui.SetNextWindowBgAlpha) == 'function') then
        imgui.SetNextWindowBgAlpha(0.0);
    end

    if (imgui.Begin('##ashitaminimap_overlay', true, window_flags)) then
        local left, top = imgui.GetCursorScreenPos();
        local atlas_toggle_hovered = update_atlas_toggle_hover(
            left,
            top,
            size);
        local hovered = handle_map_input(
            left,
            top,
            size,
            map,
            atlas_toggle_hovered);
        local hover_focus = update_hover_focus(hovered);
        minimum_zoom = zoom_minimum_for_map(map, size);
        scale = clamp(state.settings.pixels_per_yalm, minimum_zoom, ZOOM_MAX);
        if (state.settings.pixels_per_yalm ~= scale) then
            state.settings.pixels_per_yalm = scale;
            mark_configuration_changed();
        end
        local camera = camera_for_map(player, map, size, scale);
        handle_custom_waypoint_input(
            left,
            top,
            size,
            player,
            map,
            camera,
            scale,
            atlas_toggle_hovered);
        local visual_scale = marker_zoom_scale(scale);
        local entity_visual_scale = visual_scale
            * clamp(state.settings.marker_size, 0.25, 2.00);
        local draw_list = imgui.GetWindowDrawList();
        draw_map_backdrop(draw_list, left, top, size, hover_focus);
        if (vanilla_texture ~= nil) then
            draw_map_layer(
                draw_list,
                left,
                top,
                size,
                camera,
                map,
                vanilla_texture,
                scale,
                focused_opacity(state.settings.vanilla_opacity, hover_focus),
                1);
        end
        for _, layer in ipairs(structure_layers) do
            local zoom_opacity = layer_zoom_opacity(
                layer,
                scale,
                minimum_zoom);
            local visibility_boost = tonumber(layer.visibility_boost)
                or (layer.role == 'floor_transition'
                    and 1
                    or state.settings.structure_visibility_boost);
            draw_map_layer(
                draw_list,
                left,
                top,
                size,
                camera,
                map,
                layer.texture,
                scale,
                focused_opacity(layer.opacity * zoom_opacity, hover_focus),
                visibility_boost);
        end
        -- NM ranges sit immediately above the vanilla and authored pathing
        -- layers. The grid and every marker type remain clearly above them.
        local nm_spawn_hover = draw_nm_spawn_ranges(
            draw_list,
            left,
            top,
            size,
            camera,
            map,
            scale,
            player,
            state.settings.show_nm_spawn_ranges,
            true);
        state.draw_all_pathing(
            draw_list,
            left,
            top,
            size,
            player,
            camera,
            map,
            scale);
        draw_grid(draw_list, left, top, size, camera, map, scale);
        draw_treasure_spawns(
            draw_list,
            left,
            top,
            size,
            camera,
            map,
            scale,
            player.z,
            player.zone_id);
        draw_travel_references(
            draw_list,
            left,
            top,
            size,
            camera,
            map,
            scale,
            player.z,
            player.zone_id);
        local guide_route = state.draw_guide_path(
            draw_list,
            left,
            top,
            size,
            player,
            camera,
            map,
            scale);
        draw_entities(
            draw_list,
            left,
            top,
            size,
            player,
            camera,
            map,
            scale,
            entity_visual_scale);
        draw_widescan_target(
            draw_list,
            left,
            top,
            size,
            player,
            camera,
            map,
            scale,
            entity_visual_scale);
        state.draw_guide_markers(
            draw_list,
            left,
            top,
            size,
            player,
            camera,
            map,
            scale);
        local player_screen_x = left + (size / 2) + ((player.x - camera.x) * scale);
        local player_screen_y = top + (size / 2) - ((player.y - camera.y) * scale);
        draw_player(
            draw_list,
            player_screen_x,
            player_screen_y,
            player.yaw,
            visual_scale);
        state.draw_guide_path_status(
            draw_list,
            left,
            top,
            size,
            guide_route);
        state.draw_custom_waypoint(
            draw_list,
            left,
            top,
            size,
            player,
            camera,
            map,
            scale);
        if (nm_spawn_hover ~= nil) then
            draw_nm_spawn_range_card(
                draw_list,
                left,
                top,
                size,
                nm_spawn_hover.x,
                nm_spawn_hover.y,
                nm_spawn_hover.reference,
                1);
        end
        draw_badge(draw_list, left, top, player, map);
        draw_environment_clock(draw_list, left, top, size);
        draw_weather_badge(draw_list, left, top, size);
        draw_unlocked_hint(draw_list, left, top, size);
        draw_atlas_toggle_button(
            draw_list,
            left,
            top,
            size,
            atlas_toggle_hovered);
        draw_list:AddRect(
            { left, top },
            { left + size, top + size },
            color('border', { 0.67, 0.47, 0.22, 0.90 }),
            MAP_CORNER_RADIUS,
            ImDrawCornerFlags_All,
            1.0);
        imgui.Dummy({ size, size });
    end
    imgui.End();
    render_atlas_toggle_capture();
end

local function config_checkbox(label, key)
    local value = state.settings[key] == true;
    if (imgui.Checkbox(label, { value })) then
        state.settings[key] = not value;
        if (key == 'locked' and state.settings.locked == true) then
            state.dragging = false;
        end
        mark_configuration_changed();
    end
end

local function render_config_window()
    if (state.config_visible[1] ~= true) then
        return;
    end

    local first_use = rawget(_G, 'ImGuiCond_FirstUseEver') or 0;
    imgui.SetNextWindowSize({ 410, 0 }, first_use);
    local flags = bit.lshift(1, 5); -- NoCollapse
    if (imgui.Begin('AshitaMinimap Config###AshitaMinimapConfig', state.config_visible, flags)) then
        local tabs_supported = type(imgui.BeginTabBar) == 'function'
            and type(imgui.BeginTabItem) == 'function'
            and type(imgui.EndTabItem) == 'function'
            and type(imgui.EndTabBar) == 'function';
        local tab_bar_open = tabs_supported
            and imgui.BeginTabBar('##ashitaminimap_config_tabs')
            or false;
        local map_tab_open = not tabs_supported
            or (tab_bar_open
                and imgui.BeginTabItem('Map##ashitaminimap_config_map'));
        if (map_tab_open) then
        imgui.Text('Map');
        imgui.Separator();
        config_checkbox('Show minimap##ashitaminimap_visible', 'visible');
        config_checkbox('Lock map position##ashitaminimap_locked', 'locked');
        if (state.settings.locked == true) then
            imgui.TextColored({ 0.65, 0.68, 0.70, 1.00 }, 'Unlock to drag the map.');
        else
            imgui.TextColored({ 1.00, 0.71, 0.20, 1.00 }, 'Drag anywhere on the map to move it.');
        end
        imgui.Text(string.format(
            'Position: %d, %d',
            math.floor(tonumber(state.settings.x) or DEFAULTS.x),
            math.floor(tonumber(state.settings.y) or DEFAULTS.y)));

        local size_buffer = { math.floor(clamp(state.settings.size, 120, 700) + 0.5) };
        if (imgui.SliderInt('Map size##ashitaminimap_size', size_buffer, 120, 700, '%d px')) then
            state.settings.size = size_buffer[1];
            mark_configuration_changed();
        end

        local config_player = current_player();
        local config_map = map_for_player(config_player);
        local config_zoom_minimum = zoom_minimum_for_map(
            config_map,
            clamp(state.settings.size, 120, 700));
        local zoom_buffer = {
            clamp(state.settings.pixels_per_yalm, config_zoom_minimum, ZOOM_MAX),
        };
        if (imgui.SliderFloat(
                'Zoom##ashitaminimap_zoom',
                zoom_buffer,
                config_zoom_minimum,
                ZOOM_MAX,
                '%.2f px/yalm')) then
            state.settings.pixels_per_yalm = zoom_buffer[1];
            mark_configuration_changed();
        end
        imgui.TextColored({ 0.65, 0.68, 0.70, 1.00 }, 'Mouse wheel over the map also changes zoom.');
        if (config_map ~= nil and config_map.page_id ~= nil) then
            local manual_page = config_player ~= nil
                and state.settings.map_pages[config_player.zone_id]
                or nil;
            imgui.TextColored(
                { 0.65, 0.68, 0.70, 1.00 },
                string.format(
                    'Vanilla page: %d (%s)',
                    config_map.page_id,
                    manual_page ~= nil and 'manual' or 'automatic'));
        end
        if (imgui.Button('Open Atlas##ashitaminimap_open_atlas', { 104, 0 })) then
            state.atlas.visible[1] = true;
        end

        if (SHOW_MAP_CALIBRATION and config_player ~= nil and config_map ~= nil) then
            local page_key = map_page_key(config_map);
            if (state.origin_editor.zone_id ~= config_player.zone_id
                    or state.origin_editor.page_key ~= page_key) then
                local adjustment = saved_origin_adjustment(
                    config_player.zone_id,
                    page_key);
                state.origin_editor.zone_id = config_player.zone_id;
                state.origin_editor.page_key = page_key;
                state.origin_editor.x = adjustment.x;
                state.origin_editor.y = adjustment.y;
            end

            imgui.Text('Map calibration');
            imgui.Separator();
            imgui.Text(string.format(
                '%s / %s',
                config_map.name or zone_name(config_player.zone_id),
                page_key >= 0 and ('page ' .. tostring(page_key)) or 'authored map'));
            local origin_x_buffer = { clamp(state.origin_editor.x, -512, 512) };
            if (imgui.SliderFloat(
                    'Origin X adjustment##ashitaminimap_origin_x',
                    origin_x_buffer,
                    -512,
                    512,
                    '%.1f px')) then
                state.origin_editor.x = origin_x_buffer[1];
            end
            local origin_y_buffer = { clamp(state.origin_editor.y, -512, 512) };
            if (imgui.SliderFloat(
                    'Origin Y adjustment##ashitaminimap_origin_y',
                    origin_y_buffer,
                    -512,
                    512,
                    '%.1f px')) then
                state.origin_editor.y = origin_y_buffer[1];
            end
            imgui.TextColored(
                { 0.65, 0.68, 0.70, 1.00 },
                'Ctrl-click a slider to type an exact source-pixel value.');
            imgui.TextColored(
                { 0.65, 0.68, 0.70, 1.00 },
                string.format(
                    'Base origin %.1f, %.1f  |  Live %.1f, %.1f',
                    tonumber(config_map.base_origin_x) or 0,
                    tonumber(config_map.base_origin_y) or 0,
                    tonumber(config_map.origin_adjustment_x) or 0,
                    tonumber(config_map.origin_adjustment_y) or 0));
            if (config_map.live_origin == true) then
                imgui.TextColored(
                    { 0.65, 0.68, 0.70, 1.00 },
                    'Base origin and map scale are computed from stock map state.');
            end
            if (imgui.Button('Save calibration##ashitaminimap_origin_save', { 140, 0 })) then
                local zones = state.settings.origin_adjustments;
                zones[config_player.zone_id] = type(zones[config_player.zone_id]) == 'table'
                    and zones[config_player.zone_id]
                    or {};
                zones[config_player.zone_id][page_key] = {
                    x = state.origin_editor.x,
                    y = state.origin_editor.y,
                };
                mark_configuration_changed();
                local ok, message = save_configuration();
                log(ok
                    and string.format(
                        'Saved %s page %s origin adjustment: x %.1f px, y %.1f px.',
                        config_map.name or zone_name(config_player.zone_id),
                        page_key >= 0 and tostring(page_key) or 'authored',
                        state.origin_editor.x,
                        state.origin_editor.y)
                    or ('Could not save calibration: ' .. message));
            end
            imgui.TextColored(
                { 0.65, 0.68, 0.70, 1.00 },
                'Sliders preview live. Reload discards changes until saved.');
        end

        imgui.Text('Static layers');
        imgui.Separator();
        config_checkbox('Vanilla map##ashitaminimap_vanilla', 'show_map_vanilla');
        local vanilla_opacity_buffer = {
            math.floor(clamp(state.settings.vanilla_opacity, 0, 1) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Vanilla opacity##ashitaminimap_vanilla_opacity',
                vanilla_opacity_buffer,
                0,
                100,
                '%d%%')) then
            state.settings.vanilla_opacity = vanilla_opacity_buffer[1] / 100;
            mark_configuration_changed();
        end

        local backdrop_buffer = {
            math.floor(clamp(state.settings.backdrop_opacity, 0, 0.75) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Dark backdrop##ashitaminimap_backdrop',
                backdrop_buffer,
                0,
                75,
                '%d%%')) then
            state.settings.backdrop_opacity = backdrop_buffer[1] / 100;
            mark_configuration_changed();
        end
        imgui.TextColored(
            { 0.65, 0.68, 0.70, 1.00 },
            'Set backdrop to 0% to keep the unused map area fully clear.');

        imgui.Text('Markers');
        imgui.Separator();
        config_checkbox('Coordinate grid##ashitaminimap_grid', 'show_grid');
        config_checkbox('Coordinate badge##ashitaminimap_coordinate', 'show_coordinate');
        config_checkbox(
            'Numeric X/Y/Z in badge##ashitaminimap_numeric_coordinates',
            'show_numeric_coordinates');
        config_checkbox(
            'Vana time, day, moon, and weather##ashitaminimap_environment_clock',
            'show_environment_clock');
        config_checkbox(
            'Compact weather badge##ashitaminimap_weather_badge',
            'show_weather_badge');
        config_checkbox(
            'Possible treasure spawns##ashitaminimap_coffer_spawns',
            'show_coffer_spawns');
        config_checkbox(
            'Home Points and Survival Guides##ashitaminimap_travel_references',
            'show_travel_references');
        config_checkbox(
            'NM spawn ranges##ashitaminimap_nm_spawn_ranges',
            'show_nm_spawn_ranges');
        config_checkbox(
            'AshitaGuide shortest path##ashitaminimap_guide_paths',
            'show_guide_paths');
        imgui.TextColored(
            { 0.65, 0.68, 0.70, 1.00 },
            'Right-click map to set a waypoint; right-click it to clear.');
        config_checkbox('Players##ashitaminimap_players', 'show_players');
        config_checkbox('NPCs##ashitaminimap_npcs', 'show_npcs');
        config_checkbox('Monsters##ashitaminimap_monsters', 'show_monsters');
        config_checkbox(
            'Tracked Wide Scan target##ashitaminimap_widescan_target',
            'show_widescan_target');
        config_checkbox(
            'Scale dynamic markers with zoom##ashitaminimap_scale_markers',
            'scale_markers_with_zoom');
        local marker_size_buffer = {
            math.floor(clamp(state.settings.marker_size, 0.25, 2.00) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Marker size##ashitaminimap_marker_size',
                marker_size_buffer,
                25,
                200,
                '%d%%')) then
            state.settings.marker_size = marker_size_buffer[1] / 100;
            mark_configuration_changed();
        end
        imgui.TextColored(
            { 0.65, 0.68, 0.70, 1.00 },
            'Zoom scaling controls entity dots, target rings, and the player arrow.');
        imgui.TextColored(
            { 0.65, 0.68, 0.70, 1.00 },
            'Marker size controls entity dots and target rings only.');

        if (imgui.Button('Save##ashitaminimap_save', { 92, 0 })) then
            local ok, message = save_configuration();
            log(ok and ('Saved configuration to ' .. message .. '.') or ('Could not save configuration: ' .. message));
        end
        imgui.SameLine(0, 8);
        if (imgui.Button('Reset position##ashitaminimap_reset_position', { 120, 0 })) then
            state.settings.x = DEFAULTS.x;
            state.settings.y = DEFAULTS.y;
            mark_configuration_changed();
        end
        end
        if (tabs_supported and map_tab_open) then
            imgui.EndTabItem();
        end

        if (tab_bar_open
                and imgui.BeginTabItem(
                    'Developer##ashitaminimap_config_developer')) then
            imgui.Text('Developer mode');
            imgui.Separator();
            config_checkbox(
                'Enable developer mode##ashitaminimap_developer_mode',
                'developer_mode');
            imgui.TextColored(
                { 1.00, 0.71, 0.20, 1.00 },
                'Display diagnostics only. No movement or gameplay actions.');

            if (state.settings.developer_mode == true) then
                imgui.Spacing();
                config_checkbox(
                    'Show all pathing##ashitaminimap_show_all_pathing',
                    'show_all_pathing');
                imgui.TextColored(
                    { 0.65, 0.68, 0.70, 1.00 },
                    'Draw every node and connection in the active map graph.');
                imgui.TextColored(
                    { 0.65, 0.68, 0.70, 1.00 },
                    'Current-floor edges are bright cyan; other floors are dim.');

                local developer_player = current_player();
                local developer_map = map_for_player(developer_player);
                local developer_graph = developer_player ~= nil
                    and developer_map ~= nil
                    and state.path_graph_for(
                        developer_player.zone_id,
                        developer_map.page_id)
                    or nil;
                if (developer_graph ~= nil) then
                    local edge_count = 0;
                    local seen_edges = {};
                    for node_index, node in ipairs(developer_graph.nodes) do
                        for _, neighbor_index in ipairs(node[4] or {}) do
                            neighbor_index = tonumber(neighbor_index);
                            local edge_key = neighbor_index ~= nil
                                and string.format(
                                    '%d:%d',
                                    math.min(node_index, neighbor_index),
                                    math.max(node_index, neighbor_index))
                                or nil;
                            if (edge_key ~= nil
                                    and seen_edges[edge_key] ~= true) then
                                seen_edges[edge_key] = true;
                                edge_count = edge_count + 1;
                            end
                        end
                    end
                    imgui.Text(string.format(
                        'Active graph: %d nodes, %d connections',
                        #developer_graph.nodes,
                        edge_count));
                else
                    imgui.TextColored(
                        { 0.65, 0.68, 0.70, 1.00 },
                        'No navigation graph is authored for the active page.');
                end
            else
                imgui.TextColored(
                    { 0.65, 0.68, 0.70, 1.00 },
                    'Enable developer mode to reveal diagnostic controls.');
            end
            imgui.EndTabItem();
        end
        if (tab_bar_open) then
            imgui.EndTabBar();
        end
    end
    imgui.End();
end

local function available_page_ids(zone_id)
    local zone = state.vanilla_maps[zone_id];
    local result = {};
    if (type(zone) == 'table' and type(zone.pages) == 'table') then
        for page_id in pairs(zone.pages) do
            result[#result + 1] = tonumber(page_id);
        end
    end
    table.sort(result);
    return result;
end

local function select_map_page(mode)
    local player = current_player();
    if (player == nil) then
        log('Cannot select a map page before player state is available.');
        return;
    end
    local page_ids = available_page_ids(player.zone_id);
    if (#page_ids == 0) then
        log(string.format('No imported vanilla pages for zone %d.', player.zone_id));
        return;
    end
    if (mode == 'auto') then
        state.settings.map_pages[player.zone_id] = nil;
        mark_configuration_changed();
        local map = map_for_player(player);
        log(string.format(
            'Vanilla page selection is automatic%s.',
            map ~= nil and map.page_id ~= nil
                and (' (page ' .. tostring(map.page_id) .. ')')
                or ''));
        return;
    end

    local map = map_for_player(player);
    local current = map ~= nil and tonumber(map.page_id) or page_ids[1];
    local selected = tonumber(mode);
    if (mode == 'next' or mode == 'prev' or mode == 'previous') then
        local current_index = 1;
        for index, page_id in ipairs(page_ids) do
            if (page_id == current) then
                current_index = index;
                break;
            end
        end
        local step = mode == 'next' and 1 or -1;
        selected = page_ids[((current_index - 1 + step) % #page_ids) + 1];
    end
    if (selected == nil) then
        log('Usage: /aminimap page [auto | next | prev | number]');
        return;
    end
    selected = math.floor(selected);
    local zone = state.vanilla_maps[player.zone_id];
    if (zone.pages[selected] == nil) then
        log(string.format(
            'Page %d is unavailable. Available pages: %s.',
            selected,
            table.concat(page_ids, ', ')));
        return;
    end
    state.settings.map_pages[player.zone_id] = selected;
    mark_configuration_changed();
    log(string.format(
        'Selected vanilla page %d for %s.',
        selected,
        zone_name(player.zone_id)));
end

local function available_zone_ids()
    local result = {};
    for zone_id, zone in pairs(state.vanilla_maps) do
        if (tonumber(zone_id) ~= nil
                and type(zone) == 'table'
                and type(zone.pages) == 'table') then
            result[#result + 1] = math.floor(tonumber(zone_id));
        end
    end
    table.sort(result);
    return result;
end

local function atlas_zone_filter_metadata(zone_id)
    local atlas = state.atlas;
    local cached = atlas.filter_metadata[zone_id];
    if (cached ~= nil) then
        return cached;
    end

    local page_ids = available_page_ids(zone_id);
    local catalog_entry = state.path_catalog[zone_id];
    local has_pathing = type(catalog_entry) == 'string'
        or (type(catalog_entry) == 'table' and next(catalog_entry) ~= nil);
    cached = {
        page_count = #page_ids,
        waypoint_ready = nil,
        has_pathing = has_pathing,
    };
    atlas.filter_metadata[zone_id] = cached;
    return cached;
end

local function atlas_zone_waypoint_ready(zone_id, metadata)
    if (metadata.waypoint_ready ~= nil) then
        return metadata.waypoint_ready;
    end
    metadata.waypoint_ready = false;
    for _, page_id in ipairs(available_page_ids(zone_id)) do
        local map = map_for_catalog_page(zone_id, page_id);
        if (map ~= nil and map.waypoint_calibrated == true) then
            metadata.waypoint_ready = true;
            break;
        end
    end
    return metadata.waypoint_ready;
end

local function atlas_search_matches(label, search)
    label = tostring(label or ''):lower();
    search = tostring(search or ''):lower();
    local compact_label = label:gsub('[^%w]', '');
    for term in search:gmatch('%S+') do
        local compact_term = term:gsub('[^%w]', '');
        if (label:find(term, 1, true) == nil
                and (compact_term == ''
                    or compact_label:find(compact_term, 1, true) == nil)) then
            return false;
        end
    end
    return true;
end

local function atlas_filtered_zone_ids()
    local atlas = state.atlas;
    local filters = atlas.filters;
    local search = atlas.search[1];
    local result = {};
    for _, zone_id in ipairs(available_zone_ids()) do
        local metadata = atlas_zone_filter_metadata(zone_id);
        local candidate_label = string.format(
            '%s %d',
            zone_name(zone_id),
            zone_id);
        if (atlas_search_matches(candidate_label, search)
                and (filters.waypoint_ready ~= true
                    or atlas_zone_waypoint_ready(zone_id, metadata))
                and (filters.has_pathing ~= true or metadata.has_pathing)
                and (filters.multiple_pages ~= true
                    or metadata.page_count > 1)) then
            result[#result + 1] = zone_id;
        end
    end
    table.sort(result, function (left, right)
        local left_name = zone_name(left):lower();
        local right_name = zone_name(right):lower();
        return left_name == right_name and left < right
            or left_name < right_name;
    end);
    return result;
end

local function atlas_filter_checkbox(label, key)
    local filters = state.atlas.filters;
    local value = filters[key] == true;
    if (imgui.Checkbox(label, { value })) then
        filters[key] = not value;
    end
end

local function atlas_clear_filters()
    state.atlas.search[1] = '';
    state.atlas.filters.waypoint_ready = false;
    state.atlas.filters.has_pathing = false;
    state.atlas.filters.multiple_pages = false;
end

local function atlas_select_page(page_id)
    local atlas = state.atlas;
    local page_ids = available_page_ids(atlas.zone_id);
    if (#page_ids == 0) then
        atlas.page_id = nil;
        return;
    end
    local zone = state.vanilla_maps[atlas.zone_id];
    page_id = tonumber(page_id)
        or (type(zone) == 'table' and tonumber(zone.default_page) or nil);
    local selected = page_ids[1];
    for _, candidate in ipairs(page_ids) do
        if candidate == page_id then
            selected = candidate;
            break;
        end
    end
    atlas.page_id = selected;
    atlas.camera_x = nil;
    atlas.camera_y = nil;
    atlas.pixels_per_yalm = nil;
    atlas.dragging = false;
end

local function atlas_select_zone(zone_id)
    zone_id = tonumber(zone_id);
    local zone = zone_id ~= nil
        and state.vanilla_maps[math.floor(zone_id)]
        or nil;
    if (type(zone) ~= 'table'
            or type(zone.pages) ~= 'table'
            or next(zone.pages) == nil) then
        return false;
    end
    state.atlas.zone_id = math.floor(zone_id);
    atlas_select_page(nil);
    return true;
end

local function atlas_initialize()
    if (state.atlas.zone_id ~= nil
            and state.atlas.page_id ~= nil
            and map_for_catalog_page(
                state.atlas.zone_id,
                state.atlas.page_id) ~= nil) then
        return true;
    end
    local player = current_player();
    if (player ~= nil and atlas_select_zone(player.zone_id)) then
        local live_map = map_for_player(player);
        if (live_map ~= nil) then
            atlas_select_page(live_map.page_id);
        end
        return true;
    end
    local zones = available_zone_ids();
    return #zones > 0 and atlas_select_zone(zones[1]) or false;
end

local function atlas_step_selection(values, current, step)
    if (#values == 0) then
        return nil;
    end
    local current_index = 1;
    for index, value in ipairs(values) do
        if value == current then
            current_index = index;
            break;
        end
    end
    return values[((current_index - 1 + step) % #values) + 1];
end

local function atlas_reset_camera(map, size)
    local bounds = type(map.view_bounds) == 'table' and map.view_bounds or {};
    local width = tonumber(map.width) or 512;
    local height = tonumber(map.height) or 512;
    local image_scale = tonumber(map.image_pixels_per_yalm) or 0;
    local left = clamp(bounds.left or 0, 0, width);
    local top = clamp(bounds.top or 0, 0, height);
    local right = clamp(bounds.right or width, left, width);
    local bottom = clamp(bounds.bottom or height, top, height);
    local center_image_x = (left + right) / 2;
    local center_image_y = (top + bottom) / 2;
    state.atlas.camera_x = image_scale > 0
        and ((center_image_x - (tonumber(map.origin_x) or (width / 2)))
            / image_scale)
        or 0;
    state.atlas.camera_y = image_scale > 0
        and (((tonumber(map.origin_y) or (height / 2)) - center_image_y)
            / image_scale)
        or 0;
    state.atlas.pixels_per_yalm = zoom_minimum_for_map(map, size);
end

local function atlas_set_waypoint(map, x, y)
    if (map.waypoint_calibrated ~= true) then
        log(string.format(
            'Cannot set an Atlas waypoint on %s page %s until exact map calibration is available.',
            zone_name(state.atlas.zone_id),
            tostring(map.page_id)));
        return;
    end
    local graph = state.path_graph_for(state.atlas.zone_id, map.page_id);
    local waypoint_z, floor_ambiguous = state.path_waypoint_z(
        graph,
        x,
        y,
        nil,
        nil,
        nil,
        true);
    state.custom_waypoint = {
        zone_id = state.atlas.zone_id,
        page_id = tonumber(map.page_id),
        map_id = tonumber(map.page_id),
        x = x,
        y = y,
        z = waypoint_z,
        floor_ambiguous = floor_ambiguous,
        source = 'custom',
    };
    state.guide_path.route = nil;
    state.guide_path.last_attempt = 0;
    state.world_path.route = nil;
    state.world_path.last_attempt = 0;
    state.note_manual_waypoint_change(true);
    log(string.format(
        floor_ambiguous
            and 'Atlas waypoint set in %s at %.1f, %.1f; the floor is ambiguous, so it remains marker-only.'
            or 'Atlas waypoint set in %s at %.1f, %.1f (z %s).',
        zone_name(state.atlas.zone_id),
        x,
        y,
        waypoint_z ~= nil and string.format('%.1f', waypoint_z) or 'unknown'));
end

local function render_atlas_window()
    local atlas = state.atlas;
    if (atlas.visible[1] ~= true or not atlas_initialize()) then
        atlas.window_x = nil;
        atlas.window_y = nil;
        atlas.window_width = nil;
        atlas.window_height = nil;
        return;
    end

    local display_size = safe_read(function ()
        return imgui.GetIO().DisplaySize;
    end, nil);
    local display_height = display_size ~= nil
        and tonumber(display_size.y)
        or 850;
    local canvas_size = clamp(math.floor(display_height - 250), 420, 600);
    local flags = bit.bor(
        bit.lshift(1, 0),  -- NoTitleBar
        bit.lshift(1, 1),  -- NoResize
        bit.lshift(1, 3),  -- NoScrollbar
        bit.lshift(1, 5),  -- NoCollapse
        bit.lshift(1, 6),  -- AlwaysAutoResize
        bit.lshift(1, 7)); -- NoBackground
    if (imgui.Begin(
            'AshitaMinimap Atlas###AshitaMinimapAtlas',
            atlas.visible,
            flags)) then
        atlas.window_x, atlas.window_y = imgui.GetWindowPos();
        atlas.window_width, atlas.window_height = imgui.GetWindowSize();
        local atlas_draw_list = imgui.GetWindowDrawList();
        atlas_draw_list:AddRectFilled(
            { atlas.window_x, atlas.window_y },
            {
                atlas.window_x + atlas.window_width,
                atlas.window_y + atlas.window_height,
            },
            imgui.GetColorU32({ 0.040, 0.052, 0.068, 0.96 }),
            10.0);
        imgui.Text('Find');
        imgui.SameLine(0, 6);
        if (type(imgui.SetNextItemWidth) == 'function') then
            imgui.SetNextItemWidth(canvas_size - 190);
        end
        if (type(imgui.InputText) == 'function') then
            imgui.InputText(
                '##ashitaminimap_atlas_search',
                atlas.search,
                64);
        end
        imgui.SameLine(0, 6);
        local player = current_player();
        if (imgui.Button('Current##ashitaminimap_atlas_current')
                and player ~= nil) then
            atlas_clear_filters();
            atlas_select_zone(player.zone_id);
        end
        imgui.SameLine(0, 6);
        if (imgui.Button('Clear##ashitaminimap_atlas_clear_filters')) then
            atlas_clear_filters();
        end

        atlas_filter_checkbox(
            'Waypoint-ready##ashitaminimap_atlas_filter_waypoint',
            'waypoint_ready');
        imgui.SameLine(0, 12);
        atlas_filter_checkbox(
            'Pathing##ashitaminimap_atlas_filter_pathing',
            'has_pathing');
        imgui.SameLine(0, 12);
        atlas_filter_checkbox(
            'Multi-page##ashitaminimap_atlas_filter_pages',
            'multiple_pages');

        local all_zones = available_zone_ids();
        local zones = atlas_filtered_zone_ids();
        imgui.SameLine(0, 14);
        imgui.Text(string.format('%d / %d maps', #zones, #all_zones));

        if (imgui.Button('<##ashitaminimap_atlas_zone_prev', { 30, 0 })) then
            local selected = atlas_step_selection(
                zones,
                atlas.zone_id,
                -1);
            if (selected ~= nil) then
                atlas_select_zone(selected);
            end
        end
        imgui.SameLine(0, 6);
        local zone_label = string.format(
            '%s (%d)',
            zone_name(atlas.zone_id),
            atlas.zone_id);
        if (type(imgui.SetNextItemWidth) == 'function') then
            imgui.SetNextItemWidth(canvas_size - 72);
        end
        if (type(imgui.BeginCombo) == 'function'
                and imgui.BeginCombo(
                    '##ashitaminimap_atlas_zone',
                    zone_label)) then
            for _, zone_id in ipairs(zones) do
                local selected = zone_id == atlas.zone_id;
                local metadata = atlas_zone_filter_metadata(zone_id);
                local candidate_label = string.format(
                    '%s (%d)%s',
                    zone_name(zone_id),
                    zone_id,
                    metadata.page_count > 1
                        and string.format(' - %d pages', metadata.page_count)
                        or '');
                if (imgui.Selectable(candidate_label, selected)) then
                    atlas_select_zone(zone_id);
                end
                if (selected
                        and type(imgui.SetItemDefaultFocus) == 'function') then
                    imgui.SetItemDefaultFocus();
                end
            end
            if (#zones == 0) then
                imgui.Text('No maps match the current filters.');
            end
            imgui.EndCombo();
        elseif (type(imgui.BeginCombo) ~= 'function') then
            imgui.Text(zone_label);
        end
        imgui.SameLine(0, 6);
        if (imgui.Button('>##ashitaminimap_atlas_zone_next', { 30, 0 })) then
            local selected = atlas_step_selection(
                zones,
                atlas.zone_id,
                1);
            if (selected ~= nil) then
                atlas_select_zone(selected);
            end
        end

        local page_ids = available_page_ids(atlas.zone_id);
        if (imgui.Button('<##ashitaminimap_atlas_page_prev', { 30, 0 })) then
            atlas_select_page(atlas_step_selection(
                page_ids,
                atlas.page_id,
                -1));
        end
        imgui.SameLine(0, 6);
        imgui.Text(string.format(
            'Page %d of %d',
            atlas.page_id,
            #page_ids));
        imgui.SameLine(0, 6);
        if (imgui.Button('>##ashitaminimap_atlas_page_next', { 30, 0 })) then
            atlas_select_page(atlas_step_selection(
                page_ids,
                atlas.page_id,
                1));
        end
        imgui.SameLine(0, 18);
        if (imgui.Button('Reset view##ashitaminimap_atlas_reset')) then
            atlas.camera_x = nil;
        end
        if (state.custom_waypoint ~= nil) then
            imgui.SameLine(0, 6);
            if (imgui.Button(
                    'Clear waypoint##ashitaminimap_atlas_clear')) then
                state.custom_waypoint = nil;
                state.guide_path.route = nil;
                state.guide_path.last_attempt = 0;
                state.world_path.route = nil;
                state.world_path.last_attempt = 0;
                state.note_manual_waypoint_change(false);
                log('Custom waypoint cleared; AshitaGuide routing restored.');
            end
        end
        local show_nm_spawn_ranges = atlas.show_nm_spawn_ranges == true;
        if (imgui.Checkbox(
                'NM spawns##ashitaminimap_atlas_nm_spawns',
                { show_nm_spawn_ranges })) then
            atlas.show_nm_spawn_ranges = not show_nm_spawn_ranges;
        end

        local map = map_for_catalog_page(atlas.zone_id, atlas.page_id);
        if (map ~= nil) then
            if (atlas.camera_x == nil
                    or atlas.camera_y == nil
                    or atlas.pixels_per_yalm == nil) then
                atlas_reset_camera(map, canvas_size);
            end
            local minimum_zoom = zoom_minimum_for_map(map, canvas_size);
            atlas.pixels_per_yalm = clamp(
                atlas.pixels_per_yalm,
                minimum_zoom,
                ZOOM_MAX);
            local left, top = imgui.GetCursorScreenPos();
            local hovered, mouse_x, mouse_y = mouse_over_map(
                left,
                top,
                canvas_size);
            hovered = hovered and safe_read(function ()
                return imgui.IsWindowHovered();
            end, true) == true;
            local wheel = hovered
                and safe_read(function ()
                    return tonumber(imgui.GetIO().MouseWheel) or 0;
                end, 0)
                or 0;
            if (wheel ~= 0) then
                local factor = ZOOM_STEP ^ math.abs(wheel);
                atlas.pixels_per_yalm = clamp(
                    wheel > 0
                        and (atlas.pixels_per_yalm * factor)
                        or (atlas.pixels_per_yalm / factor),
                    minimum_zoom,
                    ZOOM_MAX);
            end
            if (hovered and safe_read(function ()
                    return imgui.IsMouseClicked(0);
                end, false) == true) then
                atlas.dragging = true;
                atlas.drag_mouse_x = mouse_x;
                atlas.drag_mouse_y = mouse_y;
            end
            if (atlas.dragging == true) then
                if (safe_read(function ()
                        return imgui.IsMouseDown(0);
                    end, false) == true) then
                    atlas.camera_x = atlas.camera_x
                        - ((mouse_x - atlas.drag_mouse_x)
                            / atlas.pixels_per_yalm);
                    atlas.camera_y = atlas.camera_y
                        + ((mouse_y - atlas.drag_mouse_y)
                            / atlas.pixels_per_yalm);
                    atlas.drag_mouse_x = mouse_x;
                    atlas.drag_mouse_y = mouse_y;
                else
                    atlas.dragging = false;
                end
            end
            local camera = camera_for_map(
                { x = atlas.camera_x, y = atlas.camera_y },
                map,
                canvas_size,
                atlas.pixels_per_yalm);
            atlas.camera_x = camera.x;
            atlas.camera_y = camera.y;
            if (hovered and safe_read(function ()
                    return imgui.IsMouseClicked(1);
                end, false) == true) then
                local center_x = left + (canvas_size / 2);
                local center_y = top + (canvas_size / 2);
                atlas_set_waypoint(
                    map,
                    camera.x + ((mouse_x - center_x)
                        / atlas.pixels_per_yalm),
                    camera.y - ((mouse_y - center_y)
                        / atlas.pixels_per_yalm));
            end

            local draw_list = imgui.GetWindowDrawList();
            draw_map_backdrop(draw_list, left, top, canvas_size, 0);
            local texture = texture_for(map.vanilla_image);
            if (texture ~= nil) then
                draw_map_layer(
                    draw_list,
                    left,
                    top,
                    canvas_size,
                    camera,
                    map,
                    texture,
                    atlas.pixels_per_yalm,
                    focused_opacity(state.settings.vanilla_opacity, 1),
                    state.settings.vanilla_visibility_boost);
            end
            local atlas_player = player ~= nil
                and player.zone_id == atlas.zone_id
                and player
                or { zone_id = atlas.zone_id };
            local nm_spawn_hover = draw_nm_spawn_ranges(
                draw_list,
                left,
                top,
                canvas_size,
                camera,
                map,
                atlas.pixels_per_yalm,
                atlas_player,
                atlas.show_nm_spawn_ranges,
                false);
            draw_grid(
                draw_list,
                left,
                top,
                canvas_size,
                camera,
                map,
                atlas.pixels_per_yalm);
            local waypoint = state.custom_waypoint;
            if (type(waypoint) == 'table'
                    and waypoint.zone_id == atlas.zone_id
                    and (waypoint.page_id == nil
                        or waypoint.page_id == tonumber(map.page_id))) then
                draw_waypoint_marker(
                    draw_list,
                    left,
                    top,
                    canvas_size,
                    camera,
                    atlas.pixels_per_yalm,
                    waypoint);
            end
            local player = current_player();
            if (player ~= nil
                    and player.zone_id == atlas.zone_id
                    and position_matches_active_stock_page(
                        atlas.zone_id,
                        map,
                        player)) then
                local player_x = left + (canvas_size / 2)
                    + ((player.x - camera.x) * atlas.pixels_per_yalm);
                local player_y = top + (canvas_size / 2)
                    - ((player.y - camera.y) * atlas.pixels_per_yalm);
                if (player_x >= left and player_x <= left + canvas_size
                        and player_y >= top
                        and player_y <= top + canvas_size) then
                    draw_player(
                        draw_list,
                        player_x,
                        player_y,
                        player.yaw,
                        marker_zoom_scale(atlas.pixels_per_yalm));
                end
            end
            if (nm_spawn_hover ~= nil) then
                draw_nm_spawn_range_card(
                    draw_list,
                    left,
                    top,
                    canvas_size,
                    nm_spawn_hover.x,
                    nm_spawn_hover.y,
                    nm_spawn_hover.reference,
                    1);
            end
            draw_list:AddRect(
                { left, top },
                { left + canvas_size, top + canvas_size },
                color('border', { 0.67, 0.47, 0.22, 0.90 }),
                MAP_CORNER_RADIUS,
                ImDrawCornerFlags_All,
                1.0);
            imgui.Dummy({ canvas_size, canvas_size });
            if (map.waypoint_calibrated ~= true) then
                imgui.TextColored(
                    { 1.00, 0.71, 0.20, 1.00 },
                    'Exact calibration is unavailable; waypoint placement is disabled.');
            elseif (hovered) then
                local center_x = left + (canvas_size / 2);
                local center_y = top + (canvas_size / 2);
                local hover_x = camera.x
                    + ((mouse_x - center_x) / atlas.pixels_per_yalm);
                local hover_y = camera.y
                    - ((mouse_y - center_y) / atlas.pixels_per_yalm);
                imgui.Text(string.format(
                    '%s   X %.1f  Y %.1f   Right-click to set waypoint',
                    grid_coordinate(hover_x, hover_y, map),
                    hover_x,
                    hover_y));
            else
                imgui.Text('Drag: pan   Wheel: zoom   Right-click: waypoint');
            end
        else
            imgui.TextColored(
                { 1.00, 0.45, 0.35, 1.00 },
                'This imported map page could not be loaded.');
        end
    end
    imgui.End();
end

local function print_help()
    log('Commands:');
    log('/aminimap show | hide | toggle');
    log('/aminimap config [show | hide | toggle]');
    log('/aminimap lock | unlock | save');
    log('/aminimap zoomin | zoomout');
    log('/aminimap page [auto | next | prev | number]');
    log('/aminimap atlas [show | hide | toggle | zone-id]');
    log('/aminimap grid | reload');
    log('Right-click the map to set a custom waypoint; right-click it to clear.');
end

local function current_zoom_minimum()
    local player = current_player();
    local map = map_for_player(player);
    return zoom_minimum_for_map(map, clamp(state.settings.size, 120, 700));
end

local function handle_command(e)
    local args = e.command:args();
    local name = args[1] and args[1]:lower() or '';
    if (commands[name] ~= true) then
        return;
    end

    e.blocked = true;
    local action = args[2] and args[2]:lower() or 'help';
    if (action == 'show') then
        state.settings.visible = true;
        mark_configuration_changed();
    elseif (action == 'hide') then
        state.settings.visible = false;
        mark_configuration_changed();
    elseif (action == 'toggle') then
        state.settings.visible = not state.settings.visible;
        mark_configuration_changed();
    elseif (action == 'config') then
        local mode = args[3] and args[3]:lower() or 'toggle';
        if (mode == 'show') then
            state.config_visible[1] = true;
        elseif (mode == 'hide') then
            state.config_visible[1] = false;
        elseif (mode == 'toggle') then
            state.config_visible[1] = not state.config_visible[1];
        else
            log('Usage: /aminimap config [show | hide | toggle]');
        end
    elseif (action == 'lock') then
        state.settings.locked = true;
        state.dragging = false;
        mark_configuration_changed();
    elseif (action == 'unlock') then
        state.settings.locked = false;
        mark_configuration_changed();
    elseif (action == 'save') then
        local ok, message = save_configuration();
        log(ok and ('Saved configuration to ' .. message .. '.') or ('Could not save configuration: ' .. message));
    elseif (action == 'zoomin' or action == 'in') then
        local minimum_zoom = current_zoom_minimum();
        state.settings.pixels_per_yalm = clamp(
            state.settings.pixels_per_yalm * ZOOM_STEP,
            minimum_zoom,
            ZOOM_MAX);
        mark_configuration_changed();
    elseif (action == 'zoomout' or action == 'out') then
        local minimum_zoom = current_zoom_minimum();
        state.settings.pixels_per_yalm = clamp(
            state.settings.pixels_per_yalm / ZOOM_STEP,
            minimum_zoom,
            ZOOM_MAX);
        mark_configuration_changed();
    elseif (action == 'page') then
        select_map_page(args[3] and args[3]:lower() or 'next');
    elseif (action == 'atlas') then
        local mode = args[3] and args[3]:lower() or 'toggle';
        local requested_zone = tonumber(mode);
        if (mode == 'show') then
            state.atlas.visible[1] = true;
            atlas_initialize();
        elseif (mode == 'hide') then
            state.atlas.visible[1] = false;
        elseif (mode == 'toggle') then
            state.atlas.visible[1] = not state.atlas.visible[1];
            if (state.atlas.visible[1] == true) then
                atlas_initialize();
            end
        elseif requested_zone ~= nil
                and atlas_select_zone(math.floor(requested_zone)) then
            state.atlas.visible[1] = true;
        else
            log('Usage: /aminimap atlas [show | hide | toggle | zone-id]');
        end
    elseif (action == 'grid') then
        state.settings.show_grid = not state.settings.show_grid;
        mark_configuration_changed();
    elseif (action == 'reload') then
        state.textures = {};
        load_configuration();
        log('Configuration reloaded.');
    else
        print_help();
    end
end

local function packet_value(format, data, offset)
    if (type(data) ~= 'string' or #data < offset) then
        return nil;
    end
    return tonumber(safe_read(function ()
        return struct.unpack(format, data, offset + 1);
    end, nil));
end

local function handle_widescan_packet_in(e)
    if (e.id == 0x000A) then
        state.widescan_target = nil;
        return;
    end
    if (e.id ~= 0x00F5) then
        return;
    end
    local data = e.data_modified or e.data;
    local status = packet_value('L', data, 0x14);
    if (status ~= 1) then
        state.widescan_target = nil;
        return;
    end

    -- Native 0x0F5 Wide Scan updates use client map order: X, Z, Y.
    local x = packet_value('f', data, 0x04);
    local z = packet_value('f', data, 0x08);
    local y = packet_value('f', data, 0x0C);
    local index = packet_value('H', data, 0x12);
    local valid = x ~= nil and y ~= nil and z ~= nil
        and x == x and y == y and z == z
        and math.abs(x) < 100000
        and math.abs(y) < 100000
        and math.abs(z) < 100000;
    if (not valid) then
        state.widescan_target = nil;
        return;
    end
    state.widescan_target = {
        x = x,
        y = y,
        z = z,
        index = index,
    };
end

local function handle_widescan_packet_out(e)
    if (e.id == 0x00F5 or e.id == 0x00F6) then
        -- Clear immediately while the client starts or cancels tracking. The
        -- next native server update repopulates the marker if tracking starts.
        state.widescan_target = nil;
    end
end

ashita.events.register('load', 'load_cb', function ()
    load_configuration();
    state.poll_guide_markers(true);
    state.poll_mcp_waypoint(true);
    state.apply_mcp_waypoint();
    log('Loaded. Use /aminimap help for commands.');
end);

ashita.events.register('unload', 'unload_cb', function ()
    save_configuration_if_due(true);
    state.textures = {};
    state.guide_markers.payload = nil;
    state.mcp_waypoint.pending = nil;
    state.guide_path.route = nil;
    state.world_path.route = nil;
    state.path_graphs = {};
    state.world_catalog = {};
    state.world_topology = nil;
    state.custom_waypoint = nil;
    state.widescan_target = nil;
    state.environment.time_signature_address = 0;
    state.environment.weather_signature_address = 0;
    state.environment.checked_at = 0;
    state.environment.snapshot = nil;
    state.environment.snapshot_at = 0;
    state.device = nil;
    state.config_visible[1] = false;
    state.atlas.visible[1] = false;
end);

ashita.events.register('command', 'command_cb', function (e)
    handle_command(e);
end);

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    handle_widescan_packet_in(e);
end);

ashita.events.register('packet_out', 'packet_out_cb', function (e)
    handle_widescan_packet_out(e);
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    state.poll_guide_markers(false);
    state.poll_mcp_waypoint(false);
    state.apply_mcp_waypoint();
    render_minimap();
    render_atlas_window();
    render_config_window();
    save_configuration_if_due(false);
end);
