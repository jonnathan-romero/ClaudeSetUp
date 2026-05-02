# Palette Failure Modes

Detect, warn, prevent. Each entry: symptom, cause, fix, numerical threshold to flag.

## Contents

1. [Yellow Problem (HSL/HSV lightness lies)](#yellow-problem)
2. [Oversaturated Darks](#oversaturated-darks)
3. [Hue Drift Across A Scale](#hue-drift)
4. [Insufficient Contrast](#insufficient-contrast)
5. [Dark-Mode Inversion Gotchas](#dark-mode-inversion)
6. [Rainbow For Ordered Data](#rainbow-for-ordered-data)
7. [Categorical Overload](#categorical-overload)
8. [Red/Green For Status](#red-green-status)
9. [Chroma-Mismatched Harmonies](#chroma-mismatched-harmonies)
10. [Brand-Color Shoehorning](#brand-color-shoehorning)
11. [Pure Black / Pure White](#pure-black-pure-white)
12. [All-Same-Chroma Trap](#all-same-chroma)
13. [Muddy Mid-Tones (wrong interp space)](#muddy-mid-tones)
14. [Cultural Mismatch](#cultural-mismatch)
15. [Print / Grayscale Failure](#print-grayscale-failure)

[Quick Triage](#quick-triage) at bottom.

---

### Yellow Problem
<a id="yellow-problem"></a>
**Symptom.** A 10-step ramp made by varying HSL `L` produces uneven jumps; yellow glows, blue is a black hole.

**Cause.** HSL `L` is a geometric mean of gamma-encoded sRGB channels — no model of luminance. `hsl(60 100% 50%)` (yellow) has Y ≈ 0.93; `hsl(240 100% 50%)` (blue) has Y ≈ 0.07. In OKLCh: yellow `L* ≈ 0.97`, blue `L* ≈ 0.45` — a 0.52 gap from "identical" HSL `L`.

**Fix.** Generate ramps in OKLCh / CIELAB. Pick a target `L*` series (e.g. `95, 88, 80, 70, 60, 50, 40, 30, 22, 14`); chroma + hue follow. Validate ΔL* between adjacent steps is monotone and roughly equal. Convert HSL input immediately and warn.

**Flag.** Input uses HSL/HSV for ramp generation, OR adjacent-step `|ΔL*|` varies by `>30%` of the mean step.

---

### Oversaturated Darks
<a id="oversaturated-darks"></a>
**Symptom.** Saturated dark blue button reads radioactive in dark mode; `oklch(0.2 0.2 264)` looks muddy/dirty rather than rich.

**Cause.** Chroma sensitivity peaks mid-`L*`; at low `L*` saturated colors smear and sit near sRGB's narrow dark-gamut edge. The eye can't separate chroma from dim luminance.

**Fix.** Apply chroma falloff at low `L*`. Rule of thumb: at `L* < 0.3`, cap chroma at `C_max * (L* / 0.3) ^ 0.7`. A "rich black" navy is `oklch(0.18 0.04 264)`, NOT `oklch(0.18 0.20 264)`. Mirror at the very high end — pastels need lower `C*` than mid-tones.

**Flag.** Any swatch with `L* < 0.30` AND `C* > 0.10` → flag oversaturated dark. Also flag `L* > 0.92` AND `C* > 0.12`.

---

### Hue Drift
<a id="hue-drift"></a>
**Symptom.** "Blue" 12-step scale drifts purple at step-50, teal at step-900. "Red" goes orange light, brown dark.

**Cause.** sRGB is a small lopsided gamut. Max achievable `C*` depends strongly on hue; holding hue+chroma constant while varying `L*` causes silent clip/desaturate. "Max chroma at every L*" hue-drifts because the gamut boundary's hue isn't your requested hue.

**Fix.** (1) **Chroma-as-function-of-L*.** Define `C*(L*)` envelope per hue family, tracking in-gamut max minus a `~10–15%` safety margin. (2) **Gamut-aware mapping.** CSS Color 4 `gamut-map` or `coloraide.fit('oklch-chroma')` — preserves `L*`+hue, reduces `C*`. Never clip in sRGB directly.

**Flag.** Any step that required `>5%` chroma reduction OR `>2°` hue change to fit sRGB.

---

### Insufficient Contrast
<a id="insufficient-contrast"></a>
**Symptom.** `step-500` text on `step-300` background "feels brand-y." Contrast 1.8:1. Fails WCAG AA.

**Cause.** Designers pick by hue similarity, forget `L*` separation. Neighboring scale steps differ by ΔL* ≈ 8–10 → ratio ~1.5–2.0. AA body text needs ΔL* ≥ 50 between fg/bg.

**Fix.** Bake contrast pairs into the scale's contract (Radix steps 11/12 are explicitly text vs steps 1–3 backgrounds). Compute APCA Lc and WCAG ratio for every pair; emit a compatibility matrix. Prefer APCA: `Lc 60+` body, `Lc 75+` fine text.

**Flag.** Any claimed text/bg pair with WCAG `< 4.5:1` (body) or `< 3:1` (large/UI), OR APCA `|Lc| < 60` for body.

---

### Dark-Mode Inversion
<a id="dark-mode-inversion"></a>
**Symptom.** Light palette inverted via `L*_new = 1 - L*_old`. Brand color now over-saturated against dark, accents glow, text too bright.

**Cause.** **Helmholtz–Kohlrausch:** saturated colors look lighter than `L*` predicts, more so on dark backgrounds — chroma that read "balanced" on white reads "screaming" on black. Also, dark-mode surfaces need slight chroma (`C* ≈ 0.01–0.02` of brand hue, "rich black"), not pure inversion.

**Fix.** Design dark mode as a separate scale. Mirror `L*` mostly, but **reduce `C*` by 20–40%** for the same role, with heavier falloff at the inverted dark end.

**Flag.** Dark variant of a role where `C*_dark ≥ C*_light` for the same `|L* − 0.5|` distance → flag missing chroma reduction (expect `C*_dark / C*_light ∈ [0.6, 0.8]`).

---

### Rainbow For Ordered Data
<a id="rainbow-for-ordered-data"></a>
**Symptom.** Heatmap uses jet (red→yellow→green→cyan→blue). Phantom contour bands at yellow and cyan.

**Cause.** Rainbow is non-monotone in luminance — yellow much lighter than red/blue. Equal data steps map to unequal `L*` with reversals; the eye reads `L*` changes as edges. Also fails CVD and grayscale.

**Fix.** Use a perceptually uniform sequential map: `viridis`, `magma`, `inferno`, `plasma`, `cividis`, or any OKLCh ramp with monotone `L*`. Diverging data → balanced two-hue map (RdBu, BrBG) with neutral pale midpoint and matched `|ΔL*|` arms. Refuse to emit rainbow/jet for ordered data.

**Flag.** Sequential map with non-monotone `L*` (any sign change in `ΔL*`) OR diverging map where `|max(L*) − mid| / |mid − min(L*)|` deviates from `1.0` by `>15%`.

---

### Categorical Overload
<a id="categorical-overload"></a>
**Symptom.** 14-series stacked bar in 14 colors. Series 4 vs series 11 indistinguishable.

**Cause.** Pre-attentive color discrimination tops out at `7–8` hues for unfamiliar data, `~5–6` for small marks (Healey, Ware, Munzner). Beyond → users read the legend per datum.

**Fix.** Cap categorical palettes at `8`. ColorBrewer qualitative maxes at 12 but warns `>8` is unreliable. For more categories: group into hue families with small multiples or filtering instead of more colors.

**Flag.** Categorical count `> 8`, OR pairwise OKLCh ΔE2000 `< 15` between any two members (small-mark distinguishability threshold).

---

### Red/Green For Status
<a id="red-green-status"></a>
**Symptom.** Pass/fail uses red+green only. ~6% of men with deuter/protanopia see them as the same olive-tan. Traffic lights unreadable for the most common CVD.

**Cause.** Long-wave (red/green) confusions: `~6%` of men. Short-wave (blue/yellow): `<1%`. Hue-only encoding along these axes loses information.

**Fix.** Always pair color with a secondary encoding: shape (✓/✗), label, position, texture. Pull categorical hues from CB-safe sets (ColorBrewer "colorblind safe", Wong's 8-color, IBM accessible). Auto-run deuter/prot/tritan simulation (`coloraide cvd-sim`).

**Flag.** Any encoding that conveys status/category through hue alone, OR any pair with simulated-CVD ΔE2000 `< 15` under deuteranopia or protanopia.

---

### Chroma-Mismatched Harmonies
<a id="chroma-mismatched-harmonies"></a>
**Symptom.** Primary `oklch(0.6 0.22 264)` paired with secondary `oklch(0.6 0.06 30)`. Primary screams; secondary whispers. Reads unintentional.

**Cause.** Two roles with very different `C*` and no story → eye reads high-`C*` as "active," low-`C*` as "broken/disabled." Vivid+muted is legitimate only when one is clearly subordinate and the gap reads as deliberate.

**Fix.** When designing harmonies (analogous, complementary, triadic), match `L*` and `C*` within tolerance (typically `±5` in `L*`, `±0.03` in OKLCh `C*`) unless one color is explicitly a neutral or accent.

**Flag.** Non-neutral, non-accent palette where `max(C*) / min(C*) > 3`.

---

### Brand-Color Shoehorning
<a id="brand-color-shoehorning"></a>
**Symptom.** Brand `oklch(0.62 0.18 28)` forced to be step-500 of a 12-step scale. Step-100 looks pink-salmon; step-900 looks burgundy-brown.

**Cause.** Brand chosen for emotional/positional reasons, not gamut-aware scale fit. Its `(L*, C*, h)` may be at an awkward spot — too saturated to extrapolate, or at a hue where sRGB is narrow. Forcing a fixed slot makes the rest of the scale ugly.

**Fix.** (1) **Anchor, don't pin.** Generate scale from a hue+chroma envelope; brand may land between step-500 and step-600; expose as `--brand-primary` separately. (2) **Re-tune for systems use.** Ship "brand color" + slightly-retuned "UI primary" nudged in `L*`/`C*` to land cleanly on a step (GitHub, Atlassian, Stripe).

**Flag.** Brand color `L*` or `C*` differs from the closest envelope-generated step by `> 0.03` in `L*` or `> 0.04` in `C*` while pinned to that step.

---

### Pure Black Pure White
<a id="pure-black-pure-white"></a>
**Symptom.** Long-form body in `#000` on `#fff`. Eye fatigue, harsh edges; OLED dark mode `#fff` on `#000` smears with halation/bloom.

**Cause.** `#000` on `#fff` is `~21:1` — too much for sustained reading per APCA and practitioner consensus. Pure white on OLED black causes pupil contraction and glyph bloom; pure black eliminates the chroma cue that makes a "rich black" feel intentional.

**Fix.** Default body to rich near-black (`oklch(0.15 0.02 264)`-ish) on off-white (`oklch(0.98 0.005 80)`-ish) — slight cool tint dark, slight warm tint light. Reserve `#000`/`#fff` for marks where maximum punch is intentional (logos, keylines, e-ink).

**Flag.** Body-text role uses `#000000` or `#FFFFFF`, OR APCA `|Lc| > 90` on body text/background pair.

---

### All-Same-Chroma
<a id="all-same-chroma"></a>
**Symptom.** Every role at `C* ≈ 0.18` regardless of hue/role. Cartoonish, "Bootstrap demo 2014."

**Cause.** Mature palettes vary `C*` by role (neutrals near 0, surfaces low, primaries mid, accents high) AND by hue (sRGB yellows peak lower than reds — equal-numerical-`C*` yellows look weak, reds loud). Equal `C*` collapses hierarchy.

**Fix.** Define `C*` per role and per hue family:
- Neutrals: `C* ∈ [0, 0.02]`
- Surfaces / backgrounds: `C* ∈ [0.005, 0.04]`
- Body text: `C* ∈ [0.01, 0.05]`
- Primary actions: `C* ∈ [0.10, 0.18]`
- Accents / data-viz vivids: `C* ∈ [0.18, 0.30]`
- Disabled / muted: `C* ∈ [0.02, 0.06]`

**Flag.** Palette `C*` standard deviation (excluding neutrals) `< 0.04`.

---

### Muddy Mid-Tones
<a id="muddy-mid-tones"></a>
**Symptom.** Red→green gradient passes through gray-brown. Blue→yellow passes through dirty olive.

**Cause.** Linear interpolation in sRGB averages gamma-encoded values *and* takes a chord through the chroma cylinder rather than around it — under-mixes light, desaturates the midpoint. HSL "shortest hue path" still passes through low-`C*` yellow-green for red→green.

**Fix.** Interpolate in OKLCh / LCh; choose hue-arc direction explicitly. CSS Color 4: `color-mix(in oklch shorter hue, red, green)`. **Shorter hue** for adjacent hues. **Longer hue** to preserve a vivid mid-stop on a chosen side. **Increasing/decreasing hue** for a directional series that mustn't double back.

**Flag.** Gradient interpolated in sRGB or HSL when endpoints have hue difference `> 60°`, OR gradient midpoint `C* < 0.5 * min(C*_endpoints)`.

---

### Cultural Mismatch
<a id="cultural-mismatch"></a>
**Symptom.** Finance app ships globally with red=down, green=up. In CN/HK/TW/KR/JP, red is positive/auspicious and green often signals loss — encoding actively misleads. White-as-clean reads funereal in much of East Asia.

**Cause.** Color is a socially-coded signal. Defaults baked in by the original culture propagate without question because that culture *is* the unmarked default to its designers.

**Fix.** Treat semantic color (success/danger/warning/info) as a *role* mapped to a token. Document the role-to-hue table; require explicit per-market override. Don't bake "green = good" — bake `success = $color-positive`; let `$color-positive` be locale-dependent. Bloomberg, TradingView, Asia-fintechs ship red-up/green-down skins.

**Flag.** Hard-coded hue for any semantic role (`success`, `danger`, `warning`, `info`) without a locale override hook.

---

### Print Grayscale Failure
<a id="print-grayscale-failure"></a>
**Symptom.** Chart fine on screen; B&W laser/photocopy collapses 3 of 7 series to indistinguishable mid-grays.

**Cause.** Palette relied on hue alone for series separation. When `C* → 0`, only `L*` remains; any two colors at similar `L*` become identical.

**Fix.** **Value-distinguishability check.** Convert to grayscale (`oklch(L 0 0)` per color) and require ΔL* ≥ 8 between any two series. When impossible for the count, supplement with line patterns / markers / hatching. Auto-emit grayscale preview + min-ΔL* metric.

**Flag.** Categorical palette with any pair `|ΔL*| < 0.08` (≈8 on a 0–100 scale) after chroma stripped.

---

## Quick Triage

- "Ramp looks uneven, yellow glows" → §1 [Yellow Problem](#yellow-problem)
- "Dark mode looks muddy / radioactive" → §2 [Oversaturated Darks](#oversaturated-darks)
- "Blue scale goes purple/teal at extremes" → §3 [Hue Drift](#hue-drift)
- "Text is hard to read on tinted bg" → §4 [Insufficient Contrast](#insufficient-contrast)
- "Inverted dark mode, accents glow" → §5 [Dark-Mode Inversion](#dark-mode-inversion)
- "Heatmap has phantom bands" → §6 [Rainbow For Ordered Data](#rainbow-for-ordered-data)
- "Can't tell series apart in chart" → §7 [Categorical Overload](#categorical-overload) or §15 [Print/Grayscale](#print-grayscale-failure)
- "Pass/fail uses red+green" → §8 [Red/Green For Status](#red-green-status)
- "Two brand colors clash, look unintentional" → §9 [Chroma-Mismatched Harmonies](#chroma-mismatched-harmonies)
- "Light/dark steps look pink-salmon or brown" → §10 [Brand-Color Shoehorning](#brand-color-shoehorning)
- "Body copy feels harsh / OLED bloom" → §11 [Pure Black/Pure White](#pure-black-pure-white)
- "Palette looks juvenile / Bootstrap-y" → §12 [All-Same-Chroma](#all-same-chroma)
- "Gradient passes through mud/gray" → §13 [Muddy Mid-Tones](#muddy-mid-tones)
- "Red-up/green-down feedback in Asia market" → §14 [Cultural Mismatch](#cultural-mismatch)
- "Chart unreadable when photocopied" → §15 [Print/Grayscale](#print-grayscale-failure)

---

## Sources

- Ottosson OKLab: <https://bottosson.github.io/posts/oklab/>, gamut clipping <https://bottosson.github.io/posts/gamutclipping/>, color picker <https://bottosson.github.io/posts/colorpicker/>
- CSS Color 4 hue interp + gamut map: <https://www.w3.org/TR/css-color-4/#hue-interpolation>, <https://www.w3.org/TR/css-color-4/#gamut-mapping>
- WCAG 2.2: <https://www.w3.org/TR/WCAG22/#contrast-minimum>; APCA: <https://github.com/Myndex/SAPC-APCA>
- Stripe: <https://stripe.com/blog/accessible-color-systems>; Radix: <https://www.radix-ui.com/colors/docs/palette-composition/scales>; Primer: <https://primer.style/foundations/color/overview/>
- Material 3: <https://m3.material.io/styles/color/the-color-system/color-roles>; Carbon: <https://carbondesignsystem.com/elements/color/overview/>
- ColorBrewer: <https://colorbrewer2.org/>; Wong (CVD): <https://www.nature.com/articles/nmeth.1618>; Crameri: <https://www.nature.com/articles/s41467-020-19160-7>
- Moreland: <https://www.kennethmoreland.com/color-advice/>; viridis/BIDS: <https://bids.github.io/colormap/>; Munzner VAD: <https://www.cs.ubc.ca/~tmm/vadbook/>; Tableau: <https://research.tableau.com/sites/default/files/2016-colors.pdf>
- Bloomberg red/green: <https://www.bloomberg.com/professional/blog/red-or-green-color-coding-conventions-around-the-world/>; Datawrapper: <https://blog.datawrapper.de/colors-for-data-vis-style-guides/>
- Helmholtz–Kohlrausch: <https://en.wikipedia.org/wiki/Helmholtz%E2%80%93Kohlrausch_effect>; Lyft ColorBox: <https://lyft-colorbox.herokuapp.com/>; Refactoring UI: <https://refactoringui.com/previews/building-your-color-palette/>; Ian Storm Taylor: <https://ianstormtaylor.com/design-tip-never-use-black/>
