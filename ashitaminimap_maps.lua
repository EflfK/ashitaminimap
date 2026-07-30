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
    [239] = {
        name = 'Windurst Walls',
        stock_calibration = true,
        -- Preserved partial structure evidence. Runtime structure rendering is
        -- dormant; routing completion does not depend on this texture.
        structure_image = 'assets/maps/239_partial_structure.png',
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 19, x = -72.069, y = 124.784, z = -5.013 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 20, x = -212.000, y = -99.000, z = 0.001 },
            { kind = 'home_point', name = 'Home Point #3', unlock_index = 21, x = 31.000, y = -40.000, z = -6.500 },
        }),
        treasure_spawns = {
            { kind = 'coffer', page_id = 0, x = -214.300, y = -147.650, z = 0.000 },
        },
        nm_spawn_ranges = {},
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
        grid_origin_x = 255.0,
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
    [151] = {
        name = 'Castle Oztroja',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 38, x = -221.000, y = -13.000, z = 0.250 },
        }),
        treasure_spawns = {
            { kind = 'chest', x =    7.378, y = -193.590, z = -16.293 },
            { kind = 'chest', x =  -52.531, y =  -12.087, z =  24.218 },
            { kind = 'chest', x =  -79.345, y =  -39.930, z =  23.731 },
            { kind = 'chest', x = -107.048, y =  -67.696, z =  24.218 },
            { kind = 'chest', x =  113.076, y =  -85.606, z = -16.326 },
            { kind = 'chest', x =   50.230, y = -186.078, z = -16.000 },
            { kind = 'chest', x =   66.460, y = -140.403, z =  -4.285 },
            { kind = 'chest', x = -167.569, y =  193.410, z = -16.293 },
            { kind = 'chest', x = -274.293, y =  193.509, z = -16.285 },
            { kind = 'chest', x = -206.721, y =   85.103, z = -16.000 },
            { kind = 'chest', x = -213.101, y =  139.820, z =  -4.285 },
            { kind = 'chest', x = -102.026, y =  180.448, z = -52.000 },
            { kind = 'chest', x =  -19.589, y =  -15.309, z = -15.750 },
            { kind = 'coffer', x = -102.723, y = -222.555, z = -60.000 },
            { kind = 'coffer', x = -266.089, y =  -20.133, z = -15.750 },
            { kind = 'coffer', x = -262.641, y =  -60.291, z = -20.000 },
            { kind = 'coffer', x = -144.194, y =  -15.149, z = -39.729 },
            { kind = 'coffer', x =  -80.274, y =  -80.277, z = -40.203 },
            { kind = 'coffer', x =  -15.114, y = -134.880, z = -39.745 },
            { kind = 'coffer', x =  -13.623, y = -184.540, z = -39.834 },
            { kind = 'coffer', x =  -60.369, y = -146.231, z = -71.750 },
            { kind = 'coffer', x = -139.729, y =  -53.252, z = -71.750 },
            { kind = 'coffer', x = -100.197, y =  -13.141, z = -72.511 },
        },
    },
    [157] = {
        name = 'Middle Delkfutt\'s Tower',
        stock_calibration = true,
        travel_references = travel_reference_set({}),
        treasure_spawns = {
            { kind = 'chest', x = -339.909, y =  20.816, z = -127.601 },
            { kind = 'chest', x = -420.058, y =  99.913, z = -127.601 },
            { kind = 'chest', x = -398.356, y =  20.397, z = -127.424 },
            { kind = 'chest', x = -499.848, y =  20.397, z = -127.601 },
            { kind = 'chest', x = -359.633, y = -39.286, z = -111.424 },
            { kind = 'chest', x = -416.369, y =  62.454, z = -112.000 },
            { kind = 'chest', x = -425.616, y =  -0.879, z = -111.424 },
            { kind = 'chest', x = -504.196, y =  55.353, z = -112.000 },
        },
    },
    [158] = {
        name = 'Upper Delkfutt\'s Tower',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 71, x = -365.000, y = -36.000, z = -176.500 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = -380.060, y = 20.603, z = -143.601 },
            { kind = 'chest', x = -333.356, y = -0.481, z = -144.016 },
            { kind = 'chest', x = -250.738, y = 72.633, z = -144.019 },
            { kind = 'chest', x = -220.087, y = 19.370, z = -143.601 },
        },
    },
    [184] = {
        name = 'Lower Delkfutt\'s Tower',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 46, x = 464.000, y = -51.000, z = 0.000 },
        }),
        treasure_spawns = {},
    },
    [192] = {
        name = 'Inner Horutoto Ruins',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 30, x = 453.000, y = 182.300, z = -8.000 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = -177.956, y = -220.058, z = -0.002 },
        },
    },
    [240] = {
        name = 'Port Windurst',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 22, x = -188.000, y = 101.000, z = -4.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 23, x = -207.000, y = 210.000, z = -8.159 },
            { kind = 'home_point', name = 'Home Point #3', unlock_index = 24, x = 180.000, y = 226.000, z = -12.000 },
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 2, x = -220.000, y = 179.000, z = -8.284 },
        }),
        treasure_spawns = {},
    },
    [242] = {
        name = 'Heaven\'s Tower',
        stock_calibration = true,
        travel_references = travel_reference_set({}),
        treasure_spawns = {},
    },
    [115] = {
        name = 'West Sarutabaruta',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 28, x = -13.322, y = 315.696, z = -12.458 },
        }),
        treasure_spawns = {},
    },
    [116] = {
        name = 'East Sarutabaruta',
        stock_calibration = true,
        travel_references = travel_reference_set({}),
        treasure_spawns = {},
    },
    [117] = {
        name = 'Tahrongi Canyon',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 32, x = -160.000, y = 648.000, z = 47.000 },
        }),
        treasure_spawns = {},
    },
    [118] = {
        name = 'Buburimu Peninsula',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 33, x = -485.700, y = 46.000, z = -32.000 },
        }),
        treasure_spawns = {},
    },
    [145] = {
        name = 'Giddeus',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 54, x = -132.000, y = -303.000, z = -3.000 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = -158.563, y = -226.058, z =  0.999 },
            { kind = 'chest', x = -103.777, y = -254.271, z = -0.900 },
            { kind = 'chest', x = -242.625, y = -185.404, z =  0.935 },
            { kind = 'chest', x = -267.030, y = -263.207, z = -2.156 },
            { kind = 'chest', x =  -23.626, y = -105.747, z =  0.982 },
            { kind = 'chest', x =   63.712, y = -254.442, z = -0.900 },
            { kind = 'chest', x =  125.386, y = -259.326, z = -3.168 },
            { kind = 'chest', x =  100.137, y = -230.499, z =  1.387 },
            { kind = 'chest', x =  113.058, y = -224.402, z =  1.000 },
            { kind = 'chest', x =  182.259, y = -230.619, z =  0.915 },
            { kind = 'chest', x =  213.192, y = -299.255, z = -2.309 },
        },
    },
    [194] = {
        name = 'Outer Horutoto Ruins',
        stock_calibration = true,
        travel_references = travel_reference_set({}),
        treasure_spawns = {
            { kind = 'chest', x = -423.066, y = 672.483, z = 0.000 },
        },
    },
    [198] = {
        name = 'Maze of Shakhrami',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 34, page_id = 15, x = -338.990, y = -179.000, z = -12.210 },
        }),
        treasure_spawns = {
            { kind = 'chest', page_id = 16, x =  290.287, y = -138.060, z = 20.238 },
            { kind = 'chest', page_id = 15, x =  -36.474, y =  -70.480, z =  0.063 },
            { kind = 'chest', page_id = 15, x =  260.698, y =   54.472, z = -1.274 },
            { kind = 'chest', page_id = 16, x =  125.956, y =   10.593, z = 19.805 },
            { kind = 'chest', page_id = 16, x =  -54.923, y =  -19.130, z = 18.781 },
            { kind = 'chest', page_id = 16, x =  -90.151, y = -103.097, z = 15.670 },
            { kind = 'chest', page_id = 16, x = -130.046, y =  -43.970, z = 19.263 },
            { kind = 'chest', page_id = 16, x =  -58.153, y =  -62.085, z = 20.000 },
            { kind = 'chest', page_id = 16, x =  -25.615, y =  -52.841, z = 19.763 },
            { kind = 'chest', page_id = 16, x =    0.785, y = -165.362, z = 20.000 },
            { kind = 'chest', page_id = 15, x =  397.238, y =  -29.854, z = -0.351 },
            { kind = 'chest', page_id = 16, x =  219.757, y =  -63.968, z = 18.799 },
            { kind = 'chest', page_id = 16, x =  239.982, y =  -69.393, z = 20.322 },
            { kind = 'chest', page_id = 16, x =  216.466, y = -144.039, z = 20.200 },
            { kind = 'chest', page_id = 16, x =  231.585, y = -193.004, z = 20.000 },
            { kind = 'chest', page_id = 16, x =  270.951, y = -247.144, z = 20.000 },
        },
    },
    [238] = {
        name = 'Windurst Waters',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 17, x = -32.022, y =  131.741, z = -5.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 18, x = 138.000, y =  -14.000, z =  0.001 },
            { kind = 'home_point', name = 'Home Point #3', unlock_index = 103, x =   5.000, y = -175.000, z = -4.000 },
            { kind = 'home_point', name = 'Home Point #4', unlock_index = 118, x = -92.000, y =   54.000, z = -2.000 },
        }),
        treasure_spawns = {},
    },
}
