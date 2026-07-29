#!/usr/bin/env python3
"""Generate a transparent walkable-area layer from LandSandBoat geometry.

The OBJ is the authoritative collision-space reference. The Detour navmesh
selects surfaces considered traversable and supplies a clean polygon union.
The output uses AshitaMinimap's existing world-to-image calibration.
"""

from __future__ import annotations

import argparse
import struct
from collections import defaultdict, deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


def parse_seed(value: str) -> tuple[float, float]:
    parts = value.split(",")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("seed must be world-x,world-y")
    try:
        return float(parts[0]), float(parts[1])
    except ValueError as exception:
        raise argparse.ArgumentTypeError("seed must contain two numbers") from exception


def parse_box(value: str) -> tuple[int, int, int, int]:
    parts = value.split(",")
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("box must be left,top,right,bottom")
    try:
        box = tuple(int(part) for part in parts)
    except ValueError as exception:
        raise argparse.ArgumentTypeError("box must contain four integers") from exception
    if box[0] >= box[2] or box[1] >= box[3]:
        raise argparse.ArgumentTypeError("box must have positive width and height")
    return box


def parse_rgb(value: str) -> tuple[int, int, int]:
    parts = value.split(",")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("RGB color must be red,green,blue")
    try:
        color = tuple(int(part) for part in parts)
    except ValueError as exception:
        raise argparse.ArgumentTypeError(
            "RGB color must contain three integers"
        ) from exception
    if any(channel < 0 or channel > 255 for channel in color):
        raise argparse.ArgumentTypeError(
            "RGB color channels must be between 0 and 255"
        )
    return color


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
    parser.add_argument(
        "--seam-closure-radius",
        type=float,
        default=0.25,
        help=(
            "source-pixel radius used to close raster-only navmesh seam gaps; "
            "increase only after close-zoom validation"
        ),
    )
    parser.add_argument("--minimum-hole-area", type=float, default=18.0)
    parser.add_argument(
        "--seed",
        action="append",
        type=parse_seed,
        default=[],
        help="verified walkable world-x,world-y; repeat for disconnected regions",
    )
    parser.add_argument("--maximum-step", type=float, default=0.65)
    parser.add_argument(
        "--minimum-elevation",
        type=float,
        help="minimum Detour polygon mean elevation to include",
    )
    parser.add_argument(
        "--maximum-elevation",
        type=float,
        help="maximum Detour polygon mean elevation to include",
    )
    parser.add_argument(
        "--exclude-box",
        action="append",
        type=parse_box,
        default=[],
        help="output-pixel left,top,right,bottom trim; repeat as needed",
    )
    parser.add_argument("--fill-alpha", type=int, default=76)
    parser.add_argument("--edge-alpha", type=int, default=235)
    parser.add_argument("--fill-rgb", type=parse_rgb, default=(8, 56, 62))
    parser.add_argument("--edge-rgb", type=parse_rgb, default=(64, 211, 205))
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
    # OBJ text export and compiled Detour headers can differ by a few
    # hundredths of a yalm due to decimal formatting. This remains well below
    # one source pixel at supported map scales while still rejecting genuinely
    # mismatched source revisions.
    origin_tolerance = 0.1
    for axis, (obj_value, nav_value) in enumerate(zip(obj_bounds[0], nav_origin)):
        if abs(obj_value - nav_value) > origin_tolerance:
            raise ValueError(
                f"OBJ/nav axis {axis} differs: {obj_value} versus {nav_value}"
            )


def point_in_polygon(
    polygon: list[tuple[float, ...]], x: float, y: float
) -> bool:
    winding = 0
    for index, start in enumerate(polygon):
        end = polygon[(index + 1) % len(polygon)]
        cross = (end[0] - start[0]) * (y - start[2]) - (
            end[2] - start[2]
        ) * (x - start[0])
        if abs(cross) <= 0.0001:
            continue
        direction = 1 if cross > 0 else -1
        if winding and direction != winding:
            return False
        winding = direction
    return True


def connected_component(
    polygons: list[list[tuple[float, ...]]],
    seed_x: float,
    seed_y: float,
    maximum_step: float,
) -> list[list[tuple[float, ...]]]:
    """Return the Detour polygon component containing a known walkable point.

    Exact shared edges connect polygons inside a tile. Across tile seams one
    edge can be split into several collinear spans, so overlapping horizontal
    or vertical spans are joined when their interpolated heights are within
    the configured step height.
    """

    parent = list(range(len(polygons)))
    component_size = [1] * len(polygons)

    def find(item: int) -> int:
        while parent[item] != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    def union(left: int, right: int) -> None:
        left = find(left)
        right = find(right)
        if left == right:
            return
        if component_size[left] < component_size[right]:
            left, right = right, left
        parent[right] = left
        component_size[left] += component_size[right]

    def vertex_key(vertex: tuple[float, ...]) -> tuple[float, ...]:
        return tuple(round(value, 3) for value in vertex)

    exact_edges: dict[tuple[tuple[float, ...], ...], int] = {}
    axis_edges = defaultdict(list)
    for polygon_index, polygon in enumerate(polygons):
        for edge_index, start in enumerate(polygon):
            end = polygon[(edge_index + 1) % len(polygon)]
            edge = tuple(sorted((vertex_key(start), vertex_key(end))))
            if edge in exact_edges:
                union(polygon_index, exact_edges[edge])
            else:
                exact_edges[edge] = polygon_index

            if abs(start[0] - end[0]) < 0.01:
                low, high = sorted((start[2], end[2]))
                axis_edges[("x", round((start[0] + end[0]) / 2, 2))].append(
                    (low, high, start, end, polygon_index)
                )
            elif abs(start[2] - end[2]) < 0.01:
                low, high = sorted((start[0], end[0]))
                axis_edges[("y", round((start[2] + end[2]) / 2, 2))].append(
                    (low, high, start, end, polygon_index)
                )

    def height_at(
        start: tuple[float, ...],
        end: tuple[float, ...],
        position: float,
        orientation: str,
    ) -> float:
        start_axis = start[2] if orientation == "x" else start[0]
        end_axis = end[2] if orientation == "x" else end[0]
        if abs(end_axis - start_axis) < 0.000001:
            return start[1]
        ratio = (position - start_axis) / (end_axis - start_axis)
        return start[1] + (end[1] - start[1]) * ratio

    for (orientation, _), edges in axis_edges.items():
        edges.sort(key=lambda edge: edge[0])
        for index, edge in enumerate(edges):
            for candidate in edges[index + 1 :]:
                if candidate[0] >= edge[1] - 0.01:
                    break
                overlap_low = max(edge[0], candidate[0])
                overlap_high = min(edge[1], candidate[1])
                if overlap_high - overlap_low <= 0.01:
                    continue
                midpoint = (overlap_low + overlap_high) / 2
                height_delta = abs(
                    height_at(edge[2], edge[3], midpoint, orientation)
                    - height_at(candidate[2], candidate[3], midpoint, orientation)
                )
                if height_delta <= maximum_step:
                    union(edge[4], candidate[4])

    seed_index = next(
        (
            index
            for index, polygon in enumerate(polygons)
            if point_in_polygon(polygon, seed_x, seed_y)
        ),
        None,
    )
    if seed_index is None:
        raise ValueError(
            f"walkable seed ({seed_x}, {seed_y}) is outside every nav polygon"
        )
    seed_root = find(seed_index)
    return [
        polygon
        for index, polygon in enumerate(polygons)
        if find(index) == seed_root
    ]


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
    if args.seam_closure_radius < 0:
        raise ValueError("--seam-closure-radius cannot be negative")

    obj_bounds = read_obj_bounds(args.obj)
    nav_origin, polygons = read_navmesh(args.nav)
    validate_sources(obj_bounds, nav_origin)
    total_polygons = len(polygons)
    if (
        args.minimum_elevation is not None
        or args.maximum_elevation is not None
    ):
        minimum = (
            args.minimum_elevation
            if args.minimum_elevation is not None
            else float("-inf")
        )
        maximum = (
            args.maximum_elevation
            if args.maximum_elevation is not None
            else float("inf")
        )
        if minimum > maximum:
            raise ValueError("--minimum-elevation cannot exceed --maximum-elevation")
        polygons = [
            polygon
            for polygon in polygons
            if minimum
            <= sum(vertex[1] for vertex in polygon) / len(polygon)
            <= maximum
        ]
        if not polygons:
            raise ValueError("elevation filter excluded every nav polygon")
    if args.seed:
        selected_ids = set()
        for seed_x, seed_y in args.seed:
            selected_ids.update(
                id(polygon)
                for polygon in connected_component(
                    polygons,
                    seed_x,
                    -seed_y,
                    args.maximum_step,
                )
            )
        polygons = [polygon for polygon in polygons if id(polygon) in selected_ids]

    scale = args.supersample
    mask = Image.new("L", (args.width * scale, args.height * scale), 0)
    draw = ImageDraw.Draw(mask)
    for polygon in polygons:
        draw.polygon(
            [
                (
                    (args.origin_x + vertex[0] * args.pixels_per_yalm) * scale,
                    (args.origin_y + vertex[2] * args.pixels_per_yalm) * scale,
                )
                for vertex in polygon
            ],
            fill=255,
        )

    for left, top, right, bottom in args.exclude_box:
        draw.rectangle(
            (
                left * scale,
                top * scale,
                right * scale - 1,
                bottom * scale - 1,
            ),
            fill=0,
        )

    # Seal raster-only seams without materially expanding geometry. The
    # default reproduces the former 3x3 supersampled close at scale 4.
    closure_radius = round(args.seam_closure_radius * scale)
    if closure_radius > 0:
        closure_width = closure_radius * 2 + 1
        mask = mask.filter(ImageFilter.MaxFilter(closure_width)).filter(
            ImageFilter.MinFilter(closure_width)
        )
    maximum_hole_area = round(args.minimum_hole_area * scale * scale)
    holes_filled = fill_small_holes(mask, maximum_hole_area)

    edge_width = max(3, scale * 2 - 1)
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(edge_width)))
    output = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    output.paste((*args.fill_rgb, args.fill_alpha), mask=mask)
    output.paste((*args.edge_rgb, args.edge_alpha), mask=edge)
    output = output.resize((args.width, args.height), Image.Resampling.LANCZOS)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output)
    print(
        f"wrote {args.output}: {len(polygons)}/{total_polygons} connected "
        "walkable polygons, "
        f"{holes_filled} small holes removed"
    )


if __name__ == "__main__":
    main()
