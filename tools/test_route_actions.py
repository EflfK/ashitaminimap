from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_path_graph import (
    parse_route_action,
    resolve_route_actions,
    write_graph,
)
from validate_path_graphs import validate


class RouteActionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.polygons = [
            [(0.0, 0.0, 0.0), (3.0, 0.0, 0.0), (0.0, 0.0, 3.0)],
            [(6.0, 0.0, 0.0), (9.0, 0.0, 0.0), (6.0, 0.0, 3.0)],
        ]
        self.adjacency = [{1}, {0}]

    def test_direction_specific_actions_are_generated_and_validated(self) -> None:
        forward = parse_route_action(
            "1,-1,0:7,-1,0|Use the portal.|Portal"
        )
        reverse = parse_route_action(
            "7,-1,0:1,-1,0|Trade one key to the portal.|Locked portal"
        )
        actions = resolve_route_actions(
            self.polygons,
            self.adjacency,
            [forward, reverse],
            2.0,
        )

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "graph.lua"
            write_graph(
                output,
                999,
                None,
                24.0,
                self.polygons,
                self.adjacency,
                [0, 1],
                set(),
                actions,
            )
            text = output.read_text(encoding="utf-8")
            self.assertIn("instruction = 'Use the portal.'", text)
            self.assertIn("instruction = 'Trade one key to the portal.'", text)
            self.assertEqual(validate(output), (2, 1))

    def test_action_cannot_invent_a_missing_edge(self) -> None:
        action = parse_route_action("1,-1,0:7,-1,0|Open the door.|Door")
        with self.assertRaisesRegex(ValueError, "existing directed graph edge"):
            resolve_route_actions(
                self.polygons,
                [set(), set()],
                [action],
                2.0,
            )


if __name__ == "__main__":
    unittest.main()
