# Output Formats Reference

Shipping templates for delivering a palette as code. Every section is a copy-paste-fill block.

## When to consult this

Pull this when delivering a palette as code — CSS custom properties, Tailwind v4 `@theme`, DTCG JSON, Swift `UIColor`, Compose `Color`. Triggered by "give me the tokens" or "export this palette". Skip when generating, evaluating, or accessibility-checking — that work happens upstream and produces the OKLCh values these templates consume.

## Contents

- [Quick reference](#quick-reference)
- [CSS custom properties](#css-custom-properties)
- [Tailwind v4 `@theme`](#tailwind-v4-theme)
- [W3C DTCG JSON](#w3c-dtcg-json)
- [Swift `UIColor` extension](#swift-uicolor-extension)
- [Kotlin / Compose `Color`](#kotlin--compose-color)
- [Two-layer naming](#two-layer-naming)
- [`light-dark()` dark-mode pairs](#light-dark-dark-mode-pairs)
- [Style Dictionary one-shot](#style-dictionary-one-shot)
- [Footguns](#footguns)
- [Sources](#sources)

## Quick reference

| Target           | Recommended format                                         |
| ---------------- | ---------------------------------------------------------- |
| CSS (default)    | `:root` custom properties, OKLCh + hex fallback            |
| Tailwind v4      | `@theme { --color-*-* }` block, OKLCh native               |
| Tokens (master)  | DTCG JSON, `colorSpace: "oklch"` object form               |
| Swift / SwiftUI  | `UIColor` extension, `displayP3` + sRGB fallback           |
| Kotlin / Compose | `Color(r, g, b)` object, sRGB floats                       |
| React Native     | Plain TS theme object, sRGB hex                            |
| matplotlib       | `mcolors.ListedColormap` or named dict, sRGB hex           |

Master is DTCG JSON. Everything else is an emit target from one Style Dictionary run.

## CSS custom properties

Default output. Hex line first, OKLCh second — modern browsers overwrite the hex; legacy browsers keep it. Drop the hex line when targeting evergreen-only.

```css
:root {
  color-scheme: light dark;
  --color-primary-50:  #eff6ff;
  --color-primary-50:  oklch(0.97 0.02 250);
  --color-primary-500: #3b82f6;
  --color-primary-500: oklch(0.65 0.18 250);
  --color-primary-900: #1e3a8a;
  --color-primary-900: oklch(0.28 0.10 250);
}
```

## Tailwind v4 `@theme`

Tailwind v4 generates utilities from custom properties inside `@theme`. The `--color-{family}-{shade}` prefix is load-bearing — it tells Tailwind to populate `bg-*`, `text-*`, `border-*`, `ring-*`, `divide-*`, `shadow-*`.

```css
@import "tailwindcss";

@theme {
  --color-primary-50:  oklch(0.97 0.02 250);
  --color-primary-500: oklch(0.65 0.18 250);
  --color-primary-700: oklch(0.50 0.20 250);
  --color-primary-900: oklch(0.28 0.10 250);
}
```

Family is kebab-case (`primary`, `surface-muted`); shade is the numeric scale (`50`–`950`). Anything outside `--color-*` lands in a different utility namespace.

## W3C DTCG JSON

Object form with `colorSpace`, `components`, `alpha`. Aliases use `{token.path}` references. Two-layer structure: `palette/*` literals, `semantic/*` aliases.

```json
{
  "color": {
    "primary": {
      "50":  { "$type": "color", "$value": { "colorSpace": "oklch", "components": [0.97, 0.02, 250], "alpha": 1 } },
      "500": { "$type": "color", "$value": { "colorSpace": "oklch", "components": [0.65, 0.18, 250], "alpha": 1 }, "$description": "Primary brand blue" },
      "900": { "$type": "color", "$value": { "colorSpace": "oklch", "components": [0.28, 0.10, 250], "alpha": 1 } }
    },
    "action": {
      "primary":       { "$type": "color", "$value": "{color.primary.500}" },
      "primary-hover": { "$type": "color", "$value": "{color.primary.700}" }
    },
    "surface":      { "$type": "color", "$value": "{color.gray.50}" },
    "text-primary": { "$type": "color", "$value": "{color.gray.900}" }
  }
}
```

`colorSpace` accepts `srgb`, `srgb-linear`, `hsl`, `hwb`, `lab`, `lch`, `oklab`, `oklch`, `display-p3`, `a98-rgb`, `prophoto-rgb`, `rec2020`, `xyz-d50`, `xyz-d65`. Alias chains may be unbounded but must not cycle.

## Swift `UIColor` extension

Display P3 primary on wide-gamut devices, sRGB fallback elsewhere. One `static let` per semantic token.

```swift
import UIKit

extension UIColor {
    static let actionPrimary: UIColor = {
        if UIColor.responds(to: NSSelectorFromString("colorWithDisplayP3Red:green:blue:alpha:")) {
            return UIColor(displayP3Red: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)
        }
        return UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0)
    }()
    static let actionPrimaryHover = UIColor(displayP3Red: 0.13, green: 0.32, blue: 0.85, alpha: 1.0)
    static let surface            = UIColor(displayP3Red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0)
    static let textPrimary        = UIColor(displayP3Red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
}
```

For SwiftUI, mirror with `Color(.displayP3, red:, green:, blue:, opacity:)` so wide-gamut primaries actually render on P3 displays.

## Kotlin / Compose `Color`

`androidx.compose.ui.graphics.Color` takes sRGB floats (0f..1f). Group tokens in an object that feeds `MaterialTheme`'s `ColorScheme`.

```kotlin
import androidx.compose.ui.graphics.Color

object PaletteTokens {
    val Primary50  = Color(red = 0.937f, green = 0.965f, blue = 1.000f)
    val Primary500 = Color(red = 0.231f, green = 0.510f, blue = 0.965f)
    val Primary700 = Color(red = 0.114f, green = 0.306f, blue = 0.847f)
    val Primary900 = Color(red = 0.118f, green = 0.227f, blue = 0.541f)
}
object SemanticTokens {
    val ActionPrimary      = PaletteTokens.Primary500
    val ActionPrimaryHover = PaletteTokens.Primary700
    val Surface            = Color(red = 0.969f, green = 0.980f, blue = 0.988f)
    val TextPrimary        = Color(red = 0.102f, green = 0.114f, blue = 0.133f)
}
```

For Android XML, emit `<color name="action_primary">#3373F2</color>` from the same source — Style Dictionary's `android/colors` format handles both.

## Two-layer naming

Convergent best practice (Radix, Carbon, Cloudscape): a literal palette layer named by hue/shade, plus a semantic alias layer named by role. Components consume only the semantic layer.

```css
:root {
  /* Layer 1 — literal palette. Numeric scale; never referenced by components. */
  --color-blue-500:  oklch(0.65 0.18 250);
  --color-blue-700:  oklch(0.50 0.20 250);
  --color-gray-50:   oklch(0.99 0.00 0);
  --color-gray-900:  oklch(0.18 0.01 260);

  /* Layer 2 — semantic aliases. Named by role; this is what components import. */
  --color-action-primary:       var(--color-blue-500);
  --color-action-primary-hover: var(--color-blue-700);
  --color-surface:              var(--color-gray-50);
  --color-text-primary:         var(--color-gray-900);
}
```

In DTCG, mirror the split: `palette/blue/500` literal, `semantic/action/primary` aliasing `{color.blue.500}`. In Figma Variables, two collections — literals (single mode), semantics (light/dark modes, each aliasing a different literal).

## `light-dark()` dark-mode pairs

Native CSS dark mode. Requires `color-scheme: light dark` on `:root`. Resolves at used-value time from user preference; no JS, no attribute toggle. Apply at the **semantic** layer, not the literal layer.

```css
:root {
  color-scheme: light dark;

  --color-surface:        light-dark(oklch(0.99 0.00 0),    oklch(0.18 0.01 260));
  --color-text-primary:   light-dark(oklch(0.18 0.01 260),  oklch(0.96 0.01 260));
  --color-action-primary: light-dark(oklch(0.55 0.20 250),  oklch(0.72 0.15 250));
}
```

For browsers older than Chrome 123 / Safari 17.5 / Firefox 120, pair with a `prefers-color-scheme: dark` block as fallback.

## Style Dictionary one-shot

Style Dictionary v4 with `usesDtcg: true` resolves aliases and emits every other format from one DTCG source.

```json
{
  "source": ["tokens/**/*.json"],
  "usesDtcg": true,
  "platforms": {
    "css":       { "transformGroup": "css",       "buildPath": "build/css/", "files": [{ "destination": "tokens.css", "format": "css/variables" }] },
    "tailwind":  { "transformGroup": "css",       "buildPath": "build/tw/",  "files": [{ "destination": "theme.css",  "format": "css/variables", "options": { "selector": "@theme" } }] },
    "ios-swift": { "transformGroup": "ios-swift", "buildPath": "build/ios/", "files": [{ "destination": "Tokens.swift", "format": "ios-swift/class.swift", "options": { "className": "Tokens" } }] },
    "compose":   { "transformGroup": "compose",   "buildPath": "build/android/", "files": [{ "destination": "PaletteTokens.kt", "format": "compose/object", "options": { "className": "PaletteTokens", "packageName": "com.example.tokens" } }] }
  }
}
```

Recommended pipeline:

1. **Author** DTCG JSON — two layers (`palette/*` literals, `semantic/*` aliases).
2. **Compile** with Style Dictionary v4 + `usesDtcg: true`. Add `@tokens-studio/sd-transforms` for Tokens Studio sources.
3. **Emit** CSS, Tailwind v4 `@theme`, Swift, Kotlin/Compose in one `style-dictionary build`.
4. **Version** with SemVer. Add = minor; rename or remove = major. Soft-deprecate via `$deprecated: true` + `$extensions.deprecated.replacement`.

## Footguns

- **Hue interpolation, shorter vs longer.** `color-mix(in oklch, red, blue)` defaults to `shorter hue`. Red (~30°) to blue (~250°) shorter goes through magenta; `longer hue` through yellow/green. Warn when a mix spans >180°.
- **Safari relative-color partial support.** Safari 16.4–16.5 implemented `oklch(from ...)` only in legacy `rgb()`/`hsl()` outputs and choked on `calc()` inside components. Treat Safari 17 as the realistic floor.
- **`color-mix()` gamut drift.** Mixing in `oklch` can land midpoints outside sRGB. Browsers gamut-map at paint, but two engines may map saturated mixes differently. For brand-critical mid-stops, pre-compute and emit literals.
- **Tailwind `--color-*` prefix.** `--brand-500` will not produce `bg-brand-500`; it must be `--color-brand-500`.
- **DTCG color object vs hex string.** The current draft requires the object form for non-sRGB spaces. Emit the object form even for sRGB so the master is forward-compatible.
- **SwiftUI sRGB clamp.** `Color(red:, green:, blue:)` without `.displayP3` is sRGB and clips wide-gamut primaries on P3 displays.

## Sources

- CSS Color 4 / 5: https://www.w3.org/TR/css-color-4/ , https://www.w3.org/TR/css-color-5/
- MDN: [`oklch()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/oklch) , [`color-mix()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix) , [`light-dark()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/light-dark)
- DTCG format: https://tr.designtokens.org/format/
- Style Dictionary: https://styledictionary.com — [formats](https://styledictionary.com/reference/hooks/formats/predefined/)
- Tokens Studio sd-transforms: https://github.com/tokens-studio/sd-transforms
- Tailwind v4 theme: https://tailwindcss.com/docs/theme
- Figma Variables API: https://www.figma.com/developers/api#variables
- Radix Themes color: https://www.radix-ui.com/themes/docs/theme/color
- Carbon color tokens: https://carbondesignsystem.com/elements/color/tokens/
