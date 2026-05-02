# Color Spaces Reference

## When to consult this

Open this file when palette work crosses a boundary the SKILL.md mode tables flag: building a **cross-mode** palette (light + dark with matched "weight"), expanding a brand across **media** (screen, print, fabric, signage), or answering a **gamut** question (does this OKLCh survive sRGB? do I emit P3?). Also consult when a teammate's palette is failing contrast at some hues but not others (HSL pitfall), when ramps look smudgy or skip (ΔE bands), or when "the same color" looks different on two screens (white-point / CAT confusion). For single-display, single-mode UI ramps, OKLCh + ΔE2000 is enough — skip CAM16.

## Contents

- [Pick a space (cheat sheet)](#pick-a-space-cheat-sheet)
- [sRGB, linear-sRGB, gamma](#srgb-linear-srgb-gamma)
- [HSL / HSV: the yellow problem](#hsl--hsv-the-yellow-problem)
- [CIELAB / CIELCh and ΔE2000](#cielab--cielch-and-e2000)
- [OKLab / OKLCh: the working default](#oklab--oklch-the-working-default)
- [HCT (CAM16 hue/chroma + L\* tone)](#hct-cam16-huechroma--l-tone)
- [Munsell: historical lineage](#munsell-historical-lineage)
- [Wide-gamut: P3, Rec.2020](#wide-gamut-p3-rec2020)
- [Gamut mapping (CSS Color 4)](#gamut-mapping-css-color-4)
- [CIE foundations: XYZ, illuminants, CATs](#cie-foundations-xyz-illuminants-cats)
- [Dark mode as a viewing condition](#dark-mode-as-a-viewing-condition)
- [coloraide one-liners](#coloraide-one-liners)
- [Sources](#sources)

## Pick a space (cheat sheet)

- **Blending, gradients, anti-alias, luminance math** → linear-sRGB.
- **Designer input** (rotate wheel, desaturate) → HSL is fine; convert immediately before measuring.
- **Single-display tone ramps, brand colors, contrast checks** → OKLCh.
- **Material 3-style algorithmic palettes with WCAG tone-pair guarantees** → HCT.
- **Cross-mode (light/dark) appearance match, print/signage expansion, HDR** → CAM16 (or ZCAM for HDR).
- **Color difference judgements** → ΔE2000 on CIELAB, or ΔEOK on OKLab.

## sRGB, linear-sRGB, gamma

sRGB is the default of the web, of every hex you receive, of every screenshot. Channel values are **gamma-encoded** (piecewise: small linear segment, then `((c+0.055)/1.055)^2.4`). They are **not linear in light**.

- Averaging `#000` and `#FFF` in sRGB gives `#7F7F7F`; the actual photon midpoint is `#BCBCBC`.
- A red→green gradient mixed in sRGB passes through muddy brown; in linear-sRGB through bright olive.
- WCAG relative luminance `Y = 0.2126·R + 0.7152·G + 0.0722·B` requires **linearized** channels. Computing it on raw sRGB bytes is a common bug.

**Rule:** convert to `srgb-linear` for any physical-light operation (mix, average, resample, luminance). Convert back to `srgb` only at output.

```python
Color('red').convert('srgb-linear')
```

## HSL / HSV: the yellow problem

HSL and HSV are algebraic transforms of sRGB from the 1970s. Hue as angle, lightness as scalar — intuitive, perceptually wrong.

- `hsl(60 100% 50%)` (yellow) and `hsl(240 100% 50%)` (blue) both have `L=50%`. Their relative luminance is **0.93 vs. 0.07**. Not remotely the same brightness.
- Hue is non-uniform: equal hue steps crowd in green-cyan, stretch through blues.

**Consequence:** you cannot generate accessible UI palettes by varying L in HSL. Tone ramps will look uneven; auto-pairing text and background will pass contrast at some hues, fail at others. Take HSL as input, convert to OKLCh or HCT before doing anything quantitative.

## CIELAB / CIELCh and ΔE2000

CIELAB (1976) maps CIE XYZ through a cube-root curve to `(L*, a*, b*)`:

- `L*` ∈ [0, 100], lightness, equal `ΔL*` ≈ equal perceived lightness.
- `a*` green↔red, `b*` blue↔yellow.
- `CIELCh` is the polar form: `C* = √(a*²+b*²)`, `h = atan2(b*, a*)`.

**ΔE2000** (CIEDE2000) is the workhorse perceptual distance. Practical thresholds:

- `< 1` — imperceptible side-by-side.
- `1–2` — perceptible to a trained eye.
- `2–3.5` — JND for typical viewers under controlled lighting.
- `3.5–10` — clearly noticeable; tone-ramp neighbors should sit here.
- `> 10` — obviously different colors.

A ramp with adjacent steps under ΔE2000 ≈ 5 looks smudgy; over ≈ 25 it skips. Tailwind 50→950 targets 8–12 between adjacent steps.

**Where LAB falls down:** straight lines through saturated blues bend toward purple (Abney / blue-shift); equal-`L*` ramps in saturated regions look uneven. OKLab fixes this.

## OKLab / OKLCh: the working default

Björn Ottosson's 2020 refit of LAB against IPT and CAM16-UCS. Same shape (lightness + two opponent axes + polar Lch), better behavior on saturated displays.

- `L` ∈ [0, 1] perceived lightness.
- `a` green–red, `b` blue–yellow.
- OKLCh: `C ≥ 0` (≈ 0.4 max visible), `h` degrees.

**Anchors:**

- `oklch(0.7 0.15 250)` — calm mid-blue.
- `oklch(0.7 0.15 30)` — orange-red that genuinely matches the blue's brightness.
- `oklch(0.95 0.03 110)` — warm beige card background.
- `oklch(0.45 0.18 145)` — saturated forest green, dark enough for white text.

A constant-`C`-and-`h` ramp varying `L` is visually even — why Tailwind v4 rebuilt its palette in OKLCh and CSS Color 4 added `oklch()` / `oklab()` as first-class. **Use OKLCh as the working default for screen palettes.**

## HCT (CAM16 hue/chroma + L\* tone)

Material 3's hybrid:

- **Hue** from CIECAM16 (accounts for surround / viewing conditions).
- **Chroma** from CAM16.
- **Tone** is just CIELAB `L*` (0–100), because Material's WCAG contrast math is cemented to `L*`.

The selling point: tone pairs are guaranteed — `tone 40` on `tone 90` always passes 4.5:1, etc. Use HCT when the deliverable is an algorithmic tonal palette with locked accessibility pairs (Material 3 pattern).

## Munsell: historical lineage

Albert Munsell, 1905. Three axes — Hue (10 families × 10 steps), Value (0–10), Chroma (0–~20+) — arranged by visual judgment, re-anchored to CIE in 1943. Source of the "5R 4/14" notation still used in design education and soil/textile work. The Munsell observation that **equal value steps look equal regardless of hue** is the goal every modern perceptual space inherits — OKLab gets close, HSL never could.

## Wide-gamut: P3, Rec.2020

- **Display P3** (Apple 2015+, most recent phones/laptops/monitors) — sRGB transfer, DCI-P3 primaries, ~25% larger than sRGB (mostly greens, reds).
- **Rec.2020 (BT.2020)** — UHDTV/HDR, ~75% of visible gamut. Rare native on desktop.
- **ProPhoto** — photography working space, imaginary primaries; never used for output.

**Output rule (web, 2026):** design in OKLCh, **emit P3 with sRGB fallback** (`color(display-p3 …)` with `oklch()` or hex fallback). For print or static export, sRGB is safer. Avoid Rec.2020 / ProPhoto without an HDR pipeline.

## Gamut mapping (CSS Color 4)

Many OKLCh colors don't fit sRGB or P3 (e.g. `oklch(0.7 0.4 145)`). Three strategies:

1. **Naive clipping** — per-channel clamp to [0,1]. Distorts hue, crushes chroma asymmetrically. Avoid.
2. **Chroma reduction** — binary-search `C` down at fixed `L`, `h` until in gamut. Preserves hue + lightness; classic "good enough."
3. **CSS Color 4 algorithm** — chroma reduce in OKLCh, but accept the clip when `ΔEOK` between candidate and clipped ≤ 0.02 (a JND). More saturated than pure chroma reduction, hue-faithful.

`coloraide` fit methods: `clip`, `lch-chroma`, `oklch-chroma` (CSS Color 4).

**Workflow:** generate at full OKLCh, then `fit` per output gamut — emit one set for sRGB, one for P3.

```python
Color('oklch(0.7 0.4 145)').fit('srgb', method='oklch-chroma').to_string(hex=True)
Color('oklch(0.7 0.4 145)').fit('p3',   method='oklch-chroma').to_string()
```

## CIE foundations: XYZ, illuminants, CATs

You rarely touch XYZ directly, but every space sits on top of it.

- **CIE 1931 2° Standard Observer** + **XYZ tristimulus** — reference linear-light space derived from human cone response. `Y` = luminance, `X`/`Z` chromaticity.
- **xy chromaticity diagram** — horseshoe outline = spectral locus (380–700 nm); straight bottom = line of purples. sRGB/P3/Rec.2020 are triangles inside.
- **2° vs. 10° observer** — 2° for displays and small patches (ICC default); 10° for paint chips, textiles, large surfaces.

**Standard illuminants** (white points):

| Illuminant | CCT (K) | Where it lives |
|---|---|---|
| **D50** | 5003 | ICC profile connection space, print / prepress, ISO 3664 viewing booths |
| **D65** | 6504 | sRGB, Display-P3, Rec.709/2020 — the entire web |
| A | 2856 | tungsten (legacy lab) |
| F-series | varies | fluorescent (retail/office characterization) |

Print is D50, screen is D65 — the same paper has different XYZ in each. Bridging requires a **chromatic adaptation transform (CAT)**:

- **Bradford** — ICC v2/v4 default, graphic-arts standard.
- **CAT02** — CIECAM02; better in blue/purple, but goes negative on extreme saturated blues.
- **CAT16** — CIECAM16 refit; recommended default for new work.

`coloraide` runs the CAT silently on any cross-white-point convert (e.g. `lab → srgb` does D50 LAB → D50 XYZ → Bradford → D65 XYZ → linear-sRGB → sRGB). **Most cross-domain matching bugs are an unwanted, missing, or doubled adaptation step** — when debugging, check the white point at every hop.

## Dark mode as a viewing condition

CIELAB and OKLab are color-difference models — they assume both patches are viewed under the **same conditions**. They cannot tell you the same hex looks louder on black than on white.

CAM16 takes XYZ + viewing environment (surround `dark`/`dim`/`average`/`light`, adapting luminance `L_A`, background `Y_b`, white `XYZ_w`) and outputs lightness `J`, chroma `C`, hue `h`, plus brightness `Q`, colorfulness `M`, saturation `s`.

**Practical implication:** the `dim`/`dark` surround raises perceived chroma at fixed `M`. The empirical "desaturate brand colors 10–20% for dark mode" trick is what CAM16 predicts when you hold appearance constant. OKLCh-on-`L*` palettes routinely fail this; HCT/CAM16 palettes don't.

**Reach for CAM16 when:**

- Pairing a brand color across light + dark mode with matched weight.
- Expanding screen → print / fabric / signage (CAT16 + appearance + gamut map).
- HDR systems (reference white ≠ 80 cd/m²) — prefer **ZCAM** (Jzazbz-based, valid to ~10 000 cd/m²) if the toolchain supports it.

Don't hand-roll CAM16. The forward equations are 100+ lines, the inverse is hairy. Use `coloraide` (Python) — it ships CAM16-JMh, CAM16-UCS, HCT, Jzazbz, ICtCp, ΔE-CAM16, ΔE-ITP. JS: `culori` for OKLCh/HCT basics, `material-color-utilities` or `@texel/color` for full CAM16.

## coloraide one-liners

```python
from coloraide import Color

Color('#3366cc').convert('srgb-linear')                                          # linearize for blending/luminance
Color('oklch(0.65 0.18 250)').convert('srgb').fit('oklch-chroma').to_string(hex=True)  # OKLCh -> sRGB hex
Color('oklch(0.7 0.22 145)').fit('p3', method='oklch-chroma').to_string()        # emit P3
Color('#bada55').delta_e('#c0ffee', method='2000')                               # ΔE2000
Color('hct', [250, 40, 40])                                                      # HCT seed; pair with tone-95 for 4.5:1
Color('oklch(0.65 0.18 250)').convert('cam16-jmh')                               # inspect J, M, h for surround match
```

## Sources

- CSS Color 4 — <https://www.w3.org/TR/css-color-4/>
- Ottosson, OKLab — <https://bottosson.github.io/posts/oklab/>
- Ottosson, gamut clipping — <https://bottosson.github.io/posts/gamutclipping/>
- Material 3 color system — <https://m3.material.io/styles/color/system/how-the-system-works>
- coloraide docs — <https://facelessuser.github.io/coloraide/>
- WCAG 2.2 relative luminance — <https://www.w3.org/TR/WCAG22/#dfn-relative-luminance>
- CIE 248:2022 *CIECAM16*; Fairchild, *Color Appearance Models*, 3rd ed. (2013)
