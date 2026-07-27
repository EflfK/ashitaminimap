"""Build dark-tactical map layers from calibrated vanilla-derived masks.

The source alpha coordinates are preserved. Production structure styling uses
core pixels only, so the original navigation line remains the precision anchor.
Text and static landmark symbols are split with explicit source-pixel
rectangles, allowing either overlay to be hidden without removing boundaries.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


Box = tuple[int, int, int, int]


def parse_box(value: str) -> Box:
    parts = tuple(int(part.strip()) for part in value.split(","))
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("box must be left,top,right,bottom")
    return parts


def boosted_alpha(alpha: Image.Image, multiplier: float, floor: int) -> Image.Image:
    return alpha.point(
        lambda value: 0
        if value == 0
        else min(255, max(floor, int((value * multiplier) + 0.5)))
    )


def styled_layer(
    alpha: Image.Image,
    core_color: tuple[int, int, int],
    halo_color: tuple[int, int, int],
    alpha_multiplier: float,
    alpha_floor: int,
    halo_strength: float,
) -> Image.Image:
    core_alpha = boosted_alpha(alpha, alpha_multiplier, alpha_floor)
    output = Image.new("RGBA", alpha.size, halo_color + (0,))
    if halo_strength > 0:
        dilated = alpha.filter(ImageFilter.MaxFilter(3))
        halo_alpha = ImageChops.subtract(dilated, alpha).point(
            lambda value: min(255, int((value * halo_strength) + 0.5))
        )
        output.putalpha(halo_alpha)
    core = Image.new("RGBA", alpha.size, core_color + (0,))
    core.putalpha(core_alpha)
    return Image.alpha_composite(output, core)


def select_rectangles(alpha: Image.Image, boxes: list[Box]) -> Image.Image:
    selection = Image.new("L", alpha.size, 0)
    draw = ImageDraw.Draw(selection)
    for left, top, right, bottom in boxes:
        draw.rectangle((left, top, right - 1, bottom - 1), fill=255)
    return ImageChops.multiply(alpha, selection)


def clean_structure_grid(alpha: Image.Image) -> Image.Image:
    """Remove faint decorative grid strokes without cutting map boundaries."""
    output = alpha.copy()
    source = alpha.load()
    pixels = output.load()
    width, height = alpha.size
    grid_x = {29 + (32 * index) for index in range(16)}
    grid_y = {17 + (32 * index) for index in range(16)}

    for y in range(height):
        for x in range(width):
            value = source[x, y]
            if value == 0 or value > 120:
                continue
            on_vertical_grid = x in grid_x
            on_horizontal_grid = y in grid_y
            if not on_vertical_grid and not on_horizontal_grid:
                continue

            crosses_vertical = (
                x > 0
                and x + 1 < width
                and source[x - 1, y] > 0
                and source[x + 1, y] > 0
            )
            crosses_horizontal = (
                y > 0
                and y + 1 < height
                and source[x, y - 1] > 0
                and source[x, y + 1] > 0
            )
            if (on_vertical_grid and crosses_vertical) or (
                on_horizontal_grid and crosses_horizontal
            ):
                continue
            pixels[x, y] = 0
    return output


def save(layer: Image.Image, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    layer.save(destination, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("structure_source", type=Path)
    parser.add_argument("labels_source", type=Path)
    parser.add_argument("structure_destination", type=Path)
    parser.add_argument("labels_destination", type=Path)
    parser.add_argument("landmarks_destination", type=Path)
    parser.add_argument("--label-box", action="append", default=[], type=parse_box)
    parser.add_argument("--landmark-box", action="append", default=[], type=parse_box)
    arguments = parser.parse_args()

    structure_source = Image.open(arguments.structure_source).convert("RGBA")
    labels_source = Image.open(arguments.labels_source).convert("RGBA")
    if structure_source.size != labels_source.size:
        raise ValueError("structure and label sources must have identical dimensions")

    full_alpha = ImageChops.lighter(
        structure_source.getchannel("A"),
        labels_source.getchannel("A"),
    )
    source_label_alpha = labels_source.getchannel("A")
    label_alpha = select_rectangles(source_label_alpha, arguments.label_box)
    landmark_alpha = select_rectangles(source_label_alpha, arguments.landmark_box)
    classified = ImageChops.lighter(label_alpha, landmark_alpha)
    structure_alpha = clean_structure_grid(ImageChops.subtract(full_alpha, classified))
    structure = styled_layer(
        structure_alpha,
        core_color=(82, 151, 158),
        halo_color=(2, 13, 18),
        alpha_multiplier=1.50,
        alpha_floor=82,
        halo_strength=0,
    )
    labels = styled_layer(
        label_alpha,
        core_color=(213, 184, 126),
        halo_color=(2, 10, 14),
        alpha_multiplier=1.85,
        alpha_floor=112,
        halo_strength=0,
    )
    landmarks = styled_layer(
        landmark_alpha,
        core_color=(242, 166, 61),
        halo_color=(3, 9, 12),
        alpha_multiplier=2.10,
        alpha_floor=150,
        halo_strength=0,
    )

    save(structure, arguments.structure_destination)
    save(labels, arguments.labels_destination)
    save(landmarks, arguments.landmarks_destination)


if __name__ == "__main__":
    main()
