addon.name      = 'ashitaminimap';
addon.author    = 'EflfK';
addon.version   = '0.6.3';
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
local MARKER_REFERENCE_ZOOM = 4.41;

local DEFAULTS = {
    visible = true,
    locked = true,
    x = 18,
    y = 128,
    size = 330,
    pixels_per_yalm = 4.41,
    show_map_structure = true,
    show_map_labels = true,
    show_map_landmarks = true,
    structure_opacity = 0.82,
    label_opacity = 1.00,
    landmark_opacity = 1.00,
    structure_visibility_boost = 4,
    label_visibility_boost = 4,
    landmark_visibility_boost = 4,
    backdrop_opacity = 0.12,
    show_grid = true,
    show_coordinate = true,
    show_players = true,
    show_npcs = true,
    show_monsters = true,
    show_names = false,
    scale_markers_with_zoom = true,
    marker_size = 1.00,
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
};

local state = {
    settings = DEFAULTS,
    maps = {},
    textures = {},
    device = nil,
    warned_zones = {},
    config_visible = { false },
    config_dirty = false,
    config_changed_at = 0,
    dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
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
        '    -- Independently composited static map layers.',
        string.format('    show_map_structure = %s,', bool_text(settings.show_map_structure)),
        string.format('    show_map_labels = %s,', bool_text(settings.show_map_labels)),
        string.format('    show_map_landmarks = %s,', bool_text(settings.show_map_landmarks)),
        string.format('    structure_opacity = %.3f,', clamp(settings.structure_opacity, 0, 1)),
        string.format('    label_opacity = %.3f,', clamp(settings.label_opacity, 0, 1)),
        string.format('    landmark_opacity = %.3f,', clamp(settings.landmark_opacity, 0, 1)),
        string.format(
            '    structure_visibility_boost = %d,',
            math.floor(clamp(settings.structure_visibility_boost, 1, 12) + 0.5)),
        string.format(
            '    label_visibility_boost = %d,',
            math.floor(clamp(settings.label_visibility_boost, 1, 12) + 0.5)),
        string.format(
            '    landmark_visibility_boost = %d,',
            math.floor(clamp(settings.landmark_visibility_boost, 1, 12) + 0.5)),
        string.format('    backdrop_opacity = %.3f,', clamp(settings.backdrop_opacity, 0, 0.75)),
        '',
        string.format('    show_grid = %s,', bool_text(settings.show_grid)),
        string.format('    show_coordinate = %s,', bool_text(settings.show_coordinate)),
        string.format('    show_players = %s,', bool_text(settings.show_players)),
        string.format('    show_npcs = %s,', bool_text(settings.show_npcs)),
        string.format('    show_monsters = %s,', bool_text(settings.show_monsters)),
        string.format('    show_names = %s,', bool_text(settings.show_names)),
        string.format('    scale_markers_with_zoom = %s,', bool_text(settings.scale_markers_with_zoom)),
        string.format('    marker_size = %.2f,', clamp(settings.marker_size, 0.25, 2.00)),
        '',
        '    colors = {',
        string.format('        border = %s,', color_text(colors.border, DEFAULTS.colors.border)),
        string.format('        grid = %s,', color_text(colors.grid, DEFAULTS.colors.grid)),
        string.format('        grid_text = %s,', color_text(colors.grid_text, DEFAULTS.colors.grid_text)),
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
    if (settings.label_visibility_boost == nil and settings.map_visibility_boost ~= nil) then
        state.settings.label_visibility_boost = settings.map_visibility_boost;
    end
    state.settings.size = clamp(state.settings.size, 120, 700);
    state.settings.pixels_per_yalm = clamp(state.settings.pixels_per_yalm, ZOOM_MIN, ZOOM_MAX);
    state.settings.structure_opacity = clamp(state.settings.structure_opacity, 0, 1);
    state.settings.label_opacity = clamp(state.settings.label_opacity, 0, 1);
    state.settings.landmark_opacity = clamp(state.settings.landmark_opacity, 0, 1);
    state.settings.structure_visibility_boost =
        math.floor(clamp(state.settings.structure_visibility_boost, 1, 12) + 0.5);
    state.settings.label_visibility_boost =
        math.floor(clamp(state.settings.label_visibility_boost, 1, 12) + 0.5);
    state.settings.landmark_visibility_boost =
        math.floor(clamp(state.settings.landmark_visibility_boost, 1, 12) + 0.5);
    state.settings.backdrop_opacity = clamp(state.settings.backdrop_opacity, 0, 0.75);
    state.settings.marker_size = clamp(state.settings.marker_size, 0.25, 2.00);
    state.config_dirty = false;
    state.dragging = false;
    if (settings_error ~= nil) then
        log('Config warning: ' .. tostring(settings_error));
    end

    local maps, maps_error = load_module_file('ashitaminimap_maps.lua');
    state.maps = type(maps) == 'table' and maps or {};
    if (maps_error ~= nil) then
        log('Map calibration warning: ' .. tostring(maps_error));
    end
end

local function color(name, fallback)
    local colors = state.settings.colors or {};
    return imgui.GetColorU32(colors[name] or fallback);
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
    local yaw = position ~= nil and tonumber(safe_read(function () return position.Yaw; end, nil)) or nil;

    if (index > 0) then
        x = x or tonumber(safe_read(function () return entity:GetLocalPositionX(index); end, nil));
        y = y or tonumber(safe_read(function () return entity:GetLocalPositionY(index); end, nil));
        yaw = yaw or tonumber(safe_read(function () return entity:GetLocalPositionYaw(index); end, nil));
        yaw = yaw or tonumber(safe_read(function () return entity:GetHeading(index); end, nil));
    end
    if (x == nil or y == nil or yaw == nil) then
        return nil;
    end

    return {
        x = x,
        y = y,
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

local function map_grid_yalms(map)
    return clamp(map ~= nil and map.grid_yalms or 40, 10, 1000);
end

local function grid_coordinate(x, y, map)
    local grid_yalms = map_grid_yalms(map);
    local half_cell = grid_yalms / 2;
    local column = math.floor(((tonumber(x) or 0) + half_cell) / grid_yalms) + 8;
    local row = math.floor((-(tonumber(y) or 0) + half_cell) / grid_yalms) + 8;
    return string.format('%s-%d', letters[column] or '?', row);
end

local function draw_grid(draw_list, left, top, size, player, map, scale)
    if (state.settings.show_grid ~= true) then
        return;
    end

    local right = left + size;
    local bottom = top + size;
    local center_x = left + (size / 2);
    local center_y = top + (size / 2);
    local line_color = color('grid', { 0.48, 0.60, 0.61, 0.25 });
    local text_color = color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    local shadow = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local world_radius = (size / 2) / scale;
    local grid_yalms = map_grid_yalms(map);

    local half_cell = grid_yalms / 2;
    local first_column = math.floor((player.x - world_radius + half_cell) / grid_yalms) + 8;
    local last_column = math.floor((player.x + world_radius + half_cell) / grid_yalms) + 8;
    for column = first_column, last_column do
        local boundary_world_x = ((column - 8) * grid_yalms) - half_cell;
        local screen_x = center_x + ((boundary_world_x - player.x) * scale);
        if (screen_x >= left and screen_x <= right) then
            draw_list:AddLine({ screen_x, top }, { screen_x, bottom }, line_color, 1.0);
        end

        local cell_center_world_x = ((column - 8) * grid_yalms);
        local label_x = center_x + ((cell_center_world_x - player.x) * scale);
        local label = letters[column] or '?';
        if (label_x >= left + 9 and label_x <= right - 9) then
            draw_list:AddText({ label_x - 3, top + 4 }, shadow, label);
            draw_list:AddText({ label_x - 4, top + 3 }, text_color, label);
        end
    end

    local first_row = math.floor((-(player.y + world_radius) + half_cell) / grid_yalms) + 8;
    local last_row = math.floor((-(player.y - world_radius) + half_cell) / grid_yalms) + 8;
    for row = first_row, last_row do
        local boundary_world_y = half_cell - ((row - 8) * grid_yalms);
        local screen_y = center_y - ((boundary_world_y - player.y) * scale);
        if (screen_y >= top and screen_y <= bottom) then
            draw_list:AddLine({ left, screen_y }, { right, screen_y }, line_color, 1.0);
        end

        local cell_center_world_y = -((row - 8) * grid_yalms);
        local label_y = center_y - ((cell_center_world_y - player.y) * scale);
        if (label_y >= top + 9 and label_y <= bottom - 9) then
            local label = tostring(row);
            draw_list:AddText({ left + 5, label_y - 6 }, shadow, label);
            draw_list:AddText({ left + 4, label_y - 7 }, text_color, label);
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

local function draw_entities(draw_list, left, top, size, player, scale, visual_scale)
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
                local name = tostring(safe_read(function () return entity:GetName(index); end, '') or '');
                local x = tonumber(safe_read(function () return entity:GetLocalPositionX(index); end, nil));
                local y = tonumber(safe_read(function () return entity:GetLocalPositionY(index); end, nil));
                if (name ~= '' and x ~= nil and y ~= nil) then
                    local kind = entity_kind(entity, index);
                    local enabled = (kind == 'player' and state.settings.show_players == true)
                        or (kind == 'npc' and state.settings.show_npcs == true)
                        or (kind == 'monster' and state.settings.show_monsters == true);
                    local screen_x = center_x + ((x - player.x) * scale);
                    local screen_y = center_y - ((y - player.y) * scale);
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
                        if (state.settings.show_names == true) then
                            draw_list:AddText(
                                {
                                    screen_x + (6 * visual_scale),
                                    screen_y - (7 * visual_scale),
                                },
                                shadow,
                                name);
                            draw_list:AddText(
                                {
                                    screen_x + (5 * visual_scale),
                                    screen_y - (8 * visual_scale),
                                },
                                dot_color,
                                name);
                        end
                    end
                end
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
        player,
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

    local player_image_x = (tonumber(map.origin_x) or (width / 2)) + (player.x * image_scale);
    local player_image_y = (tonumber(map.origin_y) or (height / 2)) - (player.y * image_scale);
    local source_half_pixels = ((size / 2) / scale) * image_scale;
    local u0 = (player_image_x - source_half_pixels) / width;
    local v0 = (player_image_y - source_half_pixels) / height;
    local u1 = (player_image_x + source_half_pixels) / width;
    local v1 = (player_image_y + source_half_pixels) / height;
    opacity = clamp(opacity, 0, 1);
    local passes = math.floor(clamp(visibility_boost, 1, 12) + 0.5);
    local tint = imgui.GetColorU32({ 1, 1, 1, opacity });
    for _ = 1, passes do
        draw_list:AddImage(
            texture.handle,
            { left, top },
            { left + size, top + size },
            { u0, v0 },
            { u1, v1 },
            tint);
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
        0);
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

local function handle_map_input(left, top, size)
    local hovered, mouse_x, mouse_y = mouse_over_map(left, top, size);
    local wheel = hovered
        and safe_read(function () return tonumber(imgui.GetIO().MouseWheel) or 0; end, 0)
        or 0;
    if (wheel ~= 0) then
        local factor = ZOOM_STEP ^ math.abs(wheel);
        local current = clamp(state.settings.pixels_per_yalm, ZOOM_MIN, ZOOM_MAX);
        state.settings.pixels_per_yalm = clamp(
            wheel > 0 and (current * factor) or (current / factor),
            ZOOM_MIN,
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

    local map = state.maps[player.zone_id];
    if (map == nil) then
        if (state.warned_zones[player.zone_id] ~= true) then
            state.warned_zones[player.zone_id] = true;
            log(string.format('No calibrated map for zone %d.', player.zone_id));
        end
        return;
    end

    local structure_image = map.structure_image or map.image;
    local labels_image = map.labels_image;
    local landmarks_image = map.landmarks_image;
    local structure_texture = state.settings.show_map_structure == true
        and texture_for(structure_image)
        or nil;
    local labels_texture = state.settings.show_map_labels == true
        and texture_for(labels_image)
        or nil;
    local landmarks_texture = state.settings.show_map_landmarks == true
        and texture_for(landmarks_image)
        or nil;

    local size = clamp(state.settings.size, 120, 700);
    local scale = clamp(state.settings.pixels_per_yalm, ZOOM_MIN, ZOOM_MAX);
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
        handle_map_input(left, top, size);
        scale = clamp(state.settings.pixels_per_yalm, ZOOM_MIN, ZOOM_MAX);
        local visual_scale = marker_zoom_scale(scale);
        local entity_visual_scale = visual_scale
            * clamp(state.settings.marker_size, 0.25, 2.00);
        local draw_list = imgui.GetWindowDrawList();
        draw_map_backdrop(draw_list, left, top, size);
        if (structure_texture ~= nil) then
            draw_map_layer(
                draw_list,
                left,
                top,
                size,
                player,
                map,
                structure_texture,
                scale,
                state.settings.structure_opacity,
                state.settings.structure_visibility_boost);
        end
        if (labels_texture ~= nil) then
            draw_map_layer(
                draw_list,
                left,
                top,
                size,
                player,
                map,
                labels_texture,
                scale,
                state.settings.label_opacity,
                state.settings.label_visibility_boost);
        end
        if (landmarks_texture ~= nil) then
            draw_map_layer(
                draw_list,
                left,
                top,
                size,
                player,
                map,
                landmarks_texture,
                scale,
                state.settings.landmark_opacity,
                state.settings.landmark_visibility_boost);
        end
        draw_grid(draw_list, left, top, size, player, map, scale);
        draw_entities(draw_list, left, top, size, player, scale, entity_visual_scale);
        draw_player(
            draw_list,
            left + (size / 2),
            top + (size / 2),
            player.yaw,
            visual_scale);
        draw_badge(draw_list, left, top, player, map);
        draw_unlocked_hint(draw_list, left, top, size);
        draw_list:AddRect(
            { left, top },
            { left + size, top + size },
            color('border', { 0.67, 0.47, 0.22, 0.90 }),
            0,
            0,
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

        local zoom_buffer = { clamp(state.settings.pixels_per_yalm, ZOOM_MIN, ZOOM_MAX) };
        if (imgui.SliderFloat(
                'Zoom##ashitaminimap_zoom',
                zoom_buffer,
                ZOOM_MIN,
                ZOOM_MAX,
                '%.2f px/yalm')) then
            state.settings.pixels_per_yalm = zoom_buffer[1];
            mark_configuration_changed();
        end
        imgui.TextColored({ 0.65, 0.68, 0.70, 1.00 }, 'Mouse wheel over the map also changes zoom.');

        imgui.Text('Static layers');
        imgui.Separator();
        config_checkbox('Map structure##ashitaminimap_structure', 'show_map_structure');
        local structure_opacity_buffer = {
            math.floor(clamp(state.settings.structure_opacity, 0, 1) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Structure opacity##ashitaminimap_structure_opacity',
                structure_opacity_buffer,
                0,
                100,
                '%d%%')) then
            state.settings.structure_opacity = structure_opacity_buffer[1] / 100;
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

        config_checkbox('Map labels##ashitaminimap_labels', 'show_map_labels');
        local label_opacity_buffer = {
            math.floor(clamp(state.settings.label_opacity, 0, 1) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Label opacity##ashitaminimap_label_opacity',
                label_opacity_buffer,
                0,
                100,
                '%d%%')) then
            state.settings.label_opacity = label_opacity_buffer[1] / 100;
            mark_configuration_changed();
        end

        local label_visibility_buffer = {
            math.floor(clamp(state.settings.label_visibility_boost, 1, 12) + 0.5),
        };
        if (imgui.SliderInt(
                'Label visibility##ashitaminimap_label_visibility',
                label_visibility_buffer,
                1,
                12,
                '%d x')) then
            state.settings.label_visibility_boost = label_visibility_buffer[1];
            mark_configuration_changed();
        end
        config_checkbox('Static landmarks##ashitaminimap_landmarks', 'show_map_landmarks');
        local landmark_opacity_buffer = {
            math.floor(clamp(state.settings.landmark_opacity, 0, 1) * 100 + 0.5),
        };
        if (imgui.SliderInt(
                'Landmark opacity##ashitaminimap_landmark_opacity',
                landmark_opacity_buffer,
                0,
                100,
                '%d%%')) then
            state.settings.landmark_opacity = landmark_opacity_buffer[1] / 100;
            mark_configuration_changed();
        end

        local landmark_visibility_buffer = {
            math.floor(clamp(state.settings.landmark_visibility_boost, 1, 12) + 0.5),
        };
        if (imgui.SliderInt(
                'Landmark visibility##ashitaminimap_landmark_visibility',
                landmark_visibility_buffer,
                1,
                12,
                '%d x')) then
            state.settings.landmark_visibility_boost = landmark_visibility_buffer[1];
            mark_configuration_changed();
        end
        imgui.TextColored(
            { 0.65, 0.68, 0.70, 1.00 },
            'Production maps separate structure, labels, and landmark symbols.');

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
        config_checkbox('Players##ashitaminimap_players', 'show_players');
        config_checkbox('NPCs##ashitaminimap_npcs', 'show_npcs');
        config_checkbox('Monsters##ashitaminimap_monsters', 'show_monsters');
        config_checkbox('Entity names##ashitaminimap_names', 'show_names');
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

local function print_help()
    log('Commands:');
    log('/aminimap show | hide | toggle');
    log('/aminimap config [show | hide | toggle]');
    log('/aminimap lock | unlock | save');
    log('/aminimap zoomin | zoomout');
    log('/aminimap grid | names | reload');
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
        state.settings.pixels_per_yalm = clamp(
            state.settings.pixels_per_yalm * ZOOM_STEP,
            ZOOM_MIN,
            ZOOM_MAX);
        mark_configuration_changed();
    elseif (action == 'zoomout' or action == 'out') then
        state.settings.pixels_per_yalm = clamp(
            state.settings.pixels_per_yalm / ZOOM_STEP,
            ZOOM_MIN,
            ZOOM_MAX);
        mark_configuration_changed();
    elseif (action == 'grid') then
        state.settings.show_grid = not state.settings.show_grid;
        mark_configuration_changed();
    elseif (action == 'names') then
        state.settings.show_names = not state.settings.show_names;
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
    log('Loaded. Use /aminimap help for commands.');
end);

ashita.events.register('unload', 'unload_cb', function ()
    save_configuration_if_due(true);
    state.textures = {};
    state.device = nil;
    state.config_visible[1] = false;
end);

ashita.events.register('command', 'command_cb', function (e)
    handle_command(e);
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    render_minimap();
    render_config_window();
    save_configuration_if_due(false);
end);
