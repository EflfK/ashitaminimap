addon.name      = 'ashitaminimap';
addon.author    = 'EflfK';
addon.version   = '1.6.5';
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
local ENTITY_FLOOR_TOLERANCE = 8.0;

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
    structure_visibility_boost = 4,
    backdrop_opacity = 0.12,
    show_grid = true,
    show_coordinate = true,
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
            '    structure_visibility_boost = %d,',
            math.floor(clamp(settings.structure_visibility_boost, 1, 12) + 0.5)),
        string.format('    backdrop_opacity = %.3f,', clamp(settings.backdrop_opacity, 0, 0.75)),
        '',
        string.format('    show_grid = %s,', bool_text(settings.show_grid)),
        string.format('    show_coordinate = %s,', bool_text(settings.show_coordinate)),
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
    local obsolete_layer_settings = settings.show_map_labels ~= nil
        or settings.show_map_landmarks ~= nil
        or settings.label_opacity ~= nil
        or settings.landmark_opacity ~= nil
        or settings.label_visibility_boost ~= nil
        or settings.landmark_visibility_boost ~= nil;
    state.settings.size = clamp(state.settings.size, 120, 700);
    local loaded_zoom = tonumber(state.settings.pixels_per_yalm) or DEFAULTS.pixels_per_yalm;
    state.settings.pixels_per_yalm = clamp(loaded_zoom, ZOOM_MIN, ZOOM_MAX);
    state.settings.vanilla_opacity = clamp(state.settings.vanilla_opacity, 0, 1);
    state.settings.structure_opacity = clamp(state.settings.structure_opacity, 0, 1);
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
        or obsolete_layer_settings;
    state.config_changed_at = 0;
    state.dragging = false;
    state.origin_editor.zone_id = nil;
    state.origin_editor.page_key = nil;
    if (settings_error ~= nil) then
        log('Config warning: ' .. tostring(settings_error));
    end

    local maps, maps_error = load_module_file('ashitaminimap_maps.lua');
    state.maps = type(maps) == 'table' and maps or {};
    if (maps_error ~= nil) then
        log('Map calibration warning: ' .. tostring(maps_error));
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
        merged.structure_image = authored.structure_pages[map_page_key(merged)];
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
        draw_list:AddImage(
            texture.handle,
            { destination_left, destination_top },
            { destination_right, destination_bottom },
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
                    structure_layers[#structure_layers + 1] = {
                        texture = texture,
                        opacity = type(layer) == 'table'
                            and clamp(layer.opacity or 1, 0, 1)
                            or 1,
                    };
                end
            end
        else
            local texture = texture_for(map.structure_image or map.image);
            if (texture ~= nil) then
                structure_layers[1] = {
                    texture = texture,
                    opacity = 1,
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
            draw_map_layer(
                draw_list,
                left,
                top,
                size,
                camera,
                map,
                layer.texture,
                scale,
                state.settings.structure_opacity * layer.opacity,
                state.settings.structure_visibility_boost);
        end
        draw_grid(draw_list, left, top, size, camera, map, scale);
        draw_entities(draw_list, left, top, size, player, camera, scale, entity_visual_scale);
        local player_screen_x = left + (size / 2) + ((player.x - camera.x) * scale);
        local player_screen_y = top + (size / 2) - ((player.y - camera.y) * scale);
        draw_player(
            draw_list,
            player_screen_x,
            player_screen_y,
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

        if (config_player ~= nil and config_map ~= nil) then
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
