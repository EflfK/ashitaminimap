local bit = require('bit');

local CHAT_WINDOW_SIGNATURE = 'A1????????C64059018B0D????????C6415901C20800';
local UI_HEIGHT_SIGNATURE = 'A1????????3BF07E??8BF0';
local CHAT_TOP_OFFSET = 0x42;

local M = {
    window_pointer_addresses = {},
    ui_height_pointer_address = 0,
};

local function valid_address(value)
    value = tonumber(value) or 0;
    return value > 0;
end

function M.scan()
    M.window_pointer_addresses = {};
    M.ui_height_pointer_address = 0;

    local chat_pattern = ashita.memory.find(
        'FFXiMain.dll',
        0,
        CHAT_WINDOW_SIGNATURE,
        0,
        0);
    if (valid_address(chat_pattern)) then
        local first = ashita.memory.read_uint32(chat_pattern + 0x01);
        local second = ashita.memory.read_uint32(chat_pattern + 0x0B);
        if (valid_address(first)) then
            M.window_pointer_addresses[#M.window_pointer_addresses + 1] = first;
        end
        if (valid_address(second)) then
            M.window_pointer_addresses[#M.window_pointer_addresses + 1] = second;
        end
    end

    local height_pattern = ashita.memory.find(
        'FFXiMain.dll',
        0,
        UI_HEIGHT_SIGNATURE,
        0,
        0);
    if (valid_address(height_pattern)) then
        M.ui_height_pointer_address = ashita.memory.read_uint32(height_pattern + 0x01);
    end
end

function M.top_screen_y(display_height)
    display_height = tonumber(display_height) or 0;
    if (display_height <= 0
            or #M.window_pointer_addresses == 0
            or not valid_address(M.ui_height_pointer_address)) then
        return nil;
    end

    local ui_height = tonumber(ashita.memory.read_uint32(M.ui_height_pointer_address)) or 0;
    if (ui_height <= 0 or ui_height > 16384) then
        return nil;
    end

    local top = nil;
    for _, pointer_address in ipairs(M.window_pointer_addresses) do
        local window = ashita.memory.read_uint32(pointer_address);
        if (valid_address(window)) then
            local candidate = bit.band(
                ashita.memory.read_uint32(window + CHAT_TOP_OFFSET),
                0xFFFF);
            if (candidate > 0 and candidate < ui_height
                    and (top == nil or candidate < top)) then
                top = candidate;
            end
        end
    end

    if (top == nil) then
        return nil;
    end
    return math.floor(((top * display_height) / ui_height) + 0.5);
end

ashita.events.register('load', 'native_chat_load_cb', function ()
    M.scan();
end);

ashita.events.register('packet_in', 'native_chat_zone_cb', function (e)
    if (e ~= nil and e.id == 0x000A) then
        M.scan();
    end
end);

return M;
