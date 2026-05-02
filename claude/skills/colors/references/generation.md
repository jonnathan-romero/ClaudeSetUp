# Generation Reference

**When to consult this:** you are generating a color scale (UI tonal, sequential dataviz, diverging, categorical, alpha-variant), debugging why a generated scale looks wrong (banding, muddy mids, clipped chroma, uneven steps), or choosing which generation strategy to invoke (Leonardo for contrast-locked, Radix for semantic UI, MD3 for seeded design systems, Ant for cheap HSV ramps, iWantHue for max-distance categorical). Default engine is `coloraide`. Default working space is OKLCh.

## Contents

1. coloraide cheatsheet
2. Recipes (UI scale, sequential, diverging, categorical, alpha solve)
3. Algorithm tour (Leonardo, Radix, MD3, Ant)
4. Sources

---

## 1. coloraide cheatsheet

Import once: `from coloraide import Color`.

```python
# Parse anything CSS Color 4 -> normalized Color
c = Color("#5a86d4")                       # hex
c = Color("oklch(70% 0.15 250)")           # oklch literal

# Hex <-> OKLCh
L, C, H = Color("#5a86d4").convert("oklch").coords()
hex_  = Color("oklch", [L, C, H]).convert("srgb").to_string(hex=True)

# Gamut map (CSS Color 4: reduce C, hold L+H) before serializing to sRGB
hex_ = Color("oklch", [0.7, 0.4, 250]).fit("srgb", method="oklch-chroma").to_string(hex=True)

# In-gamut test (use to drive chroma envelopes)
ok = Color("oklch", [L, C, H]).in_gamut("srgb")

# Delta E 2000 (perceptual difference; >= ~2 is human-noticeable)
dE = Color("#5a86d4").delta_e("#5a87d3", method="2000")

# WCAG 2.1 contrast ratio (1..21)
ratio = Color("white").contrast("#5a86d4", method="wcag21")

# APCA Lc (-108..108; sign = polarity; |Lc| 60 = body text floor, 90 = strong)
lc = Color("white").contrast("#1a1a1a", method="apca")

# CVD simulation (severity 0..1; types: protan, deutan, tritan)
sim = Color("#5a86d4").filter("cvd", method="brettel", type="deutan", amount=1.0)

# Interpolate N steps in OKLCh (hue takes shorter arc by default)
ramp = Color.steps(["#0d47a1", "#e3f2fd"], steps=11, space="oklch")

# Bezier easing through control points, then sample
ramp = Color.interpolate(stops, space="oklab", method="bspline")
samples = [ramp(t) for t in (i/10 for i in range(11))]

# Force hue path (longer/shorter/increasing/decreasing) for diverging arcs
ramp = Color.steps([a, b], steps=9, space="oklch", hue="longer")
```

Notes: `coords()` returns normalized values (L 0..1, C ~0..0.4, H degrees). `fit()` is destructive; `clone().fit()` preserves the original. `Color.steps` produces evenly-parametrized samples; pair with `correctLightness`-style resampling (recipe below) when you need equal perceived L deltas.

---

## 2. Recipes

### 2a. 12-step UI scale (Radix-shaped, parabolic chroma)

```
inputs: hue H, base_bg (light/dark), key_color optional
fixed L curve (light theme): [0.99, 0.97, 0.94, 0.91, 0.87, 0.82, 0.76, 0.68, 0.58, 0.52, 0.42, 0.18]
chroma envelope: C(t) = C_peak * (1 - (2t - 1)^2)        # parabola, peak at mid
                 with C_peak ~ 0.18 (P3 wide-gamut: 0.24)
                 step 9 override: hold C at key_color's native chroma  (the "pure hue")
                 steps 11,12 override: clamp C low (text legibility)
for i in 1..12:
    t = (i-1)/11
    L = L_curve[i-1]
    C = chroma_envelope(t)
    color = OKLCh(L, C, H)
    color = gamut_map(color, "srgb")           # coloraide .fit(oklch-chroma)
    if i in (11, 12):
        enforce APCA(color vs scale[2]) >= {60, 90}
            by lowering L until target met (text steps)
emit scale[1..12]
```

### 2b. Sequential dataviz ramp

```
inputs: hue H, n (e.g. 9), L_start=0.98, L_end=0.20
        C_peak=0.18, C_end_factor=0.3
for i in 0..n-1:
    t = i / (n-1)
    L = L_start + (L_end - L_start) * t
    # parabolic peak + linear floor at endpoints (chroma collapses at L->0,1)
    C = C_peak * (1 - (2t-1)^2) + C_end_factor * C_peak * (2t-1)^2
    sample = gamut_map(OKLCh(L, C, H), "srgb")
optional: resample positions so L vs t is linear (chroma.js correctLightness):
    invert L(t) -> t(L); read samples at evenly spaced L
```

### 2c. Diverging ramp

```
inputs: hue_left, hue_right, n (odd recommended), neutral_L=0.97
require: |hue_right - hue_left| >= 120  (else categorical signal blurs)
half = n // 2
left  = sequential_ramp(hue_left,  half+1, L_start=0.20, L_end=neutral_L)
right = sequential_ramp(hue_right, half+1, L_start=neutral_L, L_end=0.20)
mid   = OKLCh(neutral_L, 0.01, (hue_left + hue_right)/2)   # near-gray
emit  left[:-1] + [mid] + right[1:]
constraints to enforce:
  - mirrored L: L(left[i]) == L(right[-1-i])
  - matched chroma envelopes (identical C(t) per arm)
  - midpoint chroma < 0.02
```

### 2d. Categorical max-distance (iWantHue style)

```
inputs: N, constraint box {H_range, C_range, L_range}, optional fixed seeds
1. dense-sample candidates inside box (~5000 points), convert to OKLab
2. k-means with k=N seeded by fixed seeds (or kmeans++)
3. take centroids -> snap each back into sRGB gamut
4. optional force-vector relaxation in OKLab:
       repulsion ~ 1/dist^2 between all pairs, integrate until max_displacement < eps
       project each point back into constraint box per step
5. order by hue for stable legend assignment
```

### 2e. Alpha-variant solve (Radix alpha twins)

Goal: given solid `S` and page background `B`, find `(C, alpha)` with maximum alpha such that `alpha*C + (1-alpha)*B = S` and `C` stays in sRGB gamut.

```
solve per-channel (sRGB linear): C_k = (S_k - (1-a)*B_k) / a
binary-search alpha in (0, 1]:
    for trial alpha a:
        C = (S - (1-a)*B) / a       # vector op in linear sRGB
        if all(0 <= C_k <= 1):       # in gamut
            best = (C, a)
            try larger a (push alpha up)
        else:
            try smaller a
return best with C converted back to display sRGB
```

Tolerance ~1e-4 on alpha is plenty. For dark themes, `B` is the near-black page color, not pure black.

---

## 3. Algorithm tour

**Leonardo (Adobe).** Inverts the workflow: you specify *target contrast ratios* against a base, it returns colors that hit them. Builds a black -> key_colors -> white ramp in OKLCh / CAM02-UCS, samples densely, bisects for the swatch closest to each target ratio. Use when the deliverable is "WCAG-locked tokens at 1.5/3/4.5/7/12."

**Radix.** Hand-tuned but mechanically targeted. 12 steps with fixed semantic roles (1 app bg -> 12 high-contrast text). Steps 1-8 calibrated by perceived weight against step-2 reference; step 9 is the pure hue; steps 11-12 enforce APCA Lc >= 60/90 vs step 2. Alpha twins solved for max alpha that stays in gamut over the page bg. Use when the deliverable is a UI system with semantic slots.

**Material 3 (HCT).** Seeded design system. Convert source to HCT (CAM16 hue+chroma, L* tone), derive 5 palettes by hue rotation + chroma override (primary keeps source H, tertiary = H+60deg, neutrals at C=4/8), generate 13 tones per palette by holding (H,C) and varying T, gamut-snapping each. Use when seeding from one brand color and emitting Android / M3 token sets.

**Ant Design.** Cheapest path to a 10-step ramp. Pure HSV with fixed deltas: ±2 deg hue, sat ±0.16/0.05, value ±0.05/0.15 per step from a primary; flips rotation outside the 60-240 deg band to mimic Bezold-Brücke. No perceptual uniformity, no contrast guarantees. Use only when a Radix-grade scale is overkill and the brand is fixed.

Tour skipped in deeper detail (see `06-generation-algorithms.md`): Tailwind v4 (one-time hand-tuned OKLCh re-author, no algorithm), Coolors (harmony rotation, no ML), Khroma (per-user shallow NN over a curated pool), Huemint (transformer + diffusion conditioned on a contrast matrix), iWantHue (k-means + force-vector in LAB; covered as recipe 2d above), chroma.js Bezier + correctLightness (covered as resample step in 2b).

---

## 4. Sources

- Adobe Leonardo: https://github.com/adobe/leonardo , https://leonardocolor.io/
- Radix Colors: https://www.radix-ui.com/colors/docs/palette-composition/scales
- Material 3 HCT: https://m3.material.io/styles/color/system/how-the-system-works , https://github.com/material-foundation/material-color-utilities
- Tailwind v4 OKLCh: https://tailwindcss.com/blog/tailwindcss-v4
- Ant Design generate: https://github.com/ant-design/ant-design-colors/blob/main/src/generate.ts
- Huemint: https://huemint.com/about/
- iWantHue: https://github.com/medialab/iwanthue
- chroma.js: https://gka.github.io/chroma.js/ , http://www.vis4.net/blog/mastering-multi-hued-color-scales/
- ColorBrewer: https://colorbrewer2.org/
- coloraide: https://facelessuser.github.io/coloraide/ , https://github.com/facelessuser/coloraide
- Color.js (CSS WG reference): https://github.com/color-js/color.js
- culori (OKLCh-native JS): https://github.com/Evercoder/culori
- OKLab/OKLCh (Ottosson 2020): https://bottosson.github.io/posts/oklab/
- CSS Color 4 gamut mapping: https://www.w3.org/TR/css-color-4/#binsearch
- APCA: https://github.com/Myndex/apca-w3
