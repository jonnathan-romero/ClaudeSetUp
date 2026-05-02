#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "matplotlib>=3.8",
# ]
# ///
"""Render a labeled PNG swatch sheet for a palette JSON file.

CLI:
    uv run scripts/render_swatches.py --palette palette.json --out swatches.png

Reads a palette JSON in the format generate_scale.py emits and writes a PNG
swatch strip to --out. Each step becomes a labeled swatch (step number above,
hex below, role at the bottom). The palette name is the figure title. Emits a
JSON summary on stdout: {"out", "swatch_count", "size"}.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("render_swatches")

EQ_RC: dict[str, Any] = {
    # Background
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
    # Font
    "font.family": "sans-serif",
    "font.sans-serif": ["Helvetica", "Arial", "DejaVu Sans"],
    "font.size": 10,
    "axes.titlesize": "large",
    "axes.titleweight": "normal",
    "axes.labelsize": "medium",
    "xtick.labelsize": "small",
    "ytick.labelsize": "small",
    # Text color
    "text.color": "#000000",
    "axes.labelcolor": "#000000",
    "xtick.color": "#000000",
    "ytick.color": "#000000",
    # Spines
    "axes.edgecolor": "#444444",
    "axes.linewidth": 0.7,
    "axes.spines.top": False,
    "axes.spines.right": False,
    # Grid
    "axes.grid": True,
    "axes.axisbelow": True,
    "grid.color": "#d5cfc4",
    "grid.linewidth": 0.6,
    "grid.alpha": 0.8,
    "grid.linestyle": ":",
    # Legend
    "legend.frameon": False,
    "legend.fontsize": "small",
    # Layout & saving
    "figure.autolayout": True,
    "savefig.dpi": 200,
    "savefig.format": "png",
    "savefig.transparent": False,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.1,
    # Axis formatting
    "axes.formatter.useoffset": False,
    "axes.formatter.use_mathtext": True,
    "axes.unicode_minus": True,
    # Font embedding for PDF/PS export
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
    # Performance for large time series
    "agg.path.chunksize": 20000,
    "path.simplify": True,
}


def load_palette(path: Path) -> dict[str, Any]:
    """Load a palette JSON file.

    Args:
        path: Path to a JSON file in the format generate_scale.py emits.

    Returns:
        The parsed palette dict with keys ``name`` and ``steps``.

    Raises:
        FileNotFoundError: If the file does not exist.
        json.JSONDecodeError: If the file is not valid JSON.
    """
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def render(palette: dict[str, Any], out_path: Path) -> tuple[int, tuple[float, float]]:
    """Render a horizontal swatch strip for ``palette`` to ``out_path``.

    Each swatch is a solid rectangle of its step's hex color, labeled with the
    step number above and the hex code + role below. The palette name is the
    figure title.

    Args:
        palette: Palette dict with ``name`` and ``steps`` keys.
        out_path: Destination PNG path.

    Returns:
        ``(swatch_count, (width_inches, height_inches))``.
    """
    steps = palette["steps"]
    n = len(steps)

    # Swatch box: 1.0 wide x 1.2 tall in data units; figure scales with n.
    fig_w = max(4.0, 1.2 * n)
    fig_h = 3.0
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))

    swatch_w = 1.0
    swatch_h = 1.2
    gap = 0.1

    for i, step in enumerate(steps):
        x0 = i * (swatch_w + gap)
        ax.add_patch(
            plt.Rectangle(
                (x0, 0.0),
                swatch_w,
                swatch_h,
                facecolor=step["hex"],
                edgecolor="#444444",
                linewidth=0.5,
            )
        )
        cx = x0 + swatch_w / 2

        # Step number above the swatch — fall back to the index when the
        # palette JSON omits "step" (e.g. ad-hoc palettes hand-built for critique).
        ax.text(
            cx,
            swatch_h + 0.18,
            str(step.get("step", i + 1)),
            ha="center",
            va="bottom",
            fontsize=10,
            fontweight="bold",
        )
        # Hex below the swatch.
        ax.text(
            cx,
            -0.12,
            step["hex"],
            ha="center",
            va="top",
            fontsize=9,
            family="monospace",
        )
        # Role below the hex.
        ax.text(
            cx,
            -0.38,
            step.get("role", ""),
            ha="center",
            va="top",
            fontsize=7,
            color="#444444",
        )

    total_w = n * swatch_w + (n - 1) * gap
    ax.set_xlim(-0.1, total_w + 0.1)
    ax.set_ylim(-0.9, swatch_h + 0.6)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.grid(False)

    ax.set_title(palette.get("name", ""))

    fig.savefig(out_path)
    plt.close(fig)
    return n, (fig_w, fig_h)


def main() -> int:
    """Parse args, render the swatch sheet, and emit the JSON summary."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--palette", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    if not args.palette.exists():
        logger.error("palette file not found: %s", args.palette)
        return 2

    plt.rcParams.update(EQ_RC)

    palette = load_palette(args.palette)
    logger.info("loaded palette '%s' with %d steps", palette.get("name"), len(palette["steps"]))

    count, size = render(palette, args.out)
    logger.info("wrote %s (%d swatches)", args.out, count)

    summary = {"out": str(args.out), "swatch_count": count, "size": [size[0], size[1]]}
    sys.stdout.write(json.dumps(summary))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
