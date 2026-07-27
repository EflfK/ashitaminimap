#!/usr/bin/env python3
"""Decode a vanilla FFXI map DAT into a calibrated RGBA base layer."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from generate_vanilla_map import decode, parse_box


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--box",
        type=parse_box,
        default=(0, 0, 512, 512),
        help="visible left,top,right,bottom rectangle",
    )
    arguments = parser.parse_args()

    source = decode(arguments.source).convert("RGBA")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    left, top, _, _ = arguments.box
    region = source.crop(arguments.box)
    region.putalpha(Image.new("L", region.size, 255))
    output.paste(region, (left, top), region)

    arguments.destination.parent.mkdir(parents=True, exist_ok=True)
    output.save(arguments.destination, "PNG", optimize=True)
    print(f"wrote {arguments.destination}: visible box {arguments.box}")


if __name__ == "__main__":
    main()
