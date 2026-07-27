#!/usr/bin/env python3
"""Generate a transparent walkable-area layer from LandSandBoat geometry.

The OBJ is the authoritative collision-space reference. The Detour navmesh
selects surfaces considered traversable and supplies a clean polygon union.
The output uses AshitaMinimap's existing world-to-image calibration.
"""

from __future__ import annotations

import argparse
import struct
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("obj", type=Path, help="decompressed zone collision OBJ")
    parser.add_argument("nav", type=Path, help="compiled Detour .nav file")
    parser.add_argument("output", type=Path, help="output transparent PNG")
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--origin-x", type=float, required=True)
    parser.add_argument("--origin-y", type=float, required=True)
    parser.add_argument("--pixels-per-yalm", type=float, required=True)
    parser.add_argument("--supersample", type=int, default=4)
    parser.add_argument("--minimum-hole-area", type=float, default=18.0)
    parser.add_argument("--fill-alpha", type=int, default=76)
    parser.add_argument("--edge-alpha", type=int, default=235)
    return parser.parse_args()


def read_obj_bounds(path: Path) -> tuple[tuple[float, ...], tuple[float, ...]]:
    minimum = [float("inf")] * 3
    maximum = [float("-inf")] * 3
    count = 0
    with path.open("r", encoding="utf-8") as source:
        for line in source:
            if not line.startswith("v "):
                continue
            vertex = tuple(map(float, line.split()[1:4]))
            for axis, value in enumerate(vertex):
                minimum[axis] = min(minimum[axis], value)
                maximum[axis] = max(maximum[axis], value)
            count += 1
    if not count:
        raise ValueError(f"{path} contains no OBJ vertices")
    return tuple(minimum), tuple(maximum)


def read_navmesh(
    path: Path,
) -> tuple[tuple[float, ...], list[list[tuple[float, ...]]]]:
    data = path.read_bytes()
    magic, version, tile_count = struct.unpack_from("<iii", data, 0)
    if magic != 0x4D534554 or version != 1:
        raise ValueError(f"{path} is not a supported MSET v1 navmesh")

    nav_origin = struct.unpack_from("<3f", data, 12)
    offset = 40
    polygons = []
    for _ in range(tile_count):
        _, data_size = struct.unpack_from("<Ii", data, offset)
        offset += 8
        tile_offset = offset
        offset += data_size

        header = struct.unpack_from("<15i3f3f3f3ff", data, tile_offset)
        polygon_count, vertex_count = header[6], header[7]
        vertex_offset = tile_offset + 100
        vertices = [
            struct.unpack_from("<3f", data, vertex_offset + index * 12)
            for index in range(vertex_count)
        ]
        polygon_offset = vertex_offset + vertex_count * 12
        for index in range(polygon_count):
            polygon = struct.unpack_from(
                "<I6H6HHBB", data, polygon_offset + index * 32
            )
            vertex_total = polygon[-2]
            polygon_type = polygon[-1] & 0xC0
            if vertex_total >= 3 and not polygon_type:
                polygons.append(
                    [vertices[item] for item in polygon[1 : 1 + vertex_total]]
                )
    if offset != len(data):
        raise ValueError(f"{path} has unexpected trailing navmesh data")
    return nav_origin, polygons


def validate_sources(
    obj_bounds: tuple[tuple[float, ...], tuple[float, ...]],
    nav_origin: tuple[float, ...],
) -> None:
    for axis, (obj_value, nav_value) in enumerate(zip(obj_bounds[0], nav_origin)):
        if abs(obj_value - nav_value) > 0.01:
            raise ValueError(
                f"OBJ/nav axis {axis} differs: {obj_value} versus {nav_value}"
            )


def fill_small_holes(mask: Image.Image, maximum_area: int) -> int:
    pixels = mask.load()
    width, height = mask.size
    visited = bytearray(width * height)
    filled = 0
    for start_y in range(height):
        for start_x in range(width):
            start = start_y * width + start_x
            if visited[start] or pixels[start_x, start_y]:
                continue
            queue = deque([(start_x, start_y)])
            visited[start] = 1
            component = []
            touches_edge = False
            while queue:
                x, y = queue.popleft()
                component.append((x, y))
                touches_edge |= x in (0, width - 1) or y in (0, height - 1)
                for next_x, next_y in (
                    (x - 1, y),
                    (x + 1, y),
                    (x, y - 1),
                    (x, y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    item = next_y * width + next_x
                    if visited[item] or pixels[next_x, next_y]:
                        continue
                    visited[item] = 1
                    queue.append((next_x, next_y))
            if not touches_edge and len(component) < maximum_area:
                for x, y in component:
                    pixels[x, y] = 255
                filled += 1
    return filled


def main() -> None:
    args = parse_args()
    if args.supersample < 1:
        raise ValueError("--supersample must be at least 1")

    obj_bounds = read_obj_bounds(args.obj)
    nav_origin, polygons = read_navmesh(args.nav)
    validate_sources(obj_bounds, nav_origin)

    scale = args.supersample
    mask = Image.new("L", (args.width * scale, args.height * scale), 0)
    draw = ImageDraw.Draw(mask)
    for polygon in polygons:
        draw.polygon(
            [
                (
                    (args.origin_x + vertex[0] * args.pixels_per_yalm) * scale,
                    (args.origin_y - vertex[2] * args.pixels_per_yalm) * scale,
                )
                for vertex in polygon
            ],
            fill=255,
        )

    # Seal raster-only subpixel seams without materially expanding geometry.
    mask = mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    maximum_hole_area = round(args.minimum_hole_area * scale * scale)
    holes_filled = fill_small_holes(mask, maximum_hole_area)

    edge_width = max(3, scale * 2 - 1)
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(edge_width)))
    output = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    output.paste((8, 56, 62, args.fill_alpha), mask=mask)
    output.paste((64, 211, 205, args.edge_alpha), mask=edge)
    output = output.resize((args.width, args.height), Image.Resampling.LANCZOS)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output)
    print(
        f"wrote {args.output}: {len(polygons)} walkable polygons, "
        f"{holes_filled} small holes removed"
    )


if __name__ == "__main__":
    main()
