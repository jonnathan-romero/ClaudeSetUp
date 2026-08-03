---
name: make-it-faster
description: Measure why a Python data program is slow, then propose fixes carrying real before/after numbers — read-only on the user's source. ALWAYS trigger when the user says "make this faster", "why is this slow", "speed up this script/pipeline", "this takes forever", "it OOMs" / "runs out of memory", "profile this", "where is the time going", or names a Python program that pulls from a database or API and asks about its performance. Built for the pull → compute → output shape - MSSQL / Snowflake / Snowpark / ClickHouse / REST into Polars / NumPy / SciPy. Runs the program, splits wall clock between extraction and compute, then prototypes every candidate fix in a scratch copy to obtain a measured result before proposing it; writes a ranked report to `.perf/`. Never edits the user's files. REQUIRES a runnable entry point on realistic data - it measures a running program rather than inspecting code, so with no way to execute the target it asks for the command instead of guessing. Do NOT use for code-quality, complexity or dead-code cleanups that involve no measurement (that is `/simplify`, `code-simplifier`, and `@simplification-auditor`), for bug hunting (`/code-review`), or for writing idiomatic Polars from scratch (that is the Polars skill).
argument-hint: "Path to the script, package, or function to measure"
---

Measure why `$ARGUMENTS` is slow, then **propose** fixes. Never edit the user's source.

## Stance

**Read-only on the user's tree.** Every prototype is applied to a copy under the scratchpad. The
deliverable is a ranked report in `.perf/`, not a diff against their files. The complete write
allowlist inside the user's tree: `.perf/`, a one-line `.gitignore` append, and the `.venv`
artifacts of `uv sync` — nothing else, ever. The cached extract parked in `.perf/` is real
warehouse data: treat it as sensitive, and never paste connection strings into the report.

**Measured findings only.** If a finding has no number attached, it does not go in the report.
There is no "unverified observations" section — that was a deliberate choice, and it is what
separates this skill from the tips-dumps in the ecosystem.

**Never write an example number into the report that you did not measure.** The most-starred
public performance agent ships fabricated metrics inside its own prompt
(`"response_time_improvement": "68%"`), which teaches the model that emitting such figures *is*
the deliverable. Placeholders in this file are written as `<measured>` for exactly that reason.

## Preconditions — stop if these fail

1. **A runnable entry point on realistic data.** Without one the core loop cannot execute. Say so
   and ask for the command; do **not** fall back to proposing from inspection.
2. **The program completes, or fails in a way you can measure.** An OOM kill is a data point, not
   a blocker — `ru_maxrss` survives `SIGKILL` (verified), and exit 137 = SIGKILL, almost always
   the OOM killer (confirm via `journalctl -k` before reporting it as one).
3. **`uv` and a synced project env.** Run `uv sync` first. All profilers are injected ephemerally
   with `uv run --with`; nothing is added to `pyproject.toml`.
4. **The output stage is identified and neutralized.** These pipelines *end in a write* — a
   `MERGE` into a warehouse table, a POST, a file drop, an email. The protocol below re-runs the
   program ~25 times with live credentials: before any repeated run, find the sink and redirect
   it into `.perf/` in the scratch copy. If it cannot be neutralized, stop and ask —
   read-only-on-source does not make repeated execution side-effect-free.

## The failure modes you are the antidote to

Published benchmarks put LLMs far below expert level at this task's compute half (every
benchmark cited measures CPU-bound library code; none covers I/O-bound extraction — the failure
taxonomy transfers, the numbers do not): GSO Opt@1 **4.9%**,
SWE-Perf **2.26%** runtime gain vs a **10.85%** expert, SWE-fficiency **0.225×** expert speedup.
The taxonomy of *why* is the design spec for this skill.

- **Mislocalization is the dominant failure** — *"over 68% of expert gains occur in functions the
  LM never edits"*; *"core under-performance comes from reasoning about **where** to intervene,
  and not how large the intervention is."* This is the entire reason the skill measures before it
  proposes. Finding the right place **is** the job.
- **Workload overfitting** — LM patches *"hard-code properties of the specific evaluation workload
  (e.g. expected array shapes, dtypes, or index structures)"*. Never propose a fix that is only
  correct for the row count, dtype, or key distribution you happened to measure on.
- **Shortcut bias** — *"LMs preferentially add localized shortcuts — identity checks, ad-hoc early
  exits, and memoization… Experts instead restructure code to reduce per-element cost."* An early
  exit that happens to skip the measured input is not an optimization.
- **Reward hacking, empirically observed** — agents *"exploited stackframe introspection to detect
  when code is being run in our evaluation environment or would try to **cache computations across
  timing runs**."* A fresh process per timing run is an anti-cheat, not just cache hygiene.
- **Satisficing** — *"once the model secures a measurable speedup, it tends to stop."* Finish the
  candidate list.
- **Correctness and speed fail independently** — 9–45% of patches break tests, and a *further*
  1–18% pass tests while being **slower**. Both gates, always. Neither implies the other.

## Two currencies, two harnesses

The single most important structural decision. `cpu_fraction < 0.3` fires in the typical case for
this workload, and at that point wall-clock A/B is sampling the remote server, not the fix — so a
one-currency report cannot express the skill's best finding ("you pull 4M×60 and use 12K×6").

| | Compute findings | Extraction findings |
|---|---|---|
| Currency | **measured seconds saved** | **rows / bytes / round-trips eliminated** |
| Any time figure | timed | **derived** (bytes ÷ observed throughput) — always labelled |
| Harness | frozen local parquet extract | live source, fewer reps |
| Gate | interleaved A/B + CI + threshold | median/CI, **never min-of-N** |

Rows, bytes, and round-trips eliminated **are** measurements. Rank the two sections separately.

**Why two harnesses.** Compute prototypes benchmark against a frozen parquet extract: deterministic
input, both arms identical, free to repeat, and it satisfies report 02's requirement to fixture
or record-replay the pull stage so both arms see identical inputs. Extraction prototypes *must* hit the live source — so they get fewer
reps, `USE_CACHED_RESULT = FALSE` on both arms, and distribution comparison. **min-of-N is wrong
here**: it rests on the premise that *"there's no 'negative noise' that makes trains go faster"*,
which is false for a network round trip, where the minimum just selects the luckiest warm cache.

State the split explicitly, or you will materialize the extract and then be unable to measure any
extraction fix.

## Phase 0 — gates, before measuring anything

```bash
uv run python ~/.claude/skills/make-it-faster/scripts/runstat.py -- uv run python target.py
```

Prints `elapsed_s`, `user_s`, `sys_s`, `cpu_fraction`, `maxrss_mb`, `rc`. (`/usr/bin/time -v` is
**not installed on Arch** — this wrapper replaces it and survives an OOM kill.)

1. **I/O-bound screen.** `cpu_fraction < 0.3` → the program is waiting on the network: do not
   promise a wall-clock number; switch the primary metric to rows/bytes/round-trips. A value
   **> 1 is not a bug** — multi-threaded compute (Polars saturating cores) — and it can *mask* a
   large wait: 70 s of network plus 30 s of 16-thread Polars still shows ≈4.8. So this is a
   **coarse screen only** — the authoritative currency decision comes from the Phase-1 profile
   split: extraction ≥ 30% of wall clock means extraction findings get their own section in
   their own currency, whatever `cpu_fraction` said. Never report negative compute.
2. **Amdahl gate — in the candidate's own currency.** Profile once for the share `p` of the
   *mechanism* the candidate addresses, summed across every site it touches (never per call
   site — 20 sites × 2% is a 40% mechanism). For wall-clock findings: `p` between 5–10% of
   runtime → prototype *last*; `p` < 5% → refuse, the ceiling is inside the noise floor. Memory
   findings are exempt from the runtime gate — gate them on share of **peak RSS**; a streaming
   fix for the OOM stage is in scope at 0% of runtime.
3. **Fitness pre-check.** Three baseline runs. If they span > 10%, or show a monotone trend (thermal
   throttling), say no trustworthy measurement is possible right now rather than reporting noise.
4. **Pin threads identically across arms** — `POLARS_MAX_THREADS`, `OMP_NUM_THREADS`,
   `OPENBLAS_NUM_THREADS`, `MKL_NUM_THREADS`, `BLIS_NUM_THREADS`. A thread-count difference
   invalidates any comparison,
   and it also changes float results (see the correctness gate).

## Phase 1 — triage (minutes, then offer to go deeper)

**`python -m cProfile` alone answers all three Phase-1 questions**, with zero edits and zero
installs. CPython's profiler times on `PyTime_PerfCounterRaw` — wall clock, which **includes time
blocked** — so `cumtime` on a driver call *is* the DB wait, and C methods get parseable labels like
`{method 'execute' of 'pyodbc.Cursor' objects}`.

```bash
uv run python -m cProfile -o .perf/run.prof target.py
uv run python ~/.claude/skills/make-it-faster/scripts/profile_split.py .perf/run.prof
```

Yields the **DB-vs-compute split** (driver `cumtime` vs total), the **query/request count**
(`ncalls` — the N+1 detector, free), and **blocking I/O time**.

Two caveats to encode, not assume:
- **cProfile sees the main thread only** (`sys.setprofile` is per-thread). A `ThreadPoolExecutor`
  extraction is invisible to it. Detect threading and cross-check with py-spy.
- Its overhead scales with *Python-level* call count. On this workload class (C-dominated: driver
  fetch, Polars, NumPy) it is small. If total Python `ncalls` is very large, distrust the ratio.

**py-spy is the complement** — all threads, near-zero distortion:

```bash
uv run --with py-spy py-spy record --idle --subprocesses --threads --rate 200 \
  --format speedscope -o .perf/prof.speedscope.json -- python target.py
```

- **`--idle` is mandatory.** Verified locally on a program doing 0.1 s compute then a 0.4 s wait:
  without it, 22 samples, **100% in the compute function** — the wait vanished. With it, 71 of 96
  samples landed in the wait. Profiling a DB program without `--idle` reports the exact inverse of
  the truth.
- **Never pass `--gil`** — it *"will miss activity in extensions that release the GIL while still
  active"*, and Polars/NumPy release the GIL. It hides precisely what you are measuring.
- `--native` is not CI-tested (py-spy #640, open since 2023) — the command above deliberately
  omits it. Native time then folds into the calling Python frame, which is enough for the
  extraction-vs-compute split; add `--native` only when C-level frames matter, and drop it again
  if it errors.
- Running twice, with and without `--idle`, **isolates wait time by difference**.

**Validate the profile before acting on it.** If the output is empty or shows only profiler
overhead, the target code path was not exercised — fix the invocation, don't report the noise.

**Memory:** peak RSS from `runstat.py` is the number that predicts OOM. `memray` attribution is a
*second* step and its absolute number is not trustworthy here — Polars statically links jemalloc as
its Rust global allocator, so memray cannot interpose. Measured on a 4M-row Polars+NumPy job:
memray reported 259.2 MB against a true peak RSS of 208.5 MB.

Then **stop and offer** to prototype-and-measure the remaining candidates, with a time estimate
derived from the measured baseline runtime × candidate count.

## Phase 2 — prototype each candidate, measure, revert

1. Copy the **project root** into the scratchpad (exclude `.venv` and data dirs), so
   `pyproject.toml`, relative paths, and `.env` still resolve; run the copy with
   `uv run --project`. **Record the original state** (params, date ranges, row limits) before
   shrinking anything, and restore + re-verify at full scale at the end.
2. **Materialize the compute fixture.** Time the extraction once, write the raw extract to
   parquet keyed per `references/memory.md`'s cache-key spec, and swap the extraction stage for
   the parquet read in **both** arms. Assert parity with the live path — schema and chunk
   count — because a single-chunk parquet read erases chunk-fragmentation bottlenecks and
   un-streams the input: findings in those classes cannot be measured on this fixture, and the
   report must say so.
3. Apply **one** change. Change one thing, re-run, verify. Revert anything that didn't help.
4. Benchmark per the currency table above — `scripts/abench.py` runs the whole compute protocol
   (interleaving, fresh processes, discards, both gates, the mandated wording); **write the
   expected direction and magnitude in one sentence before running it**. For compute:
   - **Interleave `A B A B …`**, n=10 pairs (15 if runs < 5 s), **fresh process every run**.
     Never `10×A` then `10×B` — that measures cache warming, since the baseline runs cold on
     imports, page cache, TLS, connection pool, DB buffer pool and plan cache while the candidate
     inherits all of it warm.
   - Cold run is n=1, labelled unrepeatable, **never compared**. Discard 3 warm-ups.
   - **Derive the noise floor from the A-arm of the same sequence** (a separate earlier block is
     invalidated by drift). `THRESHOLD = max(5%, 3 × CV_A)`. If `CV_A > 5%`, the machine is unfit.
   - **Two gates, both required:** 95% CI on the difference of means excludes zero **and** median
     improvement > `THRESHOLD`. Report both statistics; if they disagree, that *is* the finding.
5. Run the correctness gate (below). A change that fails it is rejected regardless of speed —
   after screening suite flakes (re-run a failing test ~10×; fails-once-passes-nine is a flaky
   test, not a rejection).
6. Revert. The scratch copy is discarded; the user's tree was never touched.

Full protocol and thresholds (the canonical copy): [`references/measurement.md`](references/measurement.md).
The report templates live below in this file.

## The correctness gate

**A faster program with different numbers is a regression.** Both a test run and an end-to-end
output snapshot must agree.

**Never use library defaults.** Verified against Polars 1.43.2:

```
SIG: assert_frame_equal(..., check_exact=False, rel_tol=1e-05, abs_tol=1e-08, ...)
DEFAULTS      -> PASSED   (a 1e-6 relative error silently accepted)
equals()      -> False    (catches it)
```

The default `rel_tol=1e-5` is ~10 orders of magnitude looser than the float64 FP-reordering noise
(~1e-15) it must be distinguished from. A gate on defaults waves through real regressions.

- **Ladder:** schema/shape/dtypes exact → `DataFrame.equals()` (bitwise) → non-float columns exact
  → floats at a tolerance **declared up front** from dtype and reduction size.
- **Exact on structure, tolerant on values.** Never respond to a failure by loosening the tolerance
  — escalate to the user instead.
- **Never `check_row_order=False`** — it sorts both frames by *all* columns including floats, so a
  1-ULP change reorders rows and fakes a whole-column mismatch. Sort explicitly on non-float keys.
- The user's outputs carry **timestamps / run IDs / paths** — mask them **explicitly**
  (`--mask`) before diffing; the gate flags name-suspect columns but never auto-drops them.
- Float drift is *caused by what this skill proposes* (loop→vectorized, transposes, thread counts).
  The fix for a float32 accumulation is a **wider accumulator, not a wider tolerance**.
- **Prove the harness can fail** by perturbing 10× the declared tolerance. A verification that has
  never gone red is not a verification.
- **Coverage:** if the changed lines aren't exercised, the honest report is *"the suite does not
  constrain this change"* — not "tests pass".

```bash
uv run python ~/.claude/skills/make-it-faster/scripts/equivalence.py .perf/baseline.arrow .perf/candidate.arrow
```

Full tolerance policy and FP-nondeterminism catalogue: [`references/correctness.md`](references/correctness.md).

## The report

`.perf/YYYY-MM-DD-HHMM-<target>.md`, timestamped per run. **Append** `.perf/` to `.gitignore`
(create `.gitignore` if the repo has none); never overwrite an existing report — each run gets a
new timestamped file. Keep the flamegraph, the cached parquet extract, and the working
prototypes alongside the report. Open every report with the environment block — Python and
package versions, CPU model, governor, load, exact commands, timestamps (`abench.py` prints it).

Two ranked sections, **each in its own currency**. Use the matching template — never fill an
extraction finding into the compute template, because its interleaved-pairs CI field would then
hold a number you did not measure.

**Compute findings** — ranked by measured seconds saved:

```
### C<n>. <one-line claim>           [risk: mechanical | code-shape | architectural]
Where:       file.py:LINE
Evidence:    <profile line / ncalls / copy-report row that localized it>
Measured:    <before>s -> <after>s median, n=<pairs> interleaved pairs, fresh process each
             95% CI on the difference [<lo>, <hi>] (excludes zero), noise floor CV <measured>
Correctness: IDENTICAL | WITHIN_TOLERANCE (rel_tol <declared>, max observed <measured>)
Coverage:    <% of changed lines exercised by the suite>

Before:  ```python …```
After:   ```python …```
Why:     <mechanism — and if it explains only part of the delta, say so>
```

**Extraction findings** — ranked by rows/bytes/round-trips eliminated:

```
### E<n>. <one-line claim>           [risk: mechanical | code-shape | architectural]
Where:       file.py:LINE
Evidence:    <get_result_batches / X-ClickHouse-Summary / ncalls on execute / SELECT vs used>
Measured:    rows        <before> -> <after>
             bytes       <before> -> <after>
             round-trips <before> -> <after>
Derived:     ~<seconds>s at the observed <MB/s> throughput — DERIVED, NOT TIMED
Wall clock:  <before>s -> <after>s, n=<reps>, median; within the server's observed run-to-run
             range of <lo>-<hi>s  [omit this line entirely if the range swamps the delta]
Correctness: IDENTICAL | WITHIN_TOLERANCE (rel_tol <declared>, max observed <measured>)

Before:  ```python …```
After:   ```python …```
Why:     <mechanism>
```

Every seconds figure in the extraction template is labelled **derived, not timed**. If
`cpu_fraction < 0.3`, the wall-clock line is context, never the headline — with one exception: a
**pushdown finding that also eliminates client compute** (a server-side aggregate replacing a
client group-by) cannot be credited on the frozen fixture, because it changes the fixture's own
input. For that class, run a live end-to-end A/B (few reps, median + CI, both arms cache-busted)
and report it as a first-class second figure labelled **live-measured**, alongside the derived
transfer seconds.

Close with **what was not compared**: cold start, other hardware, other data volumes, and whether
the DB was in the same cache state for both arms. A measured speedup is a claim about *this*
machine, *this* data, and *this* server state — expert reference patches survive cross-machine
replay for only 39/102 GSO and 11/140 SWE-Perf tasks.

For a result inside the noise band, use the mandated wording — never "slightly faster" or "~2%
faster":

> **NO MEASURABLE DIFFERENCE.** Median `<measured>` → `<measured>`, n=`<pairs>` interleaved pairs.
> Measured noise floor CV `<measured>`. The 95% CI on the difference includes zero. This change is
> WITHIN NOISE — it may be a small improvement, a small regression, or nothing. It should not be
> claimed as a speedup.

## Do not

- Propose anything you did not measure, or a fix for a stage below the Amdahl gate.
- Repeatedly run a pipeline whose output stage still writes to production — neutralize sinks
  first (precondition 4).
- Compare `n×A` then `n×B`, reuse a process between timing runs, or cache across runs.
- Report a wall-clock ratio as the headline for an I/O-bound program.
- Loosen a tolerance to make a comparison pass.
- Assume streaming/laziness fixed the memory — verify, since non-streaming ops silently fall back.
- Edit, stage, or commit anything in the user's tree.

## References

Load on demand — do not read all of these up front.

| File | When |
|---|---|
| [`references/measurement.md`](references/measurement.md) | Benchmark protocol, statistics, profiler selection and exact commands |
| [`references/extraction.md`](references/extraction.md) | Snowflake, Snowpark, MSSQL, ClickHouse, REST — fast paths, diagnostics, anti-patterns |
| [`references/compute.md`](references/compute.md) | Polars and NumPy/SciPy playbook, version-pinned |
| [`references/memory.md`](references/memory.md) | OOM diagnosis, out-of-core, and dev-loop caching |
| [`references/correctness.md`](references/correctness.md) | Tolerance policy, FP nondeterminism, snapshot format |
