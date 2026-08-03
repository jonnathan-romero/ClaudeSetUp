# Measurement: protocol, statistics, and profiler selection

Everything here is version-pinned to 2026-08. Re-verify tool flags before trusting them.

## Why the naive loop is wrong

Baseline-then-fix measures **cache warming**, not the fix. The baseline runs cold on imports,
`__pycache__`, OS page cache, DNS/TLS, the connection pool, the DB buffer pool and the plan
cache; the candidate inherits all of it warm. This is a **systematic** error — no amount of
repetition or CI arithmetic removes it.

Context for the magnitude: Mytkowicz et al. (ASPLOS'09) showed a *completely inert* change —
the byte size of an unused environment variable — moving runtime *"frequently by about 33% and
once by almost 300%"*, and a **7% spread in measured speedup for the same optimisation** across
setups. Repeated identical Python runs on one untuned box show ~1–1.5% wall-clock noise.

The literature names the fix directly. Georges et al. (OOPSLA'07) list *"back-to-back
measurements ('aaabbb') versus interleaved measurements ('ababab')"* as a design axis; Scherer
(2026) is blunter: *"Avoid comparing measurements from different runs of the benchmark."*

## The protocol

**Phase 0 — gates.** `runstat.py` once. `cpu_fraction < 0.3` → I/O bound, switch currency.
Amdahl: target stage < 10% of runtime → refuse to prototype. Three-run fitness check; a spread
> 10% or a monotone trend (thermal) means stop. Pin `POLARS_MAX_THREADS`, `OMP_NUM_THREADS`,
`OPENBLAS_NUM_THREADS`, `MKL_NUM_THREADS`, `BLIS_NUM_THREADS` identically across arms.

**Keep ASLR on.** pyperf: *"ASLR must *not* be disabled manually!"* Mytkowicz froze the layout
for single-setup causal analysis; you instead sample many layouts via many fresh processes.

**Phase 1 — regime.** Warm steady state is the comparison regime. Cold start is one
observation, labelled unrepeatable, never compared — you cannot force cold anyway
(`drop_caches` needs root, and a *remote* DB's cache cannot be flushed by a client at all).
Discard 3 warm-up runs.

**Phase 2 — A/B.** Interleave `A B A B …`, n=10 pairs (15 if runs < 5 s), **fresh process every
run**. Discard run 1 of each arm, plus outliers **only where a perturbing cause is identifiable**
(Georges: *"if the outliers are a result of a perturbing event, they should be discarded"*).

**`scripts/abench.py` implements this protocol end to end** — interleave, fresh process, warm-up
and run-1 discards, both CIs, both gates, the mandated within-noise wording — use it rather than
hand-rolling the loop:

```bash
uv run python ~/.claude/skills/make-it-faster/scripts/abench.py \
  --a "uv run python baseline.py" --b "uv run python candidate.py"
```

**Pre-register the expectation.** Before the first pair, write the expected direction and rough
magnitude in one sentence — an A/B read without a pre-registered prediction is read with
rose-tinted glasses, by humans and by the agent that just authored the candidate.

When a stage delta is diluted by fixed process overhead (imports both arms pay identically), an
in-process timer around the changed region may be added as a *diagnostic*; the whole-process A/B
remains the claim of record.

**Phase 3 — statistics.** Per arm: median (headline), MAD, min, mean, stddev, n. Compute the
95% CI on the difference of **means** using the t-distribution (n < 30). Also compute the paired
per-pair difference CI — strictly tighter, because it cancels the drift interleaving exposes.

**Derive the noise floor from the A-arm of this same sequence**, never a separate earlier block
(drift invalidates it): `CV_A = stdev(A)/mean(A)`, `THRESHOLD = max(5%, 3 × CV_A)`. Abort if
`CV_A > 5%`.

**Two gates, both required** — this is pyperf's design (a t-test at α=0.95 *and* a `--min-speed`
effect size, else it prints `"Not significant!"`):

- Significance: CI on the difference of means excludes zero.
- Effect size: median improvement > `THRESHOLD`.

They deliberately use different statistics — the mean is the only one with a defined test, the
median is the one that resists this workload's right-skewed noise. **If they disagree, that is
the finding**: report both and call it inconclusive.

## Thresholds

| Quantity | Value |
|---|---|
| Warm-ups discarded | 3, plus run 1 of each arm |
| Interleaved pairs | 10, or 15 if a run is < 5 s |
| Process reuse | none — fresh every run |
| Headline statistic | median |
| Significance | 95% CI on difference of means (t, n<30), excludes 0 |
| Minimum claimable effect | `max(5%, 3 × CV of the A-arm)` |
| Machine unfit | CV > 5%, or a monotone trend across runs |
| Amdahl pre-gate | stage must be ≥ 10% of end-to-end runtime |
| I/O-bound switch | `cpu_fraction < 0.3` |

No source prescribes a numeric "real win" threshold; these rest on measured noise floors plus
off-the-shelf gates (pytest-benchmark's `min:5%`, pyperf's `--min-speed`). **This table is
canonical** — SKILL.md restates these values for the core loop; if the two ever disagree, this
file wins.

## Network-dominated work

Wall-clock A/B against a server you don't control is sampling the server. `time.process_time()`
*"does not include time elapsed during sleep"* while `perf_counter()` *"does include"* it — that
ratio is the gate. Report distributions, not averages: p50/p90/p99, CV, IQR. And **count work
instead of timing it** — round-trips, bytes, and rows are deterministic and machine-independent.

**Live-arm budget.** "Fewer reps" has a ceiling: 3–5 reps per arm against a billed warehouse or
metered API, and ask before hammering a shared production source — Phase 1's stop-and-offer
covers *time*, not money or prod load. Pin both arms to the same data where the source allows it
(Snowflake `AT(TIMESTAMP => …)`; otherwise compare on a keyed intersection and report drift).

Snowflake's result cache biases the comparison **against** the fix, systematically: identical SQL
re-run hits the 24 h cache so the baseline looks instant, but any rewrite busts it, so the
candidate pays full cost and can measure *slower* while being genuinely faster. Set
`USE_CACHED_RESULT = FALSE` on both arms. Do **not** `ALTER WAREHOUSE … SUSPEND` — ≥60 s of
credits per cycle plus a cold cache that makes the next run unrepresentative.

## Profilers

**`uvx` vs `uv run --with` is structural.** `uvx` is *isolated* — fine for out-of-process py-spy
and austin, which never import your code. **`uv run --with` is required for every in-process
profiler** (pyinstrument, scalene, viztracer, cProfile) or Polars and the DB driver won't import.
Anti-pattern: `uvx py-spy record -- uv run python prog.py` puts a `uv` wrapper between py-spy and
the interpreter.

| Tool | Blocking I/O | Native frames | Wall vs CPU |
|---|---|---|---|
| py-spy 0.4.2 | **only with `--idle`** | yes (`--native`, x86-64 Linux) | `--idle` on/off |
| scalene 2.3.0 | yes; "system" column | no frames, but **per-line Python/native/system split** | `--use-virtual-time` |
| pyinstrument 5.1.3 | yes (wall by design) | no | wall only |
| cProfile | yes (wall-clock timer) | no — and inflates the Python side | neither |

**Verified locally on this machine:** `uv run --with py-spy py-spy record` works with **no sudo**
under `ptrace_scope=1` (launch mode is unaffected); `uv run --with memray python -m memray run`
works; `/usr/bin/time -v` is **missing on Arch**.

```bash
# py-spy — primary. --idle is mandatory; --gil is forbidden.
# Deliberately omits --native (not CI-tested, py-spy #640): native time then folds into the
# calling Python frame, which is enough for extraction-vs-compute attribution. Add --native
# only when C-level frames are needed, and drop it again if it errors.
uv run --with py-spy py-spy record --idle --subprocesses --threads --rate 200 \
  --format speedscope -o .perf/prof.speedscope.json -- python target.py

# Same without --idle; the diff isolates wait time. Diff collapsed stacks against collapsed
# stacks — re-run the --idle arm with --format raw too, don't diff speedscope JSON.
uv run --with py-spy py-spy record --subprocesses --rate 200 \
  --format raw -o .perf/prof.cpu.folded -- python target.py

# scalene — Python/native/system split per line. --cli is mandatory (default opens a browser).
# If target.py takes its own arguments, separate them with ---
uv run --with scalene python -m scalene --cli --json --outfile .perf/scalene.json \
  --cpu --profile-all --reduced-profile target.py

# pyinstrument — 30% overhead, fast triage. NOTE: main thread only.
uv run --with pyinstrument pyinstrument -r speedscope -o .perf/pyinst.json target.py
```

**Blind spots to state, not paper over:** pyinstrument does not profile other threads at all.
**Nothing** here sees a pure-C thread created inside a native library and never registered with
CPython (py-spy #332, open since 2020) — a C-level connection pool is invisible to every tool.
The escape hatch for exactly that case: `strace -f -c -w -e trace=network python target.py` —
syscall counts and wall time spent in network calls, no Python cooperation needed.

## If a wrapper is unavoidable

Prefer cProfile + py-spy. When a per-query wrapper is genuinely needed (SQL text, per-query row
counts): patch module-level `connect` and return a proxy — pyodbc's C types cannot be patched or
subclassed at all (see `extraction.md`). Inject it zero-edit via a `sitecustomize.py` in a
scratch directory on `PYTHONPATH` — the exact mechanism `opentelemetry-instrument` itself uses.
Never write `.pth` files into site-packages; `PYTHONSTARTUP` is interactive-only. **OpenTelemetry
itself is rejected here**: its instrumentor list has no pyodbc, no Snowflake, no ClickHouse
(snowflake-connector-python#1891 — *"snowflake is invisible"*), and it installs packages into
the user's environment.

**Watch item:** Python 3.15's `profiling.sampling` (Tachyon, PEP 799) has `--mode=wall|cpu|gil`,
`--native`, `--subprocesses`, and needs no privileges — it likely becomes rank 1. 3.15 final is
2026-10-01. Revisit then.

## Reporting

Real win: medians, ratio, n, regime, CI, measured noise floor, **plus a qualitative claim**
("roughly 1.5× faster"), because per Scherer the qualitative form survives a hardware change
while the exact ratio does not.

Always state what was **not** compared: cold start, other hardware, other data volumes, and
whether the DB was in the same cache state for both arms.

**Record the environment per measurement** — Python and package versions (Polars/NumPy/driver),
CPU model, governor and turbo state, AC-vs-battery, load average, the exact command line, and a
timestamp per run (`abench.py` prints most of this). It is what lets a later reader judge
whether two numbers are comparable at all.

**Test the explanation before claiming causation.** If the claim is "faster because it avoids a
materialisation", show the profile line for that materialisation accounting for *most* of the
delta. If it accounts for only part: *"A is faster than B because of foo and some other factor
we don't understand yet."*
