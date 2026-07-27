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
}
