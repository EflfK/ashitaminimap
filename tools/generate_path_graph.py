"""Generate an AshitaMinimap display-only path graph from a Detour navmesh."""

from __future__ import annotations

import argparse
import math
from collections import defaultdict, deque
from pathlib import Path

from generate_walkable_map import point_in_polygon, read_navmesh
from PIL import Image


def parse_seed(value: str) -> tuple[float, float]:
    try:
        x, y = value.split(",", 1)
        return float(x), float(y)
    except ValueError as exception:
        raise argparse.ArgumentTypeError("seed must be world-x,world-y") from exception


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("nav", type=Path, help="compiled Detour .nav file")
    parser.add_argument("output", type=Path, help="output Lua graph")
    parser.add_argument("--zone-id", type=int, required=True)
    parser.add_argument("--page-id", type=int)
    parser.add_argument(
        "--seed",
        action="append",
        type=parse_seed,
        default=[],
        help=(
            "verified world-x,world-y selecting a connected component; "
            "repeat for disconnected authored components"
        ),
    )
    parser.add_argument(
        "--maximum-step",
        type=float,
        default=0.65,
        help="maximum vertical seam step in yalms (default: 0.65)",
    )
    parser.add_argument(
        "--snap-radius",
        type=float,
        default=24.0,
        help="maximum runtime endpoint snap distance in yalms (default: 24)",
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
        "--mask",
        action="append",
        type=Path,
        default=[],
        help=(
            "authored structure PNG used to retain graph-node centroids; "
            "repeat to union multiple floor/component layers"
        ),
    )
    parser.add_argument(
        "--origin-x",
        type=float,
        help="source-image X coordinate for world (0,0), required with --mask",
    )
    parser.add_argument(
        "--origin-y",
        type=float,
        help="source-image Y coordinate for world (0,0), required with --mask",
    )
    parser.add_argument(
        "--pixels-per-yalm",
        type=float,
        help="source-image scale, required with --mask",
    )
    return parser.parse_args()


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


def polygon_adjacency(
    polygons: list[list[tuple[float, ...]]], maximum_step: float
) -> list[set[int]]:
    adjacency = [set() for _ in polygons]

    def connect(left: int, right: int) -> None:
        if left != right:
            adjacency[left].add(right)
            adjacency[right].add(left)

    def vertex_key(vertex: tuple[float, ...]) -> tuple[float, ...]:
        return tuple(round(value, 3) for value in vertex)

    exact_edges: dict[tuple[tuple[float, ...], ...], int] = {}
    axis_edges: dict[
        tuple[str, float],
        list[tuple[float, float, tuple[float, ...], tuple[float, ...], int]],
    ] = defaultdict(list)
    for polygon_index, polygon in enumerate(polygons):
        for edge_index, start in enumerate(polygon):
            end = polygon[(edge_index + 1) % len(polygon)]
            edge = tuple(sorted((vertex_key(start), vertex_key(end))))
            previous = exact_edges.get(edge)
            if previous is not None:
                connect(polygon_index, previous)
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
                    connect(edge[4], candidate[4])
    return adjacency


def selected_indices(
    polygons: list[list[tuple[float, ...]]],
    adjacency: list[set[int]],
    seeds: list[tuple[float, float]],
    maximum_seed_snap: float,
) -> list[int]:
    if not seeds:
        return list(range(len(polygons)))
    visited = set()
    pending = deque()
    for seed in seeds:
        start = next(
            (
                index
                for index, polygon in enumerate(polygons)
                if point_in_polygon(polygon, seed[0], -seed[1])
            ),
            None,
        )
        if start is None:
            nearest = min(
                (
                    (
                        math.hypot(
                            sum(vertex[0] for vertex in polygon) / len(polygon)
                            - seed[0],
                            -sum(vertex[2] for vertex in polygon) / len(polygon)
                            - seed[1],
                        ),
                        index,
                    )
                    for index, polygon in enumerate(polygons)
                ),
                default=None,
            )
            if nearest is None or nearest[0] > maximum_seed_snap:
                raise ValueError(
                    f"seed {seed} is outside every navigation polygon and "
                    f"more than {maximum_seed_snap:g} yalms from the nearest center"
                )
            start = nearest[1]
        if start not in visited:
            visited.add(start)
            pending.append(start)
    while pending:
        current = pending.popleft()
        for neighbor in adjacency[current]:
            if neighbor not in visited:
                visited.add(neighbor)
                pending.append(neighbor)
    return sorted(visited)


def filter_elevation(
    polygons: list[list[tuple[float, ...]]],
    minimum: float | None,
    maximum: float | None,
) -> list[list[tuple[float, ...]]]:
    lower = minimum if minimum is not None else float("-inf")
    upper = maximum if maximum is not None else float("inf")
    if lower > upper:
        raise ValueError("--minimum-elevation cannot exceed --maximum-elevation")
    return [
        polygon
        for polygon in polygons
        if lower
        <= sum(vertex[1] for vertex in polygon) / len(polygon)
        <= upper
    ]


def filter_masks(
    polygons: list[list[tuple[float, ...]]],
    masks: list[Path],
    origin_x: float | None,
    origin_y: float | None,
    pixels_per_yalm: float | None,
) -> list[list[tuple[float, ...]]]:
    if not masks:
        return polygons
    if origin_x is None or origin_y is None or pixels_per_yalm is None:
        raise ValueError(
            "--origin-x, --origin-y, and --pixels-per-yalm are required with --mask"
        )
    if pixels_per_yalm <= 0:
        raise ValueError("--pixels-per-yalm must be positive")
    images = [Image.open(path).convert("RGBA") for path in masks]
    sizes = {image.size for image in images}
    if len(sizes) != 1:
        raise ValueError("--mask images must have identical dimensions")
    width, height = images[0].size

    def authored_at(x: float, y: float) -> bool:
        image_x = round(origin_x + x * pixels_per_yalm)
        image_y = round(origin_y - y * pixels_per_yalm)
        for image in images:
            for offset_y in (-1, 0, 1):
                for offset_x in (-1, 0, 1):
                    sample_x = image_x + offset_x
                    sample_y = image_y + offset_y
                    if (
                        0 <= sample_x < width
                        and 0 <= sample_y < height
                        and image.getpixel((sample_x, sample_y))[3] > 0
                    ):
                        return True
        return False

    return [
        polygon
        for polygon in polygons
        if authored_at(
            sum(vertex[0] for vertex in polygon) / len(polygon),
            -sum(vertex[2] for vertex in polygon) / len(polygon),
        )
    ]


def centroid(polygon: list[tuple[float, ...]]) -> tuple[float, float, float]:
    count = len(polygon)
    return (
        sum(vertex[0] for vertex in polygon) / count,
        -sum(vertex[2] for vertex in polygon) / count,
        sum(vertex[1] for vertex in polygon) / count,
    )


def lua_number(value: float) -> str:
    if not math.isfinite(value):
        raise ValueError("graph contains a non-finite coordinate")
    return f"{value:.3f}"


def write_graph(
    output: Path,
    zone_id: int,
    page_id: int | None,
    snap_radius: float,
    polygons: list[list[tuple[float, ...]]],
    adjacency: list[set[int]],
    indices: list[int],
) -> None:
    remap = {source: target + 1 for target, source in enumerate(indices)}
    lines = [
        "-- Generated by tools/generate_path_graph.py; do not hand-edit.",
        "return {",
        f"    zone_id = {zone_id},",
        f"    page_id = {page_id if page_id is not None else 'nil'},",
        f"    snap_radius = {lua_number(snap_radius)},",
        "    nodes = {",
    ]
    for source_index in indices:
        x, y, z = centroid(polygons[source_index])
        links = sorted(
            remap[neighbor]
            for neighbor in adjacency[source_index]
            if neighbor in remap
        )
        link_text = ", ".join(str(link) for link in links)
        lines.append(
            "        { "
            f"{lua_number(x)}, {lua_number(y)}, {lua_number(z)}, "
            f"{{ {link_text} }} "
            "},"
        )
    lines.extend(("    },", "}", ""))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> None:
    args = parse_args()
    _, polygons = read_navmesh(args.nav)
    polygons = filter_elevation(
        polygons,
        args.minimum_elevation,
        args.maximum_elevation,
    )
    polygons = filter_masks(
        polygons,
        args.mask,
        args.origin_x,
        args.origin_y,
        args.pixels_per_yalm,
    )
    if not polygons:
        raise ValueError("graph filters excluded every navigation polygon")
    adjacency = polygon_adjacency(polygons, args.maximum_step)
    indices = selected_indices(polygons, adjacency, args.seed, args.snap_radius)
    selected = set(indices)
    write_graph(
        args.output,
        args.zone_id,
        args.page_id,
        args.snap_radius,
        polygons,
        adjacency,
        indices,
    )
    edge_count = sum(
        1
        for index in indices
        for neighbor in adjacency[index]
        if neighbor in selected and neighbor > index
    )
    print(f"wrote {args.output}: {len(indices)} nodes, {edge_count} edges")


if __name__ == "__main__":
    main()
