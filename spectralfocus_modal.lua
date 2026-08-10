local ffi = require('ffi');

pcall(ffi.cdef, [[
    typedef struct ashitamove_modal_event_t {
        uint32_t version;
        uint32_t active;
        char menu_name[32];
    } ashitamove_modal_event_t;
]]);

local M = { active = false, menu_name = '' };

ashita.events.register('plugin_event', 'spectral_focus_modal_event_cb', function (e)
    if (e == nil or e.name ~= 'ashitamove_modal_v1' or e.data_raw == nil) then return; end
    if ((tonumber(e.size) or 0) < ffi.sizeof('ashitamove_modal_event_t')) then return; end
    local payload = ffi.cast('const ashitamove_modal_event_t*', e.data_raw);
    if (tonumber(payload.version) ~= 1) then return; end
    M.active = tonumber(payload.active) == 1;
    M.menu_name = ffi.string(payload.menu_name, 31):gsub('\x00.*$', '');
end);

ashita.events.register('load', 'spectral_focus_modal_load_cb', function ()
    AshitaCore:GetPluginManager():RaiseEvent('ashitamove_modal_query_v1', T{});
end);

function M.is_active()
    return M.active;
end

function M.is_decision()
    return M.menu_name:lower():find('query', 1, true) ~= nil;
end

return M;
