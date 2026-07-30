"""Tests for topology-aware structure component selection."""

from __future__ import annotations

import unittest

from generate_path_graph import (
    apply_transitions,
    remove_blocked_links,
    selected_indices,
)
from generate_walkable_map import component_inventory


def square(center_x: float, nav_elevation: float = 0.0) -> list[tuple[float, ...]]:
    return [
        (center_x - 0.5, nav_elevation, -0.5),
        (center_x + 0.5, nav_elevation, -0.5),
        (center_x + 0.5, nav_elevation, 0.5),
        (center_x - 0.5, nav_elevation, 0.5),
    ]


class NativeStructureTopologyTests(unittest.TestCase):
    def test_verified_transition_includes_split_component(self) -> None:
        polygons = [square(0), square(4)]
        adjacency = [set(), set()]

        apply_transitions(
            polygons,
            adjacency,
            [((0, 0, 0), (4, 0, 0))],
            0.1,
        )

        self.assertEqual(
            selected_indices(polygons, adjacency, [(0, 0)], 0),
            [0, 1],
        )

    def test_blocked_link_is_removed_before_component_selection(self) -> None:
        polygons = [square(0), square(2), square(4)]
        adjacency = [{1}, {0, 2}, {1}]

        remove_blocked_links(
            polygons,
            adjacency,
            [((2, 0, 0), (4, 0, 0))],
            0.1,
        )

        self.assertEqual(
            selected_indices(polygons, adjacency, [(0, 0)], 0),
            [0, 1],
        )

    def test_component_inventory_exposes_unselected_component(self) -> None:
        polygons = [square(0), square(2), square(8, 6)]
        adjacency = [{1}, {0}, set()]

        inventory = component_inventory(
            polygons,
            adjacency,
            selected={0, 1},
            excluded=set(),
        )

        self.assertEqual(
            [component["classification"] for component in inventory],
            ["selected", "unresolved"],
        )
        self.assertEqual(inventory[1]["polygons"], 1)
        self.assertEqual(
            inventory[1]["live_z_equivalent"],
            {"minimum": -6, "maximum": -6},
        )


if __name__ == "__main__":
    unittest.main()
