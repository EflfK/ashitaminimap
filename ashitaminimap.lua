addon.name      = 'ashitaminimap';
addon.author    = 'EflfK';
addon.version   = '1.13.1';
addon.desc      = 'Transparent Lua-rendered minimap for Ashita v4.';

require('common');

local bit = require('bit');
local d3d8 = require('d3d8');
local ffi = require('ffi');
local imgui = require('imgui');

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
local MAP_CORNER_RADIUS = 7.0;
local SHOW_MAP_CALIBRATION = false;

local DEFAULTS = {
    visible = true,
    locked = true,
    x = 18,
    y = 128,
    size = 330,
    pixels_per_yalm = 4.41,
    show_map_vanilla = true,
    show_map_structure = true,
    vanilla_opacity = 0.35,
    structure_opacity = 0.82,
    inactive_floor_opacity = 0.14,
    structure_visibility_boost = 4,
    backdrop_opacity = 0.12,
    show_grid = true,
    show_coordinate = true,
    show_coffer_spawns = true,
    show_nm_spawn_ranges = true,
    show_guide_paths = true,
    show_players = true,
    show_npcs = true,
    show_monsters = true,
    scale_markers_with_zoom = true,
    marker_size = 1.00,
    map_pages = {},
    origin_adjustments = {},
    colors = {
        border = { 0.67, 0.47, 0.22, 0.90 },
        grid = { 0.48, 0.60, 0.61, 0.25 },
        grid_text = { 0.82, 0.71, 0.51, 0.88 },
        coffer_spawn = { 1.000, 0.820, 0.200, 0.98 },
        nm_spawn_range = { 0.690, 0.145, 0.190, 0.075 },
        nm_spawn_border = { 0.890, 0.660, 0.260, 0.78 },
        player = { 0.18, 0.88, 0.90, 1.00 },
        other_player = { 0.275, 0.553, 1.000, 0.96 },
        npc = { 0.000, 0.784, 0.176, 0.96 },
        monster = { 1.000, 0.275, 0.275, 0.96 },
        target = { 1.00, 0.71, 0.20, 1.00 },
        shadow = { 0.01, 0.02, 0.025, 0.94 },
        badge = { 0.025, 0.055, 0.070, 0.88 },
        backdrop = { 0.010, 0.030, 0.040, 1.00 },
    },
};

local state = {
    settings = DEFAULTS,
    maps = {},
    path_catalog = {},
    path_graphs = {},
    vanilla_maps = {},
    textures = {},
    device = nil,
    warned_zones = {},
    reported_fallback = nil,
    stock_minimap_pointer_address = 0,
    stock_minimap_checked_at = 0,
    stock_map_table_address = 0,
    stock_map_table_checked_at = 0,
    stock_map_records = {},
    config_visible = { false },
    config_dirty = false,
    config_changed_at = 0,
    dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
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
    guide_path = {
        route = nil,
        last_attempt = 0,
        last_error = nil,
    },
    custom_waypoint = nil,
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
        string.format('    show_coffer_spawns = %s,', bool_text(settings.show_coffer_spawns)),
        string.format('    show_nm_spawn_ranges = %s,', bool_text(settings.show_nm_spawn_ranges)),
        string.format('    show_guide_paths = %s,', bool_text(settings.show_guide_paths)),
        string.format('    show_players = %s,', bool_text(settings.show_players)),
        string.format('    show_npcs = %s,', bool_text(settings.show_npcs)),
        string.format('    show_monsters = %s,', bool_text(settings.show_monsters)),
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
        string.format('        coffer_spawn = %s,', color_text(colors.coffer_spawn, DEFAULTS.colors.coffer_spawn)),
        string.format('        nm_spawn_range = %s,', color_text(colors.nm_spawn_range, DEFAULTS.colors.nm_spawn_range)),
        string.format('        nm_spawn_border = %s,', color_text(colors.nm_spawn_border, DEFAULTS.colors.nm_spawn_border)),
        string.format('        player = %s,', color_text(colors.player, DEFAULTS.colors.player)),
        string.format('        other_player = %s,', color_text(colors.other_player, DEFAULTS.colors.other_player)),
        string.format('        npc = %s,', color_text(colors.npc, DEFAULTS.colors.npc)),
        string.format('        monster = %s,', color_text(colors.monster, DEFAULTS.colors.monster)),
        string.format('        target = %s,', color_text(colors.target, DEFAULTS.colors.target)),
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
    validate_structure_layers(state.maps);
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
    if (not ok or type(value) ~= 'table'
            or tonumber(value.version) ~= 1
            or value.source ~= 'ashitaguide') then
        state.guide_markers.last_error = 'invalid marker handoff';
        return;
    end

    local zone_id = tonumber(value.zone_id);
    local updated_at = tonumber(value.updated_at);
    local normalized = {
        zone_id = zone_id ~= nil and math.floor(zone_id) or nil,
        updated_at = updated_at,
        markers = {},
    };
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
                map_id = map_id ~= nil and math.floor(map_id) or nil,
                approximate = marker.approximate == true,
            };
        end
    end
    state.guide_markers.payload = normalized;
    state.guide_markers.last_error = nil;
end

state.active_guide_markers = function (player)
    local payload = state.guide_markers.payload;
    if (type(payload) ~= 'table'
            or payload.zone_id ~= player.zone_id
            or tonumber(payload.updated_at) == nil
            or math.abs(os.time() - payload.updated_at) > 3) then
        return {};
    end
    return payload.markers;
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

state.path_graph_for = function (zone_id)
    if (state.path_graphs[zone_id] ~= nil) then
        return state.path_graphs[zone_id] ~= false
            and state.path_graphs[zone_id]
            or nil;
    end
    local filename = state.path_catalog[zone_id];
    if (type(filename) ~= 'string' or filename == '') then
        state.path_graphs[zone_id] = false;
        return nil;
    end
    local graph, error_message = load_module_file(filename);
    if (type(graph) ~= 'table'
            or tonumber(graph.zone_id) ~= zone_id
            or type(graph.nodes) ~= 'table'
            or #graph.nodes < 2) then
        state.path_graphs[zone_id] = false;
        log(string.format(
            'Invalid path graph for zone %d: %s',
            zone_id,
            tostring(error_message or filename)));
        return nil;
    end
    state.path_graphs[zone_id] = graph;
    return graph;
end

state.path_nearest_node = function (graph, x, y)
    local best_index = nil;
    local best_distance_squared = nil;
    for index, node in ipairs(graph.nodes) do
        local delta_x = (tonumber(node[1]) or 0) - x;
        local delta_y = (tonumber(node[2]) or 0) - y;
        local distance_squared = (delta_x * delta_x) + (delta_y * delta_y);
        if (best_distance_squared == nil or distance_squared < best_distance_squared) then
            best_index = index;
            best_distance_squared = distance_squared;
        end
    end
    local distance = best_distance_squared ~= nil
        and math.sqrt(best_distance_squared)
        or math.huge;
    if (distance > (tonumber(graph.snap_radius) or 24)) then
        return nil, distance;
    end
    return best_index, distance;
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
        return math.sqrt((delta_x * delta_x) + (delta_y * delta_y));
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
                    local edge_cost = math.sqrt(
                        (delta_x * delta_x) + (delta_y * delta_y));
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

state.path_projection = function (route, x, y)
    local best = nil;
    local traveled = 0;
    for index = 1, #route.points - 1 do
        local start = route.points[index];
        local finish = route.points[index + 1];
        local segment_x = finish.x - start.x;
        local segment_y = finish.y - start.y;
        local length_squared = (segment_x * segment_x) + (segment_y * segment_y);
        local ratio = length_squared > 0
            and clamp(
                (((x - start.x) * segment_x) + ((y - start.y) * segment_y))
                    / length_squared,
                0,
                1)
            or 0;
        local projected_x = start.x + (segment_x * ratio);
        local projected_y = start.y + (segment_y * ratio);
        local delta_x = x - projected_x;
        local delta_y = y - projected_y;
        local distance_squared = (delta_x * delta_x) + (delta_y * delta_y);
        local segment_length = math.sqrt(length_squared);
        if (best == nil or distance_squared < best.distance_squared) then
            best = {
                index = index,
                ratio = ratio,
                x = projected_x,
                y = projected_y,
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

state.ensure_guide_path = function (player, map)
    if (state.settings.show_guide_paths ~= true) then
        state.guide_path.route = nil;
        return nil;
    end
    local custom_waypoint = state.active_custom_waypoint(player, map);
    local markers = state.active_guide_markers(player);
    local destination = custom_waypoint or markers[1];
    if (destination == nil
            or (destination.map_id ~= nil
                and tonumber(map.page_id) ~= destination.map_id)) then
        state.guide_path.route = nil;
        return nil;
    end

    local graph = state.path_graph_for(player.zone_id);
    if (graph == nil
            or (graph.page_id ~= nil
                and tonumber(map.page_id) ~= tonumber(graph.page_id))) then
        state.guide_path.route = nil;
        return nil;
    end

    local route = state.guide_path.route;
    local same_destination = route ~= nil
        and route.zone_id == player.zone_id
        and route.destination_source == (custom_waypoint ~= nil and 'custom' or 'guide')
        and math.abs(route.destination_x - destination.x) < 0.1
        and math.abs(route.destination_y - destination.y) < 0.1;
    if (same_destination) then
        local projection = state.path_projection(route, player.x, player.y);
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
        state.path_nearest_node(graph, player.x, player.y);
    local target_index, target_distance =
        state.path_nearest_node(graph, destination.x, destination.y);
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
    local points = { { x = player.x, y = player.y } };
    for _, index in ipairs(indices) do
        local node = graph.nodes[index];
        points[#points + 1] = { x = node[1], y = node[2] };
    end
    points[#points + 1] = { x = destination.x, y = destination.y };
    route = {
        zone_id = player.zone_id,
        destination_x = destination.x,
        destination_y = destination.y,
        destination_source = custom_waypoint ~= nil and 'custom' or 'guide',
        points = points,
    };
    route.projection = state.path_projection(route, player.x, player.y);
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
local STOCK_MAP_ENTRY_SIZE = 0x0E;

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

local function stock_minimap_info()
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
        return nil;
    end
    local runtime = tonumber(safe_read(function ()
        return ashita.memory.read_uint32(pointer_address);
    end, 0)) or 0;
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
    if (type(rules) ~= 'table' or player == nil) then
        return nil;
    end
    local player_x = tonumber(player.x);
    local player_y = tonumber(player.y);
    local player_z = tonumber(player.z);
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
    return nil;
end

local function fallback_page(zone_id, player)
    local zone = state.vanilla_maps[zone_id];
    if (type(zone) ~= 'table' or type(zone.pages) ~= 'table') then
        return nil;
    end
    local manual_page = tonumber(state.settings.map_pages[zone_id]);
    local page_id = manual_page;
    local stock = stock_minimap_info();
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

local function map_for_player(player)
    if (player == nil) then
        return nil;
    end
    local authored = state.maps[player.zone_id];
    local fallback = fallback_page(player.zone_id, player);
    if (authored == nil) then
        return apply_origin_adjustment(fallback, player.zone_id);
    end
    if (fallback == nil) then
        return apply_origin_adjustment(copy_table(authored), player.zone_id);
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
    return apply_origin_adjustment(merged, player.zone_id);
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

local function draw_entities(draw_list, left, top, size, player, camera, scale, visual_scale)
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
                if (x ~= nil and y ~= nil and same_floor) then
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

local function draw_coffer_spawns(
        draw_list,
        left,
        top,
        size,
        camera,
        map,
        scale,
        player_z)
    if (state.settings.show_coffer_spawns ~= true
            or type(map.coffer_spawns) ~= 'table') then
        return;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local active_page = tonumber(map.page_id);
    for _, marker in ipairs(map.coffer_spawns) do
        local marker_page = type(marker) == 'table'
            and tonumber(marker.page_id)
            or nil;
        local x = type(marker) == 'table' and tonumber(marker.x) or nil;
        local y = type(marker) == 'table' and tonumber(marker.y) or nil;
        if (x ~= nil and y ~= nil
                and (marker_page == nil or marker_page == active_page)) then
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
                    'coffer_spawn',
                    { 1.000, 0.820, 0.200, 0.98 },
                    marker_opacity);
                -- A filled gold coffer silhouette distinguishes fixed
                -- possible-spawn references from live entity dots and rings.
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

local function draw_nm_spawn_ranges(
        draw_list,
        left,
        top,
        size,
        camera,
        map,
        scale,
        player_z)
    if (state.settings.show_nm_spawn_ranges ~= true
            or type(map.nm_spawn_ranges) ~= 'table') then
        return;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local active_page = tonumber(map.page_id);
    local mouse_x, mouse_y = imgui.GetMousePos();
    for _, reference in ipairs(map.nm_spawn_ranges) do
        local reference_page = type(reference) == 'table'
            and tonumber(reference.page_id)
            or nil;
        local points = type(reference) == 'table'
            and reference.points
            or nil;
        if (type(points) == 'table'
                and (reference_page == nil or reference_page == active_page)) then
            local floor_opacity = shares_authored_floor(
                map,
                player_z,
                reference.z)
                and 1
                or state.settings.inactive_floor_opacity;
            local fill = color_with_opacity(
                'nm_spawn_range',
                { 0.690, 0.145, 0.190, 0.075 },
                floor_opacity);
            local radius = clamp(
                (tonumber(reference.radius_yalms) or 4.5) * scale,
                3.0,
                14.0);
            local hovered = false;
            local hover_x = nil;
            local hover_y = nil;
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
    if (route == nil or projection == nil) then
        return nil;
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local outline = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local active = imgui.GetColorU32({ 0.10, 0.86, 1.00, 0.96 });
    local traveled = imgui.GetColorU32({ 0.34, 0.40, 0.44, 0.88 });

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

    local projected_point = { x = projection.x, y = projection.y };
    for index = 1, #route.points - 1 do
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
    for index = projection.index, #route.points - 1 do
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
    return route;
end

state.draw_guide_path_status = function (draw_list, left, top, size, route)
    if (route == nil or route.projection == nil or size < 180) then
        return;
    end
    local height = 38;
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
    draw_list:AddText(
        { left + 10, panel_top + 5 },
        text_color,
        string.format(
            '%s   %.0fy remaining',
            route.destination_source == 'custom'
                and 'CUSTOM WAYPOINT'
                or 'GUIDE PATH',
            route.projection.remaining));
    draw_list:AddText(
        { left + 10, panel_top + 21 },
        accent,
        route.destination_source == 'custom'
            and 'Right-click waypoint to clear'
            or 'Shortest route from map navigation graph');
    draw_list:AddText(
        { left + size - 63, panel_top + 21 },
        accent,
        'PATH ON');
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
    if (waypoint == nil) then
        return;
    end
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

state.draw_guide_markers = function (
        draw_list,
        left,
        top,
        size,
        player,
        camera,
        map,
        scale)
    if (state.active_custom_waypoint(player, map) ~= nil) then
        return;
    end
    local current_page = tonumber(map.page_id);
    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local minimum_x = left + 10;
    local maximum_x = left + size - 10;
    local minimum_y = top + 10;
    local maximum_y = top + size - 10;
    local outline = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local pulse = 0.82 + ((math.sin(os.clock() * 5) + 1) * 0.09);
    for _, marker in ipairs(state.active_guide_markers(player)) do
        if (marker.map_id == nil or current_page == marker.map_id) then
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
            if (marker.approximate == true) then
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

local function draw_badge(draw_list, left, top, player, map)
    if (state.settings.show_coordinate ~= true) then
        return;
    end
    local coordinate = grid_coordinate(player.x, player.y, map);
    local label = string.format('%s  %s', coordinate, map.name or ('Zone ' .. tostring(player.zone_id)));
    local width = math.max(66, (#label * 7) + 16);
    local badge_color = color('badge', { 0.025, 0.055, 0.070, 0.88 });
    local border = color('border', { 0.67, 0.47, 0.22, 0.90 });
    local text_color = color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    draw_list:AddRectFilled({ left + 6, top + 6 }, { left + 6 + width, top + 29 }, badge_color, 3.0);
    draw_list:AddRect({ left + 6, top + 6 }, { left + 6 + width, top + 29 }, border, 3.0, 0, 1.0);
    draw_list:AddText({ left + 14, top + 10 }, text_color, label);
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

local function draw_map_backdrop(draw_list, left, top, size)
    local opacity = clamp(state.settings.backdrop_opacity, 0, 0.75);
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
        scale)
    local hovered, mouse_x, mouse_y = mouse_over_map(left, top, size);
    if (not hovered
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
            log('Custom waypoint cleared; AshitaGuide routing restored.');
            return;
        end
    end

    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    state.custom_waypoint = {
        zone_id = player.zone_id,
        page_id = tonumber(map.page_id),
        x = camera.x + ((mouse_x - center_x) / scale),
        y = camera.y - ((mouse_y - center_y) / scale),
    };
    state.guide_path.route = nil;
    state.guide_path.last_attempt = 0;
    log(string.format(
        'Custom waypoint set at %.1f, %.1f; it overrides AshitaGuide routing.',
        state.custom_waypoint.x,
        state.custom_waypoint.y));
end

local function handle_map_input(left, top, size, map)
    local hovered, mouse_x, mouse_y = mouse_over_map(left, top, size);
    local wheel = hovered
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

    if (hovered and safe_read(function () return imgui.IsMouseClicked(0); end, false) == true) then
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
    if (state.settings.visible ~= true) then
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
    if (map.fallback == true and map.page_id ~= nil) then
        local token = string.format(
            '%d:%d:%s:%s',
            player.zone_id,
            map.page_id,
            tostring(map.live_scale == true),
            tostring(map.live_origin == true));
        if (state.reported_fallback ~= token) then
            state.reported_fallback = token;
            log(string.format(
                'Vanilla fallback: %s page %d (%s scale raw %d, %s origin %.1f, %.1f; record offsets %s, %s).',
                map.name or ('zone ' .. tostring(player.zone_id)),
                map.page_id,
                map.live_scale == true and 'stock' or 'default',
                tonumber(map.stock_scale_raw) or 0,
                map.live_origin == true and 'stock' or 'provisional',
                tonumber(map.base_origin_x) or tonumber(map.origin_x) or 0,
                tonumber(map.base_origin_y) or tonumber(map.origin_y) or 0,
                map.stock_offset_x ~= nil and tostring(map.stock_offset_x) or '?',
                map.stock_offset_y ~= nil and tostring(map.stock_offset_y) or '?'));
        end
    end

    local vanilla_image = map.vanilla_image;
    local vanilla_texture = state.settings.show_map_vanilla == true
        and texture_for(vanilla_image)
        or nil;
    local structure_layers = {};
    if (state.settings.show_map_structure == true) then
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
                                and state.settings.structure_opacity
                                or state.settings.inactive_floor_opacity);
                        else
                            opacity = opacity * state.settings.structure_opacity;
                        end
                    else
                        opacity = opacity * state.settings.structure_opacity;
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
                    opacity = state.settings.structure_opacity,
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

    imgui.SetNextWindowPos({ tonumber(state.settings.x) or 18, tonumber(state.settings.y) or 128 }, 0);
    -- The Ashita ImGui binding applies 8 px of default window padding. Account
    -- for it so the requested map square is not clipped on the right or bottom.
    imgui.SetNextWindowSize({ size + 16, size + 16 }, 0);
    if (type(imgui.SetNextWindowBgAlpha) == 'function') then
        imgui.SetNextWindowBgAlpha(0.0);
    end

    if (imgui.Begin('##ashitaminimap_overlay', true, window_flags)) then
        local left, top = imgui.GetCursorScreenPos();
        handle_map_input(left, top, size, map);
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
            scale);
        local visual_scale = marker_zoom_scale(scale);
        local entity_visual_scale = visual_scale
            * clamp(state.settings.marker_size, 0.25, 2.00);
        local draw_list = imgui.GetWindowDrawList();
        draw_map_backdrop(draw_list, left, top, size);
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
                state.settings.vanilla_opacity,
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
                layer.opacity * zoom_opacity,
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
            player.z);
        draw_grid(draw_list, left, top, size, camera, map, scale);
        draw_coffer_spawns(
            draw_list,
            left,
            top,
            size,
            camera,
            map,
            scale,
            player.z);
        local guide_route = state.draw_guide_path(
            draw_list,
            left,
            top,
            size,
            player,
            camera,
            map,
            scale);
        draw_entities(draw_list, left, top, size, player, camera, scale, entity_visual_scale);
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
        draw_unlocked_hint(draw_list, left, top, size);
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

        config_checkbox('Map structure##ashitaminimap_structure', 'show_map_structure');
        local structure_opacity_buffer = {
            math.floor(clamp(state.settings.structure_opacity, 0, 1) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Current floor opacity##ashitaminimap_structure_opacity',
                structure_opacity_buffer,
                0,
                100,
                '%d%%')) then
            state.settings.structure_opacity = structure_opacity_buffer[1] / 100;
            mark_configuration_changed();
        end

        local inactive_floor_opacity_buffer = {
            math.floor(
                clamp(state.settings.inactive_floor_opacity, 0, 1) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Other floors opacity##ashitaminimap_inactive_floor_opacity',
                inactive_floor_opacity_buffer,
                0,
                100,
                '%d%%')) then
            state.settings.inactive_floor_opacity =
                inactive_floor_opacity_buffer[1] / 100;
            mark_configuration_changed();
        end

        local structure_visibility_buffer = {
            math.floor(clamp(state.settings.structure_visibility_boost, 1, 12) + 0.5),
        };
        if (imgui.SliderInt(
                'Structure visibility##ashitaminimap_structure_visibility',
                structure_visibility_buffer,
                1,
                12,
                '%d x')) then
            state.settings.structure_visibility_boost = structure_visibility_buffer[1];
            mark_configuration_changed();
        end

        imgui.TextColored(
            { 0.65, 0.68, 0.70, 1.00 },
            'Vanilla and walkable structure are independent layers.');

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
            'Possible coffer spawns##ashitaminimap_coffer_spawns',
            'show_coffer_spawns');
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

local function print_help()
    log('Commands:');
    log('/aminimap show | hide | toggle');
    log('/aminimap config [show | hide | toggle]');
    log('/aminimap lock | unlock | save');
    log('/aminimap zoomin | zoomout');
    log('/aminimap page [auto | next | prev | number]');
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

ashita.events.register('load', 'load_cb', function ()
    load_configuration();
    state.poll_guide_markers(true);
    log('Loaded. Use /aminimap help for commands.');
end);

ashita.events.register('unload', 'unload_cb', function ()
    save_configuration_if_due(true);
    state.textures = {};
    state.guide_markers.payload = nil;
    state.guide_path.route = nil;
    state.path_graphs = {};
    state.custom_waypoint = nil;
    state.device = nil;
    state.config_visible[1] = false;
end);

ashita.events.register('command', 'command_cb', function (e)
    handle_command(e);
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    state.poll_guide_markers(false);
    render_minimap();
    render_config_window();
    save_configuration_if_due(false);
end);
