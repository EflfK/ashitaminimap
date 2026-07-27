"""Decode an FFXI 512x512 paletted map DAT into a transparent PNG.

The DAT stores a 256-entry ABGR palette at 0x70, pixel indices at 0x500,
and scanlines bottom-up. Some maps wrap horizontally; ``--x-offset`` moves
the H-8 world origin to the center of the exported texture.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops


def parse_box(value: str) -> tuple[int, int, int, int]:
    parts = tuple(int(part.strip()) for part in value.split(","))
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("box must be left,top,right,bottom")
    return parts


def decode(source: Path) -> Image.Image:
    data = source.read_bytes()
    pixel_count = 512 * 512
    if len(data) < 0x500 + pixel_count:
        raise ValueError(f"{source} is too small to contain a 512x512 map")

    palette = []
    for index in range(256):
        alpha, blue, green, red = data[0x70 + (index * 4) : 0x74 + (index * 4)]
        palette.append((red, green, blue, alpha))

    image = Image.new("RGBA", (512, 512))
    image.putdata([palette[value] for value in data[0x500 : 0x500 + pixel_count]])
    return image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)


def tactical_linework(
    image: Image.Image,
    boxes: list[tuple[int, int, int, int]],
    excluded_boxes: list[tuple[int, int, int, int]],
) -> Image.Image:
    source = image.convert("RGB")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    source_pixels = source.load()
    output_pixels = output.load()
    for y in range(source.height):
        for x in range(source.width):
            included = any(
                left <= x < right and top <= y < bottom
                for left, top, right, bottom in boxes
            )
            excluded = any(
                left <= x < right and top <= y < bottom
                for left, top, right, bottom in excluded_boxes
            )
            if not included or excluded:
                continue

            red, green, blue = source_pixels[x, y]
            luminance = (red * 0.299) + (green * 0.587) + (blue * 0.114)
            darkness = max(0.0, min(1.0, (178.0 - luminance) / 95.0))
            if darkness <= 0:
                continue

            alpha = int(235 * (darkness**1.20))
            output_pixels[x, y] = (
                int(45 + (115 * darkness)),
                int(58 + (66 * darkness)),
                int(60 + (24 * darkness)),
                alpha,
            )

    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--x-offset", type=int, default=0)
    parser.add_argument(
        "--box",
        dest="boxes",
        action="append",
        required=True,
        type=parse_box,
        help="included left,top,right,bottom rectangle; repeat for multiple regions",
    )
    parser.add_argument(
        "--exclude-box",
        dest="excluded_boxes",
        action="append",
        default=[],
        type=parse_box,
        help="excluded left,top,right,bottom rectangle; repeat as needed",
    )
    arguments = parser.parse_args()

    image = decode(arguments.source)
    if arguments.x_offset:
        image = ImageChops.offset(image, arguments.x_offset, 0)
    output = tactical_linework(image, arguments.boxes, arguments.excluded_boxes)
    arguments.destination.parent.mkdir(parents=True, exist_ok=True)
    output.save(arguments.destination, "PNG", optimize=True)


if __name__ == "__main__":
    main()
