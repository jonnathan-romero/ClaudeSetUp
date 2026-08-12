# Test failure modes — the shared catalog

Used by the `write-tests` skill (to avoid writing these) and the `@test-suite-auditor` agent
(to find them). One entry per defect class.

**What this catalog is not.** It deliberately omits advice a competent model already follows —
"use fixtures", "cover edge cases", "arrange-act-assert", "give tests clear names". That material
is ballast: it dilutes the signal and changes no behavior. Everything here is either something
measurably gotten wrong, or something that cannot be recognized without knowing a specific fact.

**Detection tags.** `[static]` = decidable from source alone (AST/grep). `[static-config]` = only
the config's presence or absence is visible, not the defect. `[runtime]` = needs the suite to run.
`[judgment]` = no predicate exists; do not pretend otherwise.

**Severity tags.** `false-pass` = the test reports green when the code is broken. `no-op` = the
test or marker does nothing at all. `brittle` = fails for reasons unrelated to its name.
`degraded` = works, but a failure teaches you nothing. Rank `false-pass` and `no-op` first — those
are the ones that make a suite actively misleading rather than merely imperfect.

## Contents

1. [**The test cannot fail**](#family-1--the-test-cannot-fail) — assertion-free, always-true
   asserts, narrow assertions, stub-echo tautologies, mock-assertion-only, non-strict `xfail`,
   unconditional skips, never-collected, typo'd markers, unmarked async. *Highest severity; start here.*
2. [**The test asserts on the wrong thing**](#family-2--the-test-asserts-on-the-wrong-thing) —
   implementation-mirroring, communication-by-default, mocking managed or unowned dependencies,
   non-autospecced mocks, wrong patch target, log/`repr` assertions, unpinned `raises`.
3. [**Nondeterminism the model introduces**](#family-3--nondeterminism-the-model-introduces) —
   `sleep()` as synchronization, order dependence, manual global mutation, set iteration,
   `approx` tolerance traps, unfrozen `now()`, unseeded randomness, real network.
4. [**Laundering and process defects**](#family-4--laundering-and-process-defects) — rerun-until-green,
   snapshot laundering, unmarked pinned bugs, mode inversion, coverage exhaustion, solo-covered lines.
5. [**Opportunity cost**](#family-5--opportunity-cost) — missing round-trip and idempotence
   properties, fabricated golden values, tautological properties, Hypothesis fixture scope.
   *Suggestions, not defects.*

---

## Family 1 — The test cannot fail

The highest-severity family. A suite full of these is worse than no suite: it reports safety.

### assertion-free-test · `false-pass` · `[static]`
Calls the code and ends — no `assert`, no `pytest.raises`, no `assert_*`.
Green as long as nothing raises, so it certifies "the import worked" while inflating coverage.
**Check:** `test-census.sh` (resolves asserting helpers to a fixpoint first — a naive AST count is
wrong by 5× on repos with a custom idiom).
**Not always a defect:** a `benchmark` fixture, a decorator that *is* the assertion, or a
`catch_warnings` block under `filterwarnings = error` all assert invisibly. The census separates
these into REVIEW.

### always-true-assertion · `false-pass` · `[static]`
`assert (x == y,)` — a stray trailing comma makes the condition a non-empty tuple, always truthy;
`x == y` with the `assert` keyword missing entirely; `assert "should have raised"`.
All three are unconditionally green, and the tuple variant is a classic reformat accident.
**Check:** ruff `F631` (assert on non-empty tuple), `B015` (comparison with no `assert`),
`PLW0129` (assert on a string literal). Exact and zero-cost. Do not conflate with `PT015`
(`assert False`), which always *fails*.

### narrow-assertion-mutant-survives · `false-pass` · `[runtime]`
`assert result is not None`, `len(out) > 0`, `isinstance(x, list)` — true of almost any
implementation, including a wrong one.
Coverage reports the line covered, so the gap is invisible to every metric anyone watches.
**Check:** `sabotage-check.sh`; a surviving sabotage *is* the operational definition. `[static]` can
flag the weak shapes as candidates; "how narrow is too narrow" is `[judgment]`.

### stub-echo-tautology · `false-pass` · `[static]`
`mock.return_value = X` → call the unit → `assert result == X`.
A tautology about the mocking library. Passes even if the unit's entire transformation is deleted.
**Check:** AST — a literal or name bound to `return_value`/`side_effect` in setup reappearing as
the expected operand with no intervening transformation.

### mock-assertion-only · `false-pass` · `[static]`
The only assertion is `assert_called_once_with(...)`.
Passes for any implementation that makes the call, including one that discards the result — and
fails on every rename or reorder. Catches nothing, breaks often.
**Check:** AST — test whose only assertion nodes are `assert_called*`/`assert_has_calls`/
`assert_any_call`, with no bare `assert` and no `pytest.raises`.

### didnt-raise-only · `degraded` · `[static]`
The whole test is "call it and assume no exception means correct."
Legitimate as a smoke test; a defect when it is the *only* test for behavior that has a value.
**Check:** AST, same predicate as assertion-free. Distinguishing intent is `[judgment]`.

### xfail-without-strict · `no-op` · `[static]`
`@pytest.mark.xfail` without `strict=True` and no repo-level `xfail_strict`/`strict_xfail`.
Reports nothing in either direction, permanently: fixed → XPASS stays green and nobody removes the
marker; regressed → XFAIL stays green. The most effective way to delete a test without deleting it.
**Check:** AST for the marker, cross-referenced against the live config table. Exact, repo-wide,
and high-yield — non-strict is the **default**, and six of nine elite Python repos leave it off.

### unconditional-skip · `no-op` · `[static]`
`@pytest.mark.skip` with no condition. Invisible in a default run — one character in the progress
bar. A skip older than a year is dead code wearing a test's name.
**Check:** AST for the marker; `pytest -ra` surfaces it at runtime; cross-check against `git log`.

### declared-but-never-collected · `no-op` · `[static]`
The function exists and never runs — shadowed by a duplicate module basename, hidden by
`collect_ignore`, filtered by a `pytest_collection_modifyitems` hook, or deselected by a marker
filter baked into `addopts` or CI.
**Check:** `test-census.sh` with a `--collect-only` dump. The dump **must** be taken with
`-o addopts=""`, or the repo's own `-q` stacks with yours and prints per-file counts instead of
node IDs — making every test look uncollected.

### typo-d-marker · `no-op` · `[static-config]`
`@pytest.mark.slwo` silently removes the test from every filtered run, forever — unless
`--strict-markers` is on.
**Check:** compare used marker names against the registered `markers` list; report whether
`--strict-markers` is enabled at all.

### async-test-not-marked · `no-op` · `[static-config]`
An `async def test_` with no `@pytest.mark.asyncio`/`anyio` and no `asyncio_mode = auto`.
On pytest ≤7 this **silently skips** — a green tick that never executed. pytest ≥8 fails it, so the
risk is largely historical, but `asyncio_mode` set with the plugin *absent* is only an error under
`--strict-config`.
**Check:** AST + the live pytest version + which async plugin is actually installed.

---

## Family 2 — The test asserts on the wrong thing

Passes and fails for the wrong reasons. Erodes trust rather than reporting danger.

### assertion-mirrors-implementation · `brittle` · `[judgment]`
The expected value was derived by reading the code under test, so the test can only confirm what
the code already does.
This is the root LLM failure, and it is measured: models "generate oracles that capture the actual
program behaviour rather than the expected one," and buggy input steers them into writing tests
that *validate* the bug. Mitigation: prompt from the spec/docstring, not the body.
**Check:** `[judgment]`. The only mechanical proxy is a sabotage or mutation survivor.

### communication-verification-by-default · `brittle` · `[static]`
Reaching for "assert it called X" when an output-based or state-based assertion was available.
The lowest rung of the verification ladder — binds the test to wiring, produces false positives on
refactors, and still misses a wrong return value.
**Check:** ratio of `assert_called*` to value/state assertions per module. Whether a better rung
existed is `[judgment]`.

### mocking-a-managed-dependency · `false-pass` · `[judgment]`
Patching the app's own database/repository/cache instead of using a real or in-memory instance.
The mock encodes assumed query semantics; real constraints, ordering, and transactions are never
exercised, so schema and query bugs pass silently. Managed (yours alone) → use it. Unmanaged
(observable by other systems: SMTP, payment API, message bus) → double it.
**Check:** AST can list `patch()` targets resolving to first-party data modules; the
managed/unmanaged call is `[judgment]`.

### mocking-what-you-dont-own · `false-pass` · `[static]`
`patch("requests.Session.send")`, `patch("boto3.client")` — freezing a third-party contract.
The mock encodes your *guess*. The library upgrades, real behavior changes, the mock keeps
returning the old shape, and the suite stays green through a production break.
**Check:** AST — `patch()`/`patch.object()` target whose root package is in the dependency
manifest but not first-party. This one is cleanly decidable.

### non-autospecced-mock · `false-pass` · `[static]`
A bare `MagicMock()` with no `spec=`/`create_autospec`.
Auto-creates every attribute, so a typo, a renamed method, or a changed signature never raises —
the test cannot detect that the collaborator's API moved.
**Check:** AST — `Mock()`/`MagicMock()` without `spec`/`spec_set`/`autospec`.

### mock-assertion-that-never-asserts · `no-op` · `[static]`
`m.called_once()`, `m.not_called()`, `m.assert_called_once` (no call).
Python guards only the `assert`/`assret`/`asert`/`aseert`/`assrt` prefixes; everything else is an
auto-created attribute that is always truthy and asserts nothing.
**Check:** AST for `Mock` attribute calls not in the real `assert_*` API, and for `assert_*`
accessed but never called.

### asyncmock-called-not-awaited · `false-pass` · `[static]`
`assert_called_once()` on an `AsyncMock` passes when the coroutine was created and never awaited;
`.called` is even `True` on creation.
**Check:** AST — `assert_called*` on a receiver bound to `AsyncMock`. Use `assert_awaited*`.

### patched-the-wrong-name · `false-pass` · `[static]`
Patching where an object is *defined* rather than where it is *looked up*.
A **valid but unused** target patches nothing and the test silently exercises the real code. Note
the asymmetry that makes this tractable: a *nonexistent* attribute raises `AttributeError` loudly,
so only the valid-but-unused case is silent. **No lint rule anywhere catches this** — not ruff, not
pylint, not flake8.
**Check:** AST — resolve the patch target string against the module actually imported by the code
under test.

### asserting-on-log-output · `brittle` · `[static]`
Using `caplog` as a proxy for behavior when a value was available.
Log text is not a contract; the assertion breaks on rewording that changes nothing.
**Check:** grep for `caplog`/`assertLogs` in tests whose subject is not logging itself.

### sensitive-equality · `brittle` · `[static]`
Asserting `str(obj)`/`repr(obj)` against a literal.
Couples the test to commas, quotes, and field order. Legitimate only when `__str__` *is* the
contract.
**Check:** AST — `Eq` with `str(...)`/`repr(...)`/f-string on one side and a literal on the other.

### whole-object-assertion · `degraded` · `[judgment]`
Asserting equality on an entire structure when one field is the behavior under test.
Fails for reasons unrelated to its name, so the failure carries no information — over-assertion
producing the same practical outcome as under-assertion: an ignored signal.

### testing-private-helpers · `brittle` · `[static]`
Direct tests of `_foo`. Pins an implementation detail as if it were a contract.
**Check:** AST — test calling a module-level `_`-prefixed callable.
**Caveat before reporting:** elite repos do this deliberately and at volume (sqlalchemy 412 sites,
pydantic 87). attrs states the policy in its ignore list. Report as a question in a repo that has
clearly chosen it.

### unpinned-pytest-raises · `false-pass` · `[static]`
`pytest.raises(ValueError)` with no `match=`, for a function that raises `ValueError` five ways.
Passes on the *wrong* error — including one raised by a typo in the test's own setup.
**Check:** AST. Note ruff's `PT011` only fires for **7 stdlib exception names**, so
`pytest.raises(MyDomainError)` is *not* flagged by default — do not assume lint covers this.
Secondary: `match=` is `re.search`, so unescaped metacharacters silently change the pattern.

### raises-block-too-wide · `degraded` · `[static]`
Several statements inside one `pytest.raises` block, so the wrong line may be the one that raises.
**Check:** ruff `PT012`, or AST on block length.

---

## Family 3 — Nondeterminism the model introduces

Passes locally, fails in CI, gets "fixed" with a rerun. One triage rule for the whole family:
a flake is not automatically a test defect — empirically 24% of flaky-test fixes modify the
code under test, and 94% of those fix a real bug. A flaky test can be a bug report.

### sleep-as-synchronization · `flaky` · `[static]`
`time.sleep()` / `asyncio.sleep()` to wait for a thread, subprocess, or server.
**The decisive number:** across 20 sleep-based flake fixes, *zero* removed the flakiness; of 42
`waitFor`-style fixes, 23 did. And generous polling is *faster* in practice — mean configured
timeout 13s vs sleep's 1.5s, because polling returns as soon as the condition holds.
**Check:** AST — `sleep(` with a nonzero argument inside a test or fixture. High precision.

### order-dependent-suite · `flaky` · `[runtime]`
One test mutates module state, a singleton, a cache, or a DB row that a later test reads.
Already broken while green: the passing order is an unenforced precondition. 12% of flaky tests
empirically, and **47% of order-dependency cases come from external resources** — so "no globals"
is not sufficient.
**Check:** `pytest -n 4 --dist load` — it splits coupled tests across processes and exposed a
planted dependency **deterministically**, where a seed sweep needed 7 tries (seed 42 was clean).
**Mandatory gate:** exclude tests marked `xdist_group` first, and if CI already runs
`--dist loadgroup`/`loadfile`, treat that as the team *declaring* those tests may share state.

### manual-global-mutation-without-restore · `flaky` · `[static]`
`os.environ["KEY"] = ...`, `os.chdir(...)`, or a bare `setattr(module, ...)` in a test —
nothing restores it, so the next test inherits the mutated state and the failure lands on the
wrong test. `monkeypatch` undoes all of these automatically.
**Check:** AST — assignment to `os.environ[...]`, `os.chdir(`, or `setattr(` on a module inside
a test/fixture body with no `monkeypatch` in scope. High precision.

### set-iteration-order-assertion · `flaky` · `[static]`
`assert list(some_set) == [...]`. Set order follows per-process-randomized string hashes.
**Dict order IS guaranteed (insertion order) — never flag it.** Only sets and frozensets.
**Check:** AST — sequence compare or subscript on a set literal/`set()`/set comprehension with no
intervening `sorted()`.

### float-equality-without-approx · `flaky` · `[static]`
`assert compute() == 3.14159`. Breaks under a different BLAS, summation order, or libm.
**Check:** AST — `Eq` against a float literal with no `pytest.approx`. High false-positive rate;
report as review, not defect.

### approx-abs-silently-drops-rel · `brittle`/`false-pass` · `[static]`
`pytest.approx(expected, abs=1e-6)` believing it *tightens* the default.
Specifying `abs` alone **disables `rel` entirely** — `approx` is a disjunction, not the additive
formula on the same docs page (that one is `numpy.isclose`). The direction depends on the
expected value's magnitude: for large values the check becomes far *stricter* than intended
(brittle false alarms); near zero it becomes *looser*, in the direction of passing.
**Check:** AST — `approx` with `abs=` and no `rel=`. Exact predicate.

### nan-equality-assumption · `brittle` · `[static]`
`approx` treats NaN as unequal to everything without `nan_ok=True`, so the failure looks like a
code bug.
**Check:** AST — `approx`/`== nan` with no `nan_ok=True` and no `isnan` guard.

### unfrozen-now · `flaky` · `[static]`
`datetime.now()`/`time.time()` in a test with an assertion derived from it.
Fails at UTC midnight, month end, leap day, or across a second boundary — after passing for months.
**Check:** AST — those calls with no `freeze_time`/`time_machine`/`travel` in scope and no injected
clock.

### unseeded-randomness · `flaky` · `[static]`
`random.*`/`np.random.*`/`uuid4()`/faker with no fixed seed → an unreproducible red build.
**Check:** AST, **and** check whether `pytest-randomly` is installed — it reseeds before every test
and neutralizes this. Skipping that check destroys the precision.

### hash-randomization-dependence · `flaky` · `[static-config]`
Anything downstream of `hash()` on str/bytes. Varies *between processes*, so local reruns never
reproduce — the classic "1-in-N CI failure with no diff."
**Check:** you can only report whether `PYTHONHASHSEED` is pinned. Do **not** claim to detect the
defect statically.

### real-network-in-unit-test · `flaky` · `[static]`
A "unit" test issuing a real HTTP request, or touching a path outside `tmp_path`.
Top-5 empirical flake cause; 60% of network flakes are remote failures outside your control.
**Check:** AST — `requests.`/`httpx.`/`urlopen`/`socket.` with no `responses`/`respx`/`vcr`/
`monkeypatch` in scope; `open(` on a non-`tmp_path` path.
**Caveat:** httpx and urllib3 deliberately run real local servers. Local is not remote.

### stale-cassette · `false-pass` · `[static-config]`
A VCR cassette recorded once and never regenerated pins a contract the provider may have abandoned.
**Check:** cassette file mtimes against repo activity. Whether upstream changed is unknowable here.

---

## Family 4 — Laundering and process defects

### rerun-until-green · `false-pass` · `[static]`
`--reruns` in `addopts`/CI, `pytest-rerunfailures`, `@pytest.mark.flaky`.
Also an **audit-blocking** finding: in a suite that reruns failures, every flaky test is invisible
in a normal run, so strip it (`-p no:rerunfailures`) before measuring anything.
**Tone:** Google and Microsoft both quarantine and rerun deliberately, and name the cost themselves
(2–16% of Google's testing budget). The honest line is **"a rerun is a ticket, not a fix"** — not
"reruns are always wrong."

### snapshot-laundering · `false-pass` · `[judgment]`
Regenerating a snapshot to make a red diff green, which records the buggy behavior as approved.
Fix the bug *before* re-recording.
**Check:** `[judgment]` in general; a snapshot file changing in the same commit as a bug fix is a
`[static]` smell worth surfacing.

### unmarked-pinned-bug · `brittle` · `[static]`
A characterization test pinning behavior that is actually a bug, with no comment saying so.
The next reader treats it as the specification and "fixes" the code to match a test that was only
ever describing what happened to be true.
**Check:** grep characterization/golden tests for an explanatory comment. Absence is the finding.

### mode-inversion · `false-pass` · `[judgment]`
Treating legacy code as new (asserting intended behavior, so the suite is red from birth and gets
"fixed" by weakening tests) or new code as legacy (pinning whatever it currently does, so bugs
become the specification).
No predicate. This is why `write-tests` declares its mode in the module docstring — the declaration
is what makes the error visible to a later reader.

### coverage-already-exhausted · `false-pass` · `[runtime]`
Treating `--cov-fail-under=90` as proof a module is tested.
At Google, **each bug-introducing change was already covered by existing tests** — coverage cannot
move on the exact line that ships the fault.
**Check:** coverage as a floor only, then `sabotage-check.sh` or a scoped mutation run.

### solo-covered-line · `degraded` · `[runtime]`
A line whose only coverage comes from one test — a per-line bus factor.
On attrs (which gates at **100%** coverage), 11.3% of covered lines are held up by exactly one
test. Cross it with the assertion-free list and you get *covered but never checked*.
**Check:** `pytest --cov-context=test --cov-branch`, then query the `arc` table of the coverage
SQLite DB (0.52s over 660k rows). Adoption of contexts is ~0.3%, which is why this finds things
nobody has looked at.
**Gotchas:** with `--cov-branch`, `line_bits` is empty and everything is in `arc`; any later plain
coverage run **wipes the contexts**, so use a separate `COVERAGE_FILE`; the empty context `''`
means import-time execution, not a test.

---

## Family 5 — Opportunity cost

Not defects. Report as suggestions, and only where they are cheap.

### missing-round-trip-property · `[static]`
Name-paired functions (`encode`/`decode`, `dumps`/`loads`, `to_x`/`from_x`) with no test applying
one to the other's output. The best value-per-token property there is, and models reach for
examples because examples dominate their training data.

### missing-idempotence-property · `[static]`
A normalizer/sanitizer/migration tested only on fresh input, never on its own output. "Apply twice"
is where double-escaping, double-prefixing, and re-migration bugs live.

### fabricated-golden-value · `false-pass` · `[judgment]`
When the correct output genuinely cannot be computed (a solver, a ranker, a numerical routine),
inventing a plausible expected value and asserting it. The made-up oracle pins wrong behavior
as correct, and the eventual fix reads as a regression.
A metamorphic relation needs no ground truth: relate two *executions* instead of predicting one
output — `sin(x) == sin(pi - x)`, `count(q) >= count(q + refinement)`; round-trip and
idempotence are the common special cases. For nondeterministic output, relate with
subset/bounds/ordering, never `==`.
**Check:** none mechanical. A weak `[static]` smell: a magic literal as the expected value with
no comment and no derivation.

### tautological-property · `false-pass` · `[judgment]`
A `@given` property that restates the implementation inside the assertion. Passes for *any*
implementation while looking like the most rigorous test in the file — **the LLM-specific
property-based failure**, because `@given` scaffolding is trivial to generate and an independent
oracle is not. A pseudo-oracle must be produced *independently* to be worth anything.
**Check:** none. Do not pretend an AST check exists; the only proxy is a mutation survivor.

### hypothesis-function-scoped-fixture · `flaky` · `[static]`
`@given` combined with a function-scoped fixture. It resets once per **test**, not once per
generated example, so state leaks between examples and failures don't reproduce from the reported
minimal case.
**Check:** exact and high-signal — any `suppress_health_check` containing
`HealthCheck.function_scoped_fixture`.

---

## Sources

Empirical claims here trace to: van Deursen, Moonen, van den Bergh & Kok, *Refactoring Test
Code*, CWI SEN-R0119 / XP2001 (the original test-smell catalog, incl. Sensitive Equality —
quoted from the primary PDF at ir.cwi.nl/pub/4324); Just et al. FSE 2014 (mutant/real-fault coupling); Petrović &
Ivanković ICSE-SEIP 2018, ICSE 2021, and TSE 2021 (mutation at Google, arid nodes, coverage
exhaustion); Luo et al. FSE 2014 (flaky-test root causes and the sleep/waitFor fix table); Micco
2016 and Lam et al. ISSTA 2019 (industry flakiness rates); Alshahwan et al. 2024 (Meta TestGen-LLM
filtration and attrition); Zhao, Zhou & Cohen ISSTA 2026 (coverage/mutation reliability for
LLM-written suites); Hora & Robbes MSR 2026 (coding agents and mock prevalence); Khorikov
(verification-style ladder, managed vs unmanaged dependencies); Freeman & Pryce GOOS (don't mock
what you don't own); Feathers (characterization tests); plus pytest, coverage.py, Hypothesis, and
mutmut primary documentation.

One honest caveat. The most-cited "test smells cause flakiness" paper is **retracted** —
smells are a comprehensibility signal, not a defect oracle, so state them weakly.
