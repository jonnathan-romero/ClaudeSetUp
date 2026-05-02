# Image Extraction

**When to consult this:** extracting palettes from logos, photos, screenshots, or moodboards — turning pixels into 2–12 named colors that feed UI scales, dataviz, or harmony analysis.

For the working CLI, see `scripts/extract_from_image.py`.

## Table of Contents

1. [Choose your input type](#choose-your-input-type)
2. [Algorithms](#algorithms)
3. [Pre-processing](#pre-processing)
4. [Picking k](#picking-k)
5. [Post-processing](#post-processing)
6. [Failure modes](#failure-modes)
7. [Sources](#sources)

---

## Choose your input type

Pre/post-processing matters more than algorithm choice. Match the input.

| Input | Recommended k | Sort order | Preprocessing flags |
|---|---|---|---|
| **Logo** (flat PNG, transparent bg) | 2–5 | frequency | `--alpha-mask`, `--corner-detect-bg`, `--drop-edge-pixels`, ΔE2000 dedup ≥ 8 |
| **Photo / moodboard** (JPEG, gradients) | 5–8 (or k=20→merge) | hue | `--downsample 300px`, `--space oklab`, `--centre-weight`, optional bilateral filter for JPEG bleed |
| **Screenshot** (UI capture) | 15–20 → group | frequency | `--drop-near-white`, `--drop-near-black`, `--space oklab`, over-extract then merge |
| **Artwork / painting** (high-res scan) | 6–10 | lightness | `--saliency-weight` (or contrast weight), `--space oklab`, no aggressive neutral filter |

Defaults if unsure: photo profile, k=8, OKLab, downsample to 300px long edge.

---

## Algorithms

The actual implementation lives in `scripts/extract_from_image.py`. This is the picker.

**Median cut (Heckbert 1982).** Build the bounding box of all pixels, split along the longest axis at the *median*, recurse until you have k boxes. `O(N log N)`. Pillow's default (`Image.Quantize.MEDIANCUT`). Decent on photos, weak on logos because it splits by count, not visual importance — small bright accents get absorbed. Pick when speed matters and the image is photographic.

**k-means in OKLab.** Lloyd's algorithm in a perceptually uniform space. `O(N · k · i)`. The current best default for "palette that feels right." sRGB k-means over-weights bright greens and merges deep saturated colors into blacks; OKLab fixes this with a cheap matrix + cube-root + matrix conversion. Pick for photos, moodboards, artwork — anywhere perception matters more than speed. Always combine with downsampling.

**MMCQ (Modified Median Cut).** Leptonica/`color-thief` variant. Splits boxes by *volume × population* so distinctive small regions survive, and uses a 5-bit (32³) RGB histogram so setup is `O(N)` regardless of image size. Still sRGB-Euclidean. Pick when you want median-cut robustness with better small-region survival and don't need OKLab perceptual fidelity — fast path for "dominant 5–10 colors of a JPEG."

When in doubt: k-means in OKLab. Median cut for cheap previews. MMCQ when small accents must survive in sRGB.

---

## Pre-processing

**Downsampling.** Single biggest speed win. Thumbnail to ~200–300px long edge or random-sample 10k–50k pixels. Centroids stay within fractional ΔE of the full-resolution result. Always do this before k-means.

**Alpha masking — the "logo on transparent background" recipe.** For RGBA logos, drop pixels with `α < 250` before clustering. Keeps brand colors clean, eliminates the antialiased-edge smear (greys between brand color and background) that median cut otherwise produces. If no alpha:
1. Sample four corner patches (~5×5 each).
2. If they cluster tightly, treat that color as background.
3. Reject pixels with ΔE2000 < 5 to that background color.
4. Optionally Canny-mask: drop pixels >N from any edge.

**Saliency weighting.** Not all pixels deserve equal vote. Pass `sample_weight` to `KMeans.fit()`:
- *Centre weight:* 2D Gaussian centred on image. Cheap; works for portraits/products.
- *Contrast weight:* local std-dev of a 7×7 neighborhood. Surfaces detail over flat skies.
- *Saliency map:* `cv2.saliency.StaticSaliencyFineGrained_create()`. Slower but matches where the eye lands.

**JPEG-bleed considerations.** Chroma subsampling and DCT smear colors across edges, polluting the palette with "in-between" hues. Mitigations: (a) erode 1–2px before extraction, (b) bilateral filter to denoise while preserving edges, (c) over-extract with high k and ΔE-merge — bleed colors die in the merge.

---

## Picking k

Default heuristic: **start with 5–8.** Few enough to be human-graspable, enough to capture variety.

Programmatic options:
- **Elbow.** Plot within-cluster SSE vs. k; pick the bend. Quick, ad-hoc.
- **Silhouette.** Maximize `sklearn.metrics.silhouette_score`. More principled, slower.
- **Over-extract + merge (preferred for screenshots and moodboards).** Run k-means with **k=20**, then greedy-merge centroids by ΔE2000 < 5, summing populations. Final count is determined by the image's actual variety, not a fixed budget. Small distinct colors aren't drowned out. Almost always better than guessing the "right" k.

For UI seeding, the user usually wants **k=1** (extract dominant brand color, generate the rest of the scale — see post-processing).

---

## Post-processing

**Sorting.**
- *Hue order* (rotate to start at red, walk OKLCh hue) — display palettes.
- *Frequency order* (largest cluster first) — "dominant color" UI.
- *Lightness order* — ramps and scales.

**Neutral filtering.** If the user asked for "interesting" colors, drop:
- `oklch.chroma < 0.04` (near-greys),
- `oklch.lightness > 0.95` (near-white),
- `oklch.lightness < 0.05` (near-black).

Skip this filter for screenshot extracts where surface/background colors *are* the goal.

**Accent promotion.** The cluster with the highest OKLCh chroma is usually the accent. Promote it for visual hierarchy even if it's not the largest cluster.

**ΔE2000 dedup.** After extraction, sort centroids by population, walk the list, drop any centroid within ΔE2000 < 3 (visually identical) or < 8 (for tighter palettes) of an earlier one. Use `coloraide.Color(...).delta_e(other, method="2000")`.

**Extracted color → step-9 of a generated UI scale.** The most common handoff. Take the most-saturated extracted color, treat it as step-500 (mid-scale) or the brand-anchor step-9, then hand off to `scripts/generate_scale.py` to produce the full 50/100/.../900 ramp via Leonardo / Material HCT / Radix. One image in, full design system out.

---

## Failure modes

**JPEG color bleed.** Chroma subsampling smears edges. Palette contains hues that don't exist in the source. *Mitigate:* erode or bilateral-filter before extracting; over-extract + ΔE-merge.

**Sky / skin domination.** Portrait against sky → ~70% of pixels in two tight clusters → k=5 returns five shades of skin and sky. *Mitigate:* saliency weighting, over-extract + merge, or HSV pre-filter to drop pixels within ε of the dominant hue.

**Oversaturated extracts that don't translate to UI.** A neon-sign photo yields a palette too vivid for surfaces and text. *Mitigate:* re-tone before use — desaturate toward step-500 lightness, or treat the extract as a *seed* (k=1) and generate the UI scale rather than using extracts directly.

**White-balance drift.** Same red shirt under fluorescent vs. tungsten extracts as two different colors. *Mitigate:* gray-world or `cv2.xphoto.createSimpleWB()` normalization before extraction if consistency across an image set matters.

**Anti-aliased logo edges.** Median cut on a non-masked logo invents a smear of in-between colors at edges. *Mitigate:* alpha-mask, or threshold pixels by neighborhood variance and drop edge pixels.

---

## Sources

- Heckbert, "Color Image Quantization for Frame Buffer Display," SIGGRAPH 1982. https://dl.acm.org/doi/10.1145/965145.801294
- Gervautz & Purgathofer, "A Simple Method for Color Quantization: Octree Quantization," 1988. https://link.springer.com/chapter/10.1007/978-3-642-83492-9_20
- Lloyd, "Least squares quantization in PCM," IEEE Trans. IT 1982. https://ieeexplore.ieee.org/document/1056489
- Wu, "Efficient Statistical Computations for Optimal Color Quantization," Graphics Gems II, 1991. https://www.ece.mcmaster.ca/~xwu/cq.c
- Leptonica MMCQ. http://www.leptonica.org/papers/mediancut.pdf
- Ottosson, "A perceptual color space for image processing" (OKLab). https://bottosson.github.io/posts/oklab/
- CSS Color Module Level 4 — OKLab/OKLCh. https://www.w3.org/TR/css-color-4/#ok-lab
- Pillow `Image.quantize`. https://pillow.readthedocs.io/en/stable/reference/Image.html#PIL.Image.Image.quantize
- scikit-learn KMeans. https://scikit-learn.org/stable/modules/clustering.html#k-means
- color-thief-py. https://github.com/fengsp/color-thief-py
- coloraide (ΔE2000, OKLab). https://facelessuser.github.io/coloraide/
