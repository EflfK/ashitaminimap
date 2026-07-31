"""Generate an AshitaMinimap display-only path graph from a Detour navmesh."""

from __future__ import annotations

import argparse
import math
from collections import defaultdict, deque
from pathlib import Path

from detour_navmesh import point_in_polygon, read_detour_topology
from PIL import Image


def parse_seed(value: str) -> tuple[float, float, float | None]:
    try:
        parts = value.split(",")
        if len(parts) not in (2, 3):
            raise ValueError
        return (
            float(parts[0]),
            float(parts[1]),
            float(parts[2]) if len(parts) == 3 else None,
        )
    except ValueError as exception:
        raise argparse.ArgumentTypeError(
            "seed must be world-x,world-y[,live-z]"
        ) from exception


def parse_transition(
    value: str,
) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    try:
        start_text, end_text = value.split(":", 1)
        start = tuple(float(part) for part in start_text.split(","))
        end = tuple(float(part) for part in end_text.split(","))
    except ValueError as exception:
        raise argparse.ArgumentTypeError(
            "transition must be start-x,start-y,start-live-z:"
            "end-x,end-y,end-live-z"
        ) from exception
    if len(start) != 3 or len(end) != 3:
        raise argparse.ArgumentTypeError(
            "transition must be start-x,start-y,start-live-z:"
            "end-x,end-y,end-live-z"
        )
    return start, end


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
            "verified world-x,world-y[,live-z] selecting a connected component; "
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
        "--adjacency-mode",
        choices=("native", "inferred"),
        default="native",
        help=(
            "native reads dtPoly neighbors and resolves only authored tile "
            "portals; inferred reconstructs every polygon edge geometrically "
            "(default: native)"
        ),
    )
    parser.add_argument(
        "--snap-radius",
        type=float,
        default=24.0,
        help="maximum runtime endpoint snap distance in yalms (default: 24)",
    )
    parser.add_argument(
        "--transition",
        action="append",
        type=parse_transition,
        default=[],
        help=(
            "authored bidirectional link between disconnected navigation "
            "polygons, expressed as start-x,start-y,start-live-z:"
            "end-x,end-y,end-live-z; repeat for multiple links"
        ),
    )
    parser.add_argument(
        "--one-way-transition",
        action="append",
        type=parse_transition,
        default=[],
        help=(
            "authored directed link from the first navigation polygon to the "
            "second, expressed as start-x,start-y,start-live-z:"
            "end-x,end-y,end-live-z; repeat for multiple links"
        ),
    )
    parser.add_argument(
        "--blocked-link",
        action="append",
        type=parse_transition,
        default=[],
        help=(
            "remove a false source-navmesh adjacency, expressed as "
            "start-x,start-y,start-live-z:end-x,end-y,end-live-z; "
            "repeat for multiple blocked links"
        ),
    )
    parser.add_argument(
        "--transition-snap-radius",
        type=float,
        default=2.0,
        help=(
            "maximum 3D distance from an authored transition endpoint to a "
            "polygon centroid (default: 2)"
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


def filtered_native_adjacency(
    source_polygons: list[list[tuple[float, ...]]]
    | tuple[tuple[tuple[float, ...], ...], ...],
    source_adjacency: list[set[int]] | tuple[frozenset[int], ...],
    polygons: list[list[tuple[float, ...]]],
) -> list[set[int]]:
    source_index = {id(polygon): index for index, polygon in enumerate(source_polygons)}
    retained_sources = [source_index[id(polygon)] for polygon in polygons]
    remap = {
        source: target for target, source in enumerate(retained_sources)
    }
    return [
        {
            remap[neighbor]
            for neighbor in source_adjacency[source]
            if neighbor in remap
        }
        for source in retained_sources
    ]


def selected_indices(
    polygons: list[list[tuple[float, ...]]],
    adjacency: list[set[int]],
    seeds: list[tuple[float, float, float | None]],
    maximum_seed_snap: float,
) -> list[int]:
    if not seeds:
        return list(range(len(polygons)))
    selection_adjacency = [set(neighbors) for neighbors in adjacency]
    for left, neighbors in enumerate(adjacency):
        for right in neighbors:
            selection_adjacency[right].add(left)
    visited = set()
    pending = deque()
    for seed in seeds:
        seed_live_z = seed[2] if len(seed) > 2 else None
        containing = [
            index
            for index, polygon in enumerate(polygons)
            if point_in_polygon(polygon, seed[0], -seed[1])
        ]
        start = (
            min(
                containing,
                key=lambda index: abs(
                    (
                        -sum(vertex[1] for vertex in polygons[index])
                        / len(polygons[index])
                    )
                    - seed_live_z
                ),
            )
            if containing and seed_live_z is not None
            else (containing[0] if containing else None)
        )
        if start is None:
            nearest = min(
                (
                    (
                        math.sqrt(
                            (
                                sum(vertex[0] for vertex in polygon)
                                / len(polygon)
                                - seed[0]
                            )
                            ** 2
                            + (
                                -sum(vertex[2] for vertex in polygon)
                                / len(polygon)
                                - seed[1]
                            )
                            ** 2
                            + (
                                (
                                    -sum(vertex[1] for vertex in polygon)
                                    / len(polygon)
                                )
                                - seed_live_z
                            )
                            ** 2
                            if seed_live_z is not None
                            else (
                                sum(vertex[0] for vertex in polygon)
                                / len(polygon)
                                - seed[0]
                            )
                            ** 2
                            + (
                                -sum(vertex[2] for vertex in polygon)
                                / len(polygon)
                                - seed[1]
                            )
                            ** 2
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
        for neighbor in selection_adjacency[current]:
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


def nearest_centroid(
    centroids: list[tuple[float, float, float]],
    endpoint: tuple[float, float, float],
    snap_radius: float,
    label: str,
) -> int:
    distance, index = min(
        (
            math.sqrt(
                (point[0] - endpoint[0]) ** 2
                + (point[1] - endpoint[1]) ** 2
                + (-point[2] - endpoint[2]) ** 2
            ),
            index,
        )
        for index, point in enumerate(centroids)
    )
    if distance > snap_radius:
        raise ValueError(
            f"{label} endpoint {endpoint} is {distance:.3f} yalms "
            f"from the nearest polygon centroid, exceeding {snap_radius:g}"
        )
    return index


def apply_transitions(
    polygons: list[list[tuple[float, ...]]],
    adjacency: list[set[int]],
    transitions: list[
        tuple[tuple[float, float, float], tuple[float, float, float]]
    ],
    snap_radius: float,
) -> None:
    if snap_radius <= 0:
        raise ValueError("--transition-snap-radius must be positive")
    centroids = [centroid(polygon) for polygon in polygons]

    for start, end in transitions:
        start_index = nearest_centroid(
            centroids, start, snap_radius, "transition"
        )
        end_index = nearest_centroid(
            centroids, end, snap_radius, "transition"
        )
        if start_index == end_index:
            raise ValueError(
                f"transition endpoints {start} and {end} resolve to one polygon"
            )
        adjacency[start_index].add(end_index)
        adjacency[end_index].add(start_index)


def apply_one_way_transitions(
    polygons: list[list[tuple[float, ...]]],
    adjacency: list[set[int]],
    transitions: list[
        tuple[tuple[float, float, float], tuple[float, float, float]]
    ],
    snap_radius: float,
) -> set[tuple[int, int]]:
    if snap_radius <= 0:
        raise ValueError("--transition-snap-radius must be positive")
    centroids = [centroid(polygon) for polygon in polygons]
    directed_edges = set()

    for start, end in transitions:
        start_index = nearest_centroid(
            centroids, start, snap_radius, "one-way transition"
        )
        end_index = nearest_centroid(
            centroids, end, snap_radius, "one-way transition"
        )
        if start_index == end_index:
            raise ValueError(
                f"one-way transition endpoints {start} and {end} "
                "resolve to one polygon"
            )
        adjacency[start_index].add(end_index)
        adjacency[end_index].discard(start_index)
        directed_edges.add((start_index, end_index))
    return directed_edges


def remove_blocked_links(
    polygons: list[list[tuple[float, ...]]],
    adjacency: list[set[int]],
    blocked_links: list[
        tuple[tuple[float, float, float], tuple[float, float, float]]
    ],
    snap_radius: float,
) -> None:
    centroids = [centroid(polygon) for polygon in polygons]
    for start, end in blocked_links:
        start_index = nearest_centroid(
            centroids, start, snap_radius, "blocked link"
        )
        end_index = nearest_centroid(
            centroids, end, snap_radius, "blocked link"
        )
        if end_index not in adjacency[start_index]:
            raise ValueError(
                f"blocked link {start} to {end} is not present in the "
                "source graph"
            )
        adjacency[start_index].remove(end_index)
        adjacency[end_index].remove(start_index)


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
    directed_edges: set[tuple[int, int]],
) -> None:
    remap = {source: target + 1 for target, source in enumerate(indices)}
    lines = [
        "-- Generated by tools/generate_path_graph.py; do not hand-edit.",
        "return {",
        f"    zone_id = {zone_id},",
        f"    page_id = {page_id if page_id is not None else 'nil'},",
        f"    snap_radius = {lua_number(snap_radius)},",
    ]
    retained_directed_edges = sorted(
        (remap[start], remap[end])
        for start, end in directed_edges
        if start in remap and end in remap
    )
    if retained_directed_edges:
        lines.append("    one_way_edges = {")
        for start, end in retained_directed_edges:
            lines.append(f"        {{ {start}, {end} }},")
        lines.append("    },")
    lines.append("    nodes = {")
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
    topology = read_detour_topology(args.nav, args.maximum_step)
    source_polygons = topology.polygons
    polygons = list(source_polygons)
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
    directed_edges = apply_one_way_transitions(
        polygons,
        adjacency,
        args.one_way_transition,
        args.transition_snap_radius,
    )
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
        directed_edges,
    )
    connections = {
        tuple(sorted((index, neighbor)))
        for index in indices
        for neighbor in adjacency[index]
        if neighbor in selected
    }
    retained_directed = sum(
        start in selected and end in selected
        for start, end in directed_edges
    )
    print(
        f"wrote {args.output}: {len(indices)} nodes, "
        f"{len(connections)} connections ({retained_directed} one-way)"
    )


if __name__ == "__main__":
    main()
