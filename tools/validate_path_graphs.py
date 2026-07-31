"""Validate generated AshitaMinimap Lua path-graph artifacts."""

from __future__ import annotations

import argparse
import math
import re
from collections import deque
from pathlib import Path


HEADER_PATTERN = re.compile(
    r"^\s*(zone_id|page_id|snap_radius)\s*=\s*([^,]+),\s*$"
)
NODE_PATTERN = re.compile(
    r"^\s*\{\s*"
    r"([-+]?\d+(?:\.\d+)?)\s*,\s*"
    r"([-+]?\d+(?:\.\d+)?)\s*,\s*"
    r"([-+]?\d+(?:\.\d+)?)\s*,\s*"
    r"\{\s*([^}]*)\}\s*"
    r"\},\s*$"
)
ONE_WAY_PATTERN = re.compile(
    r"^\s*\{\s*(\d+)\s*,\s*(\d+)\s*\},\s*$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate display-only routing graphs independently of structure "
            "images."
        )
    )
    parser.add_argument(
        "--require-connected",
        action="store_true",
        help=(
            "fail when a graph contains more than one connected component; "
            "use for zones whose supported destinations must all interroute"
        ),
    )
    parser.add_argument("graphs", nargs="+", type=Path)
    return parser.parse_args()


def parse_graph(path: Path) -> tuple[int, int | None, float, list[tuple]]:
    headers: dict[str, str] = {}
    nodes = []
    for line in path.read_text(encoding="utf-8").splitlines():
        header = HEADER_PATTERN.match(line)
        if header:
            headers[header.group(1)] = header.group(2).strip()
            continue
        node = NODE_PATTERN.match(line)
        if node:
            coordinates = tuple(float(node.group(index)) for index in range(1, 4))
            links = tuple(
                int(value.strip())
                for value in node.group(4).split(",")
                if value.strip()
            )
            nodes.append((*coordinates, links))
    zone_id = int(headers["zone_id"])
    page_text = headers["page_id"]
    page_id = None if page_text == "nil" else int(page_text)
    snap_radius = float(headers["snap_radius"])
    return zone_id, page_id, snap_radius, nodes


def validate(path: Path, require_connected: bool = False) -> tuple[int, int]:
    zone_id, page_id, snap_radius, nodes = parse_graph(path)
    one_way_edges = {
        (int(match.group(1)), int(match.group(2)))
        for line in path.read_text(encoding="utf-8").splitlines()
        if (match := ONE_WAY_PATTERN.match(line))
    }
    if zone_id <= 0:
        raise ValueError(f"{path}: invalid zone_id {zone_id}")
    if page_id is not None and page_id < 0:
        raise ValueError(f"{path}: invalid page_id {page_id}")
    if not math.isfinite(snap_radius) or snap_radius <= 0:
        raise ValueError(f"{path}: invalid snap_radius {snap_radius}")
    if len(nodes) < 2:
        raise ValueError(f"{path}: graph has fewer than two nodes")

    edges = set()
    for index, node in enumerate(nodes, start=1):
        if not all(math.isfinite(value) for value in node[:3]):
            raise ValueError(f"{path}: node {index} has non-finite coordinates")
        for neighbor in node[3]:
            if neighbor < 1 or neighbor > len(nodes):
                raise ValueError(
                    f"{path}: node {index} links to missing node {neighbor}"
                )
            if neighbor == index:
                raise ValueError(f"{path}: node {index} links to itself")
            edges.add((index, neighbor))

    for edge in one_way_edges:
        if edge not in edges:
            raise ValueError(
                f"{path}: declared one-way edge {edge[0]} -> {edge[1]} "
                "is not present"
            )
        if (edge[1], edge[0]) in edges:
            raise ValueError(
                f"{path}: declared one-way edge {edge[0]} -> {edge[1]} "
                "also has a reverse edge"
            )
    for edge in edges:
        reverse = (edge[1], edge[0])
        if reverse not in edges and edge not in one_way_edges:
            raise ValueError(
                f"{path}: edge {edge[0]} -> {edge[1]} is neither "
                "bidirectional nor declared one-way"
            )
    if require_connected:
        undirected = [set(node[3]) for node in nodes]
        for left, neighbors in enumerate(nodes, start=1):
            for right in neighbors[3]:
                undirected[right - 1].add(left)
        visited = {1}
        pending = deque([1])
        while pending:
            current = pending.popleft()
            for neighbor in undirected[current - 1]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    pending.append(neighbor)
        if len(visited) != len(nodes):
            raise ValueError(
                f"{path}: graph has disconnected routing components "
                f"({len(visited)}/{len(nodes)} nodes reachable from node 1)"
            )
    connections = {
        tuple(sorted(edge))
        for edge in edges
    }
    return len(nodes), len(connections)


def main() -> None:
    for path in args.graphs:
        nodes, edges = validate(path, args.require_connected)
        one_way_count = sum(
            1
            for line in path.read_text(encoding="utf-8").splitlines()
            if ONE_WAY_PATTERN.match(line)
        )
        print(
            f"{path}: {nodes} nodes, {edges} connections "
            f"({one_way_count} one-way)"
        )


if __name__ == "__main__":
    args = parse_args()
    main()
