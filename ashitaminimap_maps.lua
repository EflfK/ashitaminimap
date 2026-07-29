-- Map calibration is deterministic:
-- image_x = origin_x + (world_x * image_pixels_per_yalm)
-- image_y = origin_y - (world_y * image_pixels_per_yalm)
--
-- grid_yalms is zone-specific; it is map-scale-byte * 10.
-- Keep all calibration values separate from the on-screen zoom.
local function structure_layer_set(layers)
    for index, layer in ipairs(layers) do
        assert(
            type(layer) == 'table',
            string.format('structure layer %d must be a metadata table', index));
        local minimum_z = tonumber(layer.minimum_player_z);
        local maximum_z = tonumber(layer.maximum_player_z);
        local has_floor_bounds = minimum_z ~= nil or maximum_z ~= nil;
        local is_transition = layer.role == 'floor_transition';
        local is_always_visible = layer.floor_selection == 'always';
        assert(
            has_floor_bounds or is_transition or is_always_visible,
            string.format(
                'structure layer %d (%s) must declare player-Z bounds, '
                    .. 'role = floor_transition, or floor_selection = always',
                index,
                tostring(layer.image)));
        assert(
            minimum_z == nil or maximum_z == nil or minimum_z <= maximum_z,
            string.format(
                'structure layer %d (%s) has reversed player-Z bounds',
                index,
                tostring(layer.image)));
    end
    return layers;
end

-- Static travel references are active NPC records from CatsEyeXI npc_list.sql
-- at commit 314deaf03465f2b24b6a1e4e73a016ca036f1084. SQL coordinates are
-- (pos_x, vertical, pos_z); minimap records use (x, y, z). Empty sets are
-- intentional and record that a supported map was audited.
local function travel_reference_set(markers)
    for index, marker in ipairs(markers) do
        assert(
            marker.kind == 'home_point' or marker.kind == 'survival_guide',
            string.format('travel reference %d has an invalid kind', index));
        assert(
            type(marker.name) == 'string' and marker.name ~= '',
            string.format('travel reference %d must have a name', index));
        assert(
            tonumber(marker.x) ~= nil
                and tonumber(marker.y) ~= nil
                and tonumber(marker.z) ~= nil,
            string.format(
                'travel reference %d (%s) must have x, y, and z',
                index,
                marker.name));
        assert(
            (marker.kind == 'home_point'
                and tonumber(marker.unlock_index) ~= nil)
                or (marker.kind == 'survival_guide'
                    and tonumber(marker.unlock_bit) ~= nil),
            string.format(
                'travel reference %d (%s) must declare its unlock bit',
                index,
                marker.name));
    end
    return markers;
end

return {
    [107] = {
        name = 'South Gustaberg',
        image = 'assets/maps/107.png',
        width = 768,
        height = 768,
        origin_x = 384,
        origin_y = 384,
        grid_yalms = 100,
        image_pixels_per_yalm = 0.48,
        travel_references = travel_reference_set({}),
    },
    [236] = {
        name = 'Port Bastok',
        image = 'assets/maps/236.png',
        width = 768,
        height = 768,
        origin_x = 384,
        origin_y = 384,
        grid_yalms = 40,
        image_pixels_per_yalm = 1.20,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 14, x = 126.000, y =    8.000, z = 8.500 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 15, x =  40.000, y = -238.000, z = 8.500 },
        }),
    },
    [237] = {
        name = 'Metalworks',
        structure_image = 'assets/maps/237_structure.png',
        width = 512,
        height = 512,
        -- Horizontal unwrap moves X; Y remains at the 512 px texture's
        -- center coordinate. Both were verified against the stock map and
        -- live entity control points at matching display scale.
        origin_x = 253,
        origin_y = 255.5,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 16, x = 46.000, y = -19.000, z = -14.000 },
        }),
    },
    [241] = {
        name = 'Windurst Woods',
        vanilla_image = 'assets/maps/241_vanilla.png',
        structure_image = 'assets/maps/241_structure.png',
        width = 512,
        height = 512,
        -- The source page wraps at x=366. Moving that section to the left
        -- restores the complete A-O page and makes the full 512 px texture
        -- the overview boundary.
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        -- Source: ROM/18/72.DAT, internal page m_241_00. The +146 px unwrap
        -- moves the verified geometry origin from x=108.5 to x=254.5.
        origin_x = 254.5,
        origin_y = 288.0,
        -- The printed vanilla grid is independent of the geometry origin.
        -- Its H-8 cell center is one full 32 px row above world (0, 0).
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 25, x =   9.088, y =   -0.383, z = -2.500 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 26, x = 107.000, y =  -56.000, z = -5.000 },
            { kind = 'home_point', name = 'Home Point #3', unlock_index = 27, x = -92.000, y =   62.000, z = -5.000 },
            { kind = 'home_point', name = 'Home Point #4', unlock_index = 28, x =  74.000, y = -139.000, z = -7.500 },
            { kind = 'home_point', name = 'Home Point #5', unlock_index = 119, x = -43.500, y = -145.000, z =  0.000 },
        }),
    },
    [243] = {
        name = 'Ru\'Lude Gardens',
        vanilla_image = 'assets/maps/243_vanilla.png',
        -- Keep disconnected elevations in separate textures so their boundary
        -- edges and alternate-floor color remain visible where paths overlap.
        structure_layers = structure_layer_set({
            {
                image = 'assets/maps/243_structure.png',
                maximum_player_z = 2.9,
            },
            {
                image = 'assets/maps/243_stairs_structure.png',
                minimum_player_z = 3.0,
            },
            {
                image = 'assets/maps/243_upper_structure.png',
                minimum_player_z = 3.0,
            },
        }),
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        origin_x = 255.0,
        origin_y = 256.0,
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 29, x = -6.000, y =   0.001, z =  3.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 30, x = 53.000, y = -57.000, z =  9.000 },
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 27, x = 43.000, y = -69.000, z = 10.000 },
        }),
    },
    [244] = {
        name = 'Upper Jeuno',
        stock_calibration = true,
        vanilla_image = 'assets/maps/244_vanilla.png',
        -- These disconnected components have not been proven to represent
        -- separate player-Z floors. Keep that intentional legacy behavior
        -- explicit so a future floor audit cannot silently skip classification.
        structure_layers = structure_layer_set({
            {
                image = 'assets/maps/244_structure.png',
                floor_selection = 'always',
            },
            {
                image = 'assets/maps/244_stables_structure.png',
                floor_selection = 'always',
            },
        }),
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        -- Exact FFXiMain map record offsets are (-272, -304).
        origin_x = 272.0,
        origin_y = 304.0,
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 32, x = -98.981, y = 167.569, z =  0.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 33, x =  32.000, y = -44.000, z = -1.000 },
            { kind = 'home_point', name = 'Home Point #3', unlock_index = 34, x = -52.000, y =  16.000, z =  1.000 },
        }),
    },
    [245] = {
        name = 'Lower Jeuno',
        vanilla_image = 'assets/maps/245_vanilla.png',
        structure_image = 'assets/maps/245_structure.png',
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        origin_x = 255.0,
        origin_y = 256.0,
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 35, x = -98.588, y = -183.416, z =  0.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 36, x =  18.000, y =   54.000, z = -1.000 },
        }),
    },
    [246] = {
        name = 'Port Jeuno',
        structure_image = 'assets/maps/246_structure.png',
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        origin_x = 255.0,
        origin_y = 256.0,
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 37, x =   37.076, y =  8.831, z =  0.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 38, x = -155.000, y = -4.000, z = -1.000 },
        }),
    },
    [200] = {
        name = 'Garlaige Citadel',
        stock_calibration = true,
        structure_pages = {
            [1] = 'assets/maps/200_01_structure.png',
            [16] = 'assets/maps/200_16_structure.png',
        },
        -- The Minimap DLL can leave page 1 selected after the player falls
        -- through an upper-floor hole. Page 16 is the verified basement band.
        page_rules = {
            {
                page_id = 16,
                minimum_z = 14.0,
                maximum_z = 21.0,
            },
        },
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        -- Page 16 fallback values; the live page record supplies exact values.
        origin_x = 352.0,
        origin_y = 336.0,
        grid_origin_x = 256.0,
        grid_origin_y = 256.0,
        grid_yalms = 80,
        image_pixels_per_yalm = 0.40,
        travel_references = travel_reference_set({
            {
                kind = 'survival_guide',
                name = 'Survival Guide',
                unlock_bit = 23,
                x = -383.000,
                y = 363.500,
                z = -6.118,
                page_id = 1,
            },
        }),
    },
    [174] = {
        name = 'Kuftal Tunnel',
        stock_calibration = true,
        -- Kuftal's four logical maps use non-contiguous stock page IDs.
        -- Each page is an ordered set of separately rendered elevation
        -- components so overlapping floors retain their own boundaries.
        structure_pages = {
            [1] = structure_layer_set({
                {
                    image = 'assets/maps/174_01_main_structure.png',
                    minimum_player_z = -14.9,
                },
                {
                    image = 'assets/maps/174_01_lower_structure.png',
                    maximum_player_z = -15.0,
                },
                {
                    image = 'assets/maps/174_01_transition_structure.png',
                    role = 'floor_transition',
                },
            }),
            [2] = structure_layer_set({
                {
                    image = 'assets/maps/174_02_upper_structure.png',
                    minimum_player_z = 6.1,
                },
                {
                    image = 'assets/maps/174_02_lower_structure.png',
                    maximum_player_z = -6.1,
                },
                {
                    image = 'assets/maps/174_02_main_structure.png',
                    minimum_player_z = -6.0,
                    maximum_player_z = 6.0,
                },
            }),
            [15] = structure_layer_set({
                {
                    image = 'assets/maps/174_15_lower_structure.png',
                    maximum_player_z = 5.0,
                },
                {
                    image = 'assets/maps/174_15_upper_structure.png',
                    minimum_player_z = 25.1,
                },
                {
                    image = 'assets/maps/174_15_main_structure.png',
                    minimum_player_z = 5.1,
                    maximum_player_z = 25.0,
                },
            }),
            [16] = structure_layer_set({
                {
                    image = 'assets/maps/174_16_left_lower_structure.png',
                    maximum_player_z = 14.9,
                },
                {
                    image = 'assets/maps/174_16_right_lower_structure.png',
                    maximum_player_z = 14.9,
                },
                {
                    image = 'assets/maps/174_16_upper_structure.png',
                    minimum_player_z = 25.1,
                },
                {
                    image = 'assets/maps/174_16_main_structure.png',
                    minimum_player_z = 15.0,
                    maximum_player_z = 25.0,
                },
            }),
        },
        -- Fixed possible Treasure Coffer locations from CatsEyeXI's Kuftal
        -- treasure table (scripts/globals/treasure.lua). Its setPos tuples are
        -- (x, vertical, horizontal); AshitaMinimap uses (x, y, z), so the
        -- second and third coordinates are swapped here. These records are
        -- reference markers only and never inspect or imply live spawns.
        coffer_spawns = {
            { kind = 'coffer', x = 103.708, y =  208.367, z = -11.326, page_id = 2 },
            { kind = 'coffer', x = 127.993, y =   96.500, z = -11.318, page_id = 2 },
            { kind = 'coffer', x = 126.990, y =   49.802, z =  -1.319, page_id = 2 },
            { kind = 'coffer', x = 154.813, y =  -68.138, z = -10.473, page_id = 2 },
            { kind = 'coffer', x =  41.657, y =   29.949, z = -11.623, page_id = 2 },
            { kind = 'coffer', x =  15.489, y =    8.337, z = -11.354, page_id = 2 },
            { kind = 'coffer', x = -10.184, y =  127.082, z =  -1.373, page_id = 2 },
            { kind = 'coffer', x =  26.277, y =  134.207, z =  -1.554, page_id = 2 },
            { kind = 'coffer', x = -15.217, y =   51.530, z =  -1.907, page_id = 2 },
            { kind = 'coffer', x = -92.888, y =    2.676, z =  -0.282, page_id = 2 },
            { kind = 'coffer', x = -14.067, y = -132.941, z = -11.940, page_id = 2 },
            { kind = 'coffer', x = -25.934, y = -142.247, z = -11.000, page_id = 2 },
            { kind = 'coffer', x = -27.946, y = -183.709, z = -21.825, page_id = 1 },
        },
        -- Static initial-spawn references from CatsEyeXI's public
        -- scripts/zones/Kuftal_Tunnel/mobs/Amemet.lua. The source tuples use
        -- (x, vertical, horizontal); these points convert to minimap (x, y).
        -- They never inspect or imply Amemet's current position or status.
        nm_spawn_ranges = {
            {
                name = 'Amemet',
                page_id = 2,
                z = 0.0,
                floor = 'MAIN',
                spawn_type = 'Lottery',
                level = '66',
                placeholder_count = 13,
                radius_yalms = 4.5,
                points = {
                    { x = 123.046, y =  18.642 },
                    { x = 112.135, y =  38.281 },
                    { x = 112.008, y =  50.994 },
                    { x = 122.654, y =   0.840 },
                    { x = 123.186, y = -24.716 },
                    { x = 118.633, y = -43.282 },
                    { x = 109.000, y = -48.000 },
                    { x =  96.365, y =  -7.619 },
                    { x =  89.590, y =  -9.390 },
                    { x =  68.454, y =  -0.413 },
                    { x =  74.662, y =   3.685 },
                    { x =  67.998, y =  12.000 },
                    { x =  92.000, y =  14.000 },
                    { x =  99.475, y =   9.035 },
                    { x = 104.228, y =   6.567 },
                    { x = 109.032, y =  -7.990 },
                    { x = 122.583, y =   0.622 },
                    { x =  86.752, y =  -0.573 },
                    { x = 102.731, y =  -5.173 },
                    { x = 114.827, y =   9.606 },
                    { x =  96.311, y =  -4.693 },
                    { x =  97.652, y =  -8.770 },
                    { x =  90.926, y =  -0.835 },
                    { x = 109.931, y =  -7.088 },
                    { x = 112.120, y =  15.939 },
                    { x = 106.658, y =   8.578 },
                    { x = 102.354, y =  -9.346 },
                    { x = 104.305, y =  13.815 },
                    { x = 102.753, y =  -2.631 },
                    { x =  90.305, y =  -2.025 },
                    { x =  92.885, y =  -4.161 },
                    { x =  98.694, y =   5.488 },
                    { x = 100.363, y =  -2.502 },
                    { x = 110.300, y = -19.833 },
                    { x =  79.762, y =  -7.177 },
                    { x = 105.783, y =  13.513 },
                    { x = 115.739, y =  16.603 },
                    { x =  82.849, y =   5.134 },
                    { x = 102.541, y =  14.131 },
                    { x =  88.190, y =  -5.870 },
                    { x = 101.478, y =   8.986 },
                    { x = 112.781, y =  13.979 },
                    { x = 108.403, y = -11.182 },
                    { x = 115.181, y = -10.044 },
                    { x =  83.043, y =   4.495 },
                    { x =  92.363, y =  -1.750 },
                    { x =  76.068, y =  -6.919 },
                    { x =  98.145, y =  -5.397 },
                    { x = 120.448, y =  15.336 },
                    { x = 111.944, y =   0.939 },
                },
            },
        },
        -- These rules also prevent the unrecorded overview artwork on page 0
        -- from becoming the automatic fallback when Minimap.dll is unloaded.
        page_rules = {
            {
                page_id = 15,
                minimum_z = 15.0,
                maximum_y = -10.0,
            },
            {
                page_id = 16,
                minimum_z = 15.0,
                minimum_y = -10.0,
            },
            {
                page_id = 1,
                maximum_y = -175.0,
                maximum_z = 15.0,
            },
            {
                page_id = 2,
                minimum_z = -100.0,
                maximum_z = 100.0,
            },
        },
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        -- Page 2 fallback values; each recorded page supplies its exact
        -- origin and common 0.80 source scale at runtime.
        origin_x = 208.0,
        origin_y = 304.0,
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
        travel_references = travel_reference_set({
            {
                kind = 'survival_guide',
                name = 'Survival Guide',
                unlock_bit = 51,
                x = -16.000,
                y = -237.000,
                z = -20.809,
                page_id = 1,
            },
        }),
    },
}
