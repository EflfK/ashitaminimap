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
        "Castle_Oztroja.nav",
        "151.lua",
        (
            "--zone-id",
            "151",
            "--seed=-221,-13,0.25",
            "--seed=7.378,-193.590,-16.293",
            "--seed=-100.197,-13.141,-72.511",
        ),
    ),
    GraphJob(
        "Middle_Delkfutts_Tower.nav",
        "157.lua",
        (
            "--zone-id",
            "157",
            "--seed=-495.262,-37.750,-128",
            "--seed=16.367,-40.372,-76.125",
        ),
    ),
    GraphJob(
        "Upper_Delkfutts_Tower.nav",
        "158.lua",
        (
            "--zone-id",
            "158",
            "--seed=-365,-36,-176.5",
            "--seed=272.758,29.514,19.024",
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
        "Lower_Delkfutts_Tower.nav",
        "184.lua",
        (
            "--zone-id",
            "184",
            "--seed=464,-51,0",
        ),
    ),
    GraphJob(
        "Inner_Horutoto_Ruins.nav",
        "192.lua",
        (
            "--zone-id",
            "192",
            "--seed=453,182.3,-8",
            "--seed=-177.956,-220.058,-0.002",
            "--seed=429.002,180,-12.992",
            "--seed=-193.007,59.969,-15.057",
            "--seed=-259.981,250.063,6.448",
            "--seed=-259.996,242.859,6.399",
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
        "Windurst_Walls.nav",
        "239.lua",
        (
            "--zone-id",
            "239",
            "--page-id",
            "0",
            "--seed=31,-40",
            "--seed=-212,-99",
            "--transition=0.128,-37.894,-5.769:2.599,-39.386,-5.234",
        ),
    ),
    GraphJob(
        "Port_Windurst.nav",
        "240.lua",
        (
            "--zone-id",
            "240",
            "--seed=-188,101,-4",
        ),
    ),
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
        "Heavens_Tower.nav",
        "242.lua",
        (
            "--zone-id",
            "242",
            "--seed=-2.127,-25.997,-45",
            "--seed=-2.557,8.598,0.5",
            "--seed=2.05,32.4,0",
            "--seed=2.319,14,-47",
            "--seed=0,44.86,-61.521",
            "--seed=3.132,0,-47",
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
            "--transition=40.212,-25.675,-0.045:49.462,-33.508,3.155",
            "--transition=49.462,-33.508,3.155:49.462,-41.508,6.155",
            "--transition=49.462,-41.508,6.155:48.379,-47.175,8.222",
            "--transition=-0.038,-11.008,2.955:-0.038,-27.508,8.355",
            "--blocked-link=3.962,-63.008,8.755:3.962,-67.008,8.755",
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
