-- Map calibration is deterministic:
-- image_x = origin_x + (world_x * image_pixels_per_yalm)
-- image_y = origin_y - (world_y * image_pixels_per_yalm)
--
-- Keep these values separate from the on-screen zoom in the user config.
return {
    [107] = {
        name = 'South Gustaberg',
        image = 'assets/maps/107.png',
        width = 768,
        height = 768,
        origin_x = 384,
        origin_y = 384,
        image_pixels_per_yalm = 2.40,
    },
    [236] = {
        name = 'Port Bastok',
        image = 'assets/maps/236.png',
        width = 768,
        height = 768,
        origin_x = 384,
        origin_y = 384,
        image_pixels_per_yalm = 2.40,
    },
    [237] = {
        name = 'Metalworks',
        structure_image = 'assets/maps/237_structure.png',
        labels_image = 'assets/maps/237_labels.png',
        width = 512,
        height = 512,
        -- The vanilla texture's H-8 cell center is at pixel 253 after unwrap.
        origin_x = 253,
        origin_y = 253,
        image_pixels_per_yalm = 1.60,
    },
}
