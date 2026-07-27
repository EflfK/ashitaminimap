addon.name      = 'ashitaminimap';
addon.author    = 'EflfK';
addon.version   = '0.1.0';
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

local DEFAULTS = {
    visible = true,
    locked = true,
    x = 18,
    y = 128,
    size = 330,
    pixels_per_yalm = 4.41,
    map_opacity = 0.82,
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
    },
};

local state = {
    settings = DEFAULTS,
    maps = {},
    textures = {},
    device = nil,
    warned_zones = {},
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
    state.settings = merge_table(copy_table(DEFAULTS), settings or {});
    if (settings_error ~= nil) then
        log('Config warning: ' .. tostring(settings_error));
    end

    local maps, maps_error = load_module_file('ashitaminimap_maps.lua');
    state.maps = type(maps) == 'table' and maps or {};
    if (maps_error ~= nil) then
        log('Map calibration warning: ' .. tostring(maps_error));
    end
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, tonumber(value) or minimum));
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

local function texture_for(map)
    if (map == nil or map.image == nil) then
        return nil;
    end
    if (state.textures[map.image] ~= nil) then
        return state.textures[map.image] ~= false and state.textures[map.image] or nil;
    end

    local device = ensure_device();
    if (device == nil) then
        return nil;
    end

    local path = string.format('%s%s', addon.path, map.image);
    if (not ashita.fs.exists(path)) then
        state.textures[map.image] = false;
        log('Missing map asset: ' .. path);
        return nil;
    end

    local pointer = ffi.new('IDirect3DTexture8*[1]');
    local result = safe_read(function ()
        return ffi.C.D3DXCreateTextureFromFileA(device, path, pointer);
    end, -1);
    if (result ~= 0 or pointer[0] == nil) then
        state.textures[map.image] = false;
        log('Could not load map asset: ' .. path);
        return nil;
    end

    local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    local entry = {
        texture = texture,
        handle = tonumber(ffi.cast('uint32_t', texture)),
    };
    state.textures[map.image] = entry;
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

local GRID_YALMS = 20;

local function grid_coordinate(x, y)
    local half_cell = GRID_YALMS / 2;
    local column = math.floor(((tonumber(x) or 0) + half_cell) / GRID_YALMS) + 8;
    local row = math.floor((-(tonumber(y) or 0) + half_cell) / GRID_YALMS) + 8;
    return string.format('%s-%d', letters[column] or '?', row);
end

local function draw_grid(draw_list, left, top, size, player, scale)
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

    local half_cell = GRID_YALMS / 2;
    local first_column = math.floor((player.x - world_radius + half_cell) / GRID_YALMS) + 8;
    local last_column = math.floor((player.x + world_radius + half_cell) / GRID_YALMS) + 8;
    for column = first_column, last_column do
        local boundary_world_x = ((column - 8) * GRID_YALMS) - half_cell;
        local screen_x = center_x + ((boundary_world_x - player.x) * scale);
        if (screen_x >= left and screen_x <= right) then
            draw_list:AddLine({ screen_x, top }, { screen_x, bottom }, line_color, 1.0);
        end

        local cell_center_world_x = ((column - 8) * GRID_YALMS);
        local label_x = center_x + ((cell_center_world_x - player.x) * scale);
        local label = letters[column] or '?';
        if (label_x >= left + 9 and label_x <= right - 9) then
            draw_list:AddText({ label_x - 3, top + 4 }, shadow, label);
            draw_list:AddText({ label_x - 4, top + 3 }, text_color, label);
        end
    end

    local first_row = math.floor((-(player.y + world_radius) + half_cell) / GRID_YALMS) + 8;
    local last_row = math.floor((-(player.y - world_radius) + half_cell) / GRID_YALMS) + 8;
    for row = first_row, last_row do
        local boundary_world_y = half_cell - ((row - 8) * GRID_YALMS);
        local screen_y = center_y - ((boundary_world_y - player.y) * scale);
        if (screen_y >= top and screen_y <= bottom) then
            draw_list:AddLine({ left, screen_y }, { right, screen_y }, line_color, 1.0);
        end

        local cell_center_world_y = -((row - 8) * GRID_YALMS);
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

local function draw_entities(draw_list, left, top, size, player, scale)
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
                        draw_list:AddCircleFilled({ screen_x, screen_y }, 6.0, shadow, 16);
                        draw_list:AddCircleFilled({ screen_x, screen_y }, 4.5, dot_color, 16);
                        if (index == target_index) then
                            draw_list:AddCircle({ screen_x, screen_y }, 7.0,
                                color('target', { 1.00, 0.71, 0.20, 1.00 }), 20, 2.0);
                        end
                        if (state.settings.show_names == true) then
                            draw_list:AddText({ screen_x + 6, screen_y - 7 }, shadow, name);
                            draw_list:AddText({ screen_x + 5, screen_y - 8 }, dot_color, name);
                        end
                    end
                end
            end
        end
    end
end

local function draw_player(draw_list, center_x, center_y, yaw)
    local heading_x = math.cos(yaw);
    local heading_y = math.sin(yaw);
    local side_x = -heading_y;
    local side_y = heading_x;
    local tip = { center_x + (heading_x * 13), center_y + (heading_y * 13) };
    local back_x = center_x - (heading_x * 7);
    local back_y = center_y - (heading_y * 7);
    local left = { back_x + (side_x * 7), back_y + (side_y * 7) };
    local right = { back_x - (side_x * 7), back_y - (side_y * 7) };
    local shadow = color('shadow', { 0.01, 0.02, 0.025, 0.94 });
    local player_color = color('player', { 0.18, 0.88, 0.90, 1.00 });
    draw_list:AddTriangleFilled(
        { tip[1] + 1, tip[2] + 1 },
        { left[1] + 1, left[2] + 1 },
        { right[1] + 1, right[2] + 1 },
        shadow);
    draw_list:AddTriangleFilled(tip, left, right, player_color);
    draw_list:AddCircle({ center_x, center_y }, 4.0, player_color, 16, 1.5);
end

local function draw_badge(draw_list, left, top, player, map)
    if (state.settings.show_coordinate ~= true) then
        return;
    end
    local coordinate = grid_coordinate(player.x, player.y);
    local label = string.format('%s  %s', coordinate, map.name or ('Zone ' .. tostring(player.zone_id)));
    local width = math.max(66, (#label * 7) + 16);
    local badge_color = color('badge', { 0.025, 0.055, 0.070, 0.88 });
    local border = color('border', { 0.67, 0.47, 0.22, 0.90 });
    local text_color = color('grid_text', { 0.82, 0.71, 0.51, 0.88 });
    draw_list:AddRectFilled({ left + 6, top + 6 }, { left + 6 + width, top + 29 }, badge_color, 3.0);
    draw_list:AddRect({ left + 6, top + 6 }, { left + 6 + width, top + 29 }, border, 3.0, 0, 1.0);
    draw_list:AddText({ left + 14, top + 10 }, text_color, label);
end

local function draw_map_texture(draw_list, left, top, size, player, map, texture, scale)
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
    local opacity = clamp(state.settings.map_opacity, 0, 1);
    draw_list:AddImage(
        texture.handle,
        { left, top },
        { left + size, top + size },
        { u0, v0 },
        { u1, v1 },
        imgui.GetColorU32({ 1, 1, 1, opacity }));
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

    local texture = texture_for(map);
    if (texture == nil) then
        return;
    end

    local size = clamp(state.settings.size, 120, 700);
    local scale = clamp(state.settings.pixels_per_yalm, 0.10, 5.00);
    local window_flags = bit.bor(
        bit.lshift(1, 0),  -- NoTitleBar
        bit.lshift(1, 1),  -- NoResize
        bit.lshift(1, 3),  -- NoScrollbar
        bit.lshift(1, 7),  -- NoBackground
        bit.lshift(1, 8),  -- NoSavedSettings
        bit.lshift(1, 12), -- NoFocusOnAppearing
        bit.lshift(1, 13), -- NoBringToFrontOnFocus
        bit.lshift(1, 18), -- NoNavInputs
        bit.lshift(1, 19));-- NoNavFocus
    if (state.settings.locked == true) then
        window_flags = bit.bor(window_flags, bit.lshift(1, 2), bit.lshift(1, 9));
    end

    imgui.SetNextWindowPos({ tonumber(state.settings.x) or 18, tonumber(state.settings.y) or 128 }, 0);
    -- The Ashita ImGui binding applies 8 px of default window padding. Account
    -- for it so the requested map square is not clipped on the right or bottom.
    imgui.SetNextWindowSize({ size + 16, size + 16 }, 0);
    if (type(imgui.SetNextWindowBgAlpha) == 'function') then
        imgui.SetNextWindowBgAlpha(0.0);
    end

    if (imgui.Begin('##ashitaminimap_overlay', true, window_flags)) then
        local left, top = imgui.GetCursorScreenPos();
        local draw_list = imgui.GetWindowDrawList();
        draw_map_texture(draw_list, left, top, size, player, map, texture, scale);
        draw_grid(draw_list, left, top, size, player, scale);
        draw_entities(draw_list, left, top, size, player, scale);
        draw_player(draw_list, left + (size / 2), top + (size / 2), player.yaw);
        draw_badge(draw_list, left, top, player, map);
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

local function print_help()
    log('Commands:');
    log('/aminimap show | hide | toggle');
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
    elseif (action == 'hide') then
        state.settings.visible = false;
    elseif (action == 'toggle') then
        state.settings.visible = not state.settings.visible;
    elseif (action == 'zoomin' or action == 'in') then
        state.settings.pixels_per_yalm = clamp(state.settings.pixels_per_yalm * 1.20, 0.10, 5.00);
    elseif (action == 'zoomout' or action == 'out') then
        state.settings.pixels_per_yalm = clamp(state.settings.pixels_per_yalm / 1.20, 0.10, 5.00);
    elseif (action == 'grid') then
        state.settings.show_grid = not state.settings.show_grid;
    elseif (action == 'names') then
        state.settings.show_names = not state.settings.show_names;
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
    state.textures = {};
    state.device = nil;
end);

ashita.events.register('command', 'command_cb', function (e)
    handle_command(e);
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    render_minimap();
end);
