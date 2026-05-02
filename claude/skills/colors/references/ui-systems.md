# UI Palette Systems

How ten production design systems structure color. Distilled to drive defaults when generating UI palettes.

## Contents

- [When to consult this](#when-to-consult-this)
- [Tailwind CSS v4](#tailwind-css-v4)
- [Radix Colors](#radix-colors)
- [Material Design 3](#material-design-3)
- [Apple HIG](#apple-hig)
- [IBM Carbon](#ibm-carbon)
- [Adobe Spectrum 2](#adobe-spectrum-2)
- [Ant Design](#ant-design)
- [Open Color](#open-color)
- [USWDS](#uswds)
- [Cloudscape (AWS)](#cloudscape-aws)
- [Convergent patterns](#convergent-patterns)
- [What to default to in this skill](#what-to-default-to-in-this-skill)
- [Sources](#sources)

## When to consult this

Read this when generating a UI palette from scratch, aligning output to a named design system (Tailwind, Radix, Material 3, etc.), picking a numeric scale shape, choosing a working color space, or deciding how to ship dark mode and contrast variants. Skip for data-viz palettes, brand-only color picks, or single-accent selection.

## Tailwind CSS v4

- **Structure.** 11 steps per hue: `50, 100, 200, …, 900, 950`. Step `500` is the brand weight. Numeric, positional, no role contract. ~22 hue families incl. 5 neutrals.
- **Color space.** OKLCh (rebuilt in v4; v3 was sRGB hex).
- **Accessibility.** Implicit — equal step distance ≈ equal luminance distance across hues, no contractual pairings.
- **Dark mode.** `dark:` variant + manual swaps (`bg-white dark:bg-gray-900`). No auto-inversion.
- **Distinctive.** Every step exposed as a CSS custom property; slash-opacity (`bg-sky-500/50`) modulates alpha at the utility.

## Radix Colors

- **Structure.** 12-step semantic scale; each step has a contractual role: 1 app bg, 2 subtle bg, 3–5 UI element bg (rest/hover/active), 6 subtle border, 7 UI border, 8 strong border / focus, 9 solid, 10 solid hover, 11 low-contrast text, 12 high-contrast text.
- **Color space.** P3-aware perceptual; published as sRGB hex + `display-p3()`. Hand-tuned per step.
- **Accessibility.** APCA-tuned. Step 11 ≥4.5:1 (AA body); step 12 ≥7:1 (AAA).
- **Dark mode.** Paired `*Dark` scale; step N retains role across modes. Aliasing pattern: semantic vars → mode-specific scale.
- **Distinctive.** Each hue ships solid + alpha, light + dark (4 variants). Theme-invariant `blackA`/`whiteA` for shadows/scrims.

## Material Design 3

- **Structure.** 6 tonal palettes (`primary`, `secondary`, `tertiary`, `neutral`, `neutral-variant`, `error`) at tones `0, 10, 20, …, 90, 95, 99, 100`. ~30 color roles (`primary`/`on-primary`/`primary-container`/…) pick tones per scheme.
- **Color space.** HCT (Hue, Chroma, Tone) — CAM16 hue/chroma + L*-style tone.
- **Accessibility.** Role pairings tone-spaced for ≥4.5:1. Standard / medium-contrast / high-contrast schemes ship together.
- **Dark mode.** Same tonal palette, different tone per scheme. Light primary ≈ tone 40, dark ≈ tone 80; pairs are tone-symmetric around 50.
- **Distinctive.** Dynamic Color — algorithm derives all 6 palettes + role map for both schemes from a single seed (or wallpaper).

## Apple HIG

- **Structure.** Two layers. Single-color system accents (`systemBlue`, `systemRed`, …, `systemGray`) — not scales. Four-step hierarchical scales for labels/fills/backgrounds (`label`, `secondaryLabel`, `tertiaryLabel`, `quaternaryLabel`).
- **Color space.** Display P3 authoring; sRGB fallback.
- **Accessibility.** Tuned for WCAG AA against paired backgrounds. OS-level Increase Contrast and Reduce Transparency shift values automatically.
- **Dark mode.** Built into the token. `UIColor.systemBackground` resolves to one of {light, light-elevated, dark, dark-elevated}. No separate dark token.
- **Distinctive.** Semantic-mandatory; "elevated" appearance for stacked surfaces is a first-class state.

## IBM Carbon

- **Structure.** 12-grade core scale per hue (`Black, 100, 90, …, 20, 10, White`; 100 = darkest, inverse of USWDS). Large semantic token set (`background`, `layer-01/02/03`, `text-primary`, `support-error`, …) plus a layering model.
- **Color space.** sRGB hex, hand-tuned.
- **Accessibility.** Tokens designed in pairs (text-on-layer, border-on-layer); every legitimate combination meets WCAG AA. Illegal combos aren't defined.
- **Dark mode.** Four bundled themes — `white`, `g10` (light), `g90` (soft dark), `g100` (true dark). Layer tokens lighten with depth in dark themes.
- **Distinctive.** Theme-agnostic tokens: `text-secondary` resolves to a different gray per theme but means the same role.

## Adobe Spectrum 2

- **Structure.** 14 tints/shades per hue (`blue-100 … blue-1400`) plus parallel gray scale. Index encodes minimum text use: 700 = large text, 900 = small text.
- **Color space.** CIECAM02-UCS (CAM02) — replaced HSL after equal-step blues felt darker than equal-step yellows.
- **Accessibility.** Numeric index encodes text-size contract; cross-product tokens guarantee accessible pairings.
- **Dark mode.** Three independently tuned themes (light / dark / darkest), not algorithmic inversion — monotonic darkening over-darkened mid-tone UIs.
- **Distinctive.** Background-layer semantic tokens (`background-base`, `background-layer-1`, `background-layer-2`) resolve to different gray indexes per theme.

## Ant Design

- **Structure.** 10 swatches per hue, generated from one seed; seed maps to step 6 (primary). 1–5 tints, 7–10 shades.
- **Color space.** HSV/HSB working model; current generator uses Bézier curves on HSV with separate warm/cool rotation angles.
- **Accessibility.** No formal per-step contrast contract. Body-text alpha tokens (`#000000E0` light, `#FFFFFFD9` dark) carry the AA work.
- **Dark mode.** Algorithmic dark-palette generation taking seed *and* a background color; not index inversion.
- **Distinctive.** Drop-in deterministic generator (`@ant-design/colors`).

## Open Color

- **Structure.** 13 hues × 10 steps (`0–9`, lightest → darkest) = 130 colors. Numeric, no role contract.
- **Color space.** sRGB hex, hand-curated.
- **Accessibility.** Implicit — equal-index colors calibrated to similar lightness across hues.
- **Dark mode.** None built in. Convention: `0–4` for light backgrounds, `6–9` for dark.
- **Distinctive.** Seeded the 9–10-step numerical convention adopted by Tailwind, Mantine, others. Optimized for screen UI (font/bg/border), not print.

## USWDS

- **Structure.** Family + grade. Grades are luminance points on `0–100` (0 = white, 100 = black) at `5, 10, 20, …, 90`. Five families (`base`, `primary`, `secondary`, `accent-warm`, `accent-cool`) with semantic grade names (`lightest…darkest`).
- **Color space.** sRGB hex, calibrated by relative luminance.
- **Accessibility.** "Magic number" — grade Δ maps to WCAG: Δ≥40 AA Large, Δ≥50 AA normal / AAA Large, Δ≥70 AAA normal. Verify by subtraction.
- **Dark mode.** Grade-relative — flip grade selection (`text: 90` → `text: 10`); family identity preserved; magic number works either direction.
- **Distinctive.** Only major system with AA/AAA-by-construction baked into grade math.

## Cloudscape (AWS)

- **Structure.** Token-only; no numbered scale exposed. CTI naming (Category-Type-Item-Subitem-State), e.g. `color-background-input-disabled`.
- **Color space.** sRGB; values are private.
- **Accessibility.** Pre-paired tokens — designers cannot assemble a non-accessible pair from the set.
- **Dark mode.** Each token carries `{ light, dark }`; runtime resolves on `data-theme`.
- **Distinctive.** Palette-hidden, token-first. Distributed as Sass/JS/JSON via `@cloudscape-design/design-tokens`.

## Convergent patterns

What every system agrees on. These are the actionable defaults.

- **9–14 steps per hue.** Open Color/Ant 10, Tailwind 11, Radix/Carbon 12, Material ~13, Spectrum 14. Median is ~11. Nobody ships 5 or 20.
- **Perceptual color spaces won.** Tailwind v4 → OKLCh, Material 3 → HCT, Spectrum 2 → CAM02. HSL/sRGB generation breaks cross-hue contrast because equal lightness in HSL ≠ equal perceived lightness. Use OKLCh for new systems (CSS Color 4 standard, native `oklch()`).
- **Semantic role > positional number for production.** Radix step roles, Material role pairs, USWDS grade names, Cloudscape CTI tokens. Tailwind/Open Color holdouts get a semantic alias layer in practice. Ship both: numeric scale + thin semantic alias.
- **Contrast-targeted step spacing.** Pin specific steps to AA-body and AAA-body against your lightest/darkest steps so cross-hue substitution preserves contrast. USWDS Δ-math, Radix 11/12 APCA targets, Material role pairs, Spectrum 700/900.
- **APCA for new systems.** Radix is APCA-tuned; WCAG2 contrast ratio is known to misrank dark-on-light vs light-on-dark. Use APCA Lc with WCAG2 as fallback report.
- **Alpha scales are table stakes.** Radix per-hue alpha + `blackA`/`whiteA`, Tailwind slash-opacity, Apple alpha-on-label, Spectrum transparent tokens. Emit solid + alpha per hue plus theme-invariant black/white alpha for shadows/scrims.
- **Dark mode = paired scales, never inversion.** Radix `*Dark`, Material light/dark schemes, Carbon 4 themes, Spectrum 3 themes, Apple elevated/standard, Cloudscape `{light, dark}`. Hand-tune (or independently algorithm-tune) a parallel scale where step N preserves its role. Inverting lightness produces over-dark mid-tones.
- **4–6 first-class neutrals.** Tailwind 5 neutrals (slate/gray/zinc/neutral/stone), Material neutral + neutral-variant, Carbon gray-driven, Apple system gray. Ship at least one warm-leaning, one cool-leaning, plus a true gray.
- **Generated from seed for new systems; hand-tuned for legacy.** Generation only works with a perceptual space — without one, results are visually inconsistent. Allow per-hue overrides for yellow and green (chroma compresses at high lightness).
- **Three contrast modes, not two.** Material standard/medium/high, Apple Increase Contrast, Spectrum light/dark/darkest. Treat high contrast as a scheme, not an afterthought.
- **Color is one channel.** HIG, Cloudscape, Carbon, USWDS all forbid color-only state encoding. Pair color with icon, text, or shape.

## What to default to in this skill

- **12-step Radix-style semantic scale.** Numeric 1–12 with roles assigned (1 app bg → 12 high-contrast text). Emit a thin semantic alias layer on top.
- **OKLCh as the working space.** Generate algorithmically from one seed; emit `oklch()` plus sRGB hex fallback. Allow hand override on yellow/green steps where chroma compresses.
- **Pinned contrast targets.** Step 9 = solid usable; step 11 ≥ APCA Lc 60 (AA body equivalent) against step 1/2; step 12 ≥ Lc 75 (AAA body) against step 1/2.
- **Hand-tuned paired dark scale.** Emit `*Dark` where step N preserves its role. Never invert lightness. Include alpha companions (`*A`, `*DarkA`) plus theme-invariant `blackA`/`whiteA`.
- **5 neutrals + high-contrast variant.** Ship warm gray, cool gray, true gray, plus two accent-tuned neutrals. Emit a high-contrast scheme that pulls steps 11/12 further apart.

## Sources

- Tailwind v4: https://tailwindcss.com/docs/colors , https://tailwindcss.com/blog/tailwindcss-v4
- Radix Colors: https://www.radix-ui.com/colors/docs/palette-composition/scales , https://www.radix-ui.com/colors/docs/palette-composition/understanding-the-scale
- Material 3: https://m3.material.io/styles/color/system/overview , https://m3.material.io/styles/color/roles
- Apple HIG: https://developer.apple.com/design/human-interface-guidelines/color
- IBM Carbon: https://carbondesignsystem.com/elements/color/overview/
- Adobe Spectrum: https://spectrum.adobe.com/page/color-system/ , https://adobe.design/stories/design-for-scale/reinventing-adobe-spectrum-s-colors
- Ant Design: https://ant.design/docs/spec/colors , https://github.com/ant-design/ant-design-colors
- Open Color: https://yeun.github.io/open-color/
- USWDS: https://designsystem.digital.gov/design-tokens/color/overview/
- Cloudscape: https://cloudscape.design/foundation/visual-foundation/colors/
