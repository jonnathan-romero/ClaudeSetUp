# Correctness: tolerance policy and FP nondeterminism

## The headline

**Polars' `assert_frame_equal` defaults are ~10 orders of magnitude looser than the phenomenon
they need to distinguish.** Verified against 1.43.2:

```
SIG: assert_frame_equal(left, right, *, check_row_order=True, check_column_order=True,
     check_dtypes=True, check_exact=False, rel_tol=1e-05, abs_tol=1e-08,
     categorical_as_str=False)

DEFAULTS      -> PASSED   (a 1e-6 relative error silently accepted)
equals()      -> False    (catches it)
check_exact   -> failed (correct)
rel_tol=1e-12 -> failed (correct)
rtol=1e-12    -> failed (correct) + DeprecationWarning: renamed to rel_tol in 1.32.3
```

Float64 FP-reordering noise is ~1e-15 relative. The default `rel_tol=1e-5` silently passes a
0.001% error on every float column — a catastrophic financial or scientific regression. Polars'
own issue #18209 (open since 2024-08-15) demonstrates `0.1` vs `0.100000000001`: `equals()`
returns `False`, `assert_frame_equal` raises **nothing**.

**Corollary: set tolerance a priori from dtype and reduction size. Never respond to a failure by
loosening it.** A diff outside the pre-declared band is a bug, not a tuning problem — escalate.

## API differences that bite

| API | Formula | Symmetric? | rel | abs |
|---|---|---|---|---|
| `polars.testing.assert_*_equal` | `\|a-b\| <= max(rel_tol*max(\|a\|,\|b\|), abs_tol)` | **yes** | 1e-5 | 1e-8 |
| `math.isclose` | same | **yes** | 1e-9 | 0.0 |
| `np.isclose` / `np.allclose` | `\|a-b\| <= atol + rtol*\|b\|` | **no** | 1e-5 | 1e-8 |
| `np.testing.assert_allclose` | `atol + rtol*\|desired\|` | **no** | 1e-7 | **0** |

Polars follows PEP 485 (`max`-based, symmetric); NumPy *adds* them and is asymmetric — *"it
assumes b is the reference value"*. **Always pass the baseline as `desired`** (second argument).

Two traps in opposite directions: `assert_allclose` has `atol=0`, so a legitimate
cancellation-to-zero always fails; `np.isclose` has `atol=1e-8`, so *"it is unlikely that a=1e-9
and b=2e-9 should be considered 'close', yet isclose(1e-9, 2e-9) is True with default settings."*
You need both — rtol alone breaks at zero, atol alone breaks across magnitude ranges.

**Never use `assert_array_almost_equal`** — NumPy's own docs recommend against it; it is a pure
*absolute* decimal-places test with no relative component.

**Never use `check_row_order=False`** — it sorts **both frames by ALL columns**, including floats.
A legitimate 1-ULP change to a float in the implicit sort key reorders the rows and produces a
spurious whole-column mismatch that looks like a catastrophic bug. Sort explicitly on non-float
business keys instead.

**Free check:** Polars enforces null and NaN *positions* exactly regardless of tolerance — that
catches an optimization turning a finite value into `NaN`.

## The nondeterminism this skill's own proposals cause

These are not bugs. They are the direct consequence of vectorizing, transposing, and changing
thread counts.

- **Non-associativity is the root cause.** PyTorch states it cleanly: *"floating point addition
  and multiplication are not associative, so the order of the operations affects the results."*
  And the canonical vectorization example: `(A@B)[0]` is *"not guaranteed to be bitwise identical
  to A[0]@B[0] even though mathematically it's an identical computation"*; `A.sum(-1)[0]` ≠
  `A[:,0].sum()`.
- **NumPy's pairwise summation is layout-dependent** — *"the improved precision is only used when
  the summation is along the fast axis in memory."* **A transpose-for-speed changes your sums.**
- **Thread count changes partition boundaries, which changes summation order.** Pin
  `OMP_NUM_THREADS`, `MKL_NUM_THREADS`, `OPENBLAS_NUM_THREADS`, `BLIS_NUM_THREADS`,
  `POLARS_MAX_THREADS` **for the equivalence run**; measure speed in a separate, unpinned run.
  Otherwise you cannot separate "the math changed" from "the thread pool partitioned
  differently".
- Numba `fastmath=True` carries a documented **4 ULP** budget (vs 1 ULP default) on top of
  unbounded reassociation error.

**Benign bands** (naive drifts ~n·eps, pairwise ~log2(n)·eps, eps(f64)=2.22e-16 — established
for NumPy reductions; whether Polars' own `sum`/`mean` uses pairwise or naive summation is
undocumented, so for a Polars-side reduction name the mechanism as unconfirmed):

| n | benign (float64) | investigate above |
|---|---|---|
| 1e3 | ≲ 1e-15 | 1e-13 |
| 1e6 | ≲ 1e-14 | 1e-11 |
| 1e9 | ≲ 1e-13 | 1e-10 |

**float32 has essentially no headroom** — at n=1e6 legitimate reordering reaches ~1e-5, which is
*exactly the Polars default* and is business-visible (a cent on a thousand dollars). This is why
that default feels fine for float32 and is catastrophically loose for float64.

**The correct response to a float32 accumulation is a wider accumulator, not a wider tolerance.**
Pass `dtype=np.float64` to the reduction while keeping float32 storage: you keep the
memory-bandwidth win (the real source of the speedup) and restore float64 error bounds.

**What `equivalence.py` actually computes** (measured, so it doesn't get "fixed" by mistake):

| n | float64 `rel_tol` | float32 `rel_tol` |
|---|---|---|
| 1 | 1.0e-12 | 2.4e-06 |
| 1e3 | 1.0e-12 | 2.1e-05 |
| 1e6 | 1.0e-12 | 4.5e-05 |
| 1e9 | 1.0e-12 | 6.9e-05 |

The float64 **n-scaling is inert — the 1e-12 floor dominates at every realistic n**, and that is
deliberate. `20·log2(n)·eps` only reaches 8.4e-14 at n=1e6, so the floor sits deliberately between
the benign band (≲1e-14) and the investigate threshold (>1e-11): genuine reordering passes,
anything ~100× worse fails.

The script also applies `abs_tol = eps(dtype) × max|baseline column|` — one ULP at the column's
largest magnitude — so a near-zero element cannot fail on `rel_tol` alone for a difference that
is unrepresentable at the column's scale. (The research report's declared abs_tol and its own
shipped code disagreed; the eps-based form is adopted deliberately, being exactly
representability-at-scale.)

The float32 column is the honest problem. **At n≥1e3 the computed band is already looser than
Polars' own 1e-5 default** — the very default this gate exists to replace. So the script emits a
`WARNING` whenever a float32 tolerance reaches 1e-5 and names the accumulator fix. A
`WITHIN_TOLERANCE` verdict on a float32 column at large n proves very little; treat it as
"unrefuted", not "verified".

**A non-benign case that masquerades as benign:** reduction order can turn a finite result into
`inf`/`NaN`. `torch.tensor([1e20, 1e20]).norm()` → `inf`; `.double().norm()` → 1.41e20, which *is*
representable in fp32. Check `np.isfinite` counts explicitly for NumPy —
`assert_allclose(equal_nan=True)` happily passes two arrays that are both NaN in the same places.

## Order and volatility

SQL without `ORDER BY` is unordered **by definition** — *"The actual order in that case will
depend on the scan and join plan types."* So adding an index, changing a `WHERE`, or pushing a
filter down (all classic optimizations) can change row order with zero change to the result set.
Sort before comparing, always.

**Do not add `maintain_order=True` to make comparison easier** — it is *"slower than a default
group by"* **and** *"blocks the possibility to run on the streaming engine"*, i.e. it is itself a
performance regression. Sort in the verification harness instead. (Best evidence the default is
genuinely nondeterministic: Polars' own doctest tags the default `group_by` example
`# doctest: +IGNORE_RESULT`, and the `maintain_order=True` example immediately below it does not.)

`dict` preserves insertion order; **`set` does not** — `PYTHONHASHSEED=0` if column lists are
built from sets.

**Mask before comparing — but only explicitly:** `now()`/`CURRENT_TIMESTAMP`, UUIDs,
auto-increment IDs, file paths, temp dirs, hostnames. `scripts/equivalence.py` **never
auto-drops**: it flags name-suspect columns (`timestamp`, `run_id`, …) and masks only what
`--mask` names — an `event_timestamp` is business data, and auto-masking it would silently
exclude real values from the gate.

`np.random.default_rng(seed)` is the right constructor, but note *"**No Compatibility
Guarantee** — as better algorithms evolve the bit stream may change"* across NumPy versions. Fine
within one session; do **not** commit such a snapshot as a long-lived regression test without
saying so.

## Snapshot format

**Arrow IPC (`write_ipc`), not CSV or parquet.** Lossless dtypes, no pandas.

- `dataframe_regression` (pytest-regressions) is **disqualified** — it `import pandas as pd` and
  round-trips CSV. (Correction to the obvious worry: `%.17g` *is* round-trip lossless for float64;
  the real loss is **dtypes and schema**.)
- `ndarrays_regression` is usable (`.npz`) but its dtype check **silently accepts float64→float32**
  — assert dtypes yourself — and unconfigured it inherits `np.isclose`'s `rtol=1e-5, atol=1e-8`,
  the same too-loose band this gate exists to replace: **always pass `default_tolerance`
  explicitly.**
- syrupy is `repr`-based, so it captures Polars' truncated display form and hides exactly the
  small numeric diffs this gate exists to catch.
- Round-trip gotchas: Categorical/Enum physical codes are cache-dependent (compare with
  `categorical_as_str=True` or cast to String first); Datetime `ms`/`us`/`ns` are distinct dtypes;
  list-column tolerance has historically been buggy (#9264) — explode nested floats first.

## Protocol

1. **Freeze the environment** — `PYTHONHASHSEED=0`, all thread vars to 1, for the *equivalence*
   run only. Both must be set **before interpreter start** (in the parent launching the run):
   `os.environ` inside an already-running harness is a silent no-op for hashing, and the thread
   vars are read at numpy/polars import.
2. **Snapshot from the baseline before touching anything:** the output frame(s) → Arrow IPC; raw
   NumPy arrays → `np.save`/`np.savez_compressed`, never `savetxt`; the schema as text; the
   shape; null and NaN counts per column; any intermediate frame at a reduction boundary the
   change touches.
3. **Normalize both sides identically**, in the harness, never inside the optimized code.
4. **Tolerance by dtype:** schema/dtypes/shape/row-count exact · Int/UInt/Bool/String/Binary/Date
   exact · Decimal exact · Categorical exact with `categorical_as_str=True` · null and NaN
   positions exact · floats at `rel_tol` sized from dtype and reduction depth.
5. **Ladder, stopping at the first rung that passes:** schema+shape → `equals()` → non-float
   columns exact → floats within the declared tolerance.
6. **Prove the harness can fail** — perturb by **10× the declared tolerance**, not 1 ULP (a 1-ULP
   nudge is *supposed* to pass). `equivalence.py --selftest` does this.
7. **Adjudicate disagreements against a higher-precision reference** — `math.fsum` is exactly
   rounded. If the candidate is *closer* to truth than the baseline, that is still a behaviour
   change needing sign-off, but not a regression. Report both errors.
8. **Check coverage:** `pytest --cov --cov-branch --cov-report=xml` then `diff-cover
   coverage.xml --fail-under=100`. If the changed lines aren't covered, the honest report is
   *"the suite does not constrain this change"* — not "tests pass".
9. **Screen flakes before rejecting.** A candidate failing the *test suite* (as opposed to the
   snapshot) gets the failing tests re-run ~10×: fails-once-passes-nine is reported as a flaky
   test, not as a correctness regression that kills the candidate.

## What to report

**Never a boolean.** Verdict (`IDENTICAL` / `EXACT` / `WITHIN_TOLERANCE` / `CANNOT_RULE_OUT` /
`REGRESSION` — the script maps any failed assertion to `REGRESSION`, returns `EXACT` when
non-float values match exactly after declared canonicalization, and downgrades a float32 pass at
business-visible tolerance to `CANNOT_RULE_OUT`), `max_abs_diff` and `max_rel_diff` **per
column**, the rows/columns where the max occurs, the tolerance applied **and why** (dtype + n),
diff coverage on changed lines, and whether the sensitivity probe passed.

**ULP distance is the reordering-vs-bug classifier:** a few ULP → benign reordering; thousands →
investigate. `np.testing.assert_array_max_ulp` **raises** — use it to *classify* a difference,
never as a ladder gate, since a reordered sum over n=1e6 routinely differs by tens to hundreds
of ULP.

For anything you cannot rule out: say **"I cannot rule out"**, never "this is fine". Always give
the *expected* magnitude alongside the *observed* one — a bare number is not actionable. Name the
mechanism you think caused it, or say you could not identify one.

Codeflash — the closest commercial analogue — still ships with this caveat, and so should any
report from this skill: *"We recommend manually reviewing the optimized code since there might be
important input cases that we haven't verified where the behavior could differ."*
