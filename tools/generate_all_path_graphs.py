"""Regenerate every authored AshitaMinimap path graph."""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
GENERATOR = REPOSITORY_ROOT / "tools" / "generate_path_graph.py"


@dataclass(frozen=True)
class GraphJob:
    navmesh: str
    output: str
    arguments: tuple[str, ...]


JOBS = (
    GraphJob("South_Gustaberg.nav", "107.lua", ("--zone-id", "107")),
    GraphJob(
        "Davoi.nav",
        "149.lua",
        (
            "--zone-id",
            "149",
            "--page-id",
            "0",
            "--seed=143.908,-96.742",
        ),
    ),
    GraphJob(
        "Kuftal_Tunnel.nav",
        "174_01.lua",
        (
            "--zone-id",
            "174",
            "--page-id",
            "1",
            "--mask",
            "assets/maps/174_01_main_structure.png",
            "--mask",
            "assets/maps/174_01_lower_structure.png",
            "--origin-x",
            "272",
            "--origin-y",
            "96",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "Kuftal_Tunnel.nav",
        "174_02.lua",
        (
            "--zone-id",
            "174",
            "--page-id",
            "2",
            "--mask",
            "assets/maps/174_02_main_structure.png",
            "--mask",
            "assets/maps/174_02_lower_structure.png",
            "--mask",
            "assets/maps/174_02_upper_structure.png",
            "--origin-x",
            "208",
            "--origin-y",
            "304",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "Kuftal_Tunnel.nav",
        "174_15.lua",
        (
            "--zone-id",
            "174",
            "--page-id",
            "15",
            "--mask",
            "assets/maps/174_15_main_structure.png",
            "--mask",
            "assets/maps/174_15_lower_structure.png",
            "--mask",
            "assets/maps/174_15_upper_structure.png",
            "--origin-x",
            "176",
            "--origin-y",
            "160",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "Kuftal_Tunnel.nav",
        "174_16.lua",
        (
            "--zone-id",
            "174",
            "--page-id",
            "16",
            "--mask",
            "assets/maps/174_16_main_structure.png",
            "--mask",
            "assets/maps/174_16_left_lower_structure.png",
            "--mask",
            "assets/maps/174_16_right_lower_structure.png",
            "--mask",
            "assets/maps/174_16_upper_structure.png",
            "--origin-x",
            "216",
            "--origin-y",
            "304",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "Garlaige_Citadel.nav",
        "200_01.lua",
        (
            "--zone-id",
            "200",
            "--page-id",
            "1",
            "--minimum-elevation",
            "-1",
            "--maximum-elevation",
            "8",
            "--mask",
            "assets/maps/200_01_structure.png",
            "--origin-x",
            "368",
            "--origin-y",
            "368",
            "--pixels-per-yalm",
            "0.4",
        ),
    ),
    GraphJob(
        "Garlaige_Citadel.nav",
        "200_16.lua",
        (
            "--zone-id",
            "200",
            "--page-id",
            "16",
            "--minimum-elevation",
            "-21",
            "--maximum-elevation",
            "-14",
            "--mask",
            "assets/maps/200_16_structure.png",
            "--origin-x",
            "352",
            "--origin-y",
            "336",
            "--pixels-per-yalm",
            "0.4",
        ),
    ),
    GraphJob("Port_Bastok.nav", "236.lua", ("--zone-id", "236")),
    GraphJob("Metalworks.nav", "237.lua", ("--zone-id", "237")),
    GraphJob(
        "Windurst_Woods.nav",
        "241.lua",
        (
            "--zone-id",
            "241",
            "--seed=15,0",
            "--mask",
            "assets/maps/241_structure.png",
            "--origin-x",
            "254.5",
            "--origin-y",
            "288",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "RuLude_Gardens.nav",
        "243.lua",
        (
            "--zone-id",
            "243",
            "--seed=0,0",
            "--seed=51.480,-32.704",
            "--seed=49.5,-41.5",
            "--seed=44.204,-68.997",
            "--mask",
            "assets/maps/243_structure.png",
            "--mask",
            "assets/maps/243_stairs_structure.png",
            "--mask",
            "assets/maps/243_upper_structure.png",
            "--origin-x",
            "255",
            "--origin-y",
            "256",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "Upper_Jeuno.nav",
        "244.lua",
        (
            "--zone-id",
            "244",
            "--seed=0,0",
            "--seed=-57,89.5",
            "--mask",
            "assets/maps/244_structure.png",
            "--mask",
            "assets/maps/244_stables_structure.png",
            "--origin-x",
            "272",
            "--origin-y",
            "304",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "Lower_Jeuno.nav",
        "245.lua",
        (
            "--zone-id",
            "245",
            "--seed=-5.094,1.005",
            "--seed=66.990,128.422",
            "--seed=-24.010,-36.328",
            "--seed=-44.510,-75.162",
            "--seed=-62.677,-111.328",
            "--seed=-82.135,-150.328",
            "--seed=-101.844,-184.662",
            "--mask",
            "assets/maps/245_structure.png",
            "--origin-x",
            "255",
            "--origin-y",
            "256",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
    GraphJob(
        "Port_Jeuno.nav",
        "246.lua",
        (
            "--zone-id",
            "246",
            "--seed=-1.281,2.167",
            "--seed=-148.948,-1.833",
            "--seed=-77.948,119.500",
            "--seed=-4.031,119.333",
            "--seed=-79.198,-117.000",
            "--seed=-6.031,-119.333",
            "--mask",
            "assets/maps/246_structure.png",
            "--origin-x",
            "255",
            "--origin-y",
            "256",
            "--pixels-per-yalm",
            "0.8",
        ),
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("navmesh_root", type=Path)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=REPOSITORY_ROOT / "assets" / "paths",
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_args()
    arguments.output_root.mkdir(parents=True, exist_ok=True)
    for job in JOBS:
        navmesh = arguments.navmesh_root / job.navmesh
        output = arguments.output_root / job.output
        command = [
            sys.executable,
            str(GENERATOR),
            str(navmesh),
            str(output),
            *job.arguments,
        ]
        subprocess.run(command, cwd=REPOSITORY_ROOT, check=True)


if __name__ == "__main__":
    main()
