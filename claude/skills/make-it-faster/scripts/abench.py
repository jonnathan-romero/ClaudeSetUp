"""Interleaved A/B benchmark with the skill's statistical gates built in.

Enforces the protocol by construction rather than prose — the three rules agents
under time pressure are most likely to break:

- Interleaves `A B A B ...` — never `n×A` then `n×B`, which measures cache warming
  (imports, page cache, TLS, connection pool, DB buffer/plan cache), a systematic
  error no repetition removes.
- Fresh process for every run. Also an anti-cheat: published evals caught agents
  caching computations across timing runs.
- The noise floor comes from the A-arm of this same sequence, never an earlier block.

Gates (both required): the 95% t-CI on the difference of means excludes zero, AND the
median improvement exceeds `max(5%, 3 × CV_A)`. If they disagree, that IS the finding
— the result is INCONCLUSIVE, not a win. A result inside the noise band prints the
mandated WITHIN NOISE wording; never report it as "slightly faster".

Child stdout/stderr go to /dev/null (timed runs must not depend on console I/O);
correctness is the equivalence gate's job, not this script's.

Usage:
    python abench.py --a "uv run python target.py" --b "uv run python cand.py"
        [--pairs 10] [--warmups 3] [--threads N]
    python abench.py --selftest    # prove the machinery on sleep-based arms
"""

import os
import platform
import shlex
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone

THREAD_VARS = (
    "POLARS_MAX_THREADS",
    "OMP_NUM_THREADS",
    "OPENBLAS_NUM_THREADS",
    "MKL_NUM_THREADS",
    "BLIS_NUM_THREADS",
    "NUMEXPR_NUM_THREADS",
)

# Two-sided 95% t critical values, df 1..30; ~1.96 beyond.
T_975 = (
    12.706,
    4.303,
    3.182,
    2.776,
    2.571,
    2.447,
    2.365,
    2.306,
    2.262,
    2.228,
    2.201,
    2.179,
    2.160,
    2.145,
    2.131,
    2.120,
    2.110,
    2.101,
    2.093,
    2.086,
    2.080,
    2.074,
    2.069,
    2.064,
    2.060,
    2.056,
    2.052,
    2.048,
    2.045,
    2.042,
)


def t_crit(df: float) -> float:
    d = max(1, int(df))
    return T_975[d - 1] if d <= 30 else 1.96


def run_once(cmd: list[str], env: dict[str, str]) -> float:
    """Run one fresh process and return its wall-clock seconds."""
    start = time.perf_counter()
    rc = subprocess.call(
        cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    elapsed = time.perf_counter() - start
    if rc != 0:
        sys.exit(f"arm exited with rc={rc}: {' '.join(cmd)} — fix the command first.")
    return elapsed


def mean_diff_ci(a: list[float], b: list[float]) -> tuple[float, float]:
    """Welch 95% t-CI on mean(a) - mean(b)."""
    na, nb = len(a), len(b)
    va, vb = statistics.variance(a), statistics.variance(b)
    se2 = va / na + vb / nb
    if se2 == 0:
        return 0.0, 0.0
    df = se2**2 / ((va / na) ** 2 / (na - 1) + (vb / nb) ** 2 / (nb - 1))
    d = statistics.mean(a) - statistics.mean(b)
    half = t_crit(df) * se2**0.5
    return d - half, d + half


def paired_diff_ci(a: list[float], b: list[float]) -> tuple[float, float]:
    """95% t-CI on the per-pair differences — tighter, cancels interleaving drift."""
    diffs = [x - y for x, y in zip(a, b)]
    n = len(diffs)
    m = statistics.mean(diffs)
    half = t_crit(n - 1) * statistics.stdev(diffs) / n**0.5
    return m - half, m + half


def _machine_line() -> str:
    model = "?"
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    model = line.split(":", 1)[1].strip()
                    break
    except OSError:
        pass
    governor = "?"
    try:
        with open("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") as f:
            governor = f.read().strip()
    except OSError:
        pass
    load = os.getloadavg()
    return (
        f"{platform.python_version()} on {model} | governor={governor} "
        f"| load={load[0]:.2f} | {datetime.now(timezone.utc).isoformat(timespec='seconds')}"
    )


def bench(
    cmd_a: list[str],
    cmd_b: list[str],
    pairs: int,
    warmups: int,
    threads: int | None,
) -> str:
    """Run the interleaved protocol and print stats; return the verdict line."""
    env = dict(os.environ)
    if threads is not None:
        for var in THREAD_VARS:
            env[var] = str(threads)
    print(f"env: {_machine_line()}")
    pinned = {v: env[v] for v in THREAD_VARS if v in env}
    print(f"threads: {pinned or 'inherited (identical for both arms)'}")
    print(f"A: {' '.join(cmd_a)}\nB: {' '.join(cmd_b)}")

    for i in range(warmups):
        run_once(cmd_a if i % 2 == 0 else cmd_b, env)
    print(f"discarded {warmups} warm-up runs")

    a_times: list[float] = []
    b_times: list[float] = []
    for i in range(pairs + 1):
        a_times.append(run_once(cmd_a, env))
        b_times.append(run_once(cmd_b, env))
        print(f"  pair {i:>2}: A={a_times[-1]:.3f}s  B={b_times[-1]:.3f}s")
    a_times, b_times = a_times[1:], b_times[1:]
    print("discarded run 1 of each arm")

    med_a, med_b = statistics.median(a_times), statistics.median(b_times)
    cv_a = statistics.stdev(a_times) / statistics.mean(a_times)
    threshold = max(0.05, 3 * cv_a)
    lo, hi = mean_diff_ci(a_times, b_times)
    plo, phi = paired_diff_ci(a_times, b_times)
    median_gain = (med_a - med_b) / med_a

    print(
        f"\nA: median={med_a:.3f}s mean={statistics.mean(a_times):.3f}s "
        f"min={min(a_times):.3f}s stdev={statistics.stdev(a_times):.4f} n={len(a_times)}"
    )
    print(
        f"B: median={med_b:.3f}s mean={statistics.mean(b_times):.3f}s "
        f"min={min(b_times):.3f}s stdev={statistics.stdev(b_times):.4f} n={len(b_times)}"
    )
    print(f"noise floor: CV_A={cv_a:.2%}; threshold=max(5%, 3×CV_A)={threshold:.2%}")
    print(f"95% CI on mean(A)-mean(B): [{lo:+.4f}, {hi:+.4f}]s (gate)")
    print(f"95% paired-difference CI:  [{plo:+.4f}, {phi:+.4f}]s (tighter, diagnostic)")
    print(f"median improvement: {median_gain:+.2%}")

    if cv_a > 0.05:
        verdict = (
            f"MACHINE UNFIT: CV_A {cv_a:.2%} > 5% — no trustworthy comparison is "
            "possible right now (thermal/load drift?). Do not report these numbers."
        )
    else:
        significant = lo > 0 or hi < 0
        big_enough = median_gain > threshold
        if significant and big_enough and med_b < med_a:
            verdict = (
                f"IMPROVEMENT: median {med_a:.3f}s -> {med_b:.3f}s "
                f"({median_gain:+.2%}), n={len(a_times)} interleaved pairs, fresh "
                f"process each; 95% CI on the difference [{lo:.4f}, {hi:.4f}] "
                f"excludes zero; noise floor CV {cv_a:.2%}."
            )
        elif significant and med_b > med_a and (med_b - med_a) / med_a > threshold:
            verdict = (
                f"REGRESSION: candidate is slower — median {med_a:.3f}s -> "
                f"{med_b:.3f}s, CI [{lo:.4f}, {hi:.4f}] excludes zero."
            )
        elif significant != big_enough:
            verdict = (
                f"INCONCLUSIVE: the two gates disagree (CI excludes zero: "
                f"{significant}; median > threshold: {big_enough}). That IS the "
                "finding — report both statistics, do not claim a speedup."
            )
        else:
            verdict = (
                f"NO MEASURABLE DIFFERENCE. Median {med_a:.3f} -> {med_b:.3f}, "
                f"n={len(a_times)} interleaved pairs. Measured noise floor CV "
                f"{cv_a:.2%}. The 95% CI on the difference includes zero. This "
                "change is WITHIN NOISE — it may be a small improvement, a small "
                "regression, or nothing. It should not be claimed as a speedup."
            )
    print(f"\nVERDICT: {verdict}")
    return verdict


def selftest() -> None:
    """Prove both gate directions on sleep-based arms (machinery test only)."""
    py = sys.executable
    slow = [py, "-c", "import time; time.sleep(0.30)"]
    fast = [py, "-c", "import time; time.sleep(0.15)"]
    print("== selftest 1: 2x-faster candidate (expect IMPROVEMENT) ==")
    v1 = bench(slow, fast, pairs=4, warmups=1, threads=None)
    print("\n== selftest 2: identical arms (expect NO MEASURABLE DIFFERENCE) ==")
    v2 = bench(slow, slow, pairs=4, warmups=1, threads=None)
    ok = v1.startswith("IMPROVEMENT") and v2.startswith("NO MEASURABLE DIFFERENCE")
    if not ok:
        raise AssertionError(
            "SELFTEST FAILED: harness verdicts are wrong — do not trust it."
        )
    print("\nSELFTEST PASS: improvement detected and A-vs-A stayed within noise.")


def _str_arg(args: list[str], flag: str) -> str | None:
    return args[args.index(flag) + 1] if flag in args else None


if __name__ == "__main__":
    argv = sys.argv[1:]
    if argv and argv[0] == "--selftest":
        selftest()
        sys.exit(0)
    a, b = _str_arg(argv, "--a"), _str_arg(argv, "--b")
    if not a or not b:
        sys.exit(__doc__)
    n_pairs = int(_str_arg(argv, "--pairs") or 0)
    n_warmups = int(_str_arg(argv, "--warmups") or 3)
    thread_arg = _str_arg(argv, "--threads")

    cmd_a, cmd_b = shlex.split(a), shlex.split(b)
    if n_pairs == 0:
        probe = run_once(cmd_a, dict(os.environ))
        n_pairs = 15 if probe < 5.0 else 10
        print(f"probe run {probe:.3f}s -> {n_pairs} pairs (15 if < 5 s, else 10)")
    bench(cmd_a, cmd_b, n_pairs, n_warmups, int(thread_arg) if thread_arg else None)
