"""Validate supported destinations and representative routes on a path graph."""

from __future__ import annotations

import argparse
import heapq
import math
from dataclasses import dataclass
from pathlib import Path

from validate_path_graphs import parse_graph, validate


@dataclass(frozen=True)
class Point:
    name: str
    x: float
    y: float
    z: float | None


def parse_point(value: str) -> Point:
    parts = value.split(",")
    if len(parts) not in (3, 4):
        raise argparse.ArgumentTypeError("point must be name,x,y[,live-z]")
    try:
        return Point(
            name=parts[0],
            x=float(parts[1]),
            y=float(parts[2]),
            z=float(parts[3]) if len(parts) == 4 else None,
        )
    except ValueError as exception:
        raise argparse.ArgumentTypeError(
            "point coordinates must be numeric"
        ) from exception


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Snap supported destinations to a display-only graph and verify "
            "representative routes without requiring structure assets."
        )
    )
    parser.add_argument("graph", type=Path)
    parser.add_argument("--point", action="append", type=parse_point, default=[])
    parser.add_argument(
        "--route",
        action="append",
        default=[],
        help="required route expressed as start-name:end-name",
    )
    return parser.parse_args()


def nearest_node(
    nodes: list[tuple],
    snap_radius: float,
    point: Point,
    floor_tolerance: float = 4.0,
) -> tuple[int, float]:
    candidates = []
    for index, node in enumerate(nodes):
        planar = math.hypot(node[0] - point.x, node[1] - point.y)
        live_z = -node[2]
        elevation = abs(live_z - point.z) if point.z is not None else 0.0
        if point.z is None or elevation <= floor_tolerance:
            candidates.append((math.hypot(planar, elevation), planar, index))
    if not candidates:
        raise ValueError(f"{point.name}: no graph node on the requested floor")
    _, planar, index = min(candidates)
    if planar > snap_radius:
        raise ValueError(
            f"{point.name}: nearest graph node is {planar:.3f} yalms away "
            f"(snap radius {snap_radius:.3f})"
        )
    return index, planar


def shortest_route(nodes: list[tuple], start: int, target: int) -> float | None:
    costs = {start: 0.0}
    pending = [(0.0, start)]
    while pending:
        cost, current = heapq.heappop(pending)
        if cost != costs.get(current):
            continue
        if current == target:
            return cost
        current_node = nodes[current]
        for neighbor_value in current_node[3]:
            neighbor = neighbor_value - 1
            other = nodes[neighbor]
            edge = math.sqrt(
                (current_node[0] - other[0]) ** 2
                + (current_node[1] - other[1]) ** 2
                + (current_node[2] - other[2]) ** 2
            )
            candidate = cost + edge
            if candidate < costs.get(neighbor, math.inf):
                costs[neighbor] = candidate
                heapq.heappush(pending, (candidate, neighbor))
    return None


def main() -> None:
    validate(args.graph)
    _, _, snap_radius, nodes = parse_graph(args.graph)
    points = {}
    for point in args.point:
        if point.name in points:
            raise ValueError(f"duplicate point name: {point.name}")
        index, distance = nearest_node(nodes, snap_radius, point)
        points[point.name] = index
        print(
            f"{point.name}: node {index + 1}, snap {distance:.3f} yalms"
        )
    for route in args.route:
        try:
            start_name, target_name = route.split(":", 1)
        except ValueError as exception:
            raise ValueError("route must be start-name:end-name") from exception
        if start_name not in points or target_name not in points:
            raise ValueError(f"{route}: route names must reference --point")
        distance = shortest_route(
            nodes,
            points[start_name],
            points[target_name],
        )
        if distance is None:
            raise ValueError(f"{route}: no connected route")
        print(f"{route}: {distance:.3f} yalms")


if __name__ == "__main__":
    args = parse_args()
    main()
