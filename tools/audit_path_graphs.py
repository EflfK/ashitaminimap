"""Primary routing audit for display-only graphs against native Detour topology."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import tempfile
from collections import defaultdict, deque
from dataclasses import asdict, dataclass
from pathlib import Path

from generate_all_path_graphs import JOBS, REPOSITORY_ROOT
from validate_path_graphs import parse_graph


GENERATOR = REPOSITORY_ROOT / "tools" / "generate_path_graph.py"


@dataclass
class GraphMetrics:
    nodes: int
    edges: int
    components: int
    largest_component: int
    isolated_nodes: int
    long_edges: int
    steep_edges: int
    overlapping_floor_pairs: int
    nearby_component_pairs: int


@dataclass
class AuditResult:
    output: str
    zone_id: int
    page_id: int | None
    navmesh: str
    status: str
    production: GraphMetrics | None
    native: GraphMetrics | None
    inferred: GraphMetrics | None
    production_matches_native: bool
    native_only_nodes: int
    production_only_nodes: int
    native_only_edges: int
    production_only_edges: int
    native_vs_inferred_edge_delta: int
    candidate_transitions: list[dict]
    error: str | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("navmesh_root", type=Path)
    parser.add_argument(
        "--output",
        action="append",
        default=[],
        help="audit only this graph filename; repeat as needed",
    )
    parser.add_argument("--json-report", type=Path)
    parser.add_argument("--markdown-report", type=Path)
    parser.add_argument("--long-edge", type=float, default=24.0)
    parser.add_argument("--steep-edge", type=float, default=4.0)
    parser.add_argument("--candidate-radius", type=float, default=12.0)
    return parser.parse_args()


def graph_data(path: Path) -> tuple[int, int | None, list[tuple]]:
    zone_id, page_id, _, nodes = parse_graph(path)
    return zone_id, page_id, nodes


def node_key(node: tuple) -> tuple[float, float, float]:
    return tuple(round(value, 3) for value in node[:3])


def graph_sets(nodes: list[tuple]) -> tuple[set, set]:
    node_keys = {node_key(node) for node in nodes}
    edges = set()
    for index, node in enumerate(nodes, start=1):
        left = node_key(node)
        for neighbor in node[3]:
            if neighbor > index:
                edges.add(tuple(sorted((left, node_key(nodes[neighbor - 1])))))
    return node_keys, edges


def components(nodes: list[tuple]) -> tuple[list[int], list[list[int]]]:
    component_of = [-1] * len(nodes)
    groups = []
    for start in range(len(nodes)):
        if component_of[start] >= 0:
            continue
        component_id = len(groups)
        pending = deque([start])
        component_of[start] = component_id
        members = []
        while pending:
            current = pending.popleft()
            members.append(current)
            for neighbor in nodes[current][3]:
                target = neighbor - 1
                if component_of[target] < 0:
                    component_of[target] = component_id
                    pending.append(target)
        groups.append(members)
    return component_of, groups


def nearby_pairs(
    nodes: list[tuple],
    component_of: list[int],
    groups: list[list[int]],
    radius: float,
) -> tuple[int, int, list[dict]]:
    buckets: dict[tuple[int, int], list[int]] = defaultdict(list)
    for index, node in enumerate(nodes):
        buckets[
            (math.floor(node[0] / radius), math.floor(node[1] / radius))
        ].append(index)
    overlap_count = 0
    candidates_by_components: dict[tuple[int, int], dict] = {}
    for index, node in enumerate(nodes):
        bucket_x = math.floor(node[0] / radius)
        bucket_y = math.floor(node[1] / radius)
        for offset_x in (-1, 0, 1):
            for offset_y in (-1, 0, 1):
                for other_index in buckets.get(
                    (bucket_x + offset_x, bucket_y + offset_y), ()
                ):
                    if other_index <= index:
                        continue
                    other = nodes[other_index]
                    planar = math.hypot(node[0] - other[0], node[1] - other[1])
                    elevation = abs(node[2] - other[2])
                    if planar <= 1.5 and elevation > 4:
                        overlap_count += 1
                    left_component = component_of[index]
                    right_component = component_of[other_index]
                    if (
                        left_component != right_component
                        and len(groups[left_component]) >= 5
                        and len(groups[right_component]) >= 5
                        and planar > 1.5
                        and planar <= radius
                        and 2 < elevation <= 12
                    ):
                        component_pair = tuple(
                            sorted((left_component, right_component))
                        )
                        candidate = {
                            "left": index + 1,
                            "right": other_index + 1,
                            "left_component_size": len(groups[left_component]),
                            "right_component_size": len(groups[right_component]),
                            "planar": round(planar, 3),
                            "elevation": round(elevation, 3),
                            "left_xyz": [round(value, 3) for value in node[:3]],
                            "right_xyz": [
                                round(value, 3) for value in other[:3]
                            ],
                        }
                        previous = candidates_by_components.get(component_pair)
                        score = (planar, elevation)
                        if previous is None or score < (
                            previous["planar"],
                            previous["elevation"],
                        ):
                            candidates_by_components[component_pair] = candidate
    candidates = list(candidates_by_components.values())
    candidates.sort(key=lambda item: (item["planar"], item["elevation"]))
    return overlap_count, len(candidates), candidates[:10]


def metrics(
    nodes: list[tuple],
    long_edge: float,
    steep_edge: float,
    candidate_radius: float,
) -> tuple[GraphMetrics, list[dict]]:
    component_of, groups = components(nodes)
    edges = 0
    long_edges = 0
    steep_edges = 0
    for index, node in enumerate(nodes, start=1):
        for neighbor in node[3]:
            if neighbor <= index:
                continue
            edges += 1
            other = nodes[neighbor - 1]
            planar = math.hypot(node[0] - other[0], node[1] - other[1])
            elevation = abs(node[2] - other[2])
            length = math.hypot(planar, elevation)
            long_edges += length > long_edge
            steep_edges += elevation > steep_edge
    overlaps, candidates, candidate_items = nearby_pairs(
        nodes, component_of, groups, candidate_radius
    )
    sizes = [len(group) for group in groups]
    return (
        GraphMetrics(
            nodes=len(nodes),
            edges=edges,
            components=len(groups),
            largest_component=max(sizes, default=0),
            isolated_nodes=sum(size == 1 for size in sizes),
            long_edges=long_edges,
            steep_edges=steep_edges,
            overlapping_floor_pairs=overlaps,
            nearby_component_pairs=candidates,
        ),
        candidate_items,
    )


def generate(
    job,
    navmesh_root: Path,
    destination: Path,
    adjacency_mode: str,
) -> None:
    command = [
        sys.executable,
        str(GENERATOR),
        str(navmesh_root / job.navmesh),
        str(destination),
        *job.arguments,
        "--adjacency-mode",
        adjacency_mode,
    ]
    result = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())


def audit_job(job, args: argparse.Namespace, temporary: Path) -> AuditResult:
    production_path = REPOSITORY_ROOT / "assets" / "paths" / job.output
    navmesh_path = args.navmesh_root / job.navmesh
    if not production_path.exists():
        raise FileNotFoundError(f"missing production graph {production_path}")
    if not navmesh_path.exists():
        raise FileNotFoundError(f"missing navmesh {navmesh_path}")
    native_path = temporary / f"{job.output}.native.lua"
    inferred_path = temporary / f"{job.output}.inferred.lua"
    generate(job, args.navmesh_root, native_path, "native")
    generate(job, args.navmesh_root, inferred_path, "inferred")

    zone_id, page_id, production_nodes = graph_data(production_path)
    _, _, native_nodes = graph_data(native_path)
    _, _, inferred_nodes = graph_data(inferred_path)
    production_metrics, production_candidates = metrics(
        production_nodes,
        args.long_edge,
        args.steep_edge,
        args.candidate_radius,
    )
    native_metrics, native_candidates = metrics(
        native_nodes,
        args.long_edge,
        args.steep_edge,
        args.candidate_radius,
    )
    inferred_metrics, _ = metrics(
        inferred_nodes,
        args.long_edge,
        args.steep_edge,
        args.candidate_radius,
    )
    production_node_set, production_edges = graph_sets(production_nodes)
    native_node_set, native_edges = graph_sets(native_nodes)
    _, inferred_edges = graph_sets(inferred_nodes)
    matches = production_path.read_bytes() == native_path.read_bytes()
    status = "ok"
    if not matches:
        status = "production-differs"
    return AuditResult(
        output=job.output,
        zone_id=zone_id,
        page_id=page_id,
        navmesh=job.navmesh,
        status=status,
        production=production_metrics,
        native=native_metrics,
        inferred=inferred_metrics,
        production_matches_native=matches,
        native_only_nodes=len(native_node_set - production_node_set),
        production_only_nodes=len(production_node_set - native_node_set),
        native_only_edges=len(native_edges - production_edges),
        production_only_edges=len(production_edges - native_edges),
        native_vs_inferred_edge_delta=len(native_edges ^ inferred_edges),
        candidate_transitions=production_candidates or native_candidates,
    )


def markdown(results: list[AuditResult]) -> str:
    lines = [
        "# Path graph audit",
        "",
        "This is the routing-first production audit. It does not require or "
        "validate a visible structure layer.",
        "",
        "Generated by `tools/audit_path_graphs.py`. Native topology uses "
        "`dtPoly.neis` for internal neighbors and geometric matching only for "
        "edges Detour marks as external tile portals.",
        "",
        "| Graph | Status | Nodes | Edges | Components | Native diff | "
        "Inferred edge delta | Candidate component pairs |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for result in results:
        metrics_value = result.production
        native_diff = result.native_only_edges + result.production_only_edges
        lines.append(
            f"| `{result.output}` | {result.status} | "
            f"{metrics_value.nodes if metrics_value else '-'} | "
            f"{metrics_value.edges if metrics_value else '-'} | "
            f"{metrics_value.components if metrics_value else '-'} | "
            f"{native_diff} | {result.native_vs_inferred_edge_delta} | "
            f"{metrics_value.nearby_component_pairs if metrics_value else '-'} |"
        )
    findings = [result for result in results if result.status != "ok"]
    if findings:
        lines.extend(("", "## Findings", ""))
    for result in findings:
        lines.append(f"### `{result.output}`")
        lines.append("")
        if result.error:
            lines.append(f"- Error: {result.error}")
        else:
            if not result.production_matches_native:
                lines.append(
                    "- Production/native edge differences: "
                    f"{result.production_only_edges} production-only, "
                    f"{result.native_only_edges} native-only."
                )
            lines.append(
                "- Native versus inferred edge delta: "
                f"{result.native_vs_inferred_edge_delta}."
            )
        lines.append("")
    advisories = [
        result for result in results if result.candidate_transitions
    ]
    if advisories:
        lines.extend(
            (
                "",
                "## Disconnected-component advisories",
                "",
                "These are the closest elevated node pair for each pair of "
                "substantial disconnected components. Resolve every advisory "
                "that could affect a supported destination or normal route. "
                "They are review leads, not automatically safe transitions.",
                "",
            )
        )
    for result in advisories:
        lines.append(f"### `{result.output}`")
        lines.append("")
        for candidate in result.candidate_transitions[:5]:
            lines.append(
                "- "
                f"nodes {candidate['left']} and {candidate['right']} "
                f"(components {candidate['left_component_size']} / "
                f"{candidate['right_component_size']} nodes): "
                f"{candidate['planar']:.3f}y planar, "
                f"{candidate['elevation']:.3f}y elevation."
            )
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    selected = set(args.output)
    jobs = [job for job in JOBS if not selected or job.output in selected]
    results = []
    with tempfile.TemporaryDirectory(prefix="ashitaminimap-path-audit-") as folder:
        temporary = Path(folder)
        for job in jobs:
            try:
                result = audit_job(job, args, temporary)
            except Exception as exception:
                production_path = (
                    REPOSITORY_ROOT / "assets" / "paths" / job.output
                )
                zone_id = 0
                page_id = None
                production_metrics = None
                if production_path.exists():
                    zone_id, page_id, nodes = graph_data(production_path)
                    production_metrics, _ = metrics(
                        nodes,
                        args.long_edge,
                        args.steep_edge,
                        args.candidate_radius,
                    )
                result = AuditResult(
                    output=job.output,
                    zone_id=zone_id,
                    page_id=page_id,
                    navmesh=job.navmesh,
                    status="error",
                    production=production_metrics,
                    native=None,
                    inferred=None,
                    production_matches_native=False,
                    native_only_nodes=0,
                    production_only_nodes=0,
                    native_only_edges=0,
                    production_only_edges=0,
                    native_vs_inferred_edge_delta=0,
                    candidate_transitions=[],
                    error=str(exception),
                )
            results.append(result)
            print(f"{result.output}: {result.status}")
    json_text = json.dumps(
        [asdict(result) for result in results],
        indent=2,
        sort_keys=True,
    ) + "\n"
    markdown_text = markdown(results)
    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        args.json_report.write_text(json_text, encoding="utf-8", newline="\n")
    if args.markdown_report:
        args.markdown_report.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_report.write_text(
            markdown_text, encoding="utf-8", newline="\n"
        )
    if not args.json_report and not args.markdown_report:
        print(markdown_text)
    if any(result.status != "ok" for result in results):
        raise SystemExit(1)


if __name__ == "__main__":
    args = parse_args()
    main()
