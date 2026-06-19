---
name: colors
description: 'Generates and critiques color palettes — UI scales, brand palettes, dataviz colormaps — using OKLCh and color theory. ALWAYS trigger when the user mentions palette, color scheme, design tokens, brand colors, accent color, OKLCh, WCAG contrast, APCA, color blindness, dark mode colors, Tailwind colors, Radix Colors, Material Design 3, ColorBrewer, viridis, matplotlib colormap, or asks to "build a palette around #XXXXXX", "extract colors from this image", "is this palette accessible", or "what colors should I use for a [adjective] [product]". Computes via coloraide; explains color-theory reasoning. Do NOT trigger for image color editing in Photoshop, isolated hex lookups, or pure CSS layout questions unrelated to color choice.'
allowed-tools: Bash(uv run *), Read, Write
---

# Colors

Designs, generates, and critiques color palettes for UI, brand, and data visualization. Computes in OKLCh via `coloraide`; verifies accessibility with WCAG + APCA; simulates color-vision deficiency; renders previews. Outputs hex + OKLCh + role + contrast, with an explanation grounded in color theory rather than vibes.

## Choose the mode

Pick the mode that matches the user's input. If unclear, ask. Don't pick silently.

| User said... | Mode |
|---|---|
| "Build a palette around `#XXXXXX`" / "scale from this brand color" | A — Seed-color UI palette |
| "Calm fintech palette" / "warm editorial colors" / no starting hex | B — Mood-driven palette |
| Pasted a palette and asked if it's good / accessible / better | C — Critique |
| "Extract colors from this image/logo/screenshot" | D — Image extraction |
| "Sequential colormap" / "diverging palette" / "categorical chart colors" | E — Dataviz |

The skill uses the same OKLCh + accessibility machinery across all modes. The differences are inputs and output framing.

---

## Mode A — Seed-color UI palette

**Goal:** turn a single seed color into a 12-step semantic scale (light → dark) plus a paired dark-mode scale, with WCAG + APCA verified across the canonical foreground/background pairings.

**Steps:**
1. Convert the seed to OKLCh; record its L\*, C\*, h.
2. Decide where the seed sits in the scale. Tailwind, Radix, and Material 3 all place named brand near step 9, not step 5; mirror that unless told otherwise. The seed lives at whatever L\* it lives at — the rest of the scale extends from there. See [references/case-studies.md](references/case-studies.md).
3. Run the generator. It emits the palette JSON to stdout — redirect it to `palette.json`, which the downstream scripts read:
   ```
   uv run scripts/generate_scale.py --seed "#3B82F6" --name primary > palette.json
   ```
   Add `--dark` for the dark-mode pairing. Add `--system tailwind` (default), `--system radix`, or `--system material` to bias step-count and chroma curve to that convention.

   Always quote hex arguments — in fish and several other shells, an unquoted `#` starts a comment and the seed gets eaten. Same goes for the `--colors "#a,#b,#c"` arg in `simulate_cvd.py`.

   For near-grey seeds (`C* < 0.04` in OKLCh — slate / zinc / stone), the generator skips the chroma floor and emits a true neutral scale. Don't hand-tune chromatic palettes onto a near-grey seed; pair a chromatic primary with a separate neutral scale instead.
4. Run the contrast matrix:
   ```
   uv run scripts/check_contrast.py --palette palette.json
   ```
5. Inspect against [references/failure-modes.md](references/failure-modes.md). Common things to flag: oversaturated darks, hue drift at extremes, body text below APCA Lc 60.
6. Render swatches if the user wants a preview:
   ```
   uv run scripts/render_swatches.py --palette palette.json --out swatches.png
   ```

**Inline output template** (default — hex + OKLCh + role + contrast):
```
primary scale (light)
  step  hex       oklch                 role               apca-on-bg
  1     #f5f9ff   oklch(0.98 0.01 250)  app background
  2     #eaf2ff   oklch(0.95 0.03 250)  subtle background
  ...
  9     #3B82F6   oklch(0.65 0.18 250)  solid (brand)      Lc 78  ✓ body
  ...
  12    #0a1f3d   oklch(0.20 0.06 250)  high-contrast text Lc 96  ✓ AAA
```

If the user asks for code: see [references/output-formats.md](references/output-formats.md) for CSS custom properties, Tailwind v4 `@theme`, W3C design tokens, Swift, and Kotlin templates. Default to CSS custom properties unless told otherwise.

---

## Mode B — Mood-driven palette

**Goal:** turn a description ("calm fintech dashboard for older retail investors", "energetic kids' app") into 2–3 candidate palettes with rationale.

**Steps:**
1. Extract the actionable axes from the brief. The bands below are starting zones, not laws — see [references/meaning.md](references/meaning.md) for derivation, evidence, and when to break them.
   - **Activation** (calm ↔ energetic) → chroma. Low chroma reads quiet/restrained; high chroma reads loud/active. Reach for low-chroma when in doubt — over-saturation is the more common amateur mistake.
   - **Temperature** (warm ↔ cool) → hue family. Warm hues ~20–80°, cool ~200–280°. The warm/cool emotional split is one of the more empirically robust color-emotion findings; specific hue→emotion claims (e.g. "blue means trust") are convention, not fact.
   - **Formality** (playful ↔ restrained) → chroma variance across the palette. Playful palettes vary chroma widely; restrained palettes hold it close.
   - **Audience constraints** — older audiences need higher contrast; safety-critical contexts need CVD-survival; regulated industries (medical, financial) carry hue conventions that are cheaper to follow than fight.
2. Generate **2–3 candidates**, each with a short rationale (one sentence per axis decision). Use varied hue families to give the user a real choice, not three blues.
3. For each candidate, build the full UI scale via Mode A's generator. Show only steps 2, 5, 9, 11 inline; offer the full scale on request.
4. Always include APCA contrast for body text (step-11 on step-2) per candidate.

**Anti-pattern:** do not generate 3 candidates that vary only in hue. Vary in chroma posture or temperature too — give a real decision.

---

## Mode C — Critique

**Goal:** find what's wrong with a palette and propose fixes.

**Steps:**
1. Parse the palette and write it to `palette.json` in the shape the scripts expect: `{"name": "...", "steps": [{"hex": "#...", "role": "..."}, ...]}` (only `hex` is required per step). This is the same schema `generate_scale.py` emits.
2. Run the contrast matrix against expected pairings:
   ```
   uv run scripts/check_contrast.py --palette palette.json
   ```
3. Run CVD simulation for categorical / status colors:
   ```
   uv run scripts/simulate_cvd.py --colors "#3B82F6,#10B981,#EF4444" --out cvd.png
   ```
4. Walk [references/failure-modes.md](references/failure-modes.md) and flag every match with: name → symptom in this palette → fix. Common hits: oversaturated darks (high chroma persisting at low L\*), hue drift on extreme steps, red/green for status without secondary encoding, body text on a midtone background.
5. Propose concrete fixes as before/after (hex + OKLCh). Don't just diagnose.
6. If the user asks "why does this look bad," lead with the highest-impact issue and one sentence of color-theory reasoning. Tone: surgical, not preachy.

---

## Mode D — Image extraction

**Goal:** extract a palette from a photo, logo, screenshot, or moodboard, then either deliver as-is or build a UI scale around it.

**Steps:**
1. Ask what the image represents (logo / photo / screenshot / artwork) — output framing differs. See [references/image-extraction.md](references/image-extraction.md).
2. Extract:
   ```
   uv run scripts/extract_from_image.py path/to/image --k 6 --space oklab
   ```
   Defaults: weighted k-means in OKLab on a 50k-pixel sample. For logos with transparent backgrounds, add `--mask alpha`.
3. Filter near-duplicates (script does this with ΔE2000 ≥ 8 by default).
4. Sort by hue (default) or luminance (`--sort lstar`).
5. If the user wants a UI palette built around the extraction, pick the most-saturated cluster as the seed and run Mode A.
6. If the user wants a dataviz palette, hand off to Mode E: read the hue(s) of the dominant extracted cluster(s) from the output and pass them as `--hue` (sequential) or `--hues` (diverging) to `dataviz_palette.py`.

---

## Mode E — Dataviz palette

**Goal:** generate a perceptually uniform palette of the right *type* for the data.

**Picking the type** ([references/dataviz.md](references/dataviz.md)):

| Data shape | Type |
|---|---|
| Ordered, single direction (counts, density) | **Sequential** |
| Ordered, diverging from a midpoint (anomaly, deviation, pos/neg) | **Diverging** |
| Unordered identities (categories, clusters) | **Categorical** |
| Periodic (angle, time-of-day, phase) | **Cyclic** |

**Steps:**
1. Confirm the type. If the user says "rainbow" or "jet" for ordered data, push back — see [references/failure-modes.md](references/failure-modes.md) §"Rainbow for ordered data."
2. Generate:
   ```
   uv run scripts/dataviz_palette.py --type sequential --n 9 --hue 250
   uv run scripts/dataviz_palette.py --type diverging --n 11 --hues 250,30
   uv run scripts/dataviz_palette.py --type categorical --n 6 [--cvd-safe]
   ```
3. For categorical, default to `--cvd-safe` (uses Tol/Okabe-Ito-style spacing in OKLCh); cap n at 8 unless the user insists. Beyond 8, recommend secondary encoding.
4. Output: hex list + matplotlib snippet (`LinearSegmentedColormap` or `ListedColormap`) + L\* curve PNG + CVD simulation.
5. Reference defaults the user can choose instead of generating: viridis / cividis / Tol-vibrant / Okabe-Ito / ColorBrewer. Suggest these when the brief allows.

---

## Quality bars (apply to every output)

These run regardless of mode. Treat them as the floor, not the ceiling.

1. **Report values in OKLCh, not just hex.** Hex is for handoff; OKLCh is for understanding.
2. **Verify body-text contrast** with APCA (Lc ≥ 60 for body, ≥ 75 for fine text — APCA Bronze-tier guidance per the public threshold tables). WCAG 2.1 ratios are the compliance floor; APCA is closer to the perceptual truth. The contrast script reports both.
3. **Run CVD simulation** when the palette includes status colors (success/warning/error), categorical encoding, or red/green pairs. Don't ship status colors that fail deuteranopia.
4. **Explain the *why*** in 1–2 sentences per palette: which axis you optimized for, which tradeoff you made. The skill teaches as it builds — that's the point. Theory is in [references/color-spaces.md](references/color-spaces.md), [references/meaning.md](references/meaning.md).
5. **Flag known failure modes** by name when present. The full catalog with thresholds is in [references/failure-modes.md](references/failure-modes.md).

## Output: inline by default; files when warranted

Default output is inline (hex + OKLCh + contrast table + 1–2 sentences of reasoning). Write to disk only when:
- Generating a swatch PNG (`render_swatches.py` writes `swatches.png` in CWD).
- Generating CVD simulation images (`simulate_cvd.py` writes `cvd.png`).
- Generating an L\* curve / colormap preview for dataviz (script writes a preview PNG).
- The user asks for a specific code artifact (Tailwind config, design token JSON, Swift Color, Android XML). Then write the file in CWD with a sensible name.

Don't write files the user didn't ask for. Inline first.

## Scripts

All scripts live in `scripts/` and are self-contained `uv run`-style with PEP 723 inline metadata. Don't reinvent — invoke these:

| Script | Purpose |
|---|---|
| `generate_scale.py` | Seed color → 12-step OKLCh UI scale (light + dark variants). |
| `check_contrast.py` | Full WCAG + APCA contrast matrix for a palette. |
| `simulate_cvd.py` | Render a palette under protanopia/deuteranopia/tritanopia. |
| `render_swatches.py` | Render a labeled PNG swatch sheet. |
| `extract_from_image.py` | k-means in OKLab to extract a palette from an image. |
| `dataviz_palette.py` | Sequential / diverging / categorical / cyclic palettes with L\* diagnostics. |

Each script: `uv run scripts/<name>.py --help` for full options. The math is settled; don't recompute OKLCh stepping or contrast in inline Python — call the script.

## When deeper theory matters

Reach for the references when the task crosses into one of these zones:

- **Cross-mode palette (light/dark) or cross-medium (screen/print)** → [references/color-spaces.md](references/color-spaces.md) (CIELAB / OKLCh / CAM16 / HCT, gamut mapping).
- **Brand expansion / mood translation / culture-specific market** → [references/meaning.md](references/meaning.md) (harmony rules with critique, evidence-based color-emotion, cultural conventions).
- **Production design system** (component library, Figma, Tailwind config) → [references/ui-systems.md](references/ui-systems.md), [references/output-formats.md](references/output-formats.md).
- **Accessibility audit / regulated context** (medical, government) → [references/accessibility.md](references/accessibility.md).
- **"What did Linear/Stripe/Primer do?"** → [references/case-studies.md](references/case-studies.md).
- **Anything chart-shaped** → [references/dataviz.md](references/dataviz.md).
- **Pulling colors from an image** → [references/image-extraction.md](references/image-extraction.md).
- **A scale or pair looks wrong and the user can't articulate why** → [references/failure-modes.md](references/failure-modes.md).

## References

- [references/color-spaces.md](references/color-spaces.md) — OKLCh, CIELAB, HCT, gamut mapping, CIE/CAM16 foundations.
- [references/ui-systems.md](references/ui-systems.md) — Tailwind v4 / Radix / Material 3 / IBM Carbon / Apple HIG / convergent patterns.
- [references/generation.md](references/generation.md) — Algorithms (Leonardo, Radix, MD3, Ant) + `coloraide` cheatsheet.
- [references/dataviz.md](references/dataviz.md) — Sequential / diverging / categorical / cyclic; viridis, ColorBrewer, Tol, Okabe-Ito.
- [references/accessibility.md](references/accessibility.md) — WCAG 2.1, APCA / WCAG 3, color-vision deficiency.
- [references/failure-modes.md](references/failure-modes.md) — 15 named pitfalls with thresholds and fixes.
- [references/output-formats.md](references/output-formats.md) — CSS Color 4, design tokens (W3C DTCG), Tailwind v4, Style Dictionary, platform-native.
- [references/image-extraction.md](references/image-extraction.md) — k-means in OKLab, MMCQ, alpha masking, k-selection.
- [references/meaning.md](references/meaning.md) — Color harmony (with critique), cultural context, peer-reviewed color-emotion.
- [references/case-studies.md](references/case-studies.md) — Real-world palette decisions from Stripe, Linear, Vercel, Notion, Primer, Figma, Discord, Apple, Spotify.
