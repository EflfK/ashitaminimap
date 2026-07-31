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
    [100] = {
        name = 'West Ronfaure',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 6, x = -451.400, y = -218.000, z = -19.750 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Fungus Beetle', z = -20.740, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -226.570, y = -164.240 } } },
            { name = 'Jaggedy-Eared Jack', z = -19.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -281.000, y = -220.000 } } },
            { name = 'Marauder Dvogzog', z = -39.630, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -695.249, y = 21.575 } } },
        },
    },
    [101] = {
        name = 'East Ronfaure',
        stock_calibration = true,
        travel_references = travel_reference_set({}),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Rambukk', z = -20.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 236.000, y = -114.000 } } },
            { name = 'Bigmouth Billy', z = -30.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 476.000, y = -32.000 } } },
        },
    },
    [102] = {
        name = 'La Theine Plateau',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 28, x = 775.000, y = -18.000, z = 28.500 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Slumbering Samwell', z = 16.400, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 55.550, y = 94.000 } } },
            { name = 'Tumbling Truffle', z = 70.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 434.000, y = 241.000 } } },
            { name = 'Lumbering Lambert', z = -8.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -216.000, y = -107.000 } } },
            { name = 'Bloodtear Baldurf', z = 8.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 88.000, y = -239.000 } } },
            { name = 'Goblin Archaeologist', z = 23.593, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 342.811, y = -10.756 } } },
            { name = 'Nihniknoovi', z = 24.147, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 211.066, y = 257.961 } } },
        },
    },
    [103] = {
        name = 'Valkurm Dunes',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 11, x = 137.900, y = 97.000, z = -7.500 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Valkurm Emperor', z = -0.010, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -211.000, y = -34.000 } } },
            { name = 'Golden Bat', z = -8.270, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -810.440, y = 33.978 } } },
            { name = 'Marchelute', z = -10.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -716.000, y = 66.000 } } },
            { name = 'Doman', z = -4.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -768.000, y = 197.000 } } },
            { name = 'Onryo', z = -4.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -767.000, y = 196.000 } } },
        },
    },
    [104] = {
        name = 'Jugner Forest',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 2, x = 63.000, y = -14.000, z = 0.400 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'King Arthro', z = 5.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -144.000, y = 474.000 } } },
            { name = 'Meteormauler Zhagtegg', z = -8.180, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -232.300, y = -571.660 } } },
            { name = 'Fraelissa', z = -0.493, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 9.320, y = -371.654 } } },
            { name = 'Fradubio', z = -0.901, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 76.573, y = -246.241 } } },
            { name = 'Supplespine Mujwuj', z = -0.184, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 50.114, y = -240.493 } } },
            { name = 'Sappy Sycamore', z = 0.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 266.000, y = 284.000 } } },
            {
                name = 'Panzer Percival',
                z = 0.044,
                floor = 'SURFACE',
                spawn_type = 'Fixed',
                placeholder_count = 0,
                points = {
                    { x = 585.027, y = 203.418 },
                    { x = 239.541, y = 559.722 },
                },
            },
        },
    },
    [105] = {
        name = 'Batallia Downs',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 29, x = -67.000, y = 449.000, z = -2.000 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Lumber Jack', z = -23.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -670.000, y = 352.000 } } },
            { name = 'Skirling Liger', z = -16.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -394.000, y = 206.000 } } },
            { name = 'Tottering Toby', z = -7.872, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -255.542, y = 185.826 } } },
            { name = 'Eyegouger', z = -2.100, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 177.300, y = -54.540 } } },
            { name = 'Prankster Maverix', z = 7.500, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 159.000, y = -314.000 } } },
            { name = 'Ahtu', z = 15.258, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 187.811, y = -554.714 } } },
            { name = 'Sturmtiger', z = 16.462, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 145.373, y = -548.560 } } },
            { name = 'Badshah', z = -9.124, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -45.625, y = 310.523 } } },
            { name = 'Vegnix Greenthumb', z = -23.507, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -407.526, y = 412.544 } } },
            { name = 'Suparna', z = 15.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 210.000, y = -606.000 } } },
        },
    },
    [106] = {
        name = 'North Gustaberg',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 3, x = -582.687, y = 52.281, z = 40.107 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            {
                name = 'Stinging Sophie',
                z = -40.400,
                floor = 'SURFACE',
                spawn_type = 'Fixed',
                placeholder_count = 0,
                points = {
                    { x = 234.104, y = 462.288 },
                    { x = 340.381, y = 601.786 },
                },
            },
            { name = 'Bedrock Barry', z = -0.650, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -189.000, y = 268.000 } } },
            { name = 'Maighdean Uaine', z = -0.324, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 272.000, y = 797.800 } } },
        },
    },
    [107] = {
        name = 'South Gustaberg',
        stock_calibration = true,
        travel_references = travel_reference_set({}),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Bubbly Bernie', z = -2.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 745.000, y = -671.000 } } },
            { name = 'Tococo', z = 0.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -53.000, y = -197.000 } } },
            { name = 'Carnero', z = -40.010, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 160.748, y = -423.153 } } },
            { name = 'Carnero', z = -39.970, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 159.616, y = -461.112 } } },
            { name = 'Leaping Lizzy', z = 21.444, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -283.760, y = -412.182 } } },
            { name = 'Leaping Lizzy', z = 29.731, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -339.499, y = -441.475 } } },
        },
    },
    [108] = {
        name = 'Konschtat Highlands',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 30, x = -222.000, y = 827.000, z = 71.200 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Ghillie Dhu', z = -8.873, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 387.000, y = -338.999 } } },
            { name = 'Stray Mary', z = -15.805, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -257.465, y = -117.638 } } },
            { name = 'Stray Mary', z = 39.477, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -212.268, y = 329.581 } } },
            { name = 'Rampaging Ram', z = 24.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 160.000, y = 121.000 } } },
            { name = 'Steelfleece Baldarich', z = 7.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -10.000, y = 45.000 } } },
            { name = 'Highlander Lizard', z = 2.901, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -499.000, y = -48.000 } } },
            { name = 'Forger', z = 2.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -710.000, y = 102.000 } } },
            { name = 'Haty', z = 8.118, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -204.271, y = 36.959 } } },
            { name = 'Bendigeit Vran', z = 24.440, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -2.110, y = 105.396 } } },
        },
    },
    [109] = {
        name = 'Pashhow Marshlands',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 4, x = 467.000, y = 410.000, z = 24.489 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Bloodpool Vorax', z = 24.014, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -351.884, y = 513.531 } } },
            { name = 'Jolly Green', z = 24.499, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 184.993, y = -41.790 } } },
            { name = 'Ni\'Zho Bladebender', z = 24.500, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -429.953, y = -305.450 } } },
            { name = 'Ni\'Zho Bladebender', z = 23.904, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 11.309, y = -337.923 } } },
            { name = 'Toxic Tamlyn', z = 24.500, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -79.520, y = -12.540 } } },
            { name = 'Bo\'Who Warmonger', z = 24.500, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 467.436, y = -342.082 } } },
        },
    },
    [110] = {
        name = 'Rolanberry Fields',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 31, x = -228.000, y = 386.000, z = 4.120 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Silk Caterpillar', z = 0.380, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 340.000, y = 179.000 } } },
            { name = 'Black Triple Stars', z = -15.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 5.000, y = -142.000 }, { x = 76.000, y = -209.000 } } },
            { name = 'Ravenous Crawler', z = -8.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -488.800, y = -37.888 } } },
            { name = 'Eldritch Edge', z = -24.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 395.000, y = -147.000 } } },
            { name = 'Drooling Daisy', z = -31.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -763.000, y = -414.000 } } },
            { name = 'Simurgh', z = -31.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -681.000, y = -447.000 } } },
        },
    },
    [119] = {
        name = 'Meriphataud Mountains',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 36, x = -297.760, y = 422.220, z = 17.000 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Naa Zeku the Unwaiting', z = -1.452, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 407.659, y = -319.434 } } },
            { name = 'Daggerclaw Dracos', z = -16.372, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 630.430, y = -494.748 } } },
            { name = 'Waraxe Beak', z = -16.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 723.000, y = -397.000 } } },
            { name = 'Coo Keja the Unseen', z = -23.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 684.000, y = 6.000 } } },
            { name = 'Patripatan', z = -32.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 548.000, y = 600.000 } } },
        },
    },
    [120] = {
        name = 'Sauromugue Champaign',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 33, x = 344.000, y = -256.000, z = 5.659 },
        }),
        treasure_spawns = {},
        -- Static possible-spawn references from CatsEyeXI's pinned mob
        -- scripts and SQL tables. They never imply current position or status.
        nm_spawn_ranges = {
            { name = 'Bashe', z = 6.167, floor = 'SURFACE', spawn_type = 'Lottery', placeholder_count = 1, points = { { x = 537.188, y = -11.067 } } },
            { name = 'Thunderclaw Thuban', z = 16.568, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 423.313, y = -110.108 } } },
            { name = 'Blighting Brand', z = 8.000, floor = 'SURFACE', spawn_type = 'Lottery', placeholder_count = 1, points = { { x = -206.692, y = 203.594 } } },
            { name = 'Climbpix Highrise', z = 23.461, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 481.000, y = 122.486 } } },
            {
                name = 'Deadly Dodo',
                z = 40.000,
                floor = 'SURFACE',
                spawn_type = 'Lottery',
                placeholder_count = 2,
                points = {
                    { x = 238.000, y = 332.000 },
                    { x = 369.564, y = 345.197 },
                    { x = 328.456, y = 376.753 },
                    { x = 384.242, y = 345.813 },
                    { x = 327.897, y = 350.973 },
                    { x = 404.505, y = 403.374 },
                    { x = 263.360, y = 342.539 },
                    { x = 339.739, y = 391.518 },
                    { x = 229.505, y = 371.338 },
                    { x = 365.048, y = 390.478 },
                    { x = 173.271, y = 322.801 },
                    { x = 381.082, y = 362.725 },
                    { x = 370.385, y = 354.382 },
                    { x = 269.881, y = 393.710 },
                    { x = 241.439, y = 335.035 },
                    { x = 355.667, y = 396.811 },
                    { x = 232.523, y = 326.570 },
                    { x = 295.417, y = 384.079 },
                    { x = 155.492, y = 322.630 },
                    { x = 376.117, y = 343.626 },
                    { x = 318.375, y = 309.192 },
                    { x = 371.433, y = 418.874 },
                    { x = 307.933, y = 395.163 },
                    { x = 296.978, y = 371.670 },
                    { x = 307.392, y = 326.009 },
                    { x = 394.457, y = 400.577 },
                    { x = 319.657, y = 301.196 },
                    { x = 375.655, y = 337.488 },
                    { x = 242.533, y = 433.637 },
                    { x = 359.589, y = 410.539 },
                    { x = 421.166, y = 351.784 },
                    { x = 184.439, y = 328.015 },
                    { x = 340.725, y = 371.943 },
                    { x = 336.696, y = 364.475 },
                    { x = 297.261, y = 397.454 },
                    { x = 409.999, y = 353.385 },
                    { x = 304.080, y = 383.142 },
                    { x = 306.665, y = 293.697 },
                    { x = 265.350, y = 374.965 },
                    { x = 295.028, y = 360.490 },
                    { x = 436.733, y = 352.380 },
                    { x = 385.814, y = 382.925 },
                    { x = 368.035, y = 371.062 },
                    { x = 155.198, y = 311.945 },
                    { x = 331.332, y = 314.518 },
                    { x = 458.460, y = 364.424 },
                    { x = 426.908, y = 374.069 },
                    { x = 259.169, y = 323.145 },
                    { x = 194.506, y = 315.032 },
                    { x = 221.046, y = 364.831 },
                },
            },
            {
                name = 'Roc',
                z = -0.010,
                floor = 'SURFACE',
                spawn_type = 'Fixed',
                placeholder_count = 0,
                points = {
                    { x = 232.000, y = -327.000 },
                    { x = 213.997, y = -255.685 },
                    { x = 260.032, y = -306.151 },
                    { x = 279.663, y = -328.021 },
                    { x = 308.569, y = -295.158 },
                    { x = 205.831, y = -243.033 },
                    { x = 197.226, y = -295.616 },
                    { x = 367.044, y = -309.743 },
                    { x = 198.305, y = -258.350 },
                    { x = 252.489, y = -328.980 },
                    { x = 203.876, y = -236.865 },
                    { x = 240.723, y = -310.858 },
                    { x = 255.410, y = -340.951 },
                    { x = 209.015, y = -224.618 },
                    { x = 196.563, y = -273.294 },
                    { x = 266.925, y = -330.613 },
                    { x = 200.236, y = -298.671 },
                    { x = 212.020, y = -235.566 },
                    { x = 216.767, y = -250.954 },
                    { x = 277.400, y = -350.978 },
                    { x = 209.989, y = -244.348 },
                    { x = 214.700, y = -264.888 },
                    { x = 173.726, y = -244.018 },
                    { x = 202.205, y = -271.049 },
                    { x = 229.122, y = -320.375 },
                    { x = 210.545, y = -238.031 },
                    { x = 211.885, y = -273.763 },
                    { x = 235.673, y = -263.352 },
                    { x = 195.317, y = -287.885 },
                    { x = 153.669, y = -226.129 },
                    { x = 206.695, y = -267.380 },
                    { x = 270.178, y = -334.811 },
                    { x = 300.981, y = -305.046 },
                    { x = 240.526, y = -323.063 },
                    { x = 197.310, y = -272.637 },
                    { x = 354.299, y = -280.288 },
                    { x = 188.566, y = -296.794 },
                    { x = 263.840, y = -321.000 },
                    { x = 215.711, y = -312.421 },
                    { x = 212.596, y = -249.303 },
                    { x = 189.023, y = -196.885 },
                    { x = 260.332, y = -332.862 },
                    { x = 195.192, y = -194.328 },
                    { x = 199.956, y = -278.615 },
                    { x = 346.999, y = -318.475 },
                    { x = 266.687, y = -346.511 },
                    { x = 191.796, y = -250.968 },
                    { x = 304.025, y = -326.122 },
                    { x = 248.637, y = -355.112 },
                    { x = 321.210, y = -282.105 },
                },
            },
        },
    },
    [123] = {
        name = 'Yuhtunga Jungle',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 14, x = -239.500, y = -404.000, z = 0.000 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Koropokkur', z = 0.058, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -301.557, y = 207.924 } } },
            { name = 'Mischievous Micholas', z = 3.317, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -279.575, y = 16.011 } } },
            { name = 'Meww the Turtlerider', z = 17.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -384.000, y = -390.000 } } },
            { name = 'Pyuu the Spatemaker', z = 7.923, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -20.295, y = -113.263 } } },
            { name = 'Rose Garden', z = 10.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 50.000, y = 245.000 } } },
            { name = 'Bayawak', z = 3.476, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 277.882, y = 289.117 } } },
        },
    },
    [124] = {
        name = 'Yhoator Jungle',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 31, x = 197.000, y = -81.000, z = 0.001 },
        }),
        treasure_spawns = {},
        -- Static possible-spawn references from CatsEyeXI's pinned mob
        -- scripts and SQL tables. They never imply current position or status.
        nm_spawn_ranges = {
            {
                name = 'Woodland Sage',
                z = 0.345,
                floor = 'SURFACE',
                spawn_type = 'Timed',
                placeholder_count = 0,
                points = {
                    { x = 190.942, y = 94.828 },
                    { x = 219.102, y = 45.071 },
                    { x = 230.358, y = 48.605 },
                    { x = 202.027, y = 65.147 },
                    { x = 199.007, y = 68.804 },
                    { x = 212.211, y = 74.201 },
                    { x = 240.027, y = 42.375 },
                    { x = 242.065, y = 38.085 },
                    { x = 204.844, y = 49.554 },
                    { x = 217.408, y = 47.070 },
                    { x = 197.377, y = 39.511 },
                    { x = 207.544, y = 44.352 },
                    { x = 204.460, y = 35.157 },
                    { x = 204.396, y = 52.528 },
                    { x = 239.277, y = 35.625 },
                    { x = 202.185, y = 51.669 },
                    { x = 237.334, y = 46.159 },
                    { x = 211.807, y = 45.599 },
                    { x = 235.741, y = 60.963 },
                    { x = 206.051, y = 73.292 },
                    { x = 209.542, y = 49.432 },
                    { x = 204.515, y = 52.235 },
                    { x = 200.496, y = 68.871 },
                    { x = 200.374, y = 82.859 },
                    { x = 242.325, y = 77.845 },
                    { x = 232.461, y = 73.944 },
                    { x = 196.364, y = 84.094 },
                    { x = 201.000, y = 38.085 },
                    { x = 203.632, y = 60.683 },
                    { x = 223.634, y = 79.241 },
                    { x = 213.058, y = 46.280 },
                    { x = 239.913, y = 55.617 },
                    { x = 202.871, y = 62.518 },
                    { x = 248.894, y = 36.174 },
                    { x = 234.421, y = 83.652 },
                    { x = 205.247, y = 61.471 },
                    { x = 201.787, y = 58.539 },
                    { x = 208.549, y = 49.520 },
                    { x = 225.314, y = 78.223 },
                    { x = 210.971, y = 34.572 },
                    { x = 218.020, y = 77.149 },
                    { x = 232.770, y = 66.418 },
                    { x = 205.281, y = 46.910 },
                    { x = 190.863, y = 88.761 },
                    { x = 237.683, y = 49.630 },
                    { x = 206.943, y = 43.324 },
                    { x = 207.189, y = 47.552 },
                    { x = 196.674, y = 79.612 },
                    { x = 245.816, y = 41.834 },
                    { x = 239.785, y = 43.552 },
                },
            },
            {
                name = 'Powderer Penny',
                z = -2.531,
                floor = 'SURFACE',
                spawn_type = 'Timed',
                placeholder_count = 0,
                points = {
                    { x = -11.700, y = -123.250 },
                    { x = -3.466, y = -65.710 },
                    { x = 5.283, y = -95.762 },
                    { x = -15.146, y = -145.681 },
                    { x = -15.742, y = -102.386 },
                    { x = -46.099, y = -65.964 },
                    { x = -37.681, y = -124.244 },
                },
            },
            {
                name = 'Acolnahuacatl',
                z = 0.000,
                floor = 'SURFACE',
                spawn_type = 'Timed',
                placeholder_count = 0,
                points = {
                    { x = -242.500, y = -400.400 },
                    { x = -275.045, y = -441.843 },
                    { x = -278.034, y = -359.746 },
                    { x = -201.329, y = -444.798 },
                },
            },
            {
                name = 'Hoar-knuckled Rimberry',
                z = -5.023,
                floor = 'SURFACE',
                spawn_type = 'Lottery',
                placeholder_count = 2,
                points = {
                    { x = 24.922, y = -423.784 },
                    { x = 31.930, y = -407.700 },
                },
            },
            {
                name = 'Bisque-heeled Sunberry',
                z = -18.499,
                floor = 'SURFACE',
                spawn_type = 'Timed',
                placeholder_count = 0,
                points = {
                    { x = 296.401, y = -505.720 },
                    { x = 301.844, y = -526.287 },
                    { x = 297.768, y = -509.508 },
                    { x = 307.721, y = -508.739 },
                    { x = 301.095, y = -520.230 },
                    { x = 300.542, y = -535.823 },
                    { x = 300.282, y = -529.967 },
                    { x = 304.054, y = -542.151 },
                    { x = 307.117, y = -507.640 },
                    { x = 302.125, y = -544.137 },
                    { x = 302.482, y = -512.559 },
                    { x = 300.566, y = -534.386 },
                    { x = 302.281, y = -547.544 },
                    { x = 299.451, y = -499.702 },
                    { x = 298.604, y = -514.682 },
                    { x = 300.656, y = -527.634 },
                    { x = 296.003, y = -504.583 },
                    { x = 307.050, y = -518.318 },
                    { x = 300.211, y = -522.827 },
                    { x = 301.361, y = -515.915 },
                    { x = 300.088, y = -539.121 },
                    { x = 302.978, y = -539.390 },
                    { x = 303.954, y = -502.099 },
                    { x = 299.197, y = -544.995 },
                    { x = 303.977, y = -537.417 },
                    { x = 300.977, y = -512.878 },
                    { x = 304.826, y = -541.718 },
                    { x = 300.991, y = -505.109 },
                    { x = 302.582, y = -531.308 },
                    { x = 300.414, y = -514.964 },
                    { x = 299.397, y = -519.590 },
                    { x = 305.018, y = -520.864 },
                    { x = 301.675, y = -524.355 },
                    { x = 300.797, y = -531.748 },
                    { x = 299.512, y = -540.896 },
                    { x = 297.901, y = -514.013 },
                    { x = 304.629, y = -507.668 },
                    { x = 303.521, y = -532.454 },
                    { x = 307.055, y = -543.625 },
                    { x = 301.880, y = -521.569 },
                    { x = 301.330, y = -524.741 },
                    { x = 303.473, y = -545.524 },
                    { x = 308.312, y = -509.446 },
                    { x = 296.595, y = -505.966 },
                    { x = 302.471, y = -503.336 },
                    { x = 300.448, y = -539.814 },
                    { x = 298.774, y = -508.050 },
                    { x = 302.130, y = -519.046 },
                    { x = 302.110, y = -522.843 },
                    { x = 301.194, y = -531.676 },
                },
            },
            {
                name = 'Bright-handed Kunberry',
                z = -0.500,
                floor = 'SURFACE',
                spawn_type = 'Timed',
                placeholder_count = 0,
                points = {
                    { x = 227.000, y = -169.000 },
                    { x = 170.303, y = -186.105 },
                    { x = 237.418, y = -163.859 },
                    { x = 178.692, y = -165.667 },
                    { x = 202.693, y = -207.127 },
                    { x = 226.649, y = -213.963 },
                    { x = 191.895, y = -157.960 },
                    { x = 204.182, y = -193.331 },
                    { x = 236.195, y = -152.672 },
                    { x = 207.933, y = -173.478 },
                    { x = 222.153, y = -190.471 },
                    { x = 210.044, y = -177.279 },
                    { x = 176.404, y = -175.350 },
                    { x = 197.570, y = -191.125 },
                    { x = 220.152, y = -173.115 },
                    { x = 213.315, y = -183.627 },
                    { x = 200.595, y = -173.745 },
                    { x = 189.502, y = -168.138 },
                    { x = 213.277, y = -213.023 },
                    { x = 174.920, y = -155.508 },
                    { x = 171.491, y = -170.484 },
                    { x = 237.205, y = -156.992 },
                    { x = 212.337, y = -132.387 },
                    { x = 224.991, y = -210.295 },
                    { x = 228.294, y = -164.819 },
                    { x = 181.652, y = -162.661 },
                    { x = 215.317, y = -206.819 },
                    { x = 246.780, y = -188.459 },
                    { x = 206.786, y = -209.796 },
                    { x = 219.540, y = -213.919 },
                    { x = 184.936, y = -135.309 },
                    { x = 173.151, y = -189.729 },
                    { x = 215.816, y = -187.190 },
                    { x = 189.769, y = -131.560 },
                    { x = 222.947, y = -214.094 },
                    { x = 187.531, y = -158.305 },
                    { x = 197.734, y = -202.007 },
                    { x = 185.347, y = -190.552 },
                    { x = 218.084, y = -213.781 },
                    { x = 227.669, y = -159.930 },
                    { x = 204.057, y = -191.613 },
                    { x = 188.184, y = -188.101 },
                    { x = 228.658, y = -152.722 },
                    { x = 178.971, y = -137.914 },
                    { x = 228.911, y = -184.393 },
                    { x = 213.952, y = -151.060 },
                    { x = 231.206, y = -148.838 },
                    { x = 239.555, y = -175.335 },
                    { x = 195.325, y = -159.431 },
                    { x = 220.633, y = -195.269 },
                },
            },
            { name = 'Kappa Akuso', z = -1.000, floor = 'SURFACE', spawn_type = 'Timed', placeholder_count = 0, points = { { x = 205.000, y = 83.000 } } },
            { name = 'Kappa Bonze', z = -1.000, floor = 'SURFACE', spawn_type = 'Timed', placeholder_count = 0, points = { { x = 204.000, y = 83.000 } } },
            { name = 'Kappa Biwa', z = -1.000, floor = 'SURFACE', spawn_type = 'Timed', placeholder_count = 0, points = { { x = 203.000, y = 83.000 } } },
            { name = 'Edacious Opo-opo', z = 0.589, floor = 'SURFACE', spawn_type = 'Timed', placeholder_count = 0, points = { { x = 544.436, y = -436.372 } } },
        },
    },
    [126] = {
        name = 'Qufim Island',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 9, x = -252.000, y = 297.000, z = -20.000 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Slippery Sucker', z = -21.300, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 16.350, y = -25.500 } } },
            { name = 'Atkorkamuy', z = -20.821, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -200.381, y = -8.813 } } },
            { name = 'Trickster Kinetix', z = -19.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -159.000, y = 244.000 } } },
            { name = 'Qoofim', z = -21.820, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -108.200, y = 388.200 } } },
            { name = 'Dosetsu Tree', z = -20.795, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -240.000, y = 37.000 } } },
        },
    },
    [140] = {
        name = 'Ghelsba Outpost',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 2, x = -143.000, y = 7.000, z = -20.000 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {
            { name = 'Fodderchief Vokdek', z = -10.048, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -188.703, y = 45.326 } } },
            { name = 'Sureshot Snatgat', z = -10.554, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -188.164, y = 55.693 } } },
            { name = 'Strongarm Zodvad', z = -10.006, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -177.171, y = 50.070 } } },
            { name = 'Warchief Vatgit', z = -34.692, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -74.960, y = 256.968 } } },
            { name = 'Fogweaver Mozzfuzz', z = -33.723, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -84.454, y = 265.104 } } },
            { name = 'Thousandarm Deshglesh', z = -0.500, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 124.367, y = 326.606 } } },
        },
    },
    [141] = {
        name = 'Fort Ghelsba',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 34, x = -143.000, y = 7.000, z = -20.000 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = 62.583, y = 21.578, z = -61.584 },
            { kind = 'chest', x = 177.589, y = 47.830, z = -84.118 },
            { kind = 'chest', x = 114.363, y = 104.614, z = -45.114 },
            { kind = 'chest', x = 165.383, y = 139.055, z = -32.000 },
            { kind = 'chest', x = 143.690, y = -102.603, z = -45.584 },
        },
        nm_spawn_ranges = {
            { name = 'Hundredscar Hajwaj', z = -28.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 1.000, y = -52.000 } } },
            { name = 'Chariotbuster Byakzak', z = -44.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 49.000, y = -132.000 } } },
            { name = 'Kegpaunch Doshgnosh', z = -44.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 43.773, y = -119.706 } } },
        },
    },
    [142] = {
        name = 'Yughott Grotto',
        stock_calibration = true,
        travel_references = travel_reference_set({}),
        treasure_spawns = {
            { kind = 'chest', x = 143.385, y = 132.887, z = -12.362 },
            { kind = 'chest', x = 363.764, y = 167.509, z = -24.250 },
            { kind = 'chest', x = 216.953, y = 49.284, z = -12.468 },
            { kind = 'chest', x = 63.413, y = 11.611, z = -0.081 },
            { kind = 'chest', x = 12.770, y = 36.825, z = -0.383 },
            { kind = 'chest', x = -12.144, y = -63.396, z = -0.206 },
            { kind = 'chest', x = -151.230, y = -21.489, z = -0.359 },
        },
        nm_spawn_ranges = {
            { name = 'Ashmaker Gotblut', z = -0.903, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 11.669, y = -22.245 } } },
        },
    },
    [143] = {
        name = 'Palborough Mines',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 53, x = 109.000, y = -147.000, z = -38.500 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = 250.037, y = 174.156, z = -32.069 },
            { kind = 'chest', x = 241.950, y = 59.927, z = -31.769 },
            { kind = 'chest', x = 259.068, y = -71.901, z = -31.625 },
            { kind = 'chest', x = 219.331, y = 4.665, z = -31.595 },
            { kind = 'chest', x = 216.795, y = -71.373, z = -31.527 },
            { kind = 'chest', x = 262.397, y = 87.518, z = -32.202 },
            { kind = 'chest', x = 179.993, y = 93.280, z = -31.956 },
            { kind = 'chest', x = 139.909, y = 146.845, z = -31.957 },
            { kind = 'chest', x = 99.115, y = 83.067, z = -32.000 },
            { kind = 'chest', x = 21.141, y = 81.473, z = -31.944 },
            { kind = 'chest', x = 59.776, y = 5.373, z = -31.592 },
            { kind = 'chest', x = 99.917, y = -41.557, z = -32.000 },
        },
        nm_spawn_ranges = {
            { name = 'Be\'Hya Hundredwall', z = -31.230, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 258.800, y = -63.300 }, { x = 263.306, y = -54.164 }, { x = 266.467, y = -23.933 }, { x = 253.786, y = -15.844 } } },
            { name = 'Bu\'Ghi Howlblade', z = -15.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 170.000, y = 179.000 }, { x = 170.000, y = 165.000 }, { x = 166.000, y = 135.000 }, { x = 167.207, y = 159.374 }, { x = 185.502, y = 175.730 } } },
            { name = 'Qu\'Vho Deathhurler', z = -15.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 124.000, y = 242.000 }, { x = 120.000, y = 238.000 }, { x = 128.000, y = 249.000 }, { x = 121.000, y = 245.000 }, { x = 115.000, y = 246.000 } } },
            { name = 'Zi\'Ghi Boneeater', z = -32.500, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 138.839, y = 72.357 }, { x = 138.747, y = 88.684 }, { x = 128.329, y = 86.223 }, { x = 127.134, y = 70.341 } } },
            { name = 'No\'Mho Crimsonarmor', z = -31.675, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 20.433, y = -97.176 } } },
            { name = 'Ni\'Ghu Nestfender', z = -31.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 14.000, y = -94.000 } } },
        },
    },
    [147] = {
        name = 'Beadeaux',
        stock_calibration = true,
        -- Beadeaux has three stock records with a common transform. Pages 1
        -- and 15 have deterministic authored structure. Page 16 is the
        -- client's Dummy Map and remains vanilla-only until live traversal
        -- proves whether it owns reachable geometry.
        structure_pages = {
            [1] = structure_layer_set({
                {
                    image = 'assets/maps/147_01_lower_structure.png',
                    minimum_player_z = -12.3,
                    maximum_player_z = -5.3,
                },
                {
                    image = 'assets/maps/147_01_main_structure.png',
                    minimum_player_z = -4.7,
                    maximum_player_z = 8.3,
                },
            }),
            [15] = structure_layer_set({
                {
                    image = 'assets/maps/147_15_connector_structure.png',
                    minimum_player_z = 7.5,
                    maximum_player_z = 18.5,
                },
                {
                    image = 'assets/maps/147_15_mid_structure.png',
                    minimum_player_z = 18.5,
                    maximum_player_z = 25.0,
                },
                {
                    image = 'assets/maps/147_15_deep_structure.png',
                    minimum_player_z = 25.0,
                    maximum_player_z = 41.5,
                },
            }),
        },
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        -- Exact FFXiMain records for pages 1, 15, and 16 all use scale byte
        -- 2 and offsets (-272,-256).
        origin_x = 272.0,
        origin_y = 256.0,
        grid_origin_x = 256.0,
        grid_origin_y = 256.0,
        grid_yalms = 80,
        image_pixels_per_yalm = 0.40,
        travel_references = travel_reference_set({
            {
                kind = 'survival_guide',
                name = 'Survival Guide',
                unlock_bit = 26,
                x = -264.000,
                y = 107.000,
                z = 1.550,
                page_id = 1,
            },
        }),
        -- Fixed CatsEyeXI chest and coffer possibilities. Source tuples are
        -- (x, vertical, horizontal); minimap records are (x, horizontal,
        -- vertical). These references never inspect the live treasure NPC.
        treasure_spawns = {
            { kind = 'chest',  page_id =  1, x =  81.814, y =   1.523, z = -3.250 },
            { kind = 'chest',  page_id =  1, x = 122.451, y = 132.482, z = -2.468 },
            { kind = 'chest',  page_id =  1, x = 159.081, y =  78.207, z = -3.275 },
            { kind = 'chest',  page_id =  1, x = 150.931, y =  30.893, z = -2.969 },
            { kind = 'chest',  page_id =  1, x = 252.520, y = -56.725, z = -3.000 },
            { kind = 'chest',  page_id =  1, x = 161.465, y = -58.075, z = -3.000 },
            { kind = 'chest',  page_id =  1, x = 274.491, y =  45.577, z = -3.249 },
            { kind = 'chest',  page_id =  1, x = 272.330, y = 125.156, z = -3.338 },
            { kind = 'chest',  page_id =  1, x = 170.554, y = 174.293, z = -3.000 },
            { kind = 'chest',  page_id =  1, x = 107.592, y = 215.188, z = -3.000 },
            { kind = 'chest',  page_id =  1, x =  82.216, y = 117.415, z = -3.196 },
            { kind = 'chest',  page_id =  1, x =  22.898, y =  84.606, z = -2.981 },
            { kind = 'coffer', page_id = 15, x = 216.974, y =  68.790, z = 39.702 },
            { kind = 'coffer', page_id = 15, x = 369.956, y =  59.954, z = 24.075 },
            { kind = 'coffer', page_id = 15, x = 414.430, y =  91.361, z = 23.859 },
            { kind = 'coffer', page_id = 15, x = 380.187, y = 150.749, z = 24.019 },
            { kind = 'coffer', page_id = 15, x = 330.943, y =  99.591, z = 24.244 },
            { kind = 'coffer', page_id = 15, x = 256.112, y = 149.514, z = 39.805 },
            { kind = 'coffer', page_id = 15, x = 187.398, y =  95.752, z = 39.999 },
            { kind = 'coffer', page_id = 15, x = 170.601, y =  25.066, z = 39.831 },
        },
        -- Static initial-spawn and placeholder references from the pinned
        -- CatsEyeXI mob scripts and SQL tables. They report no live status.
        nm_spawn_ranges = {
            {
                name = 'Bi\'Gho Headtaker',
                page_id = 1,
                z = 1.000,
                floor = 'MAP 1',
                spawn_type = 'Lottery',
                level = '25',
                placeholder_count = 1,
                points = {
                    { x = -97.000, y = 78.000 },
                    { x = -98.611, y = 71.212 },
                },
            },
            {
                name = 'Da\'Dha Hundredmask',
                page_id = 1,
                z = 1.000,
                floor = 'MAP 1',
                spawn_type = 'Lottery',
                level = '30',
                placeholder_count = 1,
                points = {
                    { x = -184.000, y = -136.000 },
                    { x =  -71.480, y =  -62.882 },
                },
            },
            {
                name = 'Ge\'Dha Evileye',
                page_id = 1,
                z = 1.000,
                floor = 'MAP 1',
                spawn_type = 'Lottery',
                level = '30',
                placeholder_count = 1,
                points = {
                    { x = -238.000, y = -203.000 },
                    { x = -242.709, y = -188.010 },
                },
            },
            {
                name = 'Zo\'Khu Blackcloud',
                page_id = 1,
                z = -3.000,
                floor = 'MAP 1',
                spawn_type = 'Lottery',
                level = '36-38',
                placeholder_count = 1,
                points = {
                    { x = -273.000, y = -253.000 },
                    { x = -294.223, y = -206.657 },
                },
            },
            {
                name = 'Go\'Bhu Gascon',
                page_id = 1,
                z = -2.000,
                floor = 'MAP 1',
                spawn_type = 'Timed',
                level = '41-42',
                placeholder_count = 0,
                points = {
                    { x = -202.000, y = 110.000 },
                },
            },
            {
                name = 'De\'Vyu Headhunter',
                page_id = 1,
                z = -3.486,
                floor = 'MAP 1',
                spawn_type = 'Timed',
                level = '45',
                placeholder_count = 0,
                points = {
                    { x = 33.747, y = -130.112 },
                },
            },
            {
                name = 'Ga\'Bhu Unvanquished',
                page_id = 1,
                z = -3.199,
                floor = 'MAP 1',
                spawn_type = 'Lottery',
                level = '47-48',
                placeholder_count = 1,
                points = {
                    { x = 178.863, y = 192.895 },
                    { x = 139.642, y = 161.557 },
                },
            },
            {
                name = 'Magnes Quadav',
                page_id = 1,
                z = -3.519,
                floor = 'MAP 1',
                spawn_type = 'Quest',
                level = '43-45',
                placeholder_count = 0,
                points = {
                    { x = -81.333, y = -125.682 },
                    { x = -84.954, y = -120.894 },
                },
            },
            {
                name = 'Nickel Quadav',
                page_id = 1,
                z = -3.183,
                floor = 'MAP 1',
                spawn_type = 'Quest',
                level = '43-45',
                placeholder_count = 0,
                points = {
                    { x = -81.171, y = -129.277 },
                    { x = -88.153, y = -118.159 },
                },
            },
        },
    },
    [235] = {
        name = 'Bastok Markets',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 11, x = -344.000, y = -155.000, z = -10.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 12, x = -328.000, y = -33.000, z = -12.000 },
            { kind = 'home_point', name = 'Home Point #3', unlock_index = 13, x = -189.000, y = 26.000, z = -8.000 },
            { kind = 'home_point', name = 'Home Point #4', unlock_index = 100, x = -191.000, y = -69.000, z = -6.000 },
        }),
        treasure_spawns = {},
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
    [149] = {
        name = 'Davoi',
        stock_calibration = true,
        -- The raised east platform is on this same stock page but has no
        -- direct walkable connection from the surrounding ground. Preserve
        -- its violet component boundary instead of flattening it into the
        -- cyan ground network. Neither layer participates in global
        -- player-Z selection because Davoi's ordinary terrain varies in Z.
        structure_layers = structure_layer_set({
            {
                image = 'assets/maps/149_structure.png',
                floor_selection = 'always',
            },
            {
                image = 'assets/maps/149_elevated_structure.png',
                floor_selection = 'always',
            },
        }),
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        -- Exact FFXiMain page-0 record: scale byte 2 and offsets
        -- (-240,-208). The imported vanilla page supplies the printed grid.
        origin_x = 240.0,
        origin_y = 208.0,
        grid_origin_x = 256.0,
        grid_origin_y = 256.0,
        grid_yalms = 80,
        image_pixels_per_yalm = 0.40,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 36, x = 223.000, y = -10.000, z = -0.699 },
        }),
        -- Fixed possible Treasure Chest locations from CatsEyeXI's public
        -- scripts/globals/treasure.lua. Source tuples use
        -- (x, vertical, horizontal); minimap positions use (x, horizontal).
        -- These are reference markers only and never inspect the live chest.
        treasure_spawns = {
            { kind = 'chest', x =  235.907, y = -251.378, z =  3.629 },
            { kind = 'chest', x =  290.556, y = -291.040, z =  2.731 },
            { kind = 'chest', x =  297.370, y = -219.350, z =  3.250 },
            { kind = 'chest', x =  327.747, y = -190.758, z =  3.500 },
            { kind = 'chest', x =  165.449, y = -267.748, z = -0.632 },
            { kind = 'chest', x =  115.242, y = -252.004, z = -0.546 },
            { kind = 'chest', x =   65.686, y = -347.556, z =  0.628 },
            { kind = 'chest', x =   63.105, y = -191.565, z = -2.659 },
            { kind = 'chest', x = -109.608, y =   50.392, z =  2.693 },
            { kind = 'chest', x =  -59.329, y =   10.691, z = -0.672 },
            { kind = 'chest', x =  -59.163, y =   69.200, z = -0.459 },
            { kind = 'chest', x =  -14.535, y =  -67.930, z =  0.583 },
        },
        -- Static initial-spawn and placeholder references from CatsEyeXI's
        -- public Davoi mob scripts and SQL tables. They never inspect NM
        -- status, select a current placeholder, or report a live location.
        nm_spawn_ranges = {
            {
                name = 'Hawkeyed Dnatbat',
                z = -0.582,
                floor = 'SURFACE',
                spawn_type = 'Lottery',
                level = '26-28',
                placeholder_count = 3,
                points = {
                    { x = 333.895, y = -144.558 },
                    { x = 337.116, y = -110.483 },
                    { x = 336.498, y = -138.502 },
                    { x = 371.525, y = -176.188 },
                },
            },
            {
                name = 'Steelbiter Gudrud',
                z = 4.000,
                floor = 'SURFACE',
                spawn_type = 'Lottery',
                level = '33-34',
                placeholder_count = 1,
                points = {
                    { x = 244.000, y = -240.000 },
                    { x = 252.457, y = -248.655 },
                },
            },
            {
                name = 'Tigerbane Bakdak',
                z = 2.068,
                floor = 'SURFACE',
                spawn_type = 'Lottery',
                level = '31-32',
                placeholder_count = 2,
                points = {
                    { x = 174.212, y = -20.285 },
                    { x = 158.000, y = -18.000 },
                    { x = 153.880, y = -18.092 },
                },
            },
            {
                name = 'Poisonhand Gnadgad',
                z = -0.517,
                floor = 'SURFACE',
                spawn_type = 'Lottery',
                level = '39-40',
                placeholder_count = 8,
                points = {
                    { x = -61.045, y = 41.996 },
                    { x = -53.910, y = 56.606 },
                    { x = -62.647, y = 24.442 },
                    { x = -64.578, y = 61.273 },
                    { x = -59.013, y = 14.783 },
                    { x = -50.158, y = 22.257 },
                    { x = -56.626, y = 63.285 },
                    { x = -54.694, y = 42.385 },
                    { x = -60.057, y = 29.127 },
                },
            },
            {
                name = 'Blubbery Bulge',
                z = 2.295,
                floor = 'SURFACE',
                spawn_type = 'Lottery',
                level = '45-47',
                placeholder_count = 1,
                points = {
                    { x = -225.237, y = -294.764 },
                },
            },
            {
                name = 'Dirtyhanded Gochakzuk',
                z = -12.073,
                floor = 'SURFACE',
                spawn_type = 'Fixed',
                level = '71',
                placeholder_count = 0,
                points = {
                    { x = 56.259, y = -152.955 },
                },
            },
            {
                name = 'Purpleflash Brukdok',
                z = -0.091,
                floor = 'SURFACE',
                spawn_type = 'Fixed',
                level = '45',
                placeholder_count = 0,
                points = {
                    { x = -135.469, y = -184.703 },
                },
            },
            {
                name = 'Hematic Cyst',
                z = 3.676,
                floor = 'SURFACE',
                spawn_type = 'Quest',
                level = '40',
                placeholder_count = 0,
                points = {
                    { x = 177.000, y = -372.524 },
                },
            },
        },
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
    [169] = {
        name = 'Toraimarai Canal',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 115, x = -257.500, y = 82.000, z = 24.000 },
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 20, x = -308.216, y = 262.000, z = 15.999 },
        }),
        treasure_spawns = {
            { kind = 'coffer', x = 219.993, y = -49.049, z = 16.003 },
        },
    },
    [172] = {
        name = 'Zeruhn Mines',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 21, x = -10.050, y = 5.810, z = 0.000 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {},
    },
    [184] = {
        name = 'Lower Delkfutt\'s Tower',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 46, x = 464.000, y = -51.000, z = 0.000 },
        }),
        treasure_spawns = {},
    },
    [190] = {
        name = 'King Ranperre\'s Tomb',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 9, x = -452.571, y = -217.970, z = -19.807 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = 150.304, y = 245.834, z = 0.000 },
            { kind = 'chest', x = 150.304, y = 193.493, z = 0.000 },
            { kind = 'chest', x = 236.549, y = 149.944, z = -0.210 },
            { kind = 'chest', x = 203.316, y = 140.128, z = 0.000 },
            { kind = 'chest', x = 203.316, y = 129.619, z = 0.000 },
            { kind = 'chest', x = 203.316, y = 119.546, z = 0.000 },
            { kind = 'chest', x = 213.959, y = 129.619, z = 0.000 },
            { kind = 'chest', x = 236.549, y = 109.991, z = -0.169 },
            { kind = 'chest', x = 150.702, y = 85.374, z = 0.000 },
            { kind = 'chest', x = 150.702, y = 33.969, z = 0.000 },
            { kind = 'chest', x = -19.585, y = 14.740, z = 6.630 },
            { kind = 'chest', x = -118.680, y = 60.010, z = 9.000 },
            { kind = 'chest', x = -56.994, y = 155.155, z = 7.359 },
            { kind = 'chest', x = -40.195, y = -130.093, z = -0.008 },
        },
        nm_spawn_ranges = {
            { name = 'Spook', z = -0.557, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 2.912, y = -99.302 } } },
            { name = 'Gwyllgi', z = 7.726, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -65.363, y = 75.649 } } },
            { name = 'Ankou', z = -1.400, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 111.960, y = 68.750 } } },
            { name = 'Barbastelle', z = -0.500, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 133.000, y = 220.000 } } },
            { name = 'Cemetery Cherry', z = -0.600, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 33.000, y = -287.000 } } },
            { name = 'Vrtra', z = 7.134, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = 228.000, y = -311.000 } } },
        },
    },
    [191] = {
        name = 'Dangruf Wadi',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 42, x = -24.000, y = 1.000, z = -0.349 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = -499.709, y = 215.970, z = 3.262 },
            { kind = 'chest', x = -117.128, y = 134.104, z = 3.970 },
            { kind = 'chest', x = -60.745, y = 295.362, z = 3.063 },
            { kind = 'chest', x = -62.183, y = 416.434, z = 3.215 },
            { kind = 'chest', x = -287.324, y = 328.969, z = 3.538 },
            { kind = 'chest', x = -273.053, y = 332.914, z = 4.406 },
            { kind = 'chest', x = -100.291, y = 495.744, z = 3.277 },
            { kind = 'chest', x = -62.243, y = 564.120, z = 0.228 },
            { kind = 'chest', x = -206.223, y = 571.662, z = 3.874 },
            { kind = 'chest', x = -247.736, y = 576.783, z = 3.743 },
            { kind = 'chest', x = -239.459, y = 505.813, z = 4.000 },
            { kind = 'chest', x = -198.482, y = 506.684, z = 4.000 },
            { kind = 'chest', x = -264.091, y = 460.409, z = 3.255 },
            { kind = 'chest', x = -337.859, y = 384.203, z = 3.228 },
            { kind = 'chest', x = -419.957, y = 335.875, z = 3.876 },
        },
        nm_spawn_ranges = {
            { name = 'Teporingo', z = 3.000, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -189.000, y = 79.000 } } },
            { name = 'Chocoboleech', z = 4.400, floor = 'SURFACE', spawn_type = 'Fixed', placeholder_count = 0, points = { { x = -430.330, y = 115.100 } } },
        },
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
    [195] = {
        name = 'The Eldieme Necropolis',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'survival_guide', name = 'Survival Guide', unlock_bit = 21, x = 418.000, y = -99.500, z = -52.500 },
        }),
        treasure_spawns = {
            { kind = 'chest', x = 171.927, y = 20.008, z = -7.999 },
            { kind = 'chest', x = 261.094, y = 100.014, z = -33.250 },
            { kind = 'chest', x = 98.908, y = 100.046, z = -33.250 },
            { kind = 'chest', x = 98.894, y = -60.000, z = -33.250 },
            { kind = 'chest', x = 260.965, y = -59.905, z = -33.250 },
            { kind = 'chest', x = 179.926, y = -51.239, z = -32.000 },
            { kind = 'chest', x = 251.208, y = 20.054, z = -32.000 },
            { kind = 'chest', x = -518.830, y = 500.082, z = -8.000 },
            { kind = 'chest', x = -411.948, y = 499.879, z = 8.000 },
            { kind = 'chest', x = -438.279, y = 304.854, z = 0.350 },
            { kind = 'coffer', x = 159.011, y = 161.005, z = -27.999 },
            { kind = 'coffer', x = 179.864, y = 91.100, z = -32.000 },
            { kind = 'coffer', x = 108.749, y = 19.951, z = -32.000 },
            { kind = 'coffer', x = 39.264, y = -0.712, z = -28.000 },
            { kind = 'coffer', x = 174.753, y = -100.369, z = -0.418 },
            { kind = 'coffer', x = 299.967, y = 69.413, z = 0.000 },
            { kind = 'coffer', x = 300.082, y = -29.448, z = 0.000 },
            { kind = 'coffer', x = 188.319, y = 128.702, z = -0.590 },
            { kind = 'coffer', x = -386.548, y = 335.046, z = -3.000 },
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
    [249] = {
        name = 'Mhaura',
        stock_calibration = true,
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 40, x = -12.750, y = 87.286, z = -15.791 },
        }),
        treasure_spawns = {},
        nm_spawn_ranges = {},
    },
    [145] = {
        name = 'Giddeus',
        stock_calibration = true,
        -- Minimap.dll remains on page 1 after the in-zone descent. The page-15
        -- underground navmesh starts at live Z 6.067 and extends to 17.533;
        -- all retained nodes above Z 5.5 are confined to its map footprint.
        page_rules = {
            {
                page_id = 15,
                minimum_z = 5.5,
            },
            {
                page_id = 1,
            },
        },
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
        -- Page 0 is an unrecorded, compressed overview and cannot use the
        -- logical pages' world transform. When stock page metadata is absent,
        -- keep the northern and southern walks on their recorded detail pages.
        page_rules = {
            {
                page_id = 2,
                maximum_y = -100.0,
            },
            {
                page_id = 1,
            },
        },
        -- Exact FFXiMain records. These are used only when neither the stock
        -- record lookup nor Minimap.dll supplies live calibration metadata.
        page_calibrations = {
            [1] = {
                origin_x = 240.0,
                origin_y = 328.0,
                grid_origin_x = 255.0,
                grid_origin_y = 256.0,
                grid_yalms = 40,
                image_pixels_per_yalm = 0.80,
            },
            [2] = {
                origin_x = 304.0,
                origin_y = 120.0,
                grid_origin_x = 255.0,
                grid_origin_y = 256.0,
                grid_yalms = 40,
                image_pixels_per_yalm = 0.80,
            },
        },
        travel_references = travel_reference_set({
            { kind = 'home_point', name = 'Home Point #1', unlock_index = 17, x = -32.022, y =  131.741, z = -5.000 },
            { kind = 'home_point', name = 'Home Point #2', unlock_index = 18, x = 138.000, y =  -14.000, z =  0.001 },
            { kind = 'home_point', name = 'Home Point #3', unlock_index = 103, x =   5.000, y = -175.000, z = -4.000 },
            { kind = 'home_point', name = 'Home Point #4', unlock_index = 118, x = -92.000, y =   54.000, z = -2.000 },
        }),
        treasure_spawns = {},
    },
}
