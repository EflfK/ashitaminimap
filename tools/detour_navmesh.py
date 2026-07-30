"""Read native Detour polygon topology from LandSandBoat MSET v1 files."""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from pathlib import Path


DT_EXT_LINK = 0x8000
GROUND_POLYGON_TYPE = 0
POLYGON_RECORD_SIZE = 32
TILE_HEADER_SIZE = 100


@dataclass(frozen=True)
class PortalEdge:
    polygon: int
    tile_x: int
    tile_y: int
    side: int
    start: tuple[float, float, float]
    end: tuple[float, float, float]


@dataclass(frozen=True)
class DetourTopology:
    origin: tuple[float, float, float]
    polygons: tuple[tuple[tuple[float, float, float], ...], ...]
    polygon_sources: tuple[tuple[int, int, int, int], ...]
    adjacency: tuple[frozenset[int], ...]
    edge_kinds: dict[tuple[int, int], str]
    portals: tuple[PortalEdge, ...]
    internal_edges: int
    portal_edges: int


def _height_at(
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    position: float,
    axis: int,
) -> float:
    delta = end[axis] - start[axis]
    if abs(delta) < 0.000001:
        return start[1]
    ratio = (position - start[axis]) / delta
    return start[1] + (end[1] - start[1]) * ratio


def _portal_overlap(
    left: PortalEdge,
    right: PortalEdge,
    maximum_step: float,
) -> bool:
    if (left.side, right.side) not in {(0, 4), (4, 0), (2, 6), (6, 2)}:
        return False
    if left.side in (0, 4):
        if abs(left.start[0] - right.start[0]) > 0.02:
            return False
        axis = 2
    else:
        if abs(left.start[2] - right.start[2]) > 0.02:
            return False
        axis = 0
    left_low, left_high = sorted((left.start[axis], left.end[axis]))
    right_low, right_high = sorted((right.start[axis], right.end[axis]))
    overlap_low = max(left_low, right_low)
    overlap_high = min(left_high, right_high)
    if overlap_high - overlap_low <= 0.01:
        return False
    midpoint = (overlap_low + overlap_high) / 2
    height_delta = abs(
        _height_at(left.start, left.end, midpoint, axis)
        - _height_at(right.start, right.end, midpoint, axis)
    )
    return height_delta <= maximum_step


def read_detour_topology(
    path: Path,
    maximum_step: float = 0.65,
) -> DetourTopology:
    """Return ground polygons and Detour-authored adjacency.

    Internal neighbors come directly from ``dtPoly.neis``. Cross-tile geometry
    is considered only for edges explicitly marked as Detour external portals.
    """

    if maximum_step < 0:
        raise ValueError("maximum_step cannot be negative")
    data = path.read_bytes()
    magic, version, tile_count = struct.unpack_from("<iii", data, 0)
    if magic != 0x4D534554 or version != 1:
        raise ValueError(f"{path} is not a supported MSET v1 navmesh")

    origin = struct.unpack_from("<3f", data, 12)
    offset = 40
    polygons: list[tuple[tuple[float, float, float], ...]] = []
    polygon_sources: list[tuple[int, int, int, int]] = []
    local_to_global: dict[tuple[int, int], int] = {}
    tile_records = []

    for tile_serial in range(tile_count):
        _, data_size = struct.unpack_from("<Ii", data, offset)
        offset += 8
        tile_offset = offset
        offset += data_size

        header = struct.unpack_from("<15i3f3f3f3ff", data, tile_offset)
        tile_x, tile_y, tile_layer = header[2], header[3], header[4]
        polygon_count, vertex_count = header[6], header[7]
        vertex_offset = tile_offset + TILE_HEADER_SIZE
        vertices = tuple(
            struct.unpack_from("<3f", data, vertex_offset + index * 12)
            for index in range(vertex_count)
        )
        polygon_offset = vertex_offset + vertex_count * 12
        records = []
        for local_index in range(polygon_count):
            record = struct.unpack_from(
                "<I6H6HHBB",
                data,
                polygon_offset + local_index * POLYGON_RECORD_SIZE,
            )
            vertex_total = record[-2]
            polygon_type = record[-1] >> 6
            vertex_indices = record[1:7]
            neighbors = record[7:13]
            global_index = None
            if vertex_total >= 3 and polygon_type == GROUND_POLYGON_TYPE:
                global_index = len(polygons)
                local_to_global[(tile_serial, local_index)] = global_index
                polygons.append(
                    tuple(vertices[item] for item in vertex_indices[:vertex_total])
                )
                polygon_sources.append(
                    (tile_x, tile_y, tile_layer, local_index)
                )
            records.append(
                (global_index, vertex_total, vertex_indices, neighbors)
            )
        tile_records.append((tile_x, tile_y, vertices, records))

    if offset != len(data):
        raise ValueError(f"{path} has unexpected trailing navmesh data")

    adjacency = [set() for _ in polygons]
    edge_kinds: dict[tuple[int, int], str] = {}
    portals: list[PortalEdge] = []

    def connect(left: int, right: int, kind: str) -> None:
        if left == right:
            return
        adjacency[left].add(right)
        adjacency[right].add(left)
        edge_kinds[tuple(sorted((left, right)))] = kind

    for tile_serial, (tile_x, tile_y, vertices, records) in enumerate(
        tile_records
    ):
        for local_index, record in enumerate(records):
            global_index, vertex_total, vertex_indices, neighbors = record
            if global_index is None:
                continue
            for edge_index in range(vertex_total):
                neighbor = neighbors[edge_index]
                if neighbor == 0:
                    continue
                if neighbor & DT_EXT_LINK:
                    start = vertices[vertex_indices[edge_index]]
                    end = vertices[vertex_indices[(edge_index + 1) % vertex_total]]
                    portals.append(
                        PortalEdge(
                            polygon=global_index,
                            tile_x=tile_x,
                            tile_y=tile_y,
                            side=neighbor & 0xFF,
                            start=start,
                            end=end,
                        )
                    )
                    continue
                neighbor_index = local_to_global.get(
                    (tile_serial, (neighbor & 0x7FFF) - 1)
                )
                if neighbor_index is not None:
                    connect(global_index, neighbor_index, "internal")

    portal_buckets: dict[tuple[int, int, int], list[PortalEdge]] = {}
    for portal in portals:
        if portal.side == 0:
            key = (portal.tile_x + 1, portal.tile_y, 4)
        elif portal.side == 4:
            key = (portal.tile_x - 1, portal.tile_y, 0)
        elif portal.side == 2:
            key = (portal.tile_x, portal.tile_y + 1, 6)
        elif portal.side == 6:
            key = (portal.tile_x, portal.tile_y - 1, 2)
        else:
            continue
        portal_buckets.setdefault(key, []).append(portal)

    portal_lookup: dict[tuple[int, int, int], list[PortalEdge]] = {}
    for portal in portals:
        portal_lookup.setdefault(
            (portal.tile_x, portal.tile_y, portal.side), []
        ).append(portal)
    connected_portal_pairs = set()
    for key, left_edges in portal_buckets.items():
        for left in left_edges:
            for right in portal_lookup.get(key, ()):
                pair = tuple(sorted((left.polygon, right.polygon)))
                if pair in connected_portal_pairs:
                    continue
                if _portal_overlap(left, right, maximum_step):
                    connect(left.polygon, right.polygon, "portal")
                    connected_portal_pairs.add(pair)

    internal_edges = sum(kind == "internal" for kind in edge_kinds.values())
    portal_edges = sum(kind == "portal" for kind in edge_kinds.values())
    return DetourTopology(
        origin=origin,
        polygons=tuple(polygons),
        polygon_sources=tuple(polygon_sources),
        adjacency=tuple(frozenset(items) for items in adjacency),
        edge_kinds=edge_kinds,
        portals=tuple(portals),
        internal_edges=internal_edges,
        portal_edges=portal_edges,
    )


def centroid(
    polygon: tuple[tuple[float, float, float], ...],
) -> tuple[float, float, float]:
    count = len(polygon)
    return (
        sum(vertex[0] for vertex in polygon) / count,
        -sum(vertex[2] for vertex in polygon) / count,
        sum(vertex[1] for vertex in polygon) / count,
    )


def edge_length(
    polygons: tuple[tuple[tuple[float, float, float], ...], ...],
    edge: tuple[int, int],
) -> float:
    left = centroid(polygons[edge[0]])
    right = centroid(polygons[edge[1]])
    return math.sqrt(sum((left[index] - right[index]) ** 2 for index in range(3)))


def point_in_polygon(
    polygon: tuple[tuple[float, ...], ...] | list[tuple[float, ...]],
    x: float,
    y: float,
) -> bool:
    """Return whether an X/Z point lies inside a convex Detour polygon."""

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
