#!/usr/bin/env python3
"""Generate a deterministic stair/ramp transition marker layer."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--center-x", type=float, required=True)
    parser.add_argument("--center-y", type=float, required=True)
    parser.add_argument("--radius", type=float, default=8.0)
    parser.add_argument("--supersample", type=int, default=4)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    if args.radius <= 0:
        raise ValueError("--radius must be positive")
    if args.supersample < 1:
        raise ValueError("--supersample must be at least 1")

    scale = args.supersample
    center_x = round(args.center_x * scale)
    center_y = round(args.center_y * scale)
    radius = round(args.radius * scale)
    image = Image.new(
        "RGBA",
        (args.width * scale, args.height * scale),
        (0, 0, 0, 0),
    )
    draw = ImageDraw.Draw(image)
    diamond = [
        (center_x, center_y - radius),
        (center_x + radius, center_y),
        (center_x, center_y + radius),
        (center_x - radius, center_y),
    ]
    draw.polygon(
        diamond,
        fill=(112, 73, 8, 190),
        outline=(255, 190, 64, 255),
        width=max(1, round(1.5 * scale)),
    )

    # Three crossbars read as stairs at close zoom without implying a travel
    # direction or covering the underlying connector geometry.
    for offset, half_width in ((-3.5, 3.5), (0.0, 5.0), (3.5, 3.5)):
        y = round(center_y + offset * scale)
        width = round(half_width * scale)
        draw.line(
            (center_x - width, y, center_x + width, y),
            fill=(255, 226, 142, 255),
            width=max(1, round(1.25 * scale)),
        )

    image = image.resize(
        (args.width, args.height),
        Image.Resampling.LANCZOS,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)
    print(f"wrote {args.output}: transition center ({args.center_x}, {args.center_y})")


if __name__ == "__main__":
    main()
