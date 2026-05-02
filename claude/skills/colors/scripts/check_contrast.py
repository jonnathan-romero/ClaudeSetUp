#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "coloraide>=4",
# ]
# ///
"""Compute WCAG 2.1 contrast ratios and APCA Lc values.

Two modes:
  - Single pair:  check_contrast.py <fg_hex> <bg_hex>
  - Palette matrix:  check_contrast.py --palette palette.json

WCAG 2.1 ratio is the relative-luminance ratio (1.0 to 21.0), computed via
coloraide's `Color.contrast(other, method="wcag21")`. APCA Lc is the signed
SAPC-APCA value (positive for dark text on light bg, negative for light on
dark); coloraide does not ship an APCA plugin so the SAPC-APCA 0.98G-4g
formula is implemented inline (see https://github.com/Myndex/SAPC-APCA).

Output (stdout, JSON):
    Single pair:
        {"fg": "#000000", "bg": "#ffffff", "wcag": 21.0, "apca_lc": 106.04}
    Matrix:
        {"pairs": [{"fg": "...", "bg": "...", "wcag": ..., "apca_lc": ...}, ...]}
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from coloraide import Color

logger = logging.getLogger("check_contrast")

# SAPC-APCA 0.98G-4g constants. Source: https://github.com/Myndex/SAPC-APCA
_APCA_MAIN_TRC = 2.4
_APCA_R_CO = 0.2126729
_APCA_G_CO = 0.7151522
_APCA_B_CO = 0.0721750
_APCA_NORM_BG = 0.56
_APCA_NORM_TXT = 0.57
_APCA_REV_TXT = 0.62
_APCA_REV_BG = 0.65
_APCA_BLK_THRS = 0.022
_APCA_BLK_CLMP = 1.414
_APCA_SCALE_BOW = 1.14
_APCA_SCALE_WOB = 1.14
_APCA_LO_BOW_OFFSET = 0.027
_APCA_LO_WOB_OFFSET = 0.027
_APCA_DELTA_Y_MIN = 0.0005
_APCA_LO_CLIP = 0.1


def parse_hex(hex_str: str) -> Color:
    """Parse a hex color string into a coloraide Color or raise ValueError.

    Args:
        hex_str: A hex color like "#3B82F6".

    Returns:
        A coloraide Color in sRGB.

    Raises:
        ValueError: If `hex_str` is not a valid color.
    """
    try:
        return Color(hex_str).convert("srgb")
    except Exception as exc:
        raise ValueError(f"invalid color {hex_str!r}: {exc}") from exc


def _srgb_to_apca_y(color: Color) -> float:
    """Compute APCA's screen luminance Y for an sRGB color.

    APCA uses a simple gamma 2.4 (no sRGB piecewise) and its own luminance
    coefficients, distinct from WCAG's 0.2126/0.7152/0.0722.
    """
    coords = color.convert("srgb").coords()
    r, g, b = (max(0.0, min(1.0, c)) for c in coords)
    return (
        (r**_APCA_MAIN_TRC) * _APCA_R_CO
        + (g**_APCA_MAIN_TRC) * _APCA_G_CO
        + (b**_APCA_MAIN_TRC) * _APCA_B_CO
    )


def apca_lc(fg: Color, bg: Color) -> float:
    """Return the signed APCA Lc value for fg-on-bg.

    Positive Lc means dark text on light background; negative means light
    text on dark background. Magnitudes near 100 are very high contrast;
    |Lc| below ~15 is invisible per the SAPC-APCA spec.

    Args:
        fg: Foreground (text) color.
        bg: Background color.

    Returns:
        Signed Lc on roughly the [-108, +106] scale.
    """
    y_txt = _srgb_to_apca_y(fg)
    y_bg = _srgb_to_apca_y(bg)

    # Black soft clamp — stabilizes very dark colors.
    if y_txt < _APCA_BLK_THRS:
        y_txt += (_APCA_BLK_THRS - y_txt) ** _APCA_BLK_CLMP
    if y_bg < _APCA_BLK_THRS:
        y_bg += (_APCA_BLK_THRS - y_bg) ** _APCA_BLK_CLMP

    if abs(y_bg - y_txt) < _APCA_DELTA_Y_MIN:
        return 0.0

    if y_bg > y_txt:
        # Dark text on light background — positive Lc.
        sapc = (y_bg**_APCA_NORM_BG - y_txt**_APCA_NORM_TXT) * _APCA_SCALE_BOW
        out = 0.0 if sapc < _APCA_LO_CLIP else sapc - _APCA_LO_BOW_OFFSET
    else:
        # Light text on dark background — negative Lc.
        sapc = (y_bg**_APCA_REV_BG - y_txt**_APCA_REV_TXT) * _APCA_SCALE_WOB
        out = 0.0 if sapc > -_APCA_LO_CLIP else sapc + _APCA_LO_WOB_OFFSET

    return out * 100


def wcag_ratio(fg: Color, bg: Color) -> float:
    """Return the WCAG 2.1 relative-luminance contrast ratio.

    The ratio is symmetric in fg/bg and runs from 1.0 (identical) to 21.0
    (pure black on pure white).

    Args:
        fg: Foreground color.
        bg: Background color.

    Returns:
        Contrast ratio in [1.0, 21.0].
    """
    return float(fg.contrast(bg, method="wcag21"))


def _normalize_hex(color: Color) -> str:
    """Return a canonical lowercase #rrggbb string for `color`."""
    s = color.convert("srgb").to_string(hex=True).lower()
    if len(s) == 4:  # expand "#fff" to "#ffffff"
        s = "#" + "".join(ch * 2 for ch in s[1:])
    return s


def evaluate_pair(fg_hex: str, bg_hex: str) -> dict:
    """Compute WCAG and APCA for a single fg/bg hex pair.

    Args:
        fg_hex: Foreground hex string.
        bg_hex: Background hex string.

    Returns:
        A dict with keys `fg`, `bg`, `wcag`, `apca_lc`.
    """
    fg = parse_hex(fg_hex)
    bg = parse_hex(bg_hex)
    return {
        "fg": _normalize_hex(fg),
        "bg": _normalize_hex(bg),
        "wcag": round(wcag_ratio(fg, bg), 4),
        "apca_lc": round(apca_lc(fg, bg), 2),
    }


def evaluate_palette(palette_path: Path) -> dict:
    """Compute every ordered (fg, bg) pair from a palette's steps.

    Args:
        palette_path: Path to a palette JSON file with a `steps` array of
            `{"hex": ...}` entries (the format generate_scale.py emits).

    Returns:
        A dict `{"pairs": [...]}` with one entry per ordered pair. Same-color
        pairs (fg == bg) are excluded.
    """
    data = json.loads(palette_path.read_text())
    hexes = [step["hex"] for step in data["steps"]]
    pairs: list[dict] = []
    for fg in hexes:
        for bg in hexes:
            if fg == bg:
                continue
            pairs.append(evaluate_pair(fg, bg))
    return {"pairs": pairs}


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Returns:
        Process exit code (0 on success, 2 on user error).
    """
    parser = argparse.ArgumentParser(
        description="Compute WCAG 2.1 and APCA contrast for a pair or a palette matrix."
    )
    parser.add_argument("fg", nargs="?", help="Foreground hex color (single-pair mode).")
    parser.add_argument("bg", nargs="?", help="Background hex color (single-pair mode).")
    parser.add_argument("--palette", type=Path, help="Path to a palette JSON for matrix mode.")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(message)s")

    try:
        if args.palette is not None:
            payload = evaluate_palette(args.palette)
        else:
            if not args.fg or not args.bg:
                parser.error("provide <fg> <bg> or --palette PATH")
            payload = evaluate_pair(args.fg, args.bg)
    except ValueError as exc:
        logger.error(str(exc))
        return 2
    except (OSError, json.JSONDecodeError) as exc:
        logger.error("failed to read palette: %s", exc)
        return 2

    sys.stdout.write(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
