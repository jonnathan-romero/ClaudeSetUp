# Executing Notebooks

## Contents

- [Which executor](#which-executor)
- [Environment selection](#environment-selection)
- [Kernels](#kernels)
- [Parameterized and batch runs](#parameterized-and-batch-runs)
- [Timeouts and error handling](#timeouts-and-error-handling)
- [Notebooks as tests](#notebooks-as-tests)
- [Reproducibility gate](#reproducibility-gate)

## Which executor

Default to `jupyter execute` (nbclient's own CLI). Reach for papermill only when you need parameter injection.

| Tool | Command | Writes |
|---|---|---|
| **nbclient CLI** | `jupyter execute --inplace nb.ipynb` | nothing unless `--inplace` or `--output` |
| **nbconvert** | `jupyter nbconvert --execute --to notebook --inplace nb.ipynb` | in-place; use when you also want a rendered artifact |
| **papermill** | `papermill in.ipynb out.ipynb -p key value` | a separate output notebook, saved incrementally |
| **nbclient API** | `NotebookClient(nb, timeout=…).execute()` | nothing — you call `nbformat.write` |

`jupyter execute`'s only options are `--timeout`, `--startup_timeout`, `--kernel_name`, `--output`, `--allow-errors`, `--inplace`. Its default is to execute *without writing* — forget `--inplace` and the run silently produces no artifact.

## Environment selection

This is the distinction that breaks notebooks most often:

```bash
# Isolated ephemeral env — the project's own package is NOT importable
uv run --with nbclient --with ipykernel jupyter execute --inplace nb.ipynb

# Layered onto the project env — project package and its deps ARE importable
uv run --project <dir> --with nbclient jupyter execute --inplace nb.ipynb
```

Outside a project `--with` builds an isolated environment; inside one it layers onto the project environment. A notebook that does `import yourpackage` needs the second form, or it dies with `ModuleNotFoundError`.

`--with ipykernel` is only needed in the isolated case — neither nbclient nor papermill declares it, and without a kernel the run fails with an opaque `AssertionError`. Merely adding it makes a `python3` kernelspec discoverable inside the ephemeral env (ipykernel ships kernel data to `<sys.prefix>/share/jupyter/kernels/python3`), so no permanent registration is ever required.

A dependency added with `--with` exists only for that run. If the user will open the notebook in VS Code, the dependency has to be in the project environment — `uv add <pkg>` into main dependencies, after asking. Never `--dev`: a dependency group is not in the environment VS Code resolves.

## Kernels

Precedence is explicit flag, then `nb.metadata.kernelspec.name`. Override with `--kernel_name` (nbclient), `-k` (papermill), or `--ExecutePreprocessor.kernel_name` (nbconvert). A kernelspec naming a kernel that does not exist raises `NoSuchKernel`; pass `--kernel_name=python3` to force past a stale name.

Kernelspecs bake an absolute interpreter path, so a registered kernel breaks when a `.venv` is deleted or a uv-managed Python is upgraded. Prefer selecting the interpreter in VS Code over registering kernelspecs; clean up stale ones with `jupyter kernelspec list` / `remove`.

For VS Code, `ipykernel` in the project's main dependencies is all that is needed — not `jupyter`, not `notebook`. `uv sync` prunes anything not in the lockfile, so an `ipykernel` installed via `uv pip install` disappears on the next sync and the kernel dies.

Known issue: ipykernel 7 has an open VS Code hang (`vscode-jupyter` #17228, closed `not_planned`; the likely fix merged after 7.3.0 and is unreleased). Reports skew Windows. If cells hang on connect, pin `uv add "ipykernel<7"`.

## Parameterized and batch runs

Tag one cell `parameters` and put plain editable variables in it. That alone is useful — it is the notebook form of "runtime inputs as editable variables" — and nothing depends on papermill.

Papermill drives that cell for batch runs, inserting an `injected-parameters` cell immediately after the tagged one:

```bash
for r in west east north south; do
  uv run --python 3.13 --project <dir> --with papermill \
    papermill nb.ipynb "out/nb-$r.ipynb" -p region "$r"
done
```

Two caveats:

- **Pin `--python 3.13`.** papermill 2.7.0 is maintained but its CI matrix stops at 3.13, its Python 3.14 issue (#841) is open, and `papermill/engines.py` hard-imports `entrypoints`, which last shipped in 2022.
- **`-p` type coercion is a hand-rolled ladder**, not `ast.literal_eval`. `-p version 3.10` becomes the float `3.1`; `-p zip 01234` becomes the int `1234`. Use `-r key value` to force a string, and `-y`/`-f` for lists and dicts.

If no `parameters`-tagged cell exists, papermill warns and injects at index 0 — which usually runs before the imports the parameters depend on.

Without papermill, reading `os.environ` in the first cell works with every executor.

## Timeouts and error handling

- Per-cell timeout: `--timeout=600` (nbclient), `--ExecutePreprocessor.timeout=600` (nbconvert), `--execution-timeout` (papermill, default forever). `-1` disables it in nbclient.
- `--allow-errors` continues past a failing cell — nbclient and nbconvert only. **papermill's CLI has no `--allow-errors`.**
- papermill saves the output notebook *before* raising, so the traceback lands in the failing cell's outputs — the best post-mortem of the four. Exit code 1, or 138 for `DeadKernelError`.
- nbclient and nbconvert raise `CellExecutionError` → exit 1. With no `--inplace`/`--output`, `jupyter execute` leaves nothing to inspect.
- The `skip-execution` cell tag is honored by nbclient and nbconvert for cells to exclude deliberately.

## Notebooks as tests

```bash
uv run --project <dir> --with pytest --with nbmake pytest --nbmake --nbmake-timeout=600 notebooks/
```

`nbmake` answers "does it run"; `nbval` answers "does it produce the same numbers" by comparing against stored outputs. Both are functional but slow-moving — last releases 2024, last commits 2025.

## Reproducibility gate

```bash
uv run --project <dir> --with nbclient jupyter execute --timeout=600 nb.ipynb
```

No `--inplace`, so nothing is written and the nonzero exit is the entire signal. This is the machine form of restart-and-run-all: committed notebooks routinely show `execution_count` like `[7], [3], [12]`, proving cells ran out of order and that saved outputs may depend on state no top-to-bottom reader can reconstruct.
