# Accessibility & Contrast Reference

## When to consult this

Pull this file in for: any palette critique; regulated, medical, or government work (Section 508, EN 301 549, ADA-adjacent); audit or compliance tasks; dark-mode validation; or whenever a CVD claim ("colorblind-safe") is asserted.

## Table of contents

1. WCAG 2.1 contrast — formula and thresholds
2. APCA / WCAG 3 — Lc thresholds (the actionable table)
3. Color blindness — types, prevalence, simulation models
4. Practical palette implications
5. Tools
6. Companion scripts
7. Sources

---

## 1. WCAG 2.1 contrast

### Formula

Gamma-decode each sRGB channel, then weighted sum:

```
Cs = C / 255
Clin = Cs / 12.92                       if Cs <= 0.03928
Clin = ((Cs + 0.055) / 1.055) ** 2.4    otherwise
L    = 0.2126 * Rlin + 0.7152 * Glin + 0.0722 * Blin
ratio = (L_lighter + 0.05) / (L_darker + 0.05)
```

Range: 1:1 to 21:1. The `+ 0.05` is a flare/ambient-light constant, not a fudge factor.

### Thresholds

| Ratio  | Level | Applies to                                                   | SC      |
|--------|-------|--------------------------------------------------------------|---------|
| 3:1    | AA    | Large text (>= 18pt / 24px, or 14pt / 18.66px bold)          | 1.4.3   |
| 3:1    | AA    | Non-text UI components, focus rings, graphical objects       | 1.4.11  |
| 4.5:1  | AA    | Normal body text                                             | 1.4.3   |
| 4.5:1  | AAA   | Large text                                                   | 1.4.6   |
| 7:1    | AAA   | Normal body text                                             | 1.4.6   |

### Known weaknesses

- Over-flags dark-on-dark: `+0.05` flare term dominates, makes visibly distinct dark grays "fail" 4.5:1.
- Under-flags light-on-light: pale yellow on white can pass numerically and still be unreadable.
- Weight-insensitive: 700-weight 14px and 400-weight 14px treated identically below the large-text cutoff.

These are the explicit motivation for APCA.

---

## 2. APCA (WCAG 3 candidate)

Signed `Lc` value, range ~ -108 to +106. Sign = polarity (positive: dark-on-light; negative: light-on-dark). Magnitude = legibility. Polarity-asymmetric: same `|Lc|` is *not* equally readable in both directions.

### Bronze Simple Mode thresholds

| `|Lc|`   | Use case                                                          | Tier   |
|----------|-------------------------------------------------------------------|--------|
| >= 90    | Preferred body text (any size)                                    | Bronze |
| >= 75    | Body text minimum (>= 16px / 400)                                 | Bronze |
| >= 60    | Content text >= 24px, or >= 18px / 700                            | Bronze |
| >= 45    | Large headlines, non-content text (>= 36px)                       | Bronze |
| >= 30    | Non-text UI components (analog of WCAG 1.4.11)                    | Bronze |
| < 15     | Invisible / decorative only                                       | --     |

Full font-size x weight lookup: https://readtech.org/ARC/tests/visual-readability-contrast/?tn=criterion.

### Posture for 2026

- WCAG 2.1 AA = compliance floor.
- APCA Lc = quality signal (esp. dark mode).
- WCAG 3 / Silver still Working Draft; APCA not yet committed as the method but is the leading candidate. Adopted in GitHub Primer and Adobe systems.

---

## 3. Color blindness

X-linked recessive, so male-skewed (Northern European numbers): protan ~1% of males (red-weak/blind); deutan ~5% of males (green-weak, the most common form); tritan ~0.01% (rare, autosomal); achromatopsia / monochromacy ~0.003% (very rare). Combined ~8% males, ~0.5% females have some red-green deficiency — designing for **deuteranopia** covers the worst case.

### Simulation models

- **Brettel / Viénot / Mollon (1997, 1999)** — projects colors onto a plane in LMS cone space; 1997 covers all three dichromacies, 1999 is faster protan/deutan-only.
- **Machado, Oliveira, Fernandes (2009)** — single 3x3 RGB matrix per CVD type x severity (0–100%); handles anomalous trichromacy. Modern default; most accurate, most flexible.

---

## 4. Practical palette implications

### Status colors must survive deuteranopia

Red/green status pairs collapse for deutan viewers. Encode redundantly: shape (icon), position, or direct label — color reinforces, never carries alone. WCAG SC 1.4.1 ("Use of Color") is the formal rule.

Validate any invented categorical palette under deuteranopia + protanopia simulation; require pairwise CIEDE2000 ΔE > 20. Prefer pre-validated references: Paul Tol, ColorBrewer 2.0 (colorblind-safe filter), Okabe-Ito 8-color.

### Contrast matrix workflow

For any palette > a handful of tokens, the only reliable check is a **full pairwise matrix**: rows = background tokens (`bg.canvas`, `bg.subtle`, `bg.muted`, `bg.emphasis`, `bg.inverse`); columns = foreground tokens (`fg.default`, `fg.muted`, `fg.subtle`, `fg.accent`, `fg.danger`). Every cell shows WCAG ratio + APCA Lc, pass/fail at 3 / 4.5 / 7 (or Lc 60 / 75 / 90). Catches the "muted reads on canvas, disappears on subtle" class of bug. Borders, dividers, icon strokes, focus rings need checking against **every** surface they can land on.

### The dark-mode trap

Palettes tuned on white routinely fail in dark mode:

- WCAG `+0.05` flare penalizes dark-on-dark — many tokens that pass 4.5:1 on white hit ~3.5:1 on `#0F172A`.
- Saturated colors flip: a vivid red is readable on white, glares/bleeds on near-black. Desaturate and lighten — do not invert.
- Brand primary often needs **two** dark-mode variants (one for backgrounds, one for foregrounds).

Never auto-derive a dark palette by inverting lightness. Design dark tokens explicitly. Re-run the contrast matrix against dark surfaces.

---

## 5. Tools

| Tool                              | Use                                                                       |
|-----------------------------------|---------------------------------------------------------------------------|
| WebAIM Contrast Checker           | Canonical WCAG 2.1 single-pair validator                                  |
| APCA Calculator (myndex.com)      | Official APCA, with font-size x weight thresholds                         |
| Stark (Figma/Sketch/browser)      | WCAG + APCA + CVD simulation on live designs                              |
| Sim Daltonism (macOS)             | Real-time CVD filter over a screen region                                 |
| Color Oracle (cross-platform)     | Full-screen Brettel-based CVD simulator                                   |
| axe-core / axe DevTools           | Automated WCAG 2.1 contrast scan over a live page                         |
| Chrome DevTools contrast lens     | Built into color picker; AA/AAA lines, APCA toggle in experiments         |

---

## 6. Companion scripts

Pointer-only — see each script's own `--help` for arguments.

- `scripts/check_contrast.py` — compute WCAG 2.1 ratio and APCA Lc for a pair, or a full pairwise matrix over a token set. Use for the matrix workflow in Section 4.
- `scripts/simulate_cvd.py` — apply Machado 2009 (default) or Brettel 1997 to a palette / image; emits the simulated swatch grid. Use for deutan/protan/tritan validation in Sections 3–4.

---

## Sources

- WCAG 2.1: https://www.w3.org/TR/WCAG21/#contrast-minimum
- Relative luminance: https://www.w3.org/WAI/GL/wiki/Relative_luminance
- Non-text contrast (1.4.11): https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
- Use of Color (1.4.1): https://www.w3.org/WAI/WCAG21/Understanding/use-of-color.html
- APCA repo / spec: https://github.com/Myndex/SAPC-APCA
- APCA calculator: https://www.myndex.com/APCA/
- APCA readability criterion: https://readtech.org/ARC/tests/visual-readability-contrast/?tn=criterion
- WCAG 3 draft: https://www.w3.org/TR/wcag-3.0/
- Primer accessibility: https://primer.style/foundations/color/accessibility
- Brettel/Viénot/Mollon 1997: https://www.researchgate.net/publication/2811373_Computerized_simulation_of_color_appearance_for_dichromats
- Machado/Oliveira/Fernandes 2009: https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html
- Sharpe et al. 1999 (CVD prevalence) — summarized at https://en.wikipedia.org/wiki/Color_blindness#Epidemiology
- Paul Tol palettes: https://personal.sron.nl/~pault/
- ColorBrewer 2.0: https://colorbrewer2.org/
- Okabe-Ito: https://jfly.uni-koeln.de/color/
- DaltonLens-Python: https://github.com/DaltonLens/DaltonLens-Python
