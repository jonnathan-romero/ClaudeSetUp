#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "coloraide>=4",
# ]
# ///
"""Generate perceptually-uniform dataviz palettes in OKLCh.

Four palette types, each with a matplotlib snippet ready to drop into a script:

    Sequential   single-hue ramp, L* monotonic 0.95 -> 0.20, parabolic chroma.
    Diverging    two hues meeting at a near-white midpoint; L* mirrored.
    Categorical  N evenly-spaced hues at fixed L* and chroma. --cvd-safe biases
                 hue placement away from the protan/deutan confusion axis.
    Cyclic       N hues over [0, 360) at constant L*, C; first ~ last.

CLI:
    uv run scripts/dataviz_palette.py --type sequential  --n N --hue H
    uv run scripts/dataviz_palette.py --type diverging   --n N --hues H1,H2
    uv run scripts/dataviz_palette.py --type categorical --n N [--cvd-safe]
    uv run scripts/dataviz_palette.py --type cyclic      --n N

Output (stdout, JSON):
    {
      "type": "sequential",
      "n": 9,
      "colors": [{"hex": "#...", "oklch": [L, C, h]}, ...],
      "matplotlib": "<runnable snippet>"
    }

Diagnostics go to stderr via `logging`.
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import sys
from typing import Literal

from coloraide import Color

logger = logging.getLogger("dataviz_palette")

PaletteType = Literal["sequential", "diverging", "categorical", "cyclic"]

# Sequential / diverging endpoints and chroma peak. Mid-scale chroma cap of 0.18
# is the standard recipe; gamut mapping reduces it where the hue can't sustain it.
L_LIGHT_END = 0.95
L_DARK_END = 0.20
C_PEAK = 0.18
C_END_FACTOR = 0.30

# Categorical defaults. L* ~ 0.65 and C ~ 0.13 sit in the chroma sweet spot for
# mid-tone hues across sRGB and give roughly equal apparent weight per swatch.
CAT_L = 0.65
CAT_C = 0.13
CAT_N_SOFT_CAP = 8

# Tol-inspired CVD-safe pool of mutually well-separated hues (deg, OKLCh).
# Placement is biased away from the protan/deutan confusion line (the OKLab
# +a / -a axis near hue 0 deg and 180 deg) and tuned so any subset selected
# by greedy farthest-point sampling stays pairwise > ~50 deg apart, which
# keeps min OKLab chord distance > 0.11 at the categorical chroma of 0.13.
TOL_CVD_HUES: list[float] = [
    264.0,  # blue
    155.0,  # green
    85.0,   # yellow
    25.0,   # red-orange
    330.0,  # magenta
    200.0,  # cyan-teal
    60.0,   # amber
]

# L* per Tol anchor hue. Equal-L* categorical palettes converge toward similar
# mid-greys under deuteranopia because they only carry the chromatic channel.
# Varying L* across hues (Okabe-Ito / Tol convention) gives dichromats a second
# perceptual channel and survives CVD simulation far better. Values picked to
# track sRGB chroma headroom — yellow naturally sits brighter, blue darker.
CVD_HUE_LSTAR: dict[float, float] = {
    264.0: 0.50,
    155.0: 0.62,
    85.0:  0.78,
    25.0:  0.62,
    330.0: 0.55,
    200.0: 0.72,
    60.0:  0.72,
}

# Starting rotation for evenly-spaced CVD-safe hues. Anchoring at blue moves
# the entire ring off the deutan/protan confusion axis.
CVD_HUE_ROTATION = 264.0


def _hex_from_oklch(L: float, C: float, h: float) -> tuple[str, list[float]]:
    """Convert OKLCh -> gamut-mapped sRGB hex; return hex and the actual OKLCh.

    Args:
        L: OKLCh lightness in [0, 1].
        C: OKLCh chroma.
        h: OKLCh hue in degrees.

    Returns:
        (hex string, [L, C, h]) where the OKLCh tuple reflects the in-gamut color.
    """
    color = Color("oklch", [L, C, h])
    srgb = color.convert("srgb").fit()
    hex_str = srgb.to_string(hex=True).lower()
    if len(hex_str) == 4:
        hex_str = "#" + "".join(ch * 2 for ch in hex_str[1:])
    actual = srgb.convert("oklch")
    a_l = float(actual["lightness"])
    a_c = float(actual["chroma"])
    a_h = float(actual["hue"])
    if a_h != a_h:  # NaN hue (achromatic)
        a_h = h % 360.0
    a_h = a_h % 360.0
    return hex_str, [a_l, a_c, a_h]


def _chroma_envelope(t: float, c_peak: float = C_PEAK, c_end: float = C_END_FACTOR) -> float:
    """Parabolic chroma curve: peaks at t=0.5, tapers to c_end*c_peak at extremes.

    Args:
        t: Position along the ramp in [0, 1].
        c_peak: Chroma at midpoint.
        c_end: Fraction of c_peak retained at t in {0, 1}.

    Returns:
        Chroma value at position t.
    """
    bell = 1.0 - (2.0 * t - 1.0) ** 2
    tail = (2.0 * t - 1.0) ** 2
    return c_peak * bell + c_end * c_peak * tail


def build_sequential(n: int, hue: float) -> list[dict]:
    """Build a single-hue sequential ramp lightest -> darkest.

    L* steps linearly from L_LIGHT_END to L_DARK_END. Chroma follows a parabolic
    envelope so that midtones are saturated while endpoints stay in sRGB gamut.

    Args:
        n: Number of steps (>= 2).
        hue: OKLCh hue in degrees.

    Returns:
        List of {"hex", "oklch"} dicts ordered light -> dark.
    """
    out: list[dict] = []
    for i in range(n):
        t = i / (n - 1) if n > 1 else 0.0
        L = L_LIGHT_END + (L_DARK_END - L_LIGHT_END) * t
        C = _chroma_envelope(t)
        hex_str, oklch = _hex_from_oklch(L, C, hue)
        # Use the requested L (in-gamut for these targets) so monotonicity is exact.
        oklch[0] = L
        out.append({"hex": hex_str, "oklch": oklch})
    return out


def build_diverging(n: int, hue_left: float, hue_right: float) -> list[dict]:
    """Build a diverging palette: dark -> neutral light midpoint -> dark.

    The central index has the lightest L* (L_LIGHT_END) and very low chroma so
    it reads as "no signal." Step i and step n-1-i are mirrored in L*, with
    hue_left on the low side and hue_right on the high side.

    Args:
        n: Number of steps.
        hue_left: OKLCh hue (deg) for indices < midpoint.
        hue_right: OKLCh hue (deg) for indices > midpoint.

    Returns:
        List of {"hex", "oklch"} dicts.
    """
    if n == 1:
        # Degenerate: single neutral midpoint.
        L = L_LIGHT_END
        hex_str, oklch = _hex_from_oklch(L, 0.01, hue_left)
        oklch[0] = L
        return [{"hex": hex_str, "oklch": oklch}]

    out: list[dict] = []
    mid_pos = (n - 1) / 2.0
    for i in range(n):
        # d in [0, 1]: 0 at center, 1 at the farthest endpoint.
        d = abs(i - mid_pos) / mid_pos
        L = L_LIGHT_END + (L_DARK_END - L_LIGHT_END) * d
        if d == 0.0:
            # Neutral midpoint: very low chroma. Hue is arbitrary; pick hue_left.
            C = 0.005
            hue = hue_left
        else:
            # Map d back through the same parabolic envelope as the sequential ramp.
            # Position on a one-sided ramp (0 at light end, 1 at dark end) is just d.
            C = _chroma_envelope(d)
            hue = hue_left if i < mid_pos else hue_right
        hex_str, oklch = _hex_from_oklch(L, C, hue)
        oklch[0] = L
        out.append({"hex": hex_str, "oklch": oklch})
    return out


def _oklab_xy(L: float, C: float, h_deg: float) -> tuple[float, float]:
    """Convert OKLCh hue/chroma to OKLab (a, b) for distance calculations.

    Args:
        L: OKLCh lightness (unused; kept for symmetry).
        C: OKLCh chroma.
        h_deg: OKLCh hue in degrees.

    Returns:
        (a, b) in OKLab.
    """
    h = math.radians(h_deg)
    return C * math.cos(h), C * math.sin(h)


def _min_pair_distance(hues: list[float], L: float, C: float) -> float:
    """Minimum Euclidean OKLab distance between any pair of (L, C, h) colors."""
    pts = [_oklab_xy(L, C, h) for h in hues]
    best = float("inf")
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            dx = pts[i][0] - pts[j][0]
            dy = pts[i][1] - pts[j][1]
            best = min(best, math.hypot(dx, dy))
    return best


def _select_cvd_safe_hues(n: int) -> list[float]:
    """Pick N CVD-aware hues with large minimum pairwise OKLab chord distance.

    Uses evenly-spaced hues rotated so the ring starts at the CVD-safe blue
    anchor, then runs greedy farthest-point swaps against the Tol anchor pool
    to bias hue placement away from the deutan/protan confusion line while
    preserving the even-spacing distance floor.

    Args:
        n: Number of hues requested.

    Returns:
        List of N hues in degrees.
    """
    # Start with even spacing rotated to the safe band: this guarantees a
    # min hue gap of 360/n degrees, which at C = 0.13 gives ample OKLab ΔE.
    chosen: list[float] = [(CVD_HUE_ROTATION + i * 360.0 / n) % 360.0 for i in range(n)]
    if n > len(TOL_CVD_HUES):
        return chosen

    # Greedy substitution: for each slot, prefer the closest Tol anchor that
    # doesn't collapse the minimum pairwise OKLab distance below the
    # even-spacing baseline. Falls back to the even-spaced hue if no anchor
    # is acceptable.
    baseline = _min_pair_distance(chosen, CAT_L, CAT_C)
    used: set[float] = set()
    for idx in range(n):
        candidates = sorted(
            (h for h in TOL_CVD_HUES if h not in used),
            key=lambda h: min(
                abs(((h - chosen[idx] + 180.0) % 360.0) - 180.0),
                abs(((chosen[idx] - h + 180.0) % 360.0) - 180.0),
            ),
        )
        for cand in candidates:
            trial = list(chosen)
            trial[idx] = cand
            if _min_pair_distance(trial, CAT_L, CAT_C) >= baseline * 0.95:
                chosen[idx] = cand
                used.add(cand)
                break
    return chosen


def build_categorical(n: int, cvd_safe: bool) -> list[dict]:
    """Build a categorical palette of N evenly-spaced hues at fixed L* and C.

    Args:
        n: Number of categories.
        cvd_safe: If True, use Tol-inspired CVD-safe anchor hues instead of
            even circular spacing.

    Returns:
        List of {"hex", "oklch"} dicts.
    """
    if n > CAT_N_SOFT_CAP:
        logger.warning(
            "categorical n=%d exceeds soft cap of %d; colors may be hard to distinguish",
            n,
            CAT_N_SOFT_CAP,
        )
    if cvd_safe:
        hues = _select_cvd_safe_hues(n)
        # Lookup L* per Tol anchor; non-anchor hues (n > 7) fall back to CAT_L.
        lstars = [CVD_HUE_LSTAR.get(h, CAT_L) for h in hues]
    else:
        hues = [(i * 360.0 / n) % 360.0 for i in range(n)]
        lstars = [CAT_L] * n
    out: list[dict] = []
    for L, h in zip(lstars, hues):
        hex_str, oklch = _hex_from_oklch(L, CAT_C, h)
        oklch[0] = L
        oklch[1] = CAT_C
        out.append({"hex": hex_str, "oklch": oklch})
    return out


def build_cyclic(n: int) -> list[dict]:
    """Build a cyclic palette: N hues over [0, 360), constant L* and C.

    The endpoints meet because hue is taken mod 360; step[N-1] sits one step
    before wrapping to step[0].

    Args:
        n: Number of steps.

    Returns:
        List of {"hex", "oklch"} dicts.
    """
    out: list[dict] = []
    for i in range(n):
        h = (i * 360.0 / n) % 360.0
        hex_str, oklch = _hex_from_oklch(CAT_L, CAT_C, h)
        oklch[0] = CAT_L
        oklch[1] = CAT_C
        out.append({"hex": hex_str, "oklch": oklch})
    return out


# ---- matplotlib snippet generation ---------------------------------------------

EQ_RC_LITERAL = '''EQ_RC = {
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
}'''


def _format_hex_list(hexes: list[str]) -> str:
    """Render a hex list as a Python literal string."""
    return "[" + ", ".join(f'"{h}"' for h in hexes) + "]"


def matplotlib_snippet(palette_type: PaletteType, name: str, hexes: list[str]) -> str:
    """Build a runnable matplotlib snippet for the given palette.

    Sequential and diverging palettes use `LinearSegmentedColormap.from_list`;
    categorical and cyclic use `ListedColormap`. Both variants prepend the
    EQ_RC rcParams so users can drop the snippet straight into a script.

    Args:
        palette_type: One of the four palette types.
        name: Colormap name to register.
        hexes: Colors in palette order.

    Returns:
        A multi-line snippet string.
    """
    hex_literal = _format_hex_list(hexes)
    preamble = (
        "import matplotlib.pyplot as plt\n"
        f"{EQ_RC_LITERAL}\n"
        "plt.rcParams.update(EQ_RC)\n"
    )
    if palette_type in ("sequential", "diverging"):
        body = (
            "from matplotlib.colors import LinearSegmentedColormap\n"
            f'cmap = LinearSegmentedColormap.from_list("{name}", {hex_literal})\n'
        )
    else:
        body = (
            "from matplotlib.colors import ListedColormap\n"
            f'cmap = ListedColormap({hex_literal}, name="{name}")\n'
        )
    return preamble + body


# ---- CLI -----------------------------------------------------------------------


def _parse_hues_pair(s: str) -> tuple[float, float]:
    """Parse a "H1,H2" string into a (float, float) tuple."""
    parts = s.split(",")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(f"--hues expects 'H1,H2', got {s!r}")
    return float(parts[0]), float(parts[1])


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Returns:
        Process exit code (0 success, 2 user error).
    """
    parser = argparse.ArgumentParser(description="Generate dataviz palettes in OKLCh.")
    parser.add_argument(
        "--type",
        required=True,
        choices=("sequential", "diverging", "categorical", "cyclic"),
        help="Palette type.",
    )
    parser.add_argument("--n", type=int, required=True, help="Number of colors.")
    parser.add_argument("--hue", type=float, help="OKLCh hue (sequential only).")
    parser.add_argument("--hues", type=_parse_hues_pair, help="OKLCh hue pair 'H1,H2' (diverging only).")
    parser.add_argument("--cvd-safe", action="store_true", help="Bias categorical hues away from CVD confusion lines.")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(message)s")

    if args.n < 1:
        logger.error("--n must be >= 1")
        return 2

    palette_type: PaletteType = args.type
    if palette_type == "sequential":
        if args.hue is None:
            logger.error("--type sequential requires --hue")
            return 2
        colors = build_sequential(args.n, args.hue)
    elif palette_type == "diverging":
        if args.hues is None:
            logger.error("--type diverging requires --hues H1,H2")
            return 2
        colors = build_diverging(args.n, args.hues[0], args.hues[1])
    elif palette_type == "categorical":
        colors = build_categorical(args.n, cvd_safe=args.cvd_safe)
    elif palette_type == "cyclic":
        colors = build_cyclic(args.n)
    else:  # pragma: no cover - argparse choices guard this
        logger.error("unknown --type %s", palette_type)
        return 2

    snippet = matplotlib_snippet(
        palette_type,
        name=f"{palette_type}_n{args.n}",
        hexes=[c["hex"] for c in colors],
    )
    payload = {
        "type": palette_type,
        "n": args.n,
        "colors": colors,
        "matplotlib": snippet,
    }
    sys.stdout.write(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
