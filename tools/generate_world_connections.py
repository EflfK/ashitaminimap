#!/usr/bin/env python3
"""Generate the display-only cross-zone connection catalog.

CatsEyeXI's pinned zoneline table is authoritative for the server's destination
zone and arrival position.  Current LandSandBoat enriches the same zoneline IDs
with source coordinates decoded by xiregiondump.  A source coordinate is
published only when both catalogs agree on the source and destination zones.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import urllib.request
from dataclasses import dataclass
from pathlib import Path


CATS_COMMIT = "314deaf03465f2b24b6a1e4e73a016ca036f1084"
LSB_COMMIT = "bf838f7c4d52903d99bbb4baff9726ff2c66d797"
CATS_URL = (
    "https://raw.githubusercontent.com/CatsAndBoats/catseyexi/"
    f"{CATS_COMMIT}/sql/zonelines.sql"
)
LSB_URL = (
    "https://raw.githubusercontent.com/LandSandBoat/server/"
    f"{LSB_COMMIT}/sql/zonelines.sql"
)

CATS_PATTERN = re.compile(
    r"INSERT INTO `zonelines` VALUES "
    r"\((\d+),(\d+),(\d+),([^,]+),([^,]+),([^,]+),(\d+)\);"
)
LSB_PATTERN = re.compile(
    r"INSERT INTO `zonelines` VALUES "
    r"\((\d+),(\d+),([^,]+),([^,]+),([^,]+),(\d+),"
    r"([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^)]+)\);"
)


@dataclass(frozen=True)
class CatsLine:
    identifier: int
    from_zone: int
    to_zone: int
    to_x: float
    to_vertical: float
    to_horizontal: float
    rotation: int


@dataclass(frozen=True)
class LsbLine:
    identifier: int
    from_zone: int
    from_x: float
    from_vertical: float
    from_horizontal: float
    to_zone: int
    to_x: float
    to_vertical: float
    to_horizontal: float


def read_source(value: str) -> tuple[str, bytes]:
    path = Path(value)
    if path.is_file():
        return str(path.resolve()), path.read_bytes()
    with urllib.request.urlopen(value, timeout=30) as response:
        return value, response.read()


def parse_cats(text: str) -> dict[int, CatsLine]:
    result: dict[int, CatsLine] = {}
    for match in CATS_PATTERN.finditer(text):
        values = match.groups()
        record = CatsLine(
            identifier=int(values[0]),
            from_zone=int(values[1]),
            to_zone=int(values[2]),
            to_x=float(values[3]),
            to_vertical=float(values[4]),
            to_horizontal=float(values[5]),
            rotation=int(values[6]),
        )
        result[record.identifier] = record
    return result


def parse_lsb(text: str) -> dict[int, LsbLine]:
    result: dict[int, LsbLine] = {}
    for match in LSB_PATTERN.finditer(text):
        values = match.groups()
        record = LsbLine(
            identifier=int(values[0]),
            from_zone=int(values[1]),
            from_x=float(values[2]),
            from_vertical=float(values[3]),
            from_horizontal=float(values[4]),
            to_zone=int(values[5]),
            to_x=float(values[6]),
            to_vertical=float(values[7]),
            to_horizontal=float(values[8]),
        )
        result[record.identifier] = record
    return result


def finite(*values: float) -> bool:
    return all(math.isfinite(value) and abs(value) <= 100000 for value in values)


def lua_number(value: float) -> str:
    result = f"{value:.3f}"
    return "0.000" if result == "-0.000" else result


def build_catalog(
    cats: dict[int, CatsLine],
    lsb: dict[int, LsbLine],
) -> tuple[list[tuple[CatsLine, LsbLine]], list[dict[str, object]], dict[str, int]]:
    connections: list[tuple[CatsLine, LsbLine]] = []
    unresolved: list[dict[str, object]] = []
    arrival_mismatches = 0

    for identifier in sorted(cats):
        cats_line = cats[identifier]
        lsb_line = lsb.get(identifier)
        if lsb_line is None:
            unresolved.append(
                {
                    "id": identifier,
                    "reason": "missing_land_sand_boat_source",
                    "from_zone": cats_line.from_zone,
                    "to_zone": cats_line.to_zone,
                }
            )
            continue
        if (
            cats_line.from_zone != lsb_line.from_zone
            or cats_line.to_zone != lsb_line.to_zone
        ):
            unresolved.append(
                {
                    "id": identifier,
                    "reason": "zone_pair_mismatch",
                    "cats_from_zone": cats_line.from_zone,
                    "cats_to_zone": cats_line.to_zone,
                    "lsb_from_zone": lsb_line.from_zone,
                    "lsb_to_zone": lsb_line.to_zone,
                }
            )
            continue
        if not finite(
            lsb_line.from_x,
            lsb_line.from_vertical,
            lsb_line.from_horizontal,
            cats_line.to_x,
            cats_line.to_vertical,
            cats_line.to_horizontal,
        ):
            unresolved.append(
                {
                    "id": identifier,
                    "reason": "invalid_coordinate",
                    "from_zone": cats_line.from_zone,
                    "to_zone": cats_line.to_zone,
                }
            )
            continue
        if (
            abs(cats_line.to_x - lsb_line.to_x) > 0.01
            or abs(cats_line.to_vertical - lsb_line.to_vertical) > 0.01
            or abs(cats_line.to_horizontal - lsb_line.to_horizontal) > 0.01
        ):
            arrival_mismatches += 1
        connections.append((cats_line, lsb_line))

    for identifier in sorted(set(lsb) - set(cats)):
        lsb_line = lsb[identifier]
        unresolved.append(
            {
                "id": identifier,
                "reason": "not_present_on_catseye",
                "from_zone": lsb_line.from_zone,
                "to_zone": lsb_line.to_zone,
            }
        )

    counts = {
        "cats_records": len(cats),
        "land_sand_boat_records": len(lsb),
        "published_connections": len(connections),
        "unresolved_records": len(unresolved),
        "arrival_coordinate_mismatches_preserving_catseye": arrival_mismatches,
    }
    return connections, unresolved, counts


def render_lua(
    connections: list[tuple[CatsLine, LsbLine]],
    unresolved: list[dict[str, object]],
    counts: dict[str, int],
    cats_sha256: str,
    lsb_sha256: str,
) -> str:
    lines = [
        "-- Generated by tools/generate_world_connections.py; do not hand-edit.",
        "-- Coordinates use Ashita axes: x, horizontal y, vertical z.",
        "return {",
        "    schema = 1,",
        "    provenance = {",
        f"        cats_commit = '{CATS_COMMIT}',",
        f"        cats_sha256 = '{cats_sha256}',",
        f"        land_sand_boat_commit = '{LSB_COMMIT}',",
        f"        land_sand_boat_sha256 = '{lsb_sha256}',",
        "    },",
        "    counts = {",
    ]
    for key, value in counts.items():
        lines.append(f"        {key} = {value},")
    lines.extend(["    },", "    connections = {"])
    for cats_line, lsb_line in connections:
        lines.append(
            "        { "
            f"id = {cats_line.identifier}, "
            f"from_zone = {cats_line.from_zone}, "
            f"from_x = {lua_number(lsb_line.from_x)}, "
            f"from_y = {lua_number(lsb_line.from_horizontal)}, "
            f"from_z = {lua_number(lsb_line.from_vertical)}, "
            f"to_zone = {cats_line.to_zone}, "
            f"to_x = {lua_number(cats_line.to_x)}, "
            f"to_y = {lua_number(cats_line.to_horizontal)}, "
            f"to_z = {lua_number(cats_line.to_vertical)} "
            "},"
        )
    lines.extend(["    },", "    unresolved = {"])
    for record in unresolved:
        fields = []
        for key, value in record.items():
            if isinstance(value, str):
                fields.append(f"{key} = {value!r}")
            else:
                fields.append(f"{key} = {value}")
        lines.append(f"        {{ {', '.join(fields)} }},")
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cats-source", default=CATS_URL)
    parser.add_argument("--land-sand-boat-source", default=LSB_URL)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/world/connections.lua"),
    )
    parser.add_argument(
        "--audit-output",
        type=Path,
        default=Path("assets/world/connection_audit.json"),
    )
    args = parser.parse_args()

    cats_name, cats_bytes = read_source(args.cats_source)
    lsb_name, lsb_bytes = read_source(args.land_sand_boat_source)
    cats = parse_cats(cats_bytes.decode("utf-8-sig"))
    lsb = parse_lsb(lsb_bytes.decode("utf-8-sig"))
    if len(cats) != 844 or len(lsb) != 844:
        raise SystemExit(
            f"Unexpected source counts: CatsEyeXI={len(cats)}, "
            f"LandSandBoat={len(lsb)}"
        )

    connections, unresolved, counts = build_catalog(cats, lsb)
    if counts["published_connections"] != 820 or counts["unresolved_records"] != 25:
        raise SystemExit(f"Unexpected catalog audit counts: {counts}")

    cats_sha256 = hashlib.sha256(cats_bytes).hexdigest().upper()
    lsb_sha256 = hashlib.sha256(lsb_bytes).hexdigest().upper()
    lua = render_lua(
        connections,
        unresolved,
        counts,
        cats_sha256,
        lsb_sha256,
    )
    audit = {
        "schema": 1,
        "sources": {
            "catseye": {
                "location": cats_name,
                "commit": CATS_COMMIT,
                "sha256": cats_sha256,
            },
            "land_sand_boat": {
                "location": lsb_name,
                "commit": LSB_COMMIT,
                "sha256": lsb_sha256,
            },
        },
        "counts": counts,
        "unresolved": unresolved,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.audit_output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(lua, encoding="utf-8", newline="\n")
    args.audit_output.write_text(
        json.dumps(audit, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(
        f"Wrote {len(connections)} connections to {args.output}; "
        f"{len(unresolved)} unresolved records to {args.audit_output}."
    )


if __name__ == "__main__":
    main()
