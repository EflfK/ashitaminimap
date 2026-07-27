"""Split transparent tactical linework into structure and annotation layers.

Label glyphs are selected as small connected alpha components inside explicit
label regions. Long leader lines and large structural outlines remain in the
structure layer. Explicit annotation regions can move whole symbols, such as
home-point icons, to the label layer.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


Box = tuple[int, int, int, int]


def parse_box(value: str) -> Box:
    parts = tuple(int(part.strip()) for part in value.split(","))
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("box must be left,top,right,bottom")
    return parts


def pixels_in_box(box: Box, width: int, height: int):
    left, top, right, bottom = box
    for y in range(max(0, top), min(height, bottom)):
        for x in range(max(0, left), min(width, right)):
            yield x, y


def connected_components(alpha: Image.Image, box: Box) -> list[list[tuple[int, int]]]:
    width, height = alpha.size
    alpha_pixels = alpha.load()
    candidates = {
        (x, y)
        for x, y in pixels_in_box(box, width, height)
        if alpha_pixels[x, y] > 0
    }
    components: list[list[tuple[int, int]]] = []

    while candidates:
        start = candidates.pop()
        queue = deque([start])
        component = [start]
        while queue:
            x, y = queue.popleft()
            for offset_y in (-1, 0, 1):
                for offset_x in (-1, 0, 1):
                    if offset_x == 0 and offset_y == 0:
                        continue
                    neighbor = (x + offset_x, y + offset_y)
                    if neighbor in candidates:
                        candidates.remove(neighbor)
                        queue.append(neighbor)
                        component.append(neighbor)
        components.append(component)

    return components


def component_size(component: list[tuple[int, int]]) -> tuple[int, int]:
    xs = [point[0] for point in component]
    ys = [point[1] for point in component]
    return max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("structure_destination", type=Path)
    parser.add_argument("labels_destination", type=Path)
    parser.add_argument("--structure-box", required=True, type=parse_box)
    parser.add_argument("--label-box", action="append", default=[], type=parse_box)
    parser.add_argument("--annotation-box", action="append", default=[], type=parse_box)
    parser.add_argument("--glyph-max-width", type=int, default=24)
    parser.add_argument("--glyph-max-height", type=int, default=18)
    parser.add_argument("--glyph-max-pixels", type=int, default=180)
    arguments = parser.parse_args()

    source = Image.open(arguments.source).convert("RGBA")
    alpha = source.getchannel("A")
    width, height = source.size
    source_pixels = source.load()

    label_points: set[tuple[int, int]] = set()
    for box in arguments.label_box:
        for component in connected_components(alpha, box):
            component_width, component_height = component_size(component)
            if (
                component_width <= arguments.glyph_max_width
                and component_height <= arguments.glyph_max_height
                and len(component) <= arguments.glyph_max_pixels
            ):
                label_points.update(component)

    for box in arguments.annotation_box:
        label_points.update(
            (x, y)
            for x, y in pixels_in_box(box, width, height)
            if source_pixels[x, y][3] > 0
        )

    structure = Image.new("RGBA", source.size, (0, 0, 0, 0))
    labels = Image.new("RGBA", source.size, (0, 0, 0, 0))
    structure_pixels = structure.load()
    label_pixels = labels.load()
    structure_points = set(pixels_in_box(arguments.structure_box, width, height))

    for y in range(height):
        for x in range(width):
            pixel = source_pixels[x, y]
            if pixel[3] <= 0:
                continue
            if (x, y) in label_points:
                label_pixels[x, y] = pixel
            elif (x, y) in structure_points:
                structure_pixels[x, y] = pixel

    arguments.structure_destination.parent.mkdir(parents=True, exist_ok=True)
    arguments.labels_destination.parent.mkdir(parents=True, exist_ok=True)
    structure.save(arguments.structure_destination, "PNG", optimize=True)
    labels.save(arguments.labels_destination, "PNG", optimize=True)


if __name__ == "__main__":
    main()
