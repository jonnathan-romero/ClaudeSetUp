# Compute: Polars and NumPy/SciPy

Polars **1.43.2** (2026-08-01), NumPy **2.5.x**, SciPy **1.18.0**. Polars 2.0 has **not** shipped,
but 1.43.x docstrings already talk about it as settled.

## Deprecations that make advice stale

The single biggest risk in this section is proposing an API that is now a no-op.

| Item | Status |
|---|---|
| `collect(streaming=True)` | deprecated 1.25.0 → `collect(engine="streaming")` |
| `LazyFrame.profile()` | **deprecated 1.43.0** — no OSS *streaming* profiler replacement exists; on 1.43.x `lf.profile(engine="in-memory")` still returns per-node timings for in-memory queries |
| `pl.enable_string_cache()` / `pl.StringCache` | **deprecated 1.41.0, now a literal no-op** → `pl.Categories` |
| `Expr.shrink_dtype()` | **deprecated 1.33.0, turned into a NO-OP** → `Series.shrink_dtype()` |
| `Expr.apply` / `DataFrame.apply` | renamed → `map_elements` / `map_rows` |
| `collect(predicate_pushdown=…)` booleans | deprecated 1.30.0 → `optimizations=QueryOptFlags(...)` |
| `pl.threadpool_size()` | renamed → `pl.thread_pool_size()` |

Flag any code or blog snippet using `pl.StringCache()`, `pl.enable_string_cache()`, or
`pl.all().shrink_dtype()` as **stale** — those now do nothing at all.

`LazyFrame.profile()`'s deprecation reason matters: *"Due to the concurrent nature of the
streaming engine, the profiling information from this function would be misleading."* A
maintainer confirmed on #28274 that **no OSS streaming profiler exists** (polars-cloud only).
Substitute `explain(engine="streaming")`, `show_graph(engine="streaming",
plan_stage="physical")`, and `POLARS_VERBOSE=1`.

## Polars — the through-line

**"You went eager too early."** The optimizer's passes — predicate pushdown, projection
pushdown, slice pushdown, common-subplan elimination, `cluster_with_columns`, `collapse_joins`,
`fast_projection`, `sort_collapse` — run on the lazy plan. **Nuance most blogs miss: eager is
not optimization-free** — eager calls the lazy engine under the hood per statement, so
*intra-statement* optimization still happens. The real cost is **cross-statement scope**: each
eager call optimizes in its own tiny scope, so a later filter can never push back into the scan,
and the multi-statement anti-patterns — repeated `with_columns`, `filter` after a join, unused
columns — are repaired **only** when the whole chain is one lazy plan. Expect no gain from
converting a single statement; expect it from fusing the chain. The most literal "eager too
early" is the source read itself: favor `scan_parquet`/`scan_csv` over `read_*`.

Reading a plan: *"look for the filter inside the scan node (predicate pushdown) and `PROJECT
2/47 COLUMNS` (projection pushdown). If a predicate did not push down, it usually depends on a
computed column."* `PROJECT */6 COLUMNS` means nothing was pruned.

**Column-usage claims: lazy `explain()` projection is the only sound method.** AST/text matching
breaks on `pl.col(var)`, f-strings, and regex selectors, and DataFrame subclass hooks are lost
after one operation. Report text-scan results as **"columns with no textual reference found"**,
**never** as "unused columns" — a narrowed `SELECT` proposed from a text scan can break
config-driven access.

```python
print(lf.explain(optimized=False))                       # naive
print(lf.explain())                                      # optimized
print(lf.explain(engine="streaming"))                    # what streaming will run
print(lf.explain(optimizations=pl.QueryOptFlags.none())) # quantify what the optimizer buys
```

**LazyFrames don't cache** — *"every time you reuse it in separate downstream queries after it is
defined, it is computed all over again."* Fix: `pl.collect_all([lf1, lf2])`, which shares subplans
under a `SINK_MULTIPLE` with inserted `CACHE` nodes. `LazyFrame.cache()` is explicitly
discouraged: *"It is not recommended using this as the optimizer likely can do a better job."*

**The asymmetry that matters for OOM:** `collect(engine="auto")` falls back to **in-memory**;
`sink_*(engine="auto")` falls back to **streaming**. So `sink_parquet` is already bounded-memory
and `collect` is the one that needs `engine="streaming"` added.

## Polars anti-patterns

- **`map_elements`** — *"Using `map_elements` is strongly discouraged as you will be effectively
  running python 'for' loops, which will be very slow."* `map_rows` gives the four-bullet reason:
  Rust vs Python, forces materialization, can't parallelize, can't optimize. Dict lookup →
  `replace_strict` is **~19× faster at 5M rows** (vendor blog) / "10–100×" (official skill).
- **Runtime detector:** `warnings.filterwarnings("error", category=PolarsInefficientMapWarning)`.
- `.item()` mid-pipeline forces a premature collect — aggregations broadcast inside `filter`, so
  `.filter(pl.col("x") > pl.col("x").quantile(0.9))` stays lazy.
- `pl.concat` inside a loop: N round trips **and** N× chunk fragmentation later operations pay for.
- Repeated `with_columns` — batch into one call; expressions in one context run in parallel.
- `iter_rows(named=True)` is *"more expensive than returning a regular tuple"*.
- `over(mapping_strategy="join")` — *"Warning: this can be memory intensive."* `"explode"` is
  *"typically faster than `group_to_rows`"* but reorders.
- `set_sorted` is a **promise, not a computation**: *"This can lead to incorrect results if the
  data is NOT sorted!! Use with care!"*

**Correctness traps that cause silent re-runs:** strings in `then()`/`otherwise()` are *column
names*, not values — wrap literals in `pl.lit()`. `filter(pl.col("v") > 2)` drops nulls silently.
A bare aggregation in `with_columns` broadcasts the global value to every row (add `.over()`).
Null keys silently drop from inner joins unless `nulls_equal=True`.

## Polars memory and threading

- **Enum > Categorical**; the string cache is dead (§ deprecations). `pl.Categories(physical=...)`
  lets you pick UInt8/16/32.
- **`estimated_size()` under-reports String columns.** Measured: an 8-char column reports
  8.00 B/row and a 20-char column 20.00 B/row — i.e. **raw character bytes only, never the
  16-byte Arrow BinaryView struct**. True cost is ~16 B/row inlined (≤12 chars) or ~16+n buffered.
  Treat it as a lower bound on strings and as a *relative* instrument (before/after on the same
  frame), not an absolute RSS predictor.
- `POLARS_MAX_THREADS` must be set **before process start** — *"The thread pool is not behind a
  lock, so it cannot be modified once set."*
- **Polars already saturates your cores.** *"It is very unlikely that the `multiprocessing`
  module can improve your code performance in these cases."* If you must: **`spawn`, never
  `fork`** — *"Using `fork` as the method, instead of `spawn`, will cause a dead lock."*
- **`Series.to_numpy`** is zero-copy **only if all four hold**: dtype is integer/float/Datetime/
  Duration/Array; no nulls; single chunk; `writable=False`. **`DataFrame.to_numpy` has different,
  stricter conditions**: all Series fully contiguous back-to-back in memory, integer/float dtype
  only, `order="fortran"` — so on a mixed-dtype or Datetime-bearing frame, per-column
  `Series.to_numpy` beats whole-frame `to_numpy`. Use `allow_copy=False` as a hard assertion —
  but a raise on the *frame* call usually means "extract per column", while a silent copy is an
  OOM three weeks later.

## NumPy/SciPy

**`np.vectorize` is not a performance tool** — *"provided primarily for convenience, not for
performance. The implementation is essentially a for loop."* A hit in hot code is a **finding,
not a fix**. `np.frompyfunc` is barely better and *"always returns PyObject arrays"*.

**Memory layout is usually the biggest hidden cost.** *"basic indexing always creates views"* /
*"Advanced indexing, on the other hand, always creates copies."* Boolean-mask filtering is the #1
hidden allocation in pipeline code; on a sorted key, `np.searchsorted` + a slice replaces it with
a zero-copy view. Detect with `arr.flags` (`OWNDATA=False` ⇒ view) and `np.may_share_memory`
(prefer it — `shares_memory` is *"NP-complete"* and can be exponentially slow).

**Broadcasting doesn't copy, but its result does.** NumPy's own warning: *"There are, however,
cases where broadcasting is a bad idea because it leads to inefficient use of memory."* The
pairwise-distance shape at N=50k, D=3 allocates a 60 GB `(N,N,D)` intermediate; the Gram-matrix
identity never exceeds `(N,N)`.

**float32 halves memory exactly; the speed claim does not hold.** Issue-tracker counter-evidence
— treat the *direction* as the finding, not the percentages: gains are often far below 2×, and
float32 is sometimes *slower*. It converts to speed only in proportion to how bandwidth-bound the
kernel is. And it costs precision — float32 has only `2^24 = 16777216` exactly-representable
positive integers, so epoch timestamps collapse. **NumPy's own fix for accumulation is a wider
accumulator, not a narrower guard:** *"it can be advisable to use `dtype=np.float64` to use a
higher precision for the output."*

**Every binary operation in a NumPy expression allocates a full-size temporary** — `a * b + c`
allocates two arrays before the result. The zero-dependency fix class for OOM-adjacent compute:
`out=` on ufuncs (`np.add(a, b, out=buf)`) and in-place operators. **The correctness landmine:**
`a += b` mutates in place, and since any slice is a *view*, an in-place rewrite on a view
silently corrupts the base array — check `arr.flags` ownership before proposing one.

**NEP 50 (NumPy 2.0) changed promotion.** `np.float32(3) + 3.` now returns float32 (was float64) —
good. But `np.array([3], np.float32) + np.float64(3)` now returns **float64** — a silent 2×
memory regression in pre-2.0 code. Grep for `np.float64(` / `np.int64(` used as scalar literals
in expressions with narrow arrays.

**Primitives worth knowing:** `einsum(optimize=)` **defaults to False**, and NumPy's own example
goes 1520 ms → 110 ms with the path computed once. `np.dot` on 4-D inputs silently produces a 6-D
result 45× larger than `matmul`. `scipy.linalg` *"is always compiled with BLAS/LAPACK support"*
and *"it is better to use the linalg.solve command"* than to invert. `argpartition` is O(n) vs a
full sort. **`sliding_window_view` carries a documented 100× *slowdown* warning** — *"scale as
O(N*W) where frequently a special algorithm can achieve O(N)"*.

**SciPy:** build sparse in COO/DOK/LIL, *"convert to CSR or CSC format for fast arithmetic"*; the
`spmatrix` interface is being deprecated → use `*_array`. `minimize` without `jac` costs ~n+1
objective evaluations per gradient. `scipy.signal.convolve` already auto-selects FFT vs direct —
the rewrite target is `np.convolve`.

## Oversubscription — the cross-cutting one

Polars (Rayon, default = #cores) + NumPy (BLAS, default = #cores) inside a `ProcessPoolExecutor`
(P workers) spawns **P × cores × 2** threads. On a 16-core box with P=8 that is 256 threads for 16
cores. The symptom is wall clock getting **worse** as you add workers, with high system time and
low user time.

**Rule: exactly one layer gets the cores.** Either Polars/BLAS multithread and the Python loop is
serial, or the loop is parallel over P processes with BLAS/Polars pinned to 1 thread each.

```python
# Must be the first lines of the entrypoint — OpenBLAS reads these at library init.
import os
for v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
          "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(v, "1")
```

**`threadpoolctl` has a limitation that decides the fix:** *"only designed for situations where
BLAS and OpenMP are only called from the main Python thread."* It works reliably inside a
**process** pool worker, **not** inside a thread pool worker. With `ThreadPoolExecutor` around
BLAS calls, set the env vars before import instead.

OpenBLAS priority: `OPENBLAS_NUM_THREADS` > `GOTO_NUM_THREADS` > `OMP_NUM_THREADS`. Detect the
actual backend with `np.show_config()` / `np.show_runtime()` rather than assuming — macOS ≥14
PyPI wheels ship Accelerate, not OpenBLAS.

**This interaction is nowhere in the Polars docs** — measure it, don't assert it.

## Note on the vendor skill

Polars ships its own official agent skill (`github.com/polars-inc/skills`, MIT). It is a *usage*
skill — "write fast, idiomatic Polars" — and complements this one. If the user has it installed,
defer API idiom to it; this skill's job is measuring a running program.
