# Dataviz Palettes

## When to consult this

Read before generating or recommending a palette for a chart, map, or scientific figure. Dataviz palettes encode quantitative or categorical structure — picking the wrong type invents features that are not in the data. Use this file to pick the palette *type* and a published default; use `generation.md` for the math when you must construct a new one. The script `scripts/dataviz_palette.py` handles generation — call it, do not reimplement.

## Contents

- [Decision table: data shape -> palette type](#decision-table-data-shape---palette-type)
- [Sequential](#sequential)
- [Diverging](#diverging)
- [Categorical / qualitative](#categorical--qualitative)
- [Cyclic](#cyclic)
- [Reference palettes worth recommending](#reference-palettes-worth-recommending)
- [Common dataviz errors](#common-dataviz-errors)
- [Sources](#sources)

## Decision table: data shape -> palette type

This is the load-bearing artifact. Match the data, then pick the palette.

| Data shape | Examples | Palette type | First-pick default |
|---|---|---|---|
| Ordered, single direction (low -> high) | population density, elevation, probability, magnitude | **Sequential** | `viridis` (or `cividis` for CVD audiences) |
| Ordered with meaningful midpoint | anomaly vs baseline, signed return, swing vs neutral, +/- z-score | **Diverging** | ColorBrewer `RdBu` or matplotlib `coolwarm` |
| Unordered identities | countries, product lines, experimental conditions, clusters | **Categorical** | Okabe-Ito 8; Tol `bright` or `muted`; `tab10` |
| Periodic / wraps to itself | wind direction, hour of day, phase angle, day-of-year | **Cyclic** | matplotlib `twilight` |
| Ordinal but few steps (3-7) | Likert scale, severity tier, decile bucket | **Sequential** (discrete) | Brewer `YlGnBu`/`YlOrRd` at k steps |
| Ordinal with neutral middle (3-7 steps) | "strongly disagree -> strongly agree" | **Diverging** (discrete) | Brewer `RdBu` at k steps |
| Binary / boolean | pass/fail, on/off | **Categorical** (2) | Okabe-Ito blue + orange |

If the data does not match any row, stop and ask. Do not pick silently.

## Sequential

**When:** ordered data with one natural direction. "Darker means more" must be unambiguous.

**Construction:** monotonic luminance (L\* increases or decreases steadily across the ramp), optional hue arc, perceptually uniform spacing in CAM02-UCS or OKLab. See `generation.md` for the interpolation math. In practice, do not generate — pick a published one.

**Defaults to recommend:**
- `viridis` (matplotlib default since 2.0) — perceptually uniform, CVD-robust, prints to grayscale.
- `cividis` — same constraints, additionally optimized so deuteranopes see the same ramp as typical viewers. Use for clinical or public-facing scientific output.
- `plasma`, `inferno`, `magma` — same methodology as viridis, different hue arcs.
- ColorBrewer single-hue (`Blues`, `Greens`, `Oranges`) and multi-hue (`YlGnBu`, `YlOrRd`) for choropleths and discrete bins.

**Failure modes:**
- Dark-on-dark ramp (e.g., dark blue to dark red) — no luminance signal, collapses in grayscale.
- Sequential ramp on unordered data — implies false ordering.
- `jet`/`rainbow` masquerading as sequential — non-monotonic luminance, fake banding.

## Diverging

**When:** the midpoint is semantically meaningful (zero, baseline, threshold, anomaly mean). If "the middle of the data" is not special, use sequential.

**Construction (three knobs):**
1. **Endpoint hues.** Cool/warm (blue/red, blue/orange, teal/brown). Avoid red/green — fails for the most common CVDs.
2. **Midpoint.** White (cleanest, but disappears on white pages); pale gray (background-agnostic); pale yellow (adds a third hue, can read as "intermediate value" — use only when midpoint is genuinely uninteresting).
3. **Chroma balance.** Both arms must hit the same max chroma at the same lightness, or one side dominates.

See `generation.md` for Moreland's Msh-interpolation method. Do not glue two unrelated sequential ramps together — that breaks chroma balance.

**Defaults to recommend:**
- ColorBrewer `RdBu`, `BrBG`, `PuOr`, `PRGn`.
- matplotlib `coolwarm` (blue/orange, CVD-safer than RdBu).
- Tol `sunset`, `BuRd`, `PRGn`.
- Moreland's smooth blue-white-red (https://www.kennethmoreland.com/color-maps/).

**Failure modes:**
- Diverging on data without a real midpoint — visually privileges nothing.
- Red/green endpoints — unreadable for ~5% of male viewers.
- `Spectral` / `RdYlBu` treated as plain diverging — luminance-uneven, use sparingly.
- `bwr`, `seismic` — not perceptually uniform; prefer `RdBu` or `coolwarm`.

## Categorical / qualitative

**When:** unordered identities. Hue varies; lightness should be roughly comparable so no category dominates.

**Construction:** maximum-distance sampling in perceptually uniform space (CIELAB / CAM02-UCS / OKLab), iteratively maximizing minimum pairwise ΔE under lightness/chroma constraints. iWantHue (https://medialab.github.io/iwanthue/) is the canonical implementation. See `generation.md`. For ≤8 categories, do not generate — use Okabe-Ito or Tol.

**Defaults to recommend:**
- **Okabe-Ito 8** (black, orange, sky blue, bluish green, yellow, blue, vermillion, reddish purple) — de facto accessible scientific default. Wong, *Nature Methods* 2011.
- **Tol** `bright`, `vibrant`, `muted`, `light`, `high-contrast`, `dark` — each checked under deuteranope/protanope/tritanope sims and grayscale. Pick by use case (slides -> `high-contrast`; backgrounds -> `light`).
- ColorBrewer `Set1`, `Set2`, `Dark2`, `Paired`.
- matplotlib `tab10` (up to 10), `tab20` (up to 20 — but see failure modes).

**Failure modes:**
- More than ~8 categories — adjacent colors collide, legend matching fails. Re-encode: small multiples, shape + color, direct labels, or gray-out-and-highlight.
- Categorical on ordered data — `Set1` makes "2019" and "2020" look unrelated.
- Color-only encoding — pair with shape, label, or position for accessibility.

## Cyclic

**When:** periodic data where the endpoints must match exactly (359° and 0° look identical) and luminance repeats smoothly.

**Construction:** closed-loop traversal in perceptually uniform space; both endpoints land at identical L\*, a\*, b\*. See `generation.md`.

**Defaults to recommend:**
- matplotlib `twilight`, `twilight_shifted` — perceptually corrected.
- `hsv` — uneven luminance; use only when `twilight` is unavailable.

**Failure modes:**
- Sequential palette on cyclic data — discontinuity at the wrap point reads as a cliff in the data.
- `hsv` with luminance peaks — same false-banding pathology as `jet`.

## Reference palettes worth recommending

Prefer published palettes over hand-rolled ones. Where to get each:

| Palette | Source | Library access |
|---|---|---|
| viridis, plasma, inferno, magma, cividis | https://bids.github.io/colormap/ | `matplotlib.cm.viridis`; D3 `interpolateViridis`; `palettable.matplotlib` |
| ColorBrewer (Set1/2, Dark2, Paired, RdBu, YlGnBu, ...) | https://colorbrewer2.org | `palettable.colorbrewer`; `seaborn.color_palette("Blues")`; D3 `schemeBlues[k]`; R `RColorBrewer` |
| Tol (bright, vibrant, muted, sunset, ...) | https://personal.sron.nl/~pault/ + colourschemes.pdf | `palettable.tableau`-adjacent; community Python ports; raw hex from the PDF |
| Okabe-Ito 8 | https://jfly.uni-koeln.de/color/ | hardcoded hex (8 colors); `palettable.wesanderson`-style ports |
| cmocean (oceanographic sequential/diverging/cyclic) | https://matplotlib.org/cmocean/ | `cmocean.cm.*`; `palettable.cmocean` |
| Tableau 10 / 20 | Tableau | `matplotlib.cm.tab10`/`tab20`; D3 `schemeTableau10` |
| Moreland diverging | https://www.kennethmoreland.com/color-maps/ | downloadable CSV / Python snippet |
| twilight (cyclic) | matplotlib | `matplotlib.cm.twilight` |

For web/JS, `d3-scale-chromatic` (https://github.com/d3/d3-scale-chromatic) ships all of the above under one consistent API: `interpolate*` for continuous, `scheme*[k]` for k-step discrete.

## Common dataviz errors

Each error -> one-line fix.

- **Rainbow/`jet` for ordered data.** Non-monotonic luminance invents bands and fails for CVD. -> Replace with `viridis` or `cividis`.
- **Categorical palette for ordered data** (years, severity, Likert). Implies no order. -> Use a sequential ramp.
- **Sequential ramp for unordered data** (country codes via `viridis`). Implies false order. -> Use Okabe-Ito or Tol categorical.
- **Too many categories (>8).** Adjacent colors collide; legends fail. -> Re-encode: small multiples, shape+color, direct labels, gray-out-and-highlight.
- **Diverging palette without a meaningful midpoint.** Visually privileges nothing real. -> Use sequential.
- **Color-only encoding.** Inaccessible to CVD readers and grayscale prints. -> Pair color with shape, position, or label.
- **Ignoring grayscale fallback.** Reports get photocopied and printed monochrome. -> Pick a palette with monotonic luminance (viridis, Brewer "print friendly") and check.
- **Dark-on-dark sequential.** No luminance signal. -> Span lightness, not just hue.
- **Red/green diverging endpoints.** Collapses for ~5% of male viewers. -> Use blue/red or blue/orange.
- **Skipping CVD simulation.** Bugs ship to publication. -> Run through Coblis (https://www.color-blindness.com/coblis-color-blindness-simulator/) or `colorspacious.cspace_convert` before publishing.

## Sources

- Borland & Taylor, "Rainbow Color Map (Still) Considered Harmful," IEEE CG&A 2007. https://ieeexplore.ieee.org/document/4118486
- van der Walt & Smith, "A Better Default Colormap for Matplotlib," SciPy 2015. https://bids.github.io/colormap/
- Nuñez, Anderton & Renslow, "Optimizing colormaps with consideration for color vision deficiency," PLoS ONE 2018. https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0199239
- Brewer, ColorBrewer 2.0. https://colorbrewer2.org
- Tol, "Colour Schemes," SRON technical note. https://personal.sron.nl/~pault/data/colourschemes.pdf
- Okabe & Ito, "Color Universal Design." https://jfly.uni-koeln.de/color/
- Wong, "Points of view: Color blindness," *Nature Methods* 2011. https://www.nature.com/articles/nmeth.1618
- Moreland, "Diverging Color Maps for Scientific Visualization." https://www.kennethmoreland.com/color-maps/ColorMapsExpanded.pdf
- matplotlib colormap guide. https://matplotlib.org/stable/users/explain/colors/colormaps.html
- d3-scale-chromatic. https://github.com/d3/d3-scale-chromatic
- iWantHue (Jacomy). https://medialab.github.io/iwanthue/
