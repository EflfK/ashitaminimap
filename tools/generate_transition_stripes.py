#!/usr/bin/env python3
"""Generate directional floor-color stripes at a verified transition."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image


def parse_pair(value: str) -> tuple[float, float]:
    parts = value.split(",")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("value must contain two numbers")
    try:
        return float(parts[0]), float(parts[1])
    except ValueError as exception:
        raise argparse.ArgumentTypeError(
            "value must contain two numbers"
        ) from exception


def parse_rgb(value: str) -> tuple[int, int, int]:
    parts = value.split(",")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("RGB must contain three channels")
    try:
        color = tuple(int(part) for part in parts)
    except ValueError as exception:
        raise argparse.ArgumentTypeError(
            "RGB channels must be integers"
        ) from exception
    if any(channel < 0 or channel > 255 for channel in color):
        raise argparse.ArgumentTypeError("RGB channels must be from 0 to 255")
    return color


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("geometry", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--center", type=parse_pair, required=True)
    parser.add_argument(
        "--direction",
        type=parse_pair,
        required=True,
        help="source-pixel vector pointing toward the alternate floor",
    )
    parser.add_argument("--radius", type=float, default=18.0)
    parser.add_argument("--stripe-period", type=float, default=6.0)
    parser.add_argument("--main-rgb", type=parse_rgb, default=(64, 211, 205))
    parser.add_argument(
        "--alternate-rgb",
        type=parse_rgb,
        default=(166, 115, 213),
    )
    parser.add_argument("--alpha", type=int, default=210)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    if args.radius <= 0:
        raise ValueError("--radius must be positive")
    if args.stripe_period <= 0:
        raise ValueError("--stripe-period must be positive")
    if not 0 <= args.alpha <= 255:
        raise ValueError("--alpha must be between 0 and 255")

    direction_length = math.hypot(*args.direction)
    if direction_length <= 0:
        raise ValueError("--direction cannot be zero")
    direction_x = args.direction[0] / direction_length
    direction_y = args.direction[1] / direction_length

    geometry = Image.open(args.geometry).convert("RGBA")
    geometry_alpha = geometry.getchannel("A")
    output = Image.new("RGBA", geometry.size, (0, 0, 0, 0))
    pixels = output.load()
    alpha = geometry_alpha.load()
    center_x, center_y = args.center
    radius = args.radius

    left = max(0, math.floor(center_x - radius))
    top = max(0, math.floor(center_y - radius))
    right = min(geometry.width, math.ceil(center_x + radius + 1))
    bottom = min(geometry.height, math.ceil(center_y + radius + 1))
    for y in range(top, bottom):
        for x in range(left, right):
            coverage = min(1.0, alpha[x, y] / 64.0)
            if coverage <= 0:
                continue
            offset_x = x - center_x
            offset_y = y - center_y
            if math.hypot(offset_x, offset_y) > radius:
                continue

            # Constant projection creates bands perpendicular to the path.
            # The main-color share shrinks from 90% to 10% as the bands
            # approach the alternate floor; its share is 50% at the center.
            projection = offset_x * direction_x + offset_y * direction_y
            floor_progress = min(1.0, max(0.0, (projection / radius + 1) / 2))
            main_share = 0.90 - 0.80 * floor_progress
            phase = ((projection + radius) % args.stripe_period) / (
                args.stripe_period
            )
            color = (
                args.main_rgb if phase < main_share else args.alternate_rgb
            )
            pixels[x, y] = (*color, round(args.alpha * coverage))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output)
    print(
        f"wrote {args.output}: stripe center {args.center}, "
        f"direction {args.direction}"
    )


if __name__ == "__main__":
    main()
