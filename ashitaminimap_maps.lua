-- Map calibration is deterministic:
-- image_x = origin_x + (world_x * image_pixels_per_yalm)
-- image_y = origin_y - (world_y * image_pixels_per_yalm)
--
-- grid_yalms is zone-specific; it is map-scale-byte * 10.
-- Keep all calibration values separate from the on-screen zoom.
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
    },
    [243] = {
        name = 'Ru\'Lude Gardens',
        vanilla_image = 'assets/maps/243_vanilla.png',
        -- Keep disconnected elevations in separate textures so their boundary
        -- edges and alternate-floor color remain visible where paths overlap.
        structure_layers = {
            { image = 'assets/maps/243_structure.png' },
            { image = 'assets/maps/243_stairs_structure.png' },
            { image = 'assets/maps/243_upper_structure.png' },
        },
        width = 512,
        height = 512,
        view_bounds = { left = 0, top = 0, right = 512, bottom = 512 },
        origin_x = 255.0,
        origin_y = 256.0,
        grid_origin_x = 255.0,
        grid_origin_y = 256.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
    },
    [244] = {
        name = 'Upper Jeuno',
        stock_calibration = true,
        vanilla_image = 'assets/maps/244_vanilla.png',
        structure_layers = {
            { image = 'assets/maps/244_structure.png' },
            { image = 'assets/maps/244_stables_structure.png' },
        },
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
    },
    [174] = {
        name = 'Kuftal Tunnel',
        stock_calibration = true,
        -- Kuftal's four logical maps use non-contiguous stock page IDs.
        -- Each page is an ordered set of separately rendered elevation
        -- components so overlapping floors retain their own boundaries.
        structure_pages = {
            [1] = {
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
                    opacity = 0.72,
                },
            },
            [2] = {
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
            },
            [15] = {
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
            },
            [16] = {
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
    },
}
