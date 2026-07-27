"""Build dark-tactical map layers from calibrated vanilla-derived masks.

The source alpha coordinates are preserved. Styling adds only a centered
one-pixel halo, so the original navigation line remains the precision anchor.
Static landmark symbols can be split from the ordinary label layer with
explicit source-pixel rectangles.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


Box = tuple[int, int, int, int]


def parse_box(value: str) -> Box:
    parts = tuple(int(part.strip()) for part in value.split(","))
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("box must be left,top,right,bottom")
    return parts


def boosted_alpha(alpha: Image.Image, multiplier: float, floor: int) -> Image.Image:
    return alpha.point(
        lambda value: 0
        if value == 0
        else min(255, max(floor, int((value * multiplier) + 0.5)))
    )


def styled_layer(
    alpha: Image.Image,
    core_color: tuple[int, int, int],
    halo_color: tuple[int, int, int],
    alpha_multiplier: float,
    alpha_floor: int,
    halo_strength: float,
) -> Image.Image:
    core_alpha = boosted_alpha(alpha, alpha_multiplier, alpha_floor)
    dilated = alpha.filter(ImageFilter.MaxFilter(3))
    halo_alpha = ImageChops.subtract(dilated, alpha).point(
        lambda value: min(255, int((value * halo_strength) + 0.5))
    )

    output = Image.new("RGBA", alpha.size, halo_color + (0,))
    output.putalpha(halo_alpha)
    core = Image.new("RGBA", alpha.size, core_color + (0,))
    core.putalpha(core_alpha)
    return Image.alpha_composite(output, core)


def split_landmarks(label_alpha: Image.Image, boxes: list[Box]) -> tuple[Image.Image, Image.Image]:
    selection = Image.new("L", label_alpha.size, 0)
    draw = ImageDraw.Draw(selection)
    for left, top, right, bottom in boxes:
        draw.rectangle((left, top, right - 1, bottom - 1), fill=255)

    landmarks = ImageChops.multiply(label_alpha, selection)
    labels = ImageChops.subtract(label_alpha, landmarks)
    return labels, landmarks


def save(layer: Image.Image, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    layer.save(destination, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("structure_source", type=Path)
    parser.add_argument("labels_source", type=Path)
    parser.add_argument("structure_destination", type=Path)
    parser.add_argument("labels_destination", type=Path)
    parser.add_argument("landmarks_destination", type=Path)
    parser.add_argument("--landmark-box", action="append", default=[], type=parse_box)
    arguments = parser.parse_args()

    structure_source = Image.open(arguments.structure_source).convert("RGBA")
    labels_source = Image.open(arguments.labels_source).convert("RGBA")
    if structure_source.size != labels_source.size:
        raise ValueError("structure and label sources must have identical dimensions")

    label_alpha, landmark_alpha = split_landmarks(
        labels_source.getchannel("A"),
        arguments.landmark_box,
    )
    structure = styled_layer(
        structure_source.getchannel("A"),
        core_color=(82, 151, 158),
        halo_color=(2, 13, 18),
        alpha_multiplier=1.75,
        alpha_floor=92,
        halo_strength=0.72,
    )
    labels = styled_layer(
        label_alpha,
        core_color=(213, 184, 126),
        halo_color=(2, 10, 14),
        alpha_multiplier=1.85,
        alpha_floor=112,
        halo_strength=0.90,
    )
    landmarks = styled_layer(
        landmark_alpha,
        core_color=(242, 166, 61),
        halo_color=(3, 9, 12),
        alpha_multiplier=2.10,
        alpha_floor=150,
        halo_strength=1.00,
    )

    save(structure, arguments.structure_destination)
    save(labels, arguments.labels_destination)
    save(landmarks, arguments.landmarks_destination)


if __name__ == "__main__":
    main()
