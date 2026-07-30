#!/usr/bin/env python3
"""Generate a transparent walkable-area layer from LandSandBoat geometry.

The OBJ is the authoritative collision-space reference. The Detour navmesh
selects surfaces considered traversable and supplies a clean polygon union.
The output uses AshitaMinimap's existing world-to-image calibration.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

from detour_navmesh import read_detour_topology
from generate_path_graph import (
    apply_transitions,
    filter_elevation,
    filtered_native_adjacency,
    parse_transition,
    polygon_adjacency,
    remove_blocked_links,
    selected_indices,
)
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
        "--minimum-island-area",
        type=float,
        default=0.0,
        help=(
            "remove disconnected raster islands smaller than this many "
            "output pixels; useful for isolated navmesh specks"
        ),
    )
    parser.add_argument(
        "--seed",
        action="append",
        type=parse_seed,
        default=[],
        help="verified walkable world-x,world-y; repeat for disconnected regions",
    )
    parser.add_argument(
        "--exclude-seed",
        action="append",
        type=parse_seed,
        default=[],
        help=(
            "world-x,world-y selecting one connected component to omit; "
            "repeat for separately rendered overlapping components"
        ),
    )
    parser.add_argument("--maximum-step", type=float, default=0.65)
    parser.add_argument(
        "--adjacency-mode",
        choices=("native", "inferred"),
        default="native",
        help=(
            "native uses authored Detour neighbors and tile portals; inferred "
            "reconstructs polygon adjacency geometrically for comparison only"
        ),
    )
    parser.add_argument(
        "--transition",
        action="append",
        type=parse_transition,
        default=[],
        help=(
            "verified player connection expressed as "
            "start-x,start-y,start-live-z:end-x,end-y,end-live-z; repeat as needed"
        ),
    )
    parser.add_argument(
        "--blocked-link",
        action="append",
        type=parse_transition,
        default=[],
        help=(
            "verified impassable source edge expressed as "
            "start-x,start-y,start-live-z:end-x,end-y,end-live-z; repeat as needed"
        ),
    )
    parser.add_argument(
        "--transition-snap-radius",
        type=float,
        default=2.0,
        help="maximum 3D endpoint-to-polygon-centroid distance (default: 2)",
    )
    parser.add_argument(
        "--seed-snap-radius",
        type=float,
        default=0.0,
        help=(
            "maximum 2D distance for a seed outside every polygon; zero keeps "
            "the former strict containment behavior (default: 0)"
        ),
    )
    parser.add_argument(
        "--component-report",
        type=Path,
        help=(
            "write a JSON inventory of selected, excluded, and unresolved "
            "native-topology components"
        ),
    )
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


def remove_small_islands(mask: Image.Image, minimum_area: int) -> int:
    """Remove foreground components smaller than the configured raster area."""

    if minimum_area <= 0:
        return 0
    pixels = mask.load()
    width, height = mask.size
    visited = bytearray(width * height)
    removed = 0
    for start_y in range(height):
        for start_x in range(width):
            start_index = start_y * width + start_x
            if visited[start_index] or pixels[start_x, start_y] == 0:
                continue
            component = []
            queue = deque([(start_x, start_y)])
            visited[start_index] = 1
            while queue:
                x, y = queue.popleft()
                component.append((x, y))
                for next_x, next_y in (
                    (x - 1, y),
                    (x + 1, y),
                    (x, y - 1),
                    (x, y + 1),
                ):
                    if (
                        next_x < 0
                        or next_x >= width
                        or next_y < 0
                        or next_y >= height
                    ):
                        continue
                    item = next_y * width + next_x
                    if visited[item] or pixels[next_x, next_y] == 0:
                        continue
                    visited[item] = 1
                    queue.append((next_x, next_y))
            if len(component) < minimum_area:
                for x, y in component:
                    pixels[x, y] = 0
                removed += 1
    return removed


def topology_components(adjacency: list[set[int]]) -> list[list[int]]:
    groups = []
    visited = set()
    for start in range(len(adjacency)):
        if start in visited:
            continue
        group = []
        pending = deque([start])
        visited.add(start)
        while pending:
            current = pending.popleft()
            group.append(current)
            for neighbor in adjacency[current]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    pending.append(neighbor)
        groups.append(sorted(group))
    return groups


def component_inventory(
    polygons: list[list[tuple[float, ...]]]
    | list[tuple[tuple[float, ...], ...]],
    adjacency: list[set[int]],
    selected: set[int],
    excluded: set[int],
) -> list[dict]:
    inventory = []
    for component_id, indices in enumerate(topology_components(adjacency), start=1):
        vertices = [
            vertex for index in indices for vertex in polygons[index]
        ]
        index_set = set(indices)
        if index_set <= excluded:
            classification = "excluded"
        elif index_set <= selected:
            classification = "selected"
        else:
            classification = "unresolved"
        inventory.append(
            {
                "component": component_id,
                "classification": classification,
                "polygons": len(indices),
                "world_bounds": {
                    "minimum_x": round(min(vertex[0] for vertex in vertices), 3),
                    "maximum_x": round(max(vertex[0] for vertex in vertices), 3),
                    "minimum_y": round(-max(vertex[2] for vertex in vertices), 3),
                    "maximum_y": round(-min(vertex[2] for vertex in vertices), 3),
                },
                "nav_elevation": {
                    "minimum": round(min(vertex[1] for vertex in vertices), 3),
                    "maximum": round(max(vertex[1] for vertex in vertices), 3),
                },
                "live_z_equivalent": {
                    "minimum": round(-max(vertex[1] for vertex in vertices), 3),
                    "maximum": round(-min(vertex[1] for vertex in vertices), 3),
                },
            }
        )
    return inventory


def write_component_report(
    path: Path,
    nav: Path,
    adjacency_mode: str,
    polygons: list[list[tuple[float, ...]]]
    | list[tuple[tuple[float, ...], ...]],
    adjacency: list[set[int]],
    selected: set[int],
    excluded: set[int],
    transitions: int,
    blocked_links: int,
) -> None:
    components = component_inventory(
        polygons,
        adjacency,
        selected,
        excluded,
    )
    classifications = {
        classification: sum(
            component["classification"] == classification
            for component in components
        )
        for classification in ("selected", "excluded", "unresolved")
    }
    report = {
        "schema": 1,
        "navmesh": nav.name,
        "adjacency_mode": adjacency_mode,
        "verified_transitions": transitions,
        "verified_blocked_links": blocked_links,
        "polygons": len(polygons),
        "selected_polygons": len(selected),
        "excluded_polygons": len(excluded),
        "component_counts": classifications,
        "components": components,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    args = parse_args()
    if args.supersample < 1:
        raise ValueError("--supersample must be at least 1")
    if args.seam_closure_radius < 0:
        raise ValueError("--seam-closure-radius cannot be negative")
    if args.minimum_island_area < 0:
        raise ValueError("--minimum-island-area cannot be negative")

    obj_bounds = read_obj_bounds(args.obj)
    topology = read_detour_topology(args.nav, args.maximum_step)
    validate_sources(obj_bounds, topology.origin)
    source_polygons = topology.polygons
    total_polygons = len(source_polygons)
    polygons = list(
        filter_elevation(
            list(source_polygons),
            args.minimum_elevation,
            args.maximum_elevation,
        )
    )
    if not polygons:
        raise ValueError("elevation filter excluded every nav polygon")
    adjacency = (
        filtered_native_adjacency(
            source_polygons,
            topology.adjacency,
            polygons,
        )
        if args.adjacency_mode == "native"
        else polygon_adjacency(polygons, args.maximum_step)
    )
    apply_transitions(
        polygons,
        adjacency,
        args.transition,
        args.transition_snap_radius,
    )
    remove_blocked_links(
        polygons,
        adjacency,
        args.blocked_link,
        args.transition_snap_radius,
    )
    selected = set(
        selected_indices(
            polygons,
            adjacency,
            args.seed,
            args.seed_snap_radius,
        )
    )
    excluded = (
        set(
            selected_indices(
                polygons,
                adjacency,
                args.exclude_seed,
                args.seed_snap_radius,
            )
        )
        if args.exclude_seed
        else set()
    )
    selected -= excluded
    if not selected:
        raise ValueError("component selection excluded every nav polygon")
    if args.component_report:
        write_component_report(
            args.component_report,
            args.nav,
            args.adjacency_mode,
            polygons,
            adjacency,
            selected,
            excluded,
            len(args.transition),
            len(args.blocked_link),
        )
    polygons = [polygons[index] for index in sorted(selected)]

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
    minimum_island_area = round(args.minimum_island_area * scale * scale)
    islands_removed = remove_small_islands(mask, minimum_island_area)

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
        f"{holes_filled} small holes removed, "
        f"{islands_removed} small islands removed"
    )


if __name__ == "__main__":
    main()
