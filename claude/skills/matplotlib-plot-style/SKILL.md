---
name: matplotlib-plot-style
description: Apply the user's matplotlib plot styling preferences whenever writing plotting code. ALWAYS use this skill when generating matplotlib charts, figures, plots, or visualizations. Trigger on any code that imports matplotlib, creates figures, or plots data — even if the user doesn't explicitly mention styling.
---

# Matplotlib Plot Style

Apply these settings to ALL matplotlib code. Use `plt.rc_context(PLOT_RC)` for single plots or `plt.rcParams.update(PLOT_RC)` at the top of scripts/notebooks.

## Golden Reference

Every plot should follow this pattern:

```python
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

plt.rcParams.update(PLOT_RC)
palette = PALETTES["muted_classic"]

fig, ax = plt.subplots(figsize=(10, 6))
ax.plot(x, series_a, color=palette[0], linewidth=1.5, label="Series A")
ax.plot(x, series_b, color=palette[1], linewidth=1.5, label="Series B")
ax.axhline(0, color="#444444", linewidth=0.5, linestyle="--")
ax.set_title("Series Comparison")
ax.set_xlabel("X")
ax.set_ylabel("Y")
ax.legend()
fig.savefig("chart.png")
```

## rcParams

ALWAYS apply this full dict. Do NOT cherry-pick or omit settings.

```python
PLOT_RC = {
    # Background
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
    # Font — relative sizes scale with font.size
    "font.family": "sans-serif",
    "font.sans-serif": ["Helvetica", "Arial", "DejaVu Sans"],
    "font.size": 10,
    "axes.titlesize": "large",
    "axes.titleweight": "normal",
    "axes.labelsize": "medium",
    "xtick.labelsize": "small",
    "ytick.labelsize": "small",
    # Text color
    "text.color": "#000000",
    "axes.labelcolor": "#000000",
    "xtick.color": "#000000",
    "ytick.color": "#000000",
    # Spines — bottom and left only
    "axes.edgecolor": "#444444",
    "axes.linewidth": 0.7,
    "axes.spines.top": False,
    "axes.spines.right": False,
    # Grid — dotted, subtle, BEHIND data
    "axes.grid": True,
    "axes.axisbelow": True,
    "grid.color": "#d5cfc4",
    "grid.linewidth": 0.6,
    "grid.alpha": 0.8,
    "grid.linestyle": ":",
    # Legend
    "legend.frameon": False,
    "legend.fontsize": "small",
    # Layout & saving
    "figure.autolayout": True,
    "savefig.dpi": 200,
    "savefig.format": "png",
    "savefig.transparent": False,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.1,
    # Axis formatting
    "axes.formatter.useoffset": False,
    "axes.formatter.use_mathtext": True,
    "axes.unicode_minus": True,
    # Font embedding for PDF/PS export
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
    # Performance for large datasets
    "agg.path.chunksize": 20000,
    "path.simplify": True,
}
```

## Color Palettes

Seven approved palettes, 10 colors each. Pick based on context.

```python
PALETTES = {
    "deep_ocean": [
        "#1a5276", "#c0392b", "#7d8c6c", "#2c3e50", "#8e6e53",
        "#5b2c6f", "#1abc9c", "#d4a373", "#2874a6", "#943126",
    ],
    "nordic": [
        "#2e4057", "#048a81", "#8b575c", "#54577c", "#8c8a93",
        "#3c6e71", "#b07d62", "#456990", "#6d435a", "#7a9e9f",
    ],
    "sunset": [
        "#d62828", "#003049", "#f77f00", "#fcbf49", "#606c38",
        "#283618", "#e76f51", "#264653", "#a44a3f", "#8ab17d",
    ],
    "muted_classic": [
        "#4e79a7", "#e15759", "#76b7b2", "#59a14f", "#edc948",
        "#b07aa1", "#ff9da7", "#9c755f", "#bab0ac", "#f28e2b",
    ],
    "bold_primary": [
        "#1b4965", "#d90429", "#2b9348", "#e85d04", "#7209b7",
        "#4361ee", "#f72585", "#4cc9f0", "#3a0ca3", "#b5179e",
    ],
    "cool_steel": [
        "#34495e", "#7f8c8d", "#2980b9", "#8e44ad", "#16a085",
        "#c0392b", "#2c3e50", "#27ae60", "#d35400", "#8e7cc3",
    ],
    "jewel_tones": [
        "#0b3d91", "#c41e3a", "#009b7d", "#e08d3c", "#6c3461",
        "#1a6b54", "#b8860b", "#4169e1", "#8b0000", "#2e8b57",
    ],
}
```

### Palette selection

- **Analytical/data-heavy** (line charts, scatter): `deep_ocean`, `nordic`, `cool_steel`
- **Presentations/dashboards**: `muted_classic`, `bold_primary`, `sunset`
- **Multi-category bars** (categories, groups): `jewel_tones`, `muted_classic`
- **2-series comparison**: use colors 0 and 1 — they contrast well in every palette
- **Positive/negative bars**: color 0 for positive, color 1 for negative

## Line Styles

Default to solid lines. Only vary line styles when the data genuinely requires it — e.g., many overlapping series that are hard to distinguish by color alone, or greyscale output.

```python
LINE_STYLES = ["-", "--", "-.", ":", (0, (3, 1, 1, 1)), (0, (5, 2))]
```

- **Most charts**: solid lines for all series — color is enough to distinguish
- **5+ overlapping series**: consider cycling line styles if lines cross frequently
- **Thresholds/reference lines**: dashed or dotted (`ax.axhline(..., linestyle="--")`)

## Axis Formatting

### Percentage axes

```python
ax.yaxis.set_major_formatter(mticker.PercentFormatter(1.0))
```

### Currency axes

```python
from matplotlib.ticker import FuncFormatter

def currency_fmt(x, _):
    if abs(x) >= 1e9: return f"${x/1e9:.1f}B"
    if abs(x) >= 1e6: return f"${x/1e6:.1f}M"
    if abs(x) >= 1e3: return f"${x/1e3:.0f}K"
    return f"${x:.0f}"

ax.yaxis.set_major_formatter(FuncFormatter(currency_fmt))
```

### Date axes

```python
import matplotlib.dates as mdates
ax.xaxis.set_major_locator(mdates.AutoDateLocator())
ax.xaxis.set_major_formatter(mdates.ConciseDateFormatter(ax.xaxis.get_major_locator()))
```

## Multi-Panel Figures

ALWAYS use `sharex=True` for stacked panels that share an x-axis. Give the most important panel more height.

```python
fig, axes = plt.subplots(3, 1, figsize=(12, 10), sharex=True,
                         gridspec_kw={"height_ratios": [3, 1, 1]})
```

Use a bold suptitle + gray subtitle:

```python
fig.suptitle("Multi-Panel Figure", fontweight="bold", fontsize=14)
axes[0].set_title("subtitle / date range", fontsize=10, color="gray")
```

## Legend Readability

Default is `frameon=False`. Override when legend overlaps dense content (stacked areas, heatmaps, filled regions):

```python
ax.legend(frameon=True, facecolor="white", edgecolor="#cccccc", framealpha=0.9)
```

## Performance

For dense data (>10K points):
- Use `rasterized=True` on scatter plots and heatmaps to keep file sizes manageable
- The `agg.path.chunksize` setting in PLOT_RC prevents rendering crashes

## Markers

- Sparse data (few points per series): add markers (`o`, `s`, `^`, `D`)
- Dense data (many points per series): NEVER add markers (too dense)
