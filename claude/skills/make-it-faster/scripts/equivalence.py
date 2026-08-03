"""Prove an optimized program still produces the same answer.

The tolerance policy is the point. Polars' `assert_frame_equal` defaults to
`rel_tol=1e-5`, which is ~10 orders of magnitude looser than the float64 FP-reordering
noise (~1e-15) it needs to be distinguished from — verified against polars 1.43.2, where
the defaults silently PASS a 1e-6 relative error that `DataFrame.equals()` catches. So
this script declares its tolerance up front, from dtype and reduction size, and never
widens it in response to a failure.

Structure is compared exactly; only float values get a tolerance. That is Codeflash's
effective policy (their docs say "match exactly"; their shipped comparator uses
math.isclose / np.allclose with dtype and shape exact) and it is the right model.
A proposal that intentionally changes a dtype (int64→int32 narrowing, String→Enum) must
declare it via --allow-dtype-change: the baseline is then cast strictly (overflow
raises) and every other column stays under the exact-schema rule.

Masking is never automatic: columns whose names look volatile (timestamp, run_id, …)
are only reported as candidates. Dropping a business column like `event_timestamp`
because of its name would silently exclude real data from the gate — pass --mask
explicitly.

Snapshots are Arrow IPC, not CSV or parquet: lossless dtypes, no pandas. A CSV snapshot
turns a dtype regression into a silent pass.

Verdicts: IDENTICAL | EXACT | WITHIN_TOLERANCE | CANNOT_RULE_OUT | REGRESSION.

Usage:
    python equivalence.py baseline.arrow candidate.arrow [--keys a,b] [--n-reduced N]
        [--mask col,col] [--allow-dtype-change col,col]
    python equivalence.py --selftest          # prove the harness can go red
"""

import sys
from pathlib import Path

import polars as pl
from polars.testing import assert_frame_equal

EPS64 = 2.220446049250313e-16
EPS32 = 1.1920929e-07

# Column names that OFTEN vary between identical runs — reported, never auto-masked.
VOLATILE_HINTS = (
    "timestamp",
    "run_id",
    "created_at",
    "updated_at",
    "path",
    "hostname",
    "uuid",
)


def float_tolerance(dtype: pl.DataType, n_reduced: int) -> float:
    """Relative tolerance for a float column, sized from dtype and reduction depth.

    Pairwise summation drifts ~log2(n)*eps; the factor of 20 is headroom, not a sourced
    constant. float32 has essentially no headroom at large n — the fix for a float32
    accumulation is a wider accumulator, not a wider tolerance.

    Args:
        dtype: Float32 or Float64.
        n_reduced: Elements in the largest float reduction feeding this column.

    Returns:
        Relative tolerance to pass as rel_tol.
    """
    depth = max(1.0, (max(n_reduced, 2)).bit_length() - 1.0)
    if dtype == pl.Float32:
        return max(1e-6, 20.0 * depth * EPS32)
    return max(1e-12, 20.0 * depth * EPS64)


def canonicalize(df: pl.DataFrame, key_cols: list[str]) -> pl.DataFrame:
    """Put a frame in canonical form so two runs are comparable.

    Sorts rows by non-float business keys (stable, so ties on non-unique keys cannot
    reorder between runs) and columns by name. Never uses Polars'
    check_row_order=False, which sorts by ALL columns including floats — a 1-ULP change
    to a sort-key float would reorder rows and fake a whole-column mismatch.

    With no keys given, falls back to sorting by every non-float column and says so.
    Comparing unsorted is never acceptable: SQL without ORDER BY is unordered by
    definition, and a pushed-down predicate changes the plan and therefore the row
    order — that would report a spurious REGRESSION for a correct extraction fix.

    Args:
        df: Collected frame to normalize.
        key_cols: Non-float columns forming a row key. Empty selects the fallback.

    Returns:
        A row- and column-canonical frame.

    Raises:
        ValueError: If any key column has a floating-point dtype, or if no key was
            given and every column is float (no deterministic order exists).
    """
    schema = df.schema
    if not key_cols:
        key_cols = [c for c, t in schema.items() if t not in (pl.Float32, pl.Float64)]
        if not key_cols:
            raise ValueError(
                "no --keys given and every column is float: no deterministic row order "
                "exists. Pass --keys with non-float columns that uniquely identify a row."
            )
        print(
            f"NOTE: no --keys given; sorting by all non-float columns {key_cols}. "
            "Ties are order-ambiguous — pass --keys if rows are not uniquely identified."
        )
    float_keys = [c for c in key_cols if schema[c] in (pl.Float32, pl.Float64)]
    if float_keys:
        raise ValueError(f"float columns cannot be sort keys: {float_keys}")
    out = df.sort(key_cols, nulls_last=True, maintain_order=True)
    return out.select(sorted(out.columns))


def compare(
    baseline: pl.DataFrame,
    candidate: pl.DataFrame,
    key_cols: list[str],
    n_reduced: int = 1,
    allow_dtype_change: list[str] | None = None,
) -> str:
    """Compare two pipeline outputs and classify the difference.

    Args:
        baseline: Output of the original program.
        candidate: Output of the optimized program.
        key_cols: Non-float columns to sort by.
        n_reduced: Elements in the largest float reduction, sizing the tolerance.
        allow_dtype_change: Columns whose dtype is DECLARED to change (e.g. an int
            narrowing or String→Enum proposal). The baseline column is cast strictly
            to the candidate's dtype — a lossy cast raises. All other columns remain
            under the exact-schema rule.

    Returns:
        "IDENTICAL", "EXACT", "WITHIN_TOLERANCE", or "CANNOT_RULE_OUT".

    Raises:
        AssertionError: If the outputs differ beyond the declared tolerance
            (the caller maps this to VERDICT: REGRESSION).
    """
    left = canonicalize(baseline, key_cols)
    right = canonicalize(candidate, key_cols)

    for col in allow_dtype_change or []:
        assert (
            col in left.columns and col in right.columns
        ), f"--allow-dtype-change column {col!r} missing from one side"
        src, dst = left.schema[col], right.schema[col]
        if src == dst:
            print(f"NOTE: {col}: declared dtype change but both sides are {src}")
            continue
        try:
            left = left.with_columns(pl.col(col).cast(dst, strict=True))
        except pl.exceptions.PolarsError as exc:
            raise AssertionError(
                f"declared dtype change {col}: {src} -> {dst} is not lossless: {exc}"
            ) from exc
        print(f"DECLARED dtype change {col}: {src} -> {dst} (baseline cast strictly)")

    assert dict(left.schema) == dict(
        right.schema
    ), f"schema changed: {dict(left.schema)} -> {dict(right.schema)}"
    assert left.shape == right.shape, f"shape changed: {left.shape} -> {right.shape}"

    if left.equals(right):
        return "IDENTICAL"

    non_float = [c for c, t in left.schema.items() if t not in (pl.Float32, pl.Float64)]
    if non_float:
        assert_frame_equal(
            left.select(non_float),
            right.select(non_float),
            check_exact=True,
            categorical_as_str=True,
        )

    unrefuted_only = False
    float_cols = [c for c, t in left.schema.items() if t in (pl.Float32, pl.Float64)]
    for col in float_cols:
        rel = float_tolerance(left.schema[col], n_reduced)
        if rel >= 1e-5:
            # At this width the band is business-visible (a cent on a thousand dollars) and
            # looser than the Polars default this gate exists to replace, so passing proves
            # almost nothing. Widening further is the wrong move; widen the accumulator.
            unrefuted_only = True
            print(
                f"  WARNING {col}: rel_tol {rel:.3e} at n={n_reduced} is business-visible and "
                "looser than Polars' own default. A pass here proves little. Fix the "
                "ACCUMULATOR, not the tolerance: keep float32 storage but reduce with "
                "dtype=np.float64, then re-run with the float64 band."
            )
        scale = left[col].abs().max() or 1.0
        eps = EPS32 if left.schema[col] == pl.Float32 else EPS64
        diff = (left[col] - right[col]).abs()
        max_abs = diff.max() or 0.0
        max_rel = max_abs / scale if scale else 0.0
        worst_row = diff.arg_max() if max_abs else None
        print(
            f"  {col}: max_abs={max_abs:.3e} max_rel={max_rel:.3e} "
            f"(rel_tol={rel:.3e}, abs_tol={eps * scale:.3e} = 1 ULP at column max"
            + (f", worst at row {worst_row}" if worst_row is not None else "")
            + ")"
        )
        assert_frame_equal(
            left.select(col),
            right.select(col),
            check_exact=False,
            rel_tol=rel,
            abs_tol=eps * scale,
        )
    if not float_cols:
        return "EXACT"
    return "CANNOT_RULE_OUT" if unrefuted_only else "WITHIN_TOLERANCE"


def selftest() -> None:
    """Prove the comparison can go red. A gate that never fails is not a gate."""
    base = pl.DataFrame({"k": [1, 2, 3], "v": [1.0, 2.0, 3.0]})
    rel = float_tolerance(pl.Float64, 1)
    nudged = base.with_columns(pl.col("v") * (1 + 10 * rel))
    try:
        compare(base, nudged, ["k"])
    except AssertionError:
        print(
            f"SELFTEST PASS: a 10x-tolerance perturbation ({10 * rel:.3e}) was rejected."
        )
    else:
        raise AssertionError(
            "SELFTEST FAILED: harness is insensitive — do not trust its verdicts."
        )
    lossy = pl.DataFrame({"k": [1, 2], "big": [1, 2**40]})
    narrowed = lossy.with_columns(pl.col("big").cast(pl.Int32, strict=False))
    try:
        compare(lossy, narrowed, ["k"], allow_dtype_change=["big"])
    except AssertionError:
        print(
            "SELFTEST PASS: a lossy declared dtype change (int64->int32) was rejected."
        )
    else:
        raise AssertionError(
            "SELFTEST FAILED: lossy declared cast accepted — do not trust its verdicts."
        )


def _csv_arg(args: list[str], flag: str) -> list[str]:
    if flag not in args:
        return []
    return [c for c in args[args.index(flag) + 1].split(",") if c]


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--selftest":
        selftest()
        sys.exit(0)
    if len(args) < 2:
        sys.exit(__doc__)

    keys = _csv_arg(args, "--keys")
    mask = _csv_arg(args, "--mask")
    dtype_changes = _csv_arg(args, "--allow-dtype-change")
    n_reduced = 1
    if "--n-reduced" in args:
        n_reduced = int(args[args.index("--n-reduced") + 1])

    left_df = pl.read_ipc(Path(args[0]))
    right_df = pl.read_ipc(Path(args[1]))

    if mask:
        missing = [c for c in mask if c not in left_df.columns]
        if missing:
            sys.exit(f"--mask columns not in baseline: {missing}")
        print(f"MASKED (explicit --mask): {mask}")
        left_df = left_df.drop(mask)
        right_df = right_df.drop([c for c in mask if c in right_df.columns])

    looks_volatile = [
        c
        for c in left_df.columns
        if any(h in c.lower() for h in VOLATILE_HINTS) and c not in mask
    ]
    if looks_volatile:
        print(
            f"NOTE: column names look volatile: {looks_volatile} — NOT masked. If they "
            "genuinely vary between identical runs (run IDs, wall-clock stamps), pass "
            "--mask; if they carry business data (an event_timestamp), leave them in."
        )

    try:
        verdict = compare(left_df, right_df, keys, n_reduced, dtype_changes)
    except AssertionError as exc:
        print(f"FAILED: {exc}")
        print("VERDICT: REGRESSION")
        sys.exit(1)
    print(f"VERDICT: {verdict}")
