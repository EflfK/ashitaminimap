"""Create a transparent dark-tactical prototype from an installed reference map.

This is intentionally a linework extractor, not a walkable-area generator.
Production masks must be traced and calibrated from verified map geometry.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def parse_box(value: str) -> tuple[int, int, int, int]:
    parts = tuple(int(part.strip()) for part in value.split(","))
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("box must be left,top,right,bottom")
    return parts


def generate(source: Path, destination: Path, box: tuple[int, int, int, int]) -> None:
    image = Image.open(source).convert("RGB")
    output = Image.new("RGBA", image.size, (0, 0, 0, 0))
    source_pixels = image.load()
    output_pixels = output.load()
    left, top, right, bottom = box

    for y in range(max(0, top), min(image.height, bottom)):
        for x in range(max(0, left), min(image.width, right)):
            red, green, blue = source_pixels[x, y]
            luminance = (red * 0.299) + (green * 0.587) + (blue * 0.114)
            darkness = max(0.0, min(1.0, (176.0 - luminance) / 90.0))
            if darkness <= 0:
                continue

            alpha = int(220 * (darkness**1.35))
            # Dark blue-gray base with restrained amber linework.
            output_pixels[x, y] = (
                int(48 + (100 * darkness)),
                int(61 + (57 * darkness)),
                int(62 + (20 * darkness)),
                alpha,
            )

    destination.parent.mkdir(parents=True, exist_ok=True)
    output.save(destination, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--box", required=True, type=parse_box)
    arguments = parser.parse_args()
    generate(arguments.source, arguments.destination, arguments.box)


if __name__ == "__main__":
    main()
