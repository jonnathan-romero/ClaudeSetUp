---
name: jupyter-notebooks
description: Creates, edits, executes, and converts Jupyter notebooks (.ipynb) — valid notebooks from percent-format drafts, cell metadata (papermill `parameters` tags, nbconvert hide tags, slide types), headless runs, and HTML/PDF/slides/markdown export via nbconvert. ALWAYS trigger when the user mentions a notebook, .ipynb, Jupyter, nbconvert, papermill, jupytext or nbstripout; asks to "make me a notebook", "add a cell", "run this notebook", "convert/export the notebook to HTML/PDF/slides", "strip the outputs", or "parameterize this notebook"; or names a .ipynb file. ALSO trigger proactively on multi-step exploratory analysis where a notebook is the better artifact — "explore this dataset", "do some EDA", "walk through this data step by step" — even when the user never says "notebook". Do NOT use for a single chart, figure, or plot (use matplotlib-plot-style / dataviz), for searching inside .ipynb files (use file-search), or when the user asks for a script, module, CLI, or package code — those stay .py.
---

# jupyter-notebooks

Notebooks are built from a percent-format draft and assembled by `nbtool.py`. Never hand-write `.ipynb` JSON: Jupyter's first save rewrites any file that is not byte-canonical, turning the next git diff into the whole notebook.

`NBTOOL` below means `~/.claude/skills/jupyter-notebooks/scripts/nbtool.py` (executable; it fetches its own deps via uv).

## Hard rules — each of these fails silently

| Rule | Why |
|---|---|
| For a notebook inside a uv project, run uv **from the project directory** (or pass `--project <dir>`) | uv discovers the project from cwd; when already inside it, plain `uv run --with nbclient …` is correct and `--project` is redundant. What breaks is running from *outside*: `--with` then builds an **isolated** env and a notebook importing the user's own package dies with `ModuleNotFoundError`. Within a project, `--with` *layers* onto the project env instead. |
| Add `--with ipykernel` only in the standalone case | Neither nbclient nor papermill depends on it; without a kernel you get an opaque `AssertionError`. Project envs normally already have it. |
| `jupyter execute` needs `--inplace` or `--output` | Without one it executes and writes **nothing** — a silent no-op. (That makes the bare form the right CI gate: no writes, nonzero exit on any cell error.) |
| Validate explicitly; never trust the write | `nbformat.write()` logs `Notebook JSON is invalid` and saves the file anyway. `NBTOOL` validates before every write. |
| Use `NBTOOL meta` for tags and slide types | `NotebookEdit` has no metadata parameter. Tags and `slideshow.slide_type` are unreachable through it. |
| Put `logging.basicConfig(level=logging.INFO, force=True)` in the setup cell | A fresh kernel's root logger has no handlers and sits at WARNING, so `logger.info()` prints nothing. `force=True` survives re-running the cell. |
| Pin `nbconvert>=7.17.1` in every command | 7.17.1 fixes two path-traversal CVEs (arbitrary file read *and* write) affecting 6.5 onward. |
| Probe before `--to pdf` | It calls pandoc for every markdown cell and dies with `PandocMissing` if pandoc is absent — having xelatex does not help. |

## Creating a notebook

Confirm **destination path** first, and **audience** in the same question when the request does not imply one (a report to share gets framing prose; a working notebook gets headers only). One question, not two.

1. Write a percent-format draft to a temp dir **outside** the user's repo.
2. `NBTOOL from-percent draft.py -o <dest>.ipynb` — assembles valid nbformat 4.5, canonical bytes, and reuses existing cell ids on rebuild so diffs stay small.
3. Execute per the delivery rule below.
4. Delete the draft. The `.ipynb` is the single source of truth from here — the user edits it in VS Code, so any `.py` twin goes stale immediately.

Draft format — `# %%` starts a cell, `[markdown]` sets the type, attributes set metadata:

```python
# %% [markdown]
# # Momentum decay
# Lookback excludes the most recent month — short-term reversal contaminates it.

# %%
import logging

import pandas as pd

logging.basicConfig(level=logging.INFO, force=True)
logger = logging.getLogger(__name__)

# %% tags=["parameters"]
region = "west"
max_rows = 5000

# %% [markdown] slide=slide
# ## Results
```

Structure the notebook to the conventions in [references/authoring.md](references/authoring.md): imports and config in one cell at the top, runtime inputs in a single `parameters`-tagged cell (the notebook form of the "editable variables, no argparse" rule), one analytical step per cell, a markdown header per section, and reusable logic moved into the project package rather than duplicated across cells.

Defer to `matplotlib-plot-style` for every plotting decision — this skill governs the artifact, not how charts look.

Ruff lints and formats `.ipynb` natively (on by default since 0.6.0) — `uv run --with ruff ruff format nb.ipynb` needs no plugin or conversion, and only rewrites cell `source`, so canonical bytes and cell ids survive. Notebook-specific lint ignores: [references/authoring.md](references/authoring.md).

## Editing an existing notebook

`Read` the notebook, then `NotebookEdit` for cell source (it takes the `id` shown in the Read output). Use `NBTOOL meta <nb> --cell <index-or-id> --tags a,b --slide subslide` for metadata, and `NBTOOL clean <nb>` to strip outputs and execution counts.

## Executing

```bash
# Inside a uv project — the notebook can import the project's own package
uv run --project <dir> --with nbclient jupyter execute --timeout=600 --inplace nb.ipynb

# Standalone notebook, no project
uv run --with nbclient --with ipykernel --with pandas jupyter execute --inplace nb.ipynb
```

Missing dependency: name it and **ask before running `uv add`**. Add to main dependencies, never `--dev` — a dependency group would not be in the env VS Code uses. A notebook validated in a layered `--with` env is not a notebook the user can run.

On failure, split by cause. Retry errors that are actually fixable — `NameError`, wrong column, bad signature — up to 3 attempts. Stop immediately on missing data files, absent credentials, or auth failures, and say what is needed; retrying those cannot succeed. Always state plainly whether validation passed.

Batch runs over a parameter sweep, CI gates, and notebook-as-test go to [references/execute.md](references/execute.md).

## Delivering

| Request shape | What to hand over |
|---|---|
| A report to read or share | Execute and **keep** outputs — the rendered result is the point |
| A working notebook to run yourself | Execute to prove it runs, then `NBTOOL clean` — clean diffs, no stale results |
| No env access, or execution needs data/credentials that are absent | Deliver unexecuted, and say so explicitly rather than implying it was checked |

The first time a notebook lands in a git repo, mention once that committed outputs bloat diffs and that `nbstripout` via pre-commit is the fix — then configure nothing. Its pre-commit mode rewrites the working copy, so an open notebook loses its outputs on commit; that is the user's call to make. The paste-ready pre-commit block, the git-filter alternative, and `nbdime` for structural notebook diffs are in [references/git.md](references/git.md).

## Exporting

```bash
uv run --with "nbconvert==7.17.1" jupyter nbconvert --to html --template lab --embed-images nb.ipynb
```

Add `--no-input` for an inputs-hidden report. `--embed-images` inlines markdown images but MathJax and require.js still load from a CDN, so the file is portable only if the notebook has no math.

For PDF, probe and branch — the answer differs per machine:

```bash
command -v pandoc >/dev/null && kpsewhich adjustbox.sty >/dev/null 2>&1 \
  && echo latex || echo webpdf
```

`latex` → `--to pdf`. `webpdf` → `env -u DISPLAY uv run --with "nbconvert[webpdf]==7.17.1" jupyter nbconvert --to webpdf --allow-chromium-download nb.ipynb`. Unsetting `DISPLAY` is load-bearing: with it set, webpdf hangs at 100% CPU (nbconvert #2165, still open). The Chromium download is ~281 MB, once per machine. Never install system packages to fix an export — state the one command and let the user decide.

Slides, hide-cell tags, and custom templates: [references/export.md](references/export.md).
