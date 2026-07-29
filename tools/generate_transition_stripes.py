#!/usr/bin/env python3
"""Generate a tapered threshold at a verified floor transition."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image


DEFAULT_HALF_LENGTH = 7.0
DEFAULT_HALF_WIDTH = 4.5
DEFAULT_STRIPE_PERIOD = 5.0
DEFAULT_END_FEATHER = 1.5


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
    parser.add_argument(
        "--half-length",
        type=float,
        default=DEFAULT_HALF_LENGTH,
        help="half-length of the threshold along the travel direction",
    )
    parser.add_argument(
        "--half-width",
        type=float,
        default=DEFAULT_HALF_WIDTH,
        help="half-width of the threshold across the travel direction",
    )
    parser.add_argument(
        "--stripe-period",
        type=float,
        default=DEFAULT_STRIPE_PERIOD,
    )
    parser.add_argument(
        "--end-feather",
        type=float,
        default=DEFAULT_END_FEATHER,
        help="alpha-only feather distance at the two travel-direction ends",
    )
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
    if args.half_length <= 0:
        raise ValueError("--half-length must be positive")
    if args.half_width <= 0:
        raise ValueError("--half-width must be positive")
    if args.stripe_period <= 0:
        raise ValueError("--stripe-period must be positive")
    if args.end_feather < 0:
        raise ValueError("--end-feather cannot be negative")
    if args.end_feather > args.half_length:
        raise ValueError("--end-feather cannot exceed --half-length")
    if not 0 <= args.alpha <= 255:
        raise ValueError("--alpha must be between 0 and 255")

    direction_length = math.hypot(*args.direction)
    if direction_length <= 0:
        raise ValueError("--direction cannot be zero")
    direction_x = args.direction[0] / direction_length
    direction_y = args.direction[1] / direction_length
    perpendicular_x = -direction_y
    perpendicular_y = direction_x

    geometry = Image.open(args.geometry).convert("RGBA")
    geometry_alpha = geometry.getchannel("A")
    output = Image.new("RGBA", geometry.size, (0, 0, 0, 0))
    pixels = output.load()
    alpha = geometry_alpha.load()
    center_x, center_y = args.center
    half_length = args.half_length
    half_width = args.half_width
    bounds_radius = math.hypot(half_length, half_width)

    left = max(0, math.floor(center_x - bounds_radius))
    top = max(0, math.floor(center_y - bounds_radius))
    right = min(geometry.width, math.ceil(center_x + bounds_radius + 1))
    bottom = min(geometry.height, math.ceil(center_y + bounds_radius + 1))
    for y in range(top, bottom):
        for x in range(left, right):
            coverage = min(1.0, alpha[x, y] / 64.0)
            if coverage <= 0:
                continue
            offset_x = x - center_x
            offset_y = y - center_y
            projection = offset_x * direction_x + offset_y * direction_y
            across = offset_x * perpendicular_x + offset_y * perpendicular_y
            if abs(projection) > half_length or abs(across) > half_width:
                continue

            # Constant projection creates bands perpendicular to the path.
            # The main-color share shrinks from 90% to 10% as the bands
            # approach the alternate floor; its share is 50% at the center.
            floor_progress = min(
                1.0,
                max(0.0, (projection / half_length + 1) / 2),
            )
            main_share = 0.90 - 0.80 * floor_progress
            phase = ((projection + half_length) % args.stripe_period) / (
                args.stripe_period
            )
            color = (
                args.main_rgb if phase < main_share else args.alternate_rgb
            )
            end_opacity = 1.0
            if args.end_feather > 0:
                end_opacity = min(
                    1.0,
                    (half_length - abs(projection)) / args.end_feather,
                )
                # Smooth only the alpha boundary. Floor colors remain discrete.
                end_opacity = end_opacity * end_opacity * (
                    3.0 - (2.0 * end_opacity)
                )
            pixels[x, y] = (
                *color,
                round(args.alpha * coverage * end_opacity),
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output)
    print(
        f"wrote {args.output}: threshold center {args.center}, "
        f"direction {args.direction}, half-length {args.half_length}, "
        f"half-width {args.half_width}"
    )


if __name__ == "__main__":
    main()
