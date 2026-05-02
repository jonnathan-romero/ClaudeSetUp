#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "coloraide>=4",
#     "matplotlib>=3.8",
# ]
# ///
"""Simulate a palette under each color-vision-deficiency type.

Renders a comparison PNG showing the original colors and their appearance under
the selected CVD types (protanopia, deuteranopia, tritanopia) using the
Machado 2009 simulation matrices that ship with coloraide.

CLI:
    uv run scripts/simulate_cvd.py --colors "#a,#b,#c" --out path.png
                                   [--types protanopia,deuteranopia,tritanopia]

Output:
    Writes a PNG to --out with the original palette plus one row per CVD type.
    Default --types is all three.

Stdout (JSON summary):
    {
      "out": "path.png",
      "types": ["protanopia", "deuteranopia", "tritanopia"],
      "input_colors": ["#...", "#...", "#..."]
    }
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
from coloraide import Color

logging.basicConfig(
    level=logging.INFO,
    stream=sys.stderr,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("simulate_cvd")

EQ_RC = {
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
    "font.family": "sans-serif",
    "font.sans-serif": ["Helvetica", "Arial", "DejaVu Sans"],
    "font.size": 10,
    "axes.titlesize": "large",
    "axes.titleweight": "normal",
    "axes.labelsize": "medium",
    "xtick.labelsize": "small",
    "ytick.labelsize": "small",
    "text.color": "#000000",
    "axes.labelcolor": "#000000",
    "xtick.color": "#000000",
    "ytick.color": "#000000",
    "axes.edgecolor": "#444444",
    "axes.linewidth": 0.7,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "axes.axisbelow": True,
    "grid.color": "#d5cfc4",
    "grid.linewidth": 0.6,
    "grid.alpha": 0.8,
    "grid.linestyle": ":",
    "legend.frameon": False,
    "legend.fontsize": "small",
    "figure.autolayout": True,
    "savefig.dpi": 200,
    "savefig.format": "png",
    "savefig.transparent": False,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.1,
    "axes.formatter.useoffset": False,
    "axes.formatter.use_mathtext": True,
    "axes.unicode_minus": True,
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
    "agg.path.chunksize": 20000,
    "path.simplify": True,
}

# Map human-friendly CVD type names to coloraide filter names.
CVD_FILTERS: dict[str, str] = {
    "protanopia": "protan",
    "deuteranopia": "deutan",
    "tritanopia": "tritan",
}

DEFAULT_TYPES = ["protanopia", "deuteranopia", "tritanopia"]


def parse_colors(raw: str) -> list[str]:
    """Parse a comma-separated list of hex colors and normalize to #rrggbb.

    Args:
        raw: Comma-separated hex string, e.g. "#3b82f6,#10b981".

    Returns:
        List of normalized hex strings.
    """
    items = [c.strip() for c in raw.split(",") if c.strip()]
    if not items:
        raise ValueError("no colors parsed from --colors")
    return [Color(item).convert("srgb").to_string(hex=True) for item in items]


def parse_types(raw: str | None) -> list[str]:
    """Parse the --types arg into a list of validated CVD type names.

    Args:
        raw: Comma-separated string or None for the default trio.

    Returns:
        Ordered list of CVD type names.
    """
    if raw is None:
        return list(DEFAULT_TYPES)
    items = [t.strip().lower() for t in raw.split(",") if t.strip()]
    for t in items:
        if t not in CVD_FILTERS:
            raise ValueError(
                f"unknown CVD type: {t!r}; expected one of {sorted(CVD_FILTERS)}"
            )
    return items


def simulate(hex_color: str, cvd_type: str) -> str:
    """Apply a Machado-style CVD filter and return the simulated hex.

    Args:
        hex_color: Source color as a hex string.
        cvd_type: One of the keys of CVD_FILTERS.

    Returns:
        Hex string of the simulated color, clipped to the sRGB gamut.
    """
    filter_name = CVD_FILTERS[cvd_type]
    filtered = Color(hex_color).filter(filter_name, amount=1)
    return filtered.convert("srgb").fit("srgb").to_string(hex=True)


def render(
    out: Path,
    input_colors: list[str],
    types: list[str],
) -> None:
    """Render the comparison figure.

    Layout: one row per row label. The first row is "Original"; subsequent
    rows correspond to each CVD type. Each row draws horizontal swatches with
    the simulated hex code labeled below each swatch.

    Args:
        out: Destination path for the PNG.
        input_colors: Source palette hex strings.
        types: Ordered CVD type names to include after the original row.
    """
    plt.rcParams.update(EQ_RC)

    rows: list[tuple[str, list[str]]] = [("Original", list(input_colors))]
    for t in types:
        rows.append((t, [simulate(c, t) for c in input_colors]))

    n_rows = len(rows)
    n_cols = len(input_colors)
    # Figure sized so each swatch has room for its hex label.
    fig, axes = plt.subplots(
        n_rows,
        1,
        figsize=(max(4.0, 1.6 * n_cols), 1.4 * n_rows + 0.6),
        squeeze=False,
    )

    swatch_h = 1.0
    label_pad = 0.25
    for ax, (label, colors) in zip(axes[:, 0], rows, strict=True):
        ax.set_xlim(0, n_cols)
        ax.set_ylim(-label_pad - 0.4, swatch_h)
        ax.set_aspect("equal", adjustable="box")
        ax.set_title(label)
        ax.set_xticks([])
        ax.set_yticks([])
        ax.grid(False)
        for spine in ax.spines.values():
            spine.set_visible(False)
        for i, hex_color in enumerate(colors):
            ax.add_patch(
                mpatches.Rectangle(
                    (i + 0.05, 0.0),
                    0.9,
                    swatch_h,
                    facecolor=hex_color,
                    edgecolor="#444444",
                    linewidth=0.5,
                )
            )
            ax.text(
                i + 0.5,
                -label_pad,
                hex_color,
                ha="center",
                va="top",
                fontsize=8,
                family="monospace",
            )

    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out)
    plt.close(fig)


def main() -> int:
    """Entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--colors",
        required=True,
        help="Comma-separated hex colors, e.g. '#3b82f6,#10b981,#ef4444'.",
    )
    parser.add_argument(
        "--out",
        required=True,
        type=Path,
        help="Path to write the PNG.",
    )
    parser.add_argument(
        "--types",
        default=None,
        help=(
            "Comma-separated CVD types to include "
            f"(any of {sorted(CVD_FILTERS)}). Defaults to all three."
        ),
    )
    args = parser.parse_args()

    input_colors = parse_colors(args.colors)
    types = parse_types(args.types)
    log.info("simulating %d colors under %s", len(input_colors), types)

    render(args.out, input_colors, types)
    log.info("wrote %s", args.out)

    json.dump(
        {
            "out": str(args.out),
            "types": types,
            "input_colors": input_colors,
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
