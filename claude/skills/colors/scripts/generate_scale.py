#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "coloraide>=4",
# ]
# ///
"""Generate a 12-step semantic UI scale from a seed color in OKLCh.

Implements a parabolic chroma envelope over a monotonically descending L* axis.
Light mode goes L=0.985 -> L=0.10; dark mode inverts the curve and damps chroma
to avoid neon dark steps. The seed color anchors the scale at the step whose
target L is closest to the seed's measured L*; for the tailwind system that
slot also adopts the seed's chroma (Tailwind v4 convention).

Output is a JSON document on stdout. Diagnostics go to stderr via `logging`.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from typing import Literal

from coloraide import Color

logger = logging.getLogger("generate_scale")

System = Literal["tailwind", "radix", "material"]

# Radix's 12-step semantic taxonomy. Step 9 is the brand-anchoring "solid".
RADIX_ROLES: list[str] = [
    "app background",
    "subtle background",
    "ui background",
    "hovered ui",
    "active ui",
    "subtle border",
    "ui border",
    "hovered border",
    "solid",
    "hovered solid",
    "low-contrast text",
    "high-contrast text",
]

# 12 lightness anchors, lightest to darkest. Mirrors Tailwind v4 / Radix shape.
L_LIGHT: list[float] = [
    0.985, 0.970, 0.930, 0.880, 0.820, 0.740,
    0.660, 0.580, 0.500, 0.410, 0.260, 0.150,
]
# Dark mode: inverted curve. Step 1 is the darkest app bg, step 12 the brightest text.
L_DARK: list[float] = [
    0.180, 0.220, 0.270, 0.330, 0.390, 0.460,
    0.530, 0.610, 0.690, 0.770, 0.870, 0.960,
]


def parse_seed(hex_str: str) -> Color:
    """Parse a hex color string into a coloraide Color or raise ValueError.

    Args:
        hex_str: A 7-character hex color like "#3B82F6".

    Returns:
        A coloraide Color in sRGB.
    """
    try:
        return Color(hex_str)
    except Exception as exc:
        raise ValueError(f"invalid seed color {hex_str!r}: {exc}") from exc


def chroma_envelope(t: float, c_peak: float, c_end_factor: float = 0.25) -> float:
    """Parabolic chroma curve: peaks at t=0.5, tapers to c_end_factor*c_peak at t in {0,1}.

    Args:
        t: Position along the scale in [0, 1].
        c_peak: Maximum chroma at t=0.5.
        c_end_factor: Fraction of c_peak retained at the L* extremes.

    Returns:
        Chroma value at position t.
    """
    bell = 1.0 - (2.0 * t - 1.0) ** 2
    tail = (2.0 * t - 1.0) ** 2
    return c_peak * bell + c_end_factor * c_peak * tail


def nearest_anchor_index(seed_l: float, l_anchors: list[float]) -> int:
    """Return the index whose anchor L is closest to seed_l."""
    return min(range(len(l_anchors)), key=lambda i: abs(l_anchors[i] - seed_l))


def build_scale(
    seed: Color,
    system: System,
    dark: bool,
) -> list[dict]:
    """Build the 12-step OKLCh scale.

    Args:
        seed: Seed color in any input space (will be converted to OKLCh).
        system: Which step convention to apply for chroma anchoring.
        dark: Whether to emit the dark-mode curve.

    Returns:
        List of 12 step dicts ordered lightest-first.
    """
    seed_oklch = seed.convert("oklch")
    seed_l = float(seed_oklch["lightness"])
    seed_c = float(seed_oklch["chroma"])
    seed_h = float(seed_oklch["hue"])
    if seed_h != seed_h:  # NaN hue (achromatic seed)
        seed_h = 0.0

    l_anchors = L_DARK if dark else L_LIGHT
    # Dark-mode peak chroma is damped so dark backgrounds don't read as neon.
    c_peak = seed_c * (0.78 if dark else 1.0)
    # Floor the parabola peak only for chromatic seeds. For near-grey seeds
    # (C* < 0.04, e.g. slate / zinc / stone neutrals), forcing chroma up to
    # 0.12 produces visibly tinted mid-steps and a non-monotone chroma curve.
    # Keep the scale neutral by leaving c_peak at the seed's own chroma.
    if seed_c >= 0.04:
        c_peak = max(c_peak, 0.12)

    # Anchor the seed to whichever step's L is closest (so a near-white seed
    # doesn't get force-slammed into step 9).
    anchor_idx = nearest_anchor_index(seed_l, l_anchors)

    # For the tailwind system, also pin step 9 to carry the seed's chroma —
    # Tailwind v4's 500/600 stops are the brand's chroma identity.
    tailwind_anchor = 8 if system == "tailwind" else None

    steps: list[dict] = []
    n = 12
    for i in range(n):
        t = i / (n - 1)
        L = l_anchors[i]
        if i == anchor_idx:
            C = seed_c if not dark else seed_c * 0.85
        elif tailwind_anchor is not None and i == tailwind_anchor:
            C = seed_c if not dark else seed_c * 0.80
        else:
            C = chroma_envelope(t, c_peak)

        oklch = Color("oklch", [L, C, seed_h])
        # fit() reduces chroma along constant-L,H until the color is in sRGB gamut.
        srgb = oklch.convert("srgb").fit(method="oklch-chroma")
        hex_str = srgb.to_string(hex=True).lower()
        if len(hex_str) == 4:  # short form like "#fff"
            hex_str = "#" + "".join(ch * 2 for ch in hex_str[1:])

        # Read back the gamut-mapped OKLCh so the reported (L,C,h) matches the hex.
        actual = srgb.convert("oklch")
        actual_l = float(actual["lightness"])
        actual_c = float(actual["chroma"])
        actual_h = float(actual["hue"])
        if actual_h != actual_h:
            actual_h = 0.0
        actual_h = actual_h % 360.0

        steps.append(
            {
                "step": i + 1,
                "hex": hex_str,
                "oklch": [actual_l, actual_c, actual_h],
                "role": RADIX_ROLES[i],
            }
        )

    _enforce_strict_l_monotonic(steps)
    return steps


def _enforce_strict_l_monotonic(steps: list[dict]) -> None:
    """Nudge L values down by epsilon if gamut mapping flattened adjacent steps.

    The contract requires *strictly* decreasing L*. Gamut clipping at the bright
    end can collapse step 1 and step 2 to identical white; bump them apart.
    """
    eps = 1e-6
    for i in range(len(steps) - 1):
        if steps[i]["oklch"][0] <= steps[i + 1]["oklch"][0]:
            steps[i]["oklch"][0] = steps[i + 1]["oklch"][0] + eps
    # Clamp to [0, 1] in case the bumps pushed past the boundary.
    for s in steps:
        s["oklch"][0] = min(1.0, max(0.0, s["oklch"][0]))


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Returns:
        Process exit code (0 on success, nonzero on user error).
    """
    parser = argparse.ArgumentParser(description="Generate a 12-step OKLCh UI scale from a seed color.")
    parser.add_argument("--seed", required=True, help="Seed color hex like #3B82F6.")
    parser.add_argument("--name", required=True, help="Palette name.")
    parser.add_argument("--dark", action="store_true", help="Emit the dark-mode curve.")
    parser.add_argument(
        "--system",
        choices=("tailwind", "radix", "material"),
        default="tailwind",
        help="Step-count and chroma convention.",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(message)s")

    try:
        seed = parse_seed(args.seed)
    except ValueError as exc:
        logger.error(str(exc))
        return 2

    steps = build_scale(seed=seed, system=args.system, dark=args.dark)

    payload = {
        "name": args.name,
        "system": args.system,
        "mode": "dark" if args.dark else "light",
        "steps": steps,
    }
    sys.stdout.write(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
