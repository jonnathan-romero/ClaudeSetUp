# Case Studies: Real-World Product Palettes

## When to consult this

- User references a specific company's design language ("make it feel like Linear", "Stripe-style dashboard").
- Explaining *why* a known palette works — Linear's purple, Stripe's blurple, Primer's tokens, Geist's monochrome.
- Teaching the recurring lessons: "your brand color is not at step-500", "dark mode is a separate design", "marketing palette is not product palette", "tokens encode role, not value".

## Contents

- [1. Stripe](#1-stripe)
- [2. Linear](#2-linear)
- [3. Vercel / Geist](#3-vercel--geist)
- [4. Notion](#4-notion)
- [5. GitHub Primer](#5-github-primer)
- [6. Figma](#6-figma)
- [7. Discord](#7-discord)
- [8. Slack](#8-slack)
- [9. Apple iOS / macOS](#9-apple-ios--macos)
- [10. Spotify](#10-spotify)
- [11. Pentagram (Mastercard, Verizon)](#11-pentagram-mastercard-verizon)
- [12. Atlassian](#12-atlassian)
- [Convergent lessons](#convergent-lessons)
- [Anti-lessons](#anti-lessons)
- [Sources](#sources)

---

## 1. Stripe

- Structure: one signature blurple (~`#635BFF`), long warm-cool slate ramp, tightly bounded semantic accents.
- Distinctive choice: brand color appears at maybe 2% of pixels; gradients live on marketing only, never the dashboard.
- Copy this: marketing palette and product palette are different palettes — keep them separated.
- Source: <https://stripe.com/blog>, <https://stripe.com/press>

## 2. Linear

- Structure: dark-first, ~12-step warm-near-black neutral ramp, one indigo/purple accent plus issue-status colors.
- Distinctive choice: dark mode is the canonical design, light mode is the derivative; OKLCh in CSS variables.
- Copy this: design dark mode first when users live in the app for hours, and never let status colors collide with brand color.
- Source: <https://linear.app/blog>, <https://linear.app/method>

## 3. Vercel / Geist

- Structure: pure black/white core with no chromatic neutral tinting, single `#0070F3` accent, semantic states only when needed.
- Distinctive choice: zero neutral hue — most teams add warm or cool tint to avoid sterility; Geist refuses on purpose.
- Copy this: one accent is enough if typography and spacing carry the system; let user content be the color.
- Source: <https://vercel.com/geist/introduction>

## 4. Notion

- Structure: warm earthy chrome neutrals, fixed 9-color user palette (gray, brown, orange, yellow, green, blue, purple, pink, red) in fg + bg variants.
- Distinctive choice: the 9 user colors are unevenly spaced and skewed warm — harmony rules broken on purpose.
- Copy this: user-facing color names are a contract; once shipped, "blue" cannot meaningfully change.
- Source: <https://www.notion.so/blog>

## 5. GitHub Primer

- Structure: 10-step scales per hue, strict semantic tokens above (`fg.default`, `canvas.subtle`, `accent.emphasis`), multiple dark variants.
- Distinctive choice: APCA-driven contrast evaluation; light + dark + dark-dimmed + dark-high-contrast all from the same primitives.
- Copy this: tokens then components then product — never reference raw scales in product code; ship more than one dark mode.
- Source: <https://primer.style/foundations/color>, <https://github.com/primer/primitives>

## 6. Figma

- Structure: near-monochrome chrome, single `~#0D99FF` brand accent, few semantic states.
- Distinctive choice: chrome must lose every visual fight against canvas content (the VS Code / Photoshop / DAW constraint).
- Copy this: if your product renders user content, chrome stays neutral and brand-as-accent — never brand-as-chrome.
- Source: <https://www.figma.com/blog>

## 7. Discord

- Structure: blurple at brand level, dark-mode-first, tight 4-5 step near-black ramp, constrained user role-color palette.
- Distinctive choice: 2021 rebrand shifted blurple `#7289DA` → `#5865F2` specifically for contrast on the dark canvas.
- Copy this: brand colors should be re-tuned when the canonical environment changes (e.g., light → dark).
- Source: <https://discord.com/blog/discord-new-brand>

## 8. Slack

- Structure: one primary aubergine `#4A154B`, accent green and yellow, neutral chrome — down from 11+ colors pre-2019.
- Distinctive choice: dark-chroma sidebar gave Slack a recognizable silhouette in every product screenshot for years.
- Copy this: a "many colors" identity ages badly; subtract until what remains is unmistakable.
- Source: <https://www.pentagram.com/work/slack>

## 9. Apple iOS / macOS

- Structure: dynamic system colors (`systemBlue`, etc.) that resolve differently per light/dark, normal/high-contrast, sRGB/P3 gamut.
- Distinctive choice: a color is a function of context — `systemBlue` is correct, `#007AFF` is wrong (only one of four resolutions).
- Copy this: plan for wide gamut (specify in P3 or OKLCh, sRGB fallback) and ship a high-contrast variant — not optional.
- Source: <https://developer.apple.com/design/human-interface-guidelines/color>

## 10. Spotify

- Structure: Spotify Green at brand level, near-black backgrounds, white type, ~12 saturated cartoon genre tiles isolated from UI.
- Distinctive choice: green is so locked that every other color choice answers "does this fight or support the green?"; some surfaces shifted `#1DB954` → `#1ED760` for contrast.
- Copy this: a locked brand color forces honesty about *where* it can appear (e.g., not body text if it only clears AA at large sizes).
- Source: <https://spotify.design>

## 11. Pentagram (Mastercard, Verizon)

- Structure: brand-system reductions — Mastercard kept its 50-year red/yellow overlap; Verizon went from ~20 colors to red + black.
- Distinctive choice: Pentagram's job is usually to *protect* existing color equity, not invent new equity.
- Copy this: most rebrand work is removing colors, not adding them; one high-saturation accent on a high-contrast neutral foundation is the strongest move.
- Source: <https://www.pentagram.com/work/mastercard>, <https://www.pentagram.com/work/verizon>

## 12. Atlassian

- Structure: ~120 semantic tokens (e.g., `color.background.accent.blue.subtle`), light + dark with planned third mode, hex primitives below.
- Distinctive choice: token names encode role + hue + emphasis — readable without lookup; dark mode is a separate token resolution, not inversion.
- Copy this: encode role in token names, and budget for the migration (codemods + multi-quarter rollout) when adopting tokens.
- Source: <https://atlassian.design/foundations/color-new>

---

## Convergent lessons

1. **Brand color sits where its L\* lands, not at step-500.** Stripe blurple, Linear purple, Vercel blue, Discord blurple — none of these live at the median lightness of the neutral ramp. Build the scale around the brand color; do not squeeze the brand color into a slot.
2. **Tokens encode role, not value.** `color.fg.danger` survives a rebrand; `red-500` does not. Primer, Atlassian, Geist, and Apple all reference colors only through role-encoded tokens — product code never sees raw hex.
3. **Dark mode is a separate design, not `filter: invert()`.** Every team that ships great dark mode (Linear, Discord, Spotify, Primer, Atlassian) maintains a separate set of token resolutions per mode, often with desaturated accents.
4. **APCA is the working tool; WCAG 2 is the compliance floor.** Primer is the public flagship; Apple has been perceptual since iOS 7. Use APCA to predict what users see, keep WCAG 2.1 ratios for auditors.
5. **Neutrals carry more aesthetic weight than the accent does.** Pure gray reads "tool" (Geist), warm gray reads "document" (Notion), cool gray reads "infrastructure" (Stripe), near-black-with-a-hint reads "focused work" (Linear). Pick the neutral hue intentionally before generating.
6. **Marketing palette ≠ product palette.** Stripe's gradient era never entered the dashboard. Don't unify the two; the constraints are different.
7. **OKLCh is the new default.** Linear, Geist v4, Atlassian, recent Primer all ship OKLCh in CSS for equal-perceived-lightness across hues, smoother dark generation, and predictable mixing.
8. **Subtract until what remains is unmistakable.** Pentagram's pattern across Slack, Mastercard, Verizon — most rebrand work is removal. Restraint plus discipline plus tokens is the throughline.

## Anti-lessons

- **Notion's irregular 9-color wheel** works because the colors are decorative and locked by user contract — do not break harmony rules in a UI palette where colors carry state.
- **Spotify's saturated cartoon genre tiles** work because each tile is a self-contained surface — do not mix that aesthetic into the chrome.
- **Geist's pure-gray neutrals** work for tool-makers serving designers — do not copy for consumer products; pure neutrals read as cold/sterile outside that context.
- **Slack's aubergine sidebar** worked as a brand moment — do not assume any dark-chroma chrome color earns the same recognition; it took years and a consistent silhouette.
- **Stripe's marketing gradients** worked as a 2017–2021 marketing era — do not import gradients into a dashboard; they read dated and compete with state.

## Sources

- Stripe: <https://stripe.com/blog>, <https://stripe.com/press>
- Linear: <https://linear.app/blog>, <https://linear.app/method>, <https://linear.app/changelog>
- Vercel / Geist: <https://vercel.com/geist/introduction>, <https://vercel.com/blog>, <https://github.com/vercel/geist-ui>
- Notion: <https://www.notion.so/blog>
- GitHub Primer: <https://primer.style/foundations/color>, <https://github.com/primer/primitives>, <https://github.blog/engineering/>
- Figma: <https://www.figma.com/blog>, <https://config.figma.com>
- Discord: <https://discord.com/blog>, <https://discord.com/blog/discord-new-brand>
- Slack: <https://www.pentagram.com/work/slack>, <https://slack.engineering>
- Apple HIG: <https://developer.apple.com/design/human-interface-guidelines/color>, <https://developer.apple.com/documentation/uikit/uicolor>
- Spotify: <https://spotify.design>, <https://engineering.atspotify.com>
- Pentagram: <https://www.pentagram.com/work/mastercard>, <https://www.pentagram.com/work/verizon>, <https://www.pentagram.com/work/slack>
- Atlassian: <https://atlassian.design/foundations/color-new>
