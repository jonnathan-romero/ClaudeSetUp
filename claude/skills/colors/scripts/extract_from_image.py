#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "coloraide>=4",
#     "pillow>=11",
#     "numpy>=2",
#     "scikit-learn>=1.5",
# ]
# ///
"""Extract a palette from an image via k-means clustering in OKLab.

Loads an image, optionally masks out fully-transparent pixels, downsamples
to a manageable point cloud, clusters with k-means in a perceptual color
space (default: OKLab), deduplicates near-identical clusters by ΔE2000,
and prints a JSON palette to stdout.

CLI:
    uv run scripts/extract_from_image.py <image_path>
        [--k <int>]                       # default 6
        [--space oklab|cielab|srgb]       # default oklab
        [--mask alpha]                    # ignore fully-transparent pixels
        [--sort hue|lstar|frequency]      # default hue

Output (stdout, JSON):
    {
      "k": 3,
      "space": "oklab",
      "colors": [
        {"hex": "#...", "oklch": [L, C, h], "weight": 0.33},
        ...
      ]
    }
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import numpy as np
from coloraide import Color
from PIL import Image
from sklearn.cluster import KMeans

logging.basicConfig(
    level=logging.INFO,
    stream=sys.stderr,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

MAX_SAMPLES = 50_000
DEDUP_DELTA_E = 8.0
RANDOM_STATE = 0


def load_pixels(path: Path, mask_alpha: bool) -> np.ndarray:
    """Load an image and return an (N, 3) array of sRGB pixels in [0, 1].

    Args:
        path: Path to the image file.
        mask_alpha: If True and the image has an alpha channel, drop pixels
            with alpha == 0.

    Returns:
        Float32 array of shape (N, 3) with sRGB values in [0, 1].

    Raises:
        FileNotFoundError: If `path` does not exist.
    """
    if not path.exists():
        raise FileNotFoundError(f"image not found: {path}")

    img = Image.open(path)
    if mask_alpha and img.mode in ("RGBA", "LA") or "transparency" in img.info:
        img = img.convert("RGBA")
        arr = np.asarray(img)
        alpha = arr[..., 3]
        rgb = arr[..., :3][alpha > 0]
    else:
        img = img.convert("RGB")
        arr = np.asarray(img)
        rgb = arr.reshape(-1, 3)

    return rgb.astype(np.float32) / 255.0


def downsample(pixels: np.ndarray, max_samples: int = MAX_SAMPLES) -> np.ndarray:
    """Randomly sample at most `max_samples` rows from `pixels`."""
    if pixels.shape[0] <= max_samples:
        return pixels
    rng = np.random.default_rng(RANDOM_STATE)
    idx = rng.choice(pixels.shape[0], size=max_samples, replace=False)
    return pixels[idx]


def srgb_to_space(pixels: np.ndarray, space: str) -> np.ndarray:
    """Convert (N, 3) sRGB pixels in [0, 1] to the chosen color space."""
    out = np.empty_like(pixels)
    for i, p in enumerate(pixels):
        c = Color("srgb", [float(p[0]), float(p[1]), float(p[2])])
        out[i] = c.convert(space).coords()
    return out


def centroid_to_color(centroid: np.ndarray, space: str) -> Color:
    """Build a coloraide Color from a centroid in the given space."""
    return Color(space, [float(centroid[0]), float(centroid[1]), float(centroid[2])])


def color_to_oklch(color: Color) -> tuple[float, float, float]:
    """Return (L, C, h) in OKLCh; replace NaN hue (achromatic) with 0."""
    oklch = color.convert("oklch")
    L = float(oklch["lightness"])
    C = float(oklch["chroma"])
    h_raw = oklch["hue"]
    h = 0.0 if h_raw is None or (isinstance(h_raw, float) and np.isnan(h_raw)) else float(h_raw)
    h = h % 360.0
    return L, C, h


def color_to_hex(color: Color) -> str:
    """Return a `#rrggbb` hex string, gamut-mapping if needed."""
    srgb = color.convert("srgb").fit()
    return srgb.to_string(hex=True, names=False)


def dedup_by_delta_e(
    colors: list[Color], weights: list[float], threshold: float = DEDUP_DELTA_E
) -> tuple[list[Color], list[float]]:
    """Greedy-merge clusters whose ΔE2000 < threshold, keeping the heavier one.

    Walks clusters in descending weight order. For each, if no kept cluster is
    within `threshold` ΔE2000, keep it. Otherwise add its weight to the nearest
    kept cluster.

    Returns:
        (kept_colors, kept_weights) — same order as kept_colors was discovered.
    """
    order = sorted(range(len(colors)), key=lambda i: -weights[i])
    kept_colors: list[Color] = []
    kept_weights: list[float] = []

    for i in order:
        c = colors[i]
        w = weights[i]
        merged = False
        for j, k in enumerate(kept_colors):
            if c.delta_e(k, method="2000") < threshold:
                kept_weights[j] += w
                merged = True
                break
        if not merged:
            kept_colors.append(c)
            kept_weights.append(w)

    return kept_colors, kept_weights


def sort_palette(
    entries: list[dict], sort_by: str
) -> list[dict]:
    """Sort palette entries in-place-ish by the chosen key."""
    if sort_by == "hue":
        return sorted(entries, key=lambda e: e["oklch"][2])
    if sort_by == "lstar":
        return sorted(entries, key=lambda e: e["oklch"][0])
    if sort_by == "frequency":
        return sorted(entries, key=lambda e: -e["weight"])
    raise ValueError(f"unknown sort: {sort_by}")


def extract(
    image_path: Path,
    k: int,
    space: str,
    mask_alpha: bool,
    sort_by: str,
) -> dict:
    """Run the full extraction pipeline and return the palette dict."""
    logger.info("loading %s", image_path)
    pixels = load_pixels(image_path, mask_alpha=mask_alpha)
    logger.info("loaded %d pixels", pixels.shape[0])

    if pixels.shape[0] == 0:
        raise ValueError("no opaque pixels to cluster")

    sampled = downsample(pixels)
    logger.info("clustering %d sampled pixels in %s with k=%d", sampled.shape[0], space, k)

    converted = srgb_to_space(sampled, space)

    n_clusters = min(k, sampled.shape[0])
    km = KMeans(n_clusters=n_clusters, n_init=10, random_state=RANDOM_STATE)
    labels = km.fit_predict(converted)
    centers = km.cluster_centers_

    counts = np.bincount(labels, minlength=n_clusters).astype(np.float64)
    total = counts.sum()
    weights = (counts / total).tolist()

    cluster_colors = [centroid_to_color(c, space) for c in centers]

    kept_colors, kept_weights = dedup_by_delta_e(cluster_colors, weights)
    logger.info("dedup: %d → %d clusters", len(cluster_colors), len(kept_colors))

    entries = []
    for color, weight in zip(kept_colors, kept_weights, strict=True):
        L, C, h = color_to_oklch(color)
        entries.append(
            {
                "hex": color_to_hex(color),
                "oklch": [L, C, h],
                "weight": float(weight),
            }
        )

    entries = sort_palette(entries, sort_by)

    return {"k": k, "space": space, "colors": entries}


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image_path", type=Path)
    parser.add_argument("--k", type=int, default=6)
    parser.add_argument(
        "--space",
        choices=("oklab", "cielab", "srgb"),
        default="oklab",
    )
    parser.add_argument("--mask", choices=("alpha",), default=None)
    parser.add_argument(
        "--sort",
        choices=("hue", "lstar", "frequency"),
        default="hue",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint. Returns process exit code."""
    args = parse_args(argv)
    try:
        palette = extract(
            image_path=args.image_path,
            k=args.k,
            space=args.space,
            mask_alpha=(args.mask == "alpha"),
            sort_by=args.sort,
        )
    except FileNotFoundError as exc:
        logger.error("%s", exc)
        return 2
    except Exception:
        logger.exception("extraction failed")
        return 1

    json.dump(palette, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
