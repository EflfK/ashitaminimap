#!/usr/bin/env python3
"""Generate a path-clipped color blend at a verified floor transition."""

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


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


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
    parser.add_argument("--rgb", default="122,86,160")
    parser.add_argument("--maximum-alpha", type=int, default=190)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    if args.radius <= 0:
        raise ValueError("--radius must be positive")
    if not 0 <= args.maximum_alpha <= 255:
        raise ValueError("--maximum-alpha must be between 0 and 255")

    color = tuple(int(part) for part in args.rgb.split(","))
    if len(color) != 3 or any(channel < 0 or channel > 255 for channel in color):
        raise ValueError("--rgb must contain three channels from 0 to 255")

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
            geometry_opacity = alpha[x, y] / 255.0
            if geometry_opacity <= 0:
                continue
            offset_x = x - center_x
            offset_y = y - center_y
            distance = math.hypot(offset_x, offset_y)
            if distance > radius:
                continue

            projection = (
                offset_x * direction_x + offset_y * direction_y
            ) / radius
            directional_weight = smoothstep((projection + 0.65) / 1.3)
            radial_weight = smoothstep((radius - distance) / (radius * 0.35))
            weight = directional_weight * radial_weight
            pixels[x, y] = (
                *color,
                round(args.maximum_alpha * geometry_opacity * weight),
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output)
    print(
        f"wrote {args.output}: gradient center {args.center}, "
        f"direction {args.direction}"
    )


if __name__ == "__main__":
    main()
