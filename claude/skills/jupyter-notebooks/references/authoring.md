# Authoring Notebooks

## Contents

- [Why nbformat and not raw JSON](#why-nbformat-and-not-raw-json)
- [The nbformat 4.5 schema](#the-nbformat-45-schema)
- [What actually corrupts a notebook](#what-actually-corrupts-a-notebook)
- [Cell metadata that matters](#cell-metadata-that-matters)
- [Structure conventions](#structure-conventions)
- [Anti-patterns](#anti-patterns)
- [Showing output in a cell](#showing-output-in-a-cell)
- [jupytext](#jupytext)

## Why nbformat and not raw JSON

`nbformat`'s writer is byte-canonical: `indent=1`, `sort_keys=True`, `separators=(",", ": ")`, `ensure_ascii=False`, `split_lines=True`, and a trailing newline. Hand-written JSON with `indent=2` or unsorted keys is *valid* but non-canonical, so Jupyter's first save rewrites the entire file and the next git diff is the whole notebook.

`nbformat.v4.new_code_cell()` also auto-fills `id`, `execution_count=None`, and `outputs=[]`, so required fields cannot be forgotten. `new_notebook()` sets `nbformat_minor = 5`.

`scripts/nbtool.py` wraps all of this. Reach for the `nbformat` API directly only for a transformation `nbtool` does not cover.

## The nbformat 4.5 schema

Root requires `["metadata", "nbformat_minor", "nbformat", "cells"]` and is `additionalProperties: false` — any extra root key is a validation error. `nbformat` must be 4; `nbformat_minor` at least 5.

Per-cell required fields:

- code — `["id", "cell_type", "metadata", "source", "outputs", "execution_count"]`
- markdown / raw — `["id", "cell_type", "metadata", "source"]`

`id` must match `^[a-zA-Z0-9-_]+$`, 1–64 chars; nbformat generates `uuid.uuid4().hex[:8]`.

Minimal valid notebook:

```json
{"cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}
```

`metadata.kernelspec` requires `name` and `display_name`; `metadata.language_info` requires `name`. Neither is required by the schema, but without `kernelspec` an editor prompts for a kernel and without `language_info` syntax highlighting is off.

## What actually corrupts a notebook

- **`nbformat.write()` does not guarantee validity.** `writes()` calls `validate()` inside a `try` and, on `ValidationError`, logs `Notebook JSON is invalid: …` and writes anyway. Always validate explicitly and check.
- **`nbformat_minor: 4` with `id` fields present** is a hard `ValidationError` — the v4.4 cell schema is `additionalProperties: false` and has no `id`. Easy to hit by copying an old template.
- **Missing `id`** raises `MissingIDFieldWarning` ("this will become a hard error in future nbformat versions") and is auto-repaired; **duplicate `id`** is repaired with a `DuplicateCellId` warning, or raises `Non-unique cell id` when repair is disabled.
- **Missing `"metadata": {}` on a cell**, or a code cell missing `outputs`/`execution_count` — both required even when empty or `null`.
- Files must be UTF-8. `ensure_ascii=False` means non-ASCII is written literally.

`source` as a single string is **valid** — the schema's `multiline_string` accepts string or array. A list of lines is only better for line-based diffs, which is what `split_lines()` produces.

## Cell metadata that matters

| Metadata | Consumer | Values |
|---|---|---|
| `tags: ["parameters"]` | papermill | marks the cell whose values get overridden |
| `tags: ["remove_cell" / "remove_input" / "remove_output"]` | nbconvert `TagRemovePreprocessor` | names are yours to choose; see export.md |
| `slideshow: {"slide_type": …}` | nbconvert slides | `slide`, `subslide`, `fragment`, `notes`, `skip`, `-` |
| `jupyter: {"source_hidden": true}` | JupyterLab | collapses input in the UI |

`NotebookEdit` cannot write any of it — its parameters are only `notebook_path`, `cell_id`, `cell_type`, `edit_mode`, `new_source`. Use `nbtool.py meta`, or set it in the percent draft's cell header.

## Structure conventions

From Rule et al., *Ten Simple Rules for Reproducible Research in Jupyter Notebooks* (PLOS Comput Biol, 2019) and cookiecutter-data-science:

- **One meaningful step per cell.** "Avoid long cells (we suggest that anything over 100 lines or one page is too long)."
- **Markdown headers as the spine** — they are what makes a notebook navigable.
- **Fixed opening order**: title markdown cell → one cell holding imports and logging setup → one `parameters`-tagged cell of runtime inputs → the work. Imports precede the parameters cell so that papermill's injected override cell, which lands immediately after the tagged one, still runs with everything imported.
- **Runtime inputs in one `parameters`-tagged cell** — the notebook form of "editable variables, no argparse".
- **Move reusable logic into the project package** and import it. Signals it is time: duplicated notebooks, functions copy-pasted between notebooks, classes defined in a notebook.
- **Split long notebooks** into several plus a top-level index notebook.
- **Restart-and-run-all is the correctness test.** A notebook that only works in the order you happened to run it is not reproducible.
- Naming: `<date>-<topic>.ipynb` or CCDS's `<step>-<initials>-<description>.ipynb`.

## Anti-patterns

| Anti-pattern | Fix |
|---|---|
| Out-of-order execution (`[7], [3], [12]`) | Restart and run all before delivering or committing |
| Mega-cell over ~100 lines | One analytical step per cell |
| Code cells with no narrative | Markdown header per section; a sentence only where intent is not readable from the code |
| Copy-pasted cell variants | Wrap in a function and call it |
| Reusable logic living in the notebook | Move to the project package, import it |
| Committed outputs | `nbtool.py clean`, or nbstripout via pre-commit |
| Imports scattered mid-notebook | Single top import cell |
| `df = df.dropna()` rebinding the source frame | New name per step — re-running the cell twice must be safe |

## Showing output in a cell

- **Bare trailing expression** is idiomatic and renders rich output, but only for the *last* expression in the cell (`ast_node_interactivity` defaults to `last_expr`).
- **`display()`** from `IPython.display` is needed for rich output mid-cell — two objects, or inside a loop or conditional. Import it explicitly so the code stays valid plain Python.
- **`print()`** produces a plain-text stream output with no rich rendering. The project rule is `logging` over `print`; in a notebook that requires `logging.basicConfig(level=logging.INFO, force=True)` in the setup cell, because a fresh kernel's root logger has no handlers and sits at WARNING. Without it `logger.info()` is silently invisible while `logger.warning()` still appears via `logging.lastResort`.

## jupytext

Not required by this skill — `nbtool.py` parses percent format directly, which avoids both the install and jupytext's id churn. Use jupytext when the artifact should genuinely *live* as a versioned text file.

If you do: never run bare `jupytext --to ipynb` against a checked-in notebook. The text formats do not store cell ids, so nbformat regenerates random ones on every conversion (jupytext #735), and text formats do not carry outputs at all. Use the paired commands instead — `jupytext --set-formats ipynb,py notebook.ipynb` then `jupytext --sync`, or `jupytext --update --to notebook nb.py` — which preserve ids and outputs.
