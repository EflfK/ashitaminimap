"""Regenerate and audit every navmesh-authored structure selector."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
GENERATOR = ROOT / "tools" / "generate_walkable_map.py"
OBJ_COMMIT = "694970ce54a4fb53b69db52b8375c605686bc350"
NAVMESH_COMMIT = "d5de48de84868bde744e4864768a611e5aad82b0"


@dataclass(frozen=True)
class StructureJob:
    navmesh: str
    obj: str
    output: str
    arguments: tuple[str, ...]
    compare_production: bool = True


def job(
    navmesh: str,
    output: str,
    *arguments: str,
    compare_production: bool = True,
) -> StructureJob:
    return StructureJob(
        navmesh=navmesh,
        obj=navmesh.replace(".nav", ".obj"),
        output=output,
        arguments=arguments,
        compare_production=compare_production,
    )


JOBS = (
    job(
        "Kuftal_Tunnel.nav",
        "174_01_main_structure.png",
        "--origin-x=272",
        "--origin-y=96",
        "--pixels-per-yalm=0.8",
        "--maximum-elevation=15",
        "--seam-closure-radius=1.25",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_01_lower_structure.png",
        "--origin-x=272",
        "--origin-y=96",
        "--pixels-per-yalm=0.8",
        "--minimum-elevation=15",
        "--seam-closure-radius=1.25",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_02_main_structure.png",
        "--origin-x=208",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--minimum-elevation=-6",
        "--maximum-elevation=6",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_02_upper_structure.png",
        "--origin-x=208",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--maximum-elevation=-6",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_02_lower_structure.png",
        "--origin-x=208",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--minimum-elevation=6",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_15_main_structure.png",
        "--origin-x=176",
        "--origin-y=160",
        "--pixels-per-yalm=0.8",
        "--seed=126.245,-50.1",
        "--maximum-elevation=-17",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_15_upper_structure.png",
        "--origin-x=176",
        "--origin-y=160",
        "--pixels-per-yalm=0.8",
        "--seed=40.112,-186.667",
        "--maximum-elevation=-25",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_15_lower_structure.png",
        "--origin-x=176",
        "--origin-y=160",
        "--pixels-per-yalm=0.8",
        "--seed=64.112,14.083",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_16_main_structure.png",
        "--origin-x=216",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--seed=36.528,140.083",
        "--minimum-elevation=-25",
        "--maximum-elevation=-15",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_16_upper_structure.png",
        "--origin-x=216",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--seed=56.112,135",
        "--maximum-elevation=-25",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_16_left_lower_structure.png",
        "--origin-x=216",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--seed=-49.43,101",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
        compare_production=False,
    ),
    job(
        "Kuftal_Tunnel.nav",
        "174_16_right_lower_structure.png",
        "--origin-x=216",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--seed=179.695,112",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
        compare_production=False,
    ),
    job(
        "Garlaige_Citadel.nav",
        "200_01_structure.png",
        "--origin-x=368",
        "--origin-y=368",
        "--pixels-per-yalm=0.4",
        "--minimum-elevation=-1",
        "--maximum-elevation=8",
        "--exclude-box=0,0,212,512",
        "--exclude-box=290,0,512,512",
        "--exclude-box=0,0,512,212",
        "--exclude-box=0,298,512,512",
    ),
    job(
        "Garlaige_Citadel.nav",
        "200_16_structure.png",
        "--origin-x=352",
        "--origin-y=336",
        "--pixels-per-yalm=0.4",
        "--minimum-elevation=-21",
        "--maximum-elevation=-14",
    ),
    job(
        "Windurst_Woods.nav",
        "241_structure.png",
        "--origin-x=254.5",
        "--origin-y=288",
        "--pixels-per-yalm=0.8",
        "--seed=15,0",
        "--exclude-box=146,360,207,371",
    ),
    job(
        "RuLude_Gardens.nav",
        "243_structure.png",
        "--origin-x=255",
        "--origin-y=256",
        "--pixels-per-yalm=0.8",
        "--seed=0,0",
        "--blocked-link=3.962,-63.008,8.755:3.962,-67.008,8.755",
    ),
    job(
        "RuLude_Gardens.nav",
        "243_stairs_structure.png",
        "--origin-x=255",
        "--origin-y=256",
        "--pixels-per-yalm=0.8",
        "--seed=51.480,-32.704",
        "--seed=49.5,-41.5",
        "--transition=49.462,-33.508,3.155:49.462,-41.508,6.155",
        "--blocked-link=3.962,-63.008,8.755:3.962,-67.008,8.755",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
    ),
    job(
        "RuLude_Gardens.nav",
        "243_upper_structure.png",
        "--origin-x=255",
        "--origin-y=256",
        "--pixels-per-yalm=0.8",
        "--seed=44.204,-68.997",
        "--blocked-link=3.962,-63.008,8.755:3.962,-67.008,8.755",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
    ),
    job(
        "Upper_Jeuno.nav",
        "244_structure.png",
        "--origin-x=272",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--seed=0,0",
    ),
    job(
        "Upper_Jeuno.nav",
        "244_stables_structure.png",
        "--origin-x=272",
        "--origin-y=304",
        "--pixels-per-yalm=0.8",
        "--seed=-57,89.5",
        "--fill-rgb=42,30,66",
        "--edge-rgb=181,132,255",
    ),
    job(
        "Lower_Jeuno.nav",
        "245_structure.png",
        "--origin-x=255",
        "--origin-y=256",
        "--pixels-per-yalm=0.8",
        "--seed=-5.094,1.005",
        "--seed=66.990,128.422",
        "--seed=-24.010,-36.328",
        "--seed=-44.510,-75.162",
        "--seed=-62.677,-111.328",
        "--seed=-82.135,-150.328",
        "--seed=-101.844,-184.662",
    ),
    job(
        "Port_Jeuno.nav",
        "246_structure.png",
        "--origin-x=255",
        "--origin-y=256",
        "--pixels-per-yalm=0.8",
        "--seed=-1.281,2.167",
        "--seed=-148.948,-1.833",
        "--seed=-77.948,119.500",
        "--seed=-4.031,119.333",
        "--seed=-79.198,-117.000",
        "--seed=-6.031,-119.333",
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("obj_root", type=Path)
    parser.add_argument("navmesh_root", type=Path)
    parser.add_argument(
        "--report-root",
        type=Path,
        default=ROOT / "assets" / "maps" / "component-reports",
    )
    parser.add_argument("--markdown-report", type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def generate(
    job_value: StructureJob,
    args: argparse.Namespace,
    output: Path,
    report: Path,
    mode: str,
) -> None:
    command = [
        sys.executable,
        str(GENERATOR),
        str(args.obj_root / job_value.obj),
        str(args.navmesh_root / job_value.navmesh),
        str(output),
        *job_value.arguments,
        f"--adjacency-mode={mode}",
        f"--component-report={report}",
    ]
    result = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    report_data = json.loads(report.read_text(encoding="utf-8"))
    report_data["generation_arguments"] = list(job_value.arguments)
    report_data["sources"] = {
        "obj": {
            "commit": OBJ_COMMIT,
            "file": job_value.obj,
            "sha256": sha256(args.obj_root / job_value.obj),
        },
        "navmesh": {
            "commit": NAVMESH_COMMIT,
            "file": job_value.navmesh,
            "sha256": sha256(args.navmesh_root / job_value.navmesh),
        },
    }
    report.write_text(
        json.dumps(report_data, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def write_special_reports(args: argparse.Namespace) -> None:
    reports = {
        "237_structure.json": {
            "schema": 1,
            "asset": "237_structure.png",
            "asset_sha256": sha256(
                ROOT / "assets" / "maps" / "237_structure.png"
            ),
            "status": "legacy-rebuild-required",
            "certified": False,
            "reason": (
                "The committed Metalworks asset is a linework prototype, not "
                "a seeded navmesh-generated production structure."
            ),
            "sources": {
                "obj": {
                    "commit": OBJ_COMMIT,
                    "file": "Metalworks.obj",
                    "sha256": sha256(args.obj_root / "Metalworks.obj"),
                },
                "navmesh": {
                    "commit": NAVMESH_COMMIT,
                    "file": "Metalworks.nav",
                    "sha256": sha256(
                        args.navmesh_root / "Metalworks.nav"
                    ),
                },
            },
        },
        "174_01_transition_structure.json": {
            "schema": 1,
            "asset": "174_01_transition_structure.png",
            "asset_sha256": sha256(
                ROOT
                / "assets"
                / "maps"
                / "174_01_transition_structure.png"
            ),
            "status": "verified-derived-transition",
            "certified": True,
            "reason": (
                "This clipped stripe layer visualizes a live-verified floor "
                "transition and is not a seeded navmesh component."
            ),
        },
    }
    for name, data in reports.items():
        (args.report_root / name).write_text(
            json.dumps(data, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )


def main() -> None:
    results = []
    args.report_root.mkdir(parents=True, exist_ok=True)
    write_special_reports(args)
    with tempfile.TemporaryDirectory(
        prefix="ashitaminimap-structure-audit-"
    ) as folder:
        temporary = Path(folder)
        for job_value in JOBS:
            native_output = temporary / f"native-{job_value.output}"
            inferred_output = temporary / f"inferred-{job_value.output}"
            native_report = args.report_root / (
                Path(job_value.output).stem + ".json"
            )
            inferred_report = temporary / (
                Path(job_value.output).stem + "-inferred.json"
            )
            try:
                generate(
                    job_value,
                    args,
                    native_output,
                    native_report,
                    "native",
                )
                generate(
                    job_value,
                    args,
                    inferred_output,
                    inferred_report,
                    "inferred",
                )
                production = ROOT / "assets" / "maps" / job_value.output
                topology_match = (
                    native_output.read_bytes() == inferred_output.read_bytes()
                )
                production_match = (
                    native_output.read_bytes() == production.read_bytes()
                    if job_value.compare_production
                    else None
                )
                native_data = json.loads(
                    native_report.read_text(encoding="utf-8")
                )
                status = "ok"
                if not topology_match:
                    status = "topology-differs"
                elif production_match is False:
                    status = "production-differs"
                results.append(
                    {
                        "output": job_value.output,
                        "status": status,
                        "production_comparison": (
                            "exact"
                            if job_value.compare_production
                            else "selector-only"
                        ),
                        "production_matches_native": production_match,
                        "native_matches_inferred": topology_match,
                        "selected_polygons": native_data[
                            "selected_polygons"
                        ],
                        "native_sha256": sha256(native_output),
                    }
                )
            except Exception as exception:
                results.append(
                    {
                        "output": job_value.output,
                        "status": "error",
                        "error": str(exception),
                    }
                )
            print(f"{job_value.output}: {results[-1]['status']}")

    lines = [
        "# Structure topology audit",
        "",
        "Native and inferred selectors are compared for every navmesh-authored "
        "structure layer. `exact` rows also reproduce and hash-check the "
        "committed PNG. Kuftal rows are selector-only because their final "
        "page clipping is recorded separately from the topology selector.",
        "",
        "| Layer | Status | Production check | Selected polygons |",
        "| --- | --- | --- | ---: |",
    ]
    for result in results:
        lines.append(
            f"| `{result['output']}` | {result['status']} | "
            f"{result.get('production_comparison', '-')} | "
            f"{result.get('selected_polygons', '-')} |"
        )
    lines.extend(
        (
            "",
            "Metalworks `237_structure.png` is a legacy linework prototype, "
            "not a navmesh-generated production structure. It remains an "
            "explicit production-rebuild item and is not certified by this "
            "audit.",
            "",
            "Kuftal's `174_01_transition_structure.png` is a clipped visual "
            "transition treatment derived from verified route evidence rather "
            "than a seeded navmesh component.",
            "",
        )
    )
    markdown = "\n".join(lines)
    if args.markdown_report:
        args.markdown_report.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_report.write_text(
            markdown,
            encoding="utf-8",
            newline="\n",
        )
    else:
        print(markdown)
    if any(result["status"] != "ok" for result in results):
        raise SystemExit(1)


if __name__ == "__main__":
    args = parse_args()
    main()
