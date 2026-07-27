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
        labels_image = 'assets/maps/237_labels.png',
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
        labels_image = 'assets/maps/241_labels.png',
        landmarks_image = 'assets/maps/241_landmarks.png',
        width = 512,
        height = 512,
        -- The DAT contains another composite page to the right. Clamp the
        -- overview camera to the actual Windurst Woods page.
        view_bounds = { left = 0, top = 0, right = 350, bottom = 512 },
        -- Source: ROM/18/72.DAT, internal page m_241_00. This page does not
        -- wrap. Stock-map control points at matched zoom place the sampled
        -- H-8 origin at (108.5, 288.0), one row below the drawn-grid estimate.
        origin_x = 108.5,
        origin_y = 288.0,
        grid_yalms = 40,
        image_pixels_per_yalm = 0.80,
    },
}
