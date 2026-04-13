# Matplotlib Plot Style

Apply the user's preferred matplotlib style settings whenever writing plotting code. This ensures visual consistency across all charts and figures.

## How to apply

Choose the method based on context:
- **`plt.rc_context(RC)`** as a context manager when the style should apply to a single figure or block of plots
- **`plt.rcParams.update(RC)`** at the top of a script/notebook when all plots in the file should use this style

## rcParams

```python
EQ_RC = {
    # Background
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
    # Font — uses relative sizes so everything scales with font.size
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
    # Grid — dotted, subtle
    "axes.grid": True,
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
}
```

## Color palettes

Seven approved palettes with 10 colors each. Pick whichever best fits the chart type and data context — e.g., "Muted Classic" for general-purpose multi-series, "Sunset" for high-energy presentations, "Deep Ocean" for financial reports, "Nordic" for subdued analytical work.

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

### Palette selection guidelines

- **Financial/analytical charts** (returns, drawdowns, factor exposures): Deep Ocean, Nordic, or Cool Steel
- **Presentations/dashboards**: Muted Classic, Bold Primary, or Sunset
- **Multi-category bar charts** (sectors, months): Jewel Tones or Muted Classic — these have the most visually distinct colors
- **Two-series comparison** (strategy vs benchmark): use colors 0 and 1 from any palette — they are designed to contrast well
- **Positive/negative coloring** (PnL bars, returns): use color 0 for positive, color 1 for negative

## Line styles

Use varied line styles to improve readability, especially when many series share a plot or when the chart may be printed in greyscale. Combine color with linestyle so series remain distinguishable even without color.

```python
LINE_STYLES = ["-", "--", "-.", ":", (0, (3, 1, 1, 1)), (0, (5, 2))]
```

### When to vary line styles

- **3+ overlapping line series**: cycle through styles so lines remain distinguishable where they cross or overlap
- **Primary vs secondary series**: solid (`-`) for the main series, dashed (`--`) for benchmarks/references/secondary comparisons
- **Confidence intervals / bands**: use the same color as the main line but with a dotted or dash-dot style for the bounds
- **Thresholds / reference lines**: always dashed or dotted (e.g., `ax.axhline(..., linestyle="--")`) to visually separate them from data
- **2 series only**: solid for both is fine — color alone is enough to distinguish them

### Legend readability

The default is `legend.frameon: False` (no background). Override this per-plot when the legend overlaps dense content like stacked areas, heatmaps, or filled regions:
```python
ax.legend(frameon=True, facecolor="white", edgecolor="#cccccc", framealpha=0.9)
```

### Markers

Add markers sparingly — they help when data points are sparse or when series cross frequently:
- Monthly or less frequent data: consider adding markers (`o`, `s`, `^`, `D`)
- Daily or higher frequency: no markers (too dense, clutters the chart)

## Usage example

```python
import matplotlib.pyplot as plt

plt.rcParams.update(EQ_RC)
palette = PALETTES["muted_classic"]

fig, ax = plt.subplots()
for i, (name, data) in enumerate(series.items()):
    ax.plot(dates, data, color=palette[i], linestyle=LINE_STYLES[i % len(LINE_STYLES)], label=name)
ax.set_title("Cumulative Returns")
ax.legend()
```
