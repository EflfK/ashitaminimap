from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAPS_PATH = ROOT / "ashitaminimap_maps.lua"
ZONE_PATTERN = re.compile(r"^    \[(\d+)\] = \{$", re.MULTILINE)
HOME_POINT_PATTERN = re.compile(
    r"\{[^{}]*kind = 'home_point'[^{}]*\}",
    re.DOTALL,
)
UNLOCK_PATTERN = re.compile(r"unlock_index = (\d+)")


def authored_home_points() -> dict[int, tuple[int, ...]]:
    text = MAPS_PATH.read_text(encoding="utf-8")
    zones = list(ZONE_PATTERN.finditer(text))
    result: dict[int, list[int]] = {}

    for marker in HOME_POINT_PATTERN.finditer(text):
        zone_matches = [zone for zone in zones if zone.start() < marker.start()]
        if not zone_matches:
            raise AssertionError("Home Point appears before a zone declaration")
        zone_id = int(zone_matches[-1].group(1))
        unlock = UNLOCK_PATTERN.search(marker.group(0))
        if unlock is None:
            raise AssertionError(f"zone {zone_id} Home Point lacks unlock_index")
        result.setdefault(zone_id, []).append(int(unlock.group(1)))

    return {zone_id: tuple(indexes) for zone_id, indexes in result.items()}


class TravelReferenceTests(unittest.TestCase):
    def test_home_point_unlock_indexes_are_globally_unique(self) -> None:
        by_zone = authored_home_points()
        owners: dict[int, int] = {}
        for zone_id, indexes in by_zone.items():
            for unlock_index in indexes:
                self.assertNotIn(
                    unlock_index,
                    owners,
                    f"unlock index {unlock_index} is assigned to both "
                    f"zones {owners.get(unlock_index)} and {zone_id}",
                )
                owners[unlock_index] = zone_id

    def test_corrected_canonical_unlock_fixtures(self) -> None:
        by_zone = authored_home_points()
        expected = {
            52: (74,),
            79: (75,),
            145: (54,),
            160: (57, 93),
            162: (58,),
            204: (55, 94),
        }
        for zone_id, indexes in expected.items():
            self.assertEqual(by_zone.get(zone_id), indexes)


if __name__ == "__main__":
    unittest.main()
