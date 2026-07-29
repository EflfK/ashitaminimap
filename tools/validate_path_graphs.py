"""Validate generated AshitaMinimap Lua path-graph artifacts."""

from __future__ import annotations

import argparse
import math
import re
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
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


def validate(path: Path) -> tuple[int, int]:
    zone_id, page_id, snap_radius, nodes = parse_graph(path)
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

    for edge in edges:
        if (edge[1], edge[0]) not in edges:
            raise ValueError(
                f"{path}: edge {edge[0]} -> {edge[1]} is not bidirectional"
            )
    return len(nodes), len(edges) // 2


def main() -> None:
    for path in args.graphs:
        nodes, edges = validate(path)
        print(f"{path}: {nodes} nodes, {edges} bidirectional edges")


if __name__ == "__main__":
    args = parse_args()
    main()
