---
name: write-tests
description: Write pytest tests for one specified Python file — new code you just wrote, or legacy code you don't yet trust. ALWAYS trigger when the user says "write tests for this file", "add tests for <file.py>", "this module has no tests", "cover this with tests", "write unit tests", "add pytest tests", "test this function", "I need tests before I refactor this", or names a .py file and asks for tests. Branches on two modes with opposite discipline — new code (tests encode intended behavior) and legacy (characterization tests pin ACTUAL behavior, bugs included). Do NOT use to audit an existing suite repo-wide for tests that cannot fail (that is the `@test-suite-auditor` agent), to configure pytest/conftest/CI/coverage gates, to debug one specific failing or flaky test, or for general code review (use /code-review). "Clean up / tidy / restyle these tests" when they already exist and already pass is /simplify, not this skill — trigger here when tests are MISSING, or when existing tests do not actually check anything and need rewriting. Python and pytest only.
argument-hint: "Path to the .py file to write tests for"
---

Write pytest tests for the one Python file the user names (`$ARGUMENTS`). Test **that one
module's** public behavior; read around it to understand the contract, but create or extend
only its test file.

**The bar this skill exists to clear.** Coverage proves a line *ran*. It does not prove anything
was checked, and at Google 70% of real high-priority bugs were coupled to a mutant **on lines the
existing tests already covered** — coverage had exhausted its usefulness before the bug shipped.
Meanwhile the measured LLM failure is not "too few tests," it is tests whose assertions restate the
implementation: in Meta's TestGen-LLM pipeline ~56% of test classes that built *and* passed
reliably still added no coverage, and one that cleared every automated filter was rejected by a
human "because it failed to contain an assertion." So: **a test that still passes when you break
the code is not a test**, and this skill's stop condition is proving otherwise.

## Step 0 — decide the mode, out loud, before writing anything

These two jobs look identical and invert the meaning of every failure. Say which one you are in,
in your first message, and put it in the test module's docstring.

| | **New-code mode** | **Legacy mode** |
|---|---|---|
| When | You (or the user) just wrote this code | Code that predates you, untested, about to be refactored |
| Tests encode | **Intended** behavior, from the spec/docstring/signature | **Actual** behavior, bugs included |
| A failing test means | The **code** is wrong — fix the code | Your **expectation** was wrong — fix the test |
| Where the expected value comes from | The specification | Running it and *observing* — see below |
| Bugs you notice | Fix them | **Pin them**, mark them, do not fix |

**If in doubt, ask.** Getting this backwards is the most expensive mistake available here: in legacy
mode "fixing" a test to match intended behavior silently deletes the safety net the user asked for.

**Read the spec, not the implementation, wherever one exists.** Deriving assertions from the code
you are testing produces a *derived oracle* — it can only confirm what the code already does, and
it cannot find a bug that is already there. When a docstring, type signature, or issue describes
intent, that is your source. This is exactly why LLM-written tests "capture the actual program
behaviour rather than the expected one," and it is measurable: buggy input steers models into
writing tests that validate the erroneous behavior.

### Legacy mode: how to get the expected value honestly

Do **not** guess a plausible value and assert it. Do this instead:

1. Write the assertion with a deliberately wrong expectation (`assert normalize(" A ") == "PLACEHOLDER"`).
2. Run it. The failure message reports the **actual** value.
3. Pin that value, and say in a comment that it is observed, not specified.
4. If the observed value looks wrong, **still pin it** — and flag it separately in your summary as
   a suspected bug. A characterization test documents the system as it is; that is its whole job.

```python
def test_normalize_strips_and_lowers():
    """CHARACTERIZATION: pins observed behavior, not intended behavior."""
    # Observed 2026-08-12, not specified. Trailing-space handling looks
    # accidental -- see summary; do not "fix" this test to match intuition.
    assert normalize("  Hello ") == "hello"
```

## The spine — prefer the highest rung of this ladder you can reach

Every assertion is one of three kinds. They are not equal, and the order is the single most useful
rule in this skill:

| Rung | Kind | Assert on | Reach for it |
|---|---|---|---|
| **1** | **Output-based** | the return value of a call | **Always first.** Survives refactoring, because input→output is the contract |
| **2** | **State-based** | observable state after the call | When the unit's job *is* a state change |
| **3** | **Communication** | that a collaborator was called | **Last resort only** |

Rung 1 has the best protection against false positives, because input-output behavior changes less
often during refactoring than anything else. Rung 3 binds the test to *how* the module is wired
rather than *what* it produces, which yields false alarms on every refactor while still missing a
wrong return value.

**Needing rung 3 is a design signal, not just a test signal.** Output-based assertions are only
available for code written functionally. If the only thing you can check is "it called the thing,"
say so in your summary — that is information about the code, not a verdict about the tests.

```python
# Rung 1 -- preferred
assert parse_duration("1h30m") == timedelta(hours=1, minutes=30)

# Rung 3 -- what to avoid as the ONLY assertion
mock_send.assert_called_once_with(payload)   # passes for any impl that calls send,
                                             # including one that discards the result
```

### Test doubles — the two questions

A double is justified only when **both** answers say so. Otherwise use the real object, an
in-memory fake, or `monkeypatch`.

1. **Is the dependency *unmanaged*?** Unmanaged = observable outside your system (SMTP, a payment
   API, a message bus other services read). Your own database is *managed* — use the real thing or
   an in-memory equivalent; a mocked repository encodes your guess about query semantics and lets
   real schema, ordering, and transaction bugs pass green.
2. **Is it an outgoing *command*, not a query?** Verifying a query ("it asked for the config") is
   asserting on plumbing.

Two absolute rules on top:

- **Never mock what you don't own.** Patching `requests.Session.send` or `boto3.client` freezes
  your *guess* about a third-party contract; the library upgrades, real behavior changes, the mock
  keeps returning the old shape, and the suite stays green through a production break. Wrap it in
  an interface you own, then fake that.
- **Use `create_autospec` / `spec=`.** A bare `MagicMock` auto-creates every attribute, so a typo
  or a removed method never raises and the test cannot detect that the collaborator's API changed.

For calibration: in real, heavily-tested Python libraries mocking runs **0.9–2.6% of tests**.
Flask has zero `MagicMock` and zero `patch()` across 378 tests. httpx — a *network* library — runs
a real uvicorn server rather than mocking the network. If your test file is mostly mocks, that is
the anomaly, not the norm.

## Process

1. **Read the target module** top to bottom: public surface, the contract in docstrings and type
   hints, branches, boundaries, error paths, and what it actually talks to.
2. **Read the repo's conventions before writing a line** — the existing test files next door, and
   the config gates. `[tool.pytest]` (pytest 9) and `[tool.pytest.ini_options]` (pytest 8 and
   earlier) are **different tables**, and pytest 8 ignores the new one silently, so check both.
   Note `addopts`, `testpaths`, `filterwarnings`, `xfail_strict`, `--import-mode`, and which async
   plugin is in play (anyio and pytest-asyncio are not interchangeable). Match the file's existing
   idiom — if the suite asserts through a helper like `eq_()` or `assert_format()`, use it.
3. **Declare the mode** (Step 0) and write the tests, highest rung first.
4. **Run them.** They must pass — and in new-code mode, a failure here means the *code* is wrong,
   so stop and say so rather than bending the test.
5. **Prove they can fail** (below). This is the step that makes the rest worth anything.
6. **Show the diff and report**, including anything you deliberately did not test.

## Verify — the tests must fail when the code breaks

A green suite is not evidence. Prove detection mechanically, on 3–5 **load-bearing** statements of
the module — the ones carrying the behavior you claim to have tested:

```bash
~/.claude/skills/_shared/sabotage_check/sabotage-check.sh delete <file> <line> \
    pytest <testfile> -x -q -p no:randomly
```

**The exit codes are inverted relative to the other `_shared/` verifiers. Read them:**

| Exit | Meaning | Do |
|---|---|---|
| `0` | **Detected** — the suite went red. The good outcome | Move to the next statement |
| `1` | **Survived** — broken code, green suite. **The finding** | Add the assertion that would have caught it. If nothing should catch it, the *statement* may be dead — say so |
| `2` | Inconclusive — dirty file, timeout, collection error, or the deletion merely unbound a name | Not a verdict. Retry with `negate` mode, or target a different statement |

Exit `2` on a `NameError` is deliberate and important: deleting `result = f(x)` makes later lines
crash, and an assertion-free smoke test "detects" that just as loudly as a real test would. A crash
is the code breaking, not your tests working.

Use `negate` mode for conditions — `delete` leaves boundary faults (`<` vs `<=`) alive:

```bash
~/.claude/skills/_shared/sabotage_check/sabotage-check.sh negate <file> <line> pytest <testfile> -x -q
```

The script requires the target file to be **tracked and clean in git**, restores it from a
byte-exact backup verified by checksum, and refuses to run if the suite is already red. It never
leaves mutated source behind.

### Census the file you just wrote

```bash
~/.claude/skills/_shared/test_census/test-census.sh <testdir>
```

Anything of yours under **ASSERTION-FREE** is a test that certifies "the import worked." Fix it or
delete it. **REVIEW** entries are the legitimate exceptions (a `benchmark` fixture or a decorator
carrying the assertion) — confirm, don't reflexively change.

### Optional escalation: a real mutation run

Only when the user asks, or when a module is genuinely critical **and** its tests are fast and
pure-unit. It catches the boundary and operator faults deletion misses.

```toml
[tool.mutmut]
source_paths = ["src"]
only_mutate = ["src/pkg/target.py"]        # bounds GENERATION; the CLI glob does not
pytest_add_cli_args_test_selection = ["tests/test_target.py"]
pytest_add_cli_args = ["-p", "no:randomly"]
mutate_only_covered_lines = true
do_not_mutate_patterns = ['logger\.\w+']
```
```bash
mutmut run "pkg.target*" --max-children 4 && mutmut results
```

Non-obvious facts that will otherwise cost you a run:

- **`--paths-to-mutate` does not exist in mutmut 3.** It was renamed to `source_paths` in config;
  a stale flag aborts the run, and a swallowed error reads as "no surviving mutants."
- The positional glob filters which mutants get **tested**, not which get **generated** — bound
  generation with `only_mutate` or you pay for the whole tree.
- **Never run `mutmut apply`** — it opens the real source with mode `w`.
- Treat any run reporting `timeout`, `suspicious`, or `segfault` as **invalid, not as survivors**;
  verdicts shift with `--max-children` alone.
- Assert `killed > 0` before quoting anything. mutmut can mark every mutant "No Tests" on an
  import-path mismatch and report a clean sheet meaning "nothing was ever tested."
- mutmut mutates **inside functions only** — module-level constants, dataclass field defaults, and
  enum members produce zero mutants and look perfectly tested regardless.

**Triage each survivor; never chase a score.** Google abandoned the absolute mutation score as
infeasible to compute and impossible to surface actionably, and Python has the *worst* mutant
productivity of seven languages (70.6%) — expect junk. A survivor you decide not to kill gets a
`# pragma: no mutate` with a one-line reason, so the suppression is visible in the diff.

**Never kill a mutant by asserting on an implementation detail** — a log message, a preallocated
capacity, a private attribute, an exact internal call count. That raises the number and makes the
suite worse, and it is the documented failure mode of mutation-driven test writing. Google's
defense against it is human reviewers pushing back; you don't have one.

## Do not

- **Write a test whose expected value you derived from the implementation** — that is a tautology
  wearing an assertion's clothes. Same for `mock.return_value = X; ...; assert result == X`.
- **Assert on `str()`/`repr()`** unless it is genuinely the contract — it couples the test to
  commas and field order.
- **Assert on log output** as a proxy for behavior.
- **Test private helpers** (`_foo`) directly, or the standard library, or trivial getters.
- **Use `time.sleep()` to synchronize.** Measured: 0 of 20 sleep-based flake fixes removed the
  flake; poll with a timeout or inject a clock instead.
- **Leave nondeterminism in**: `set` iteration order (dict order *is* guaranteed — don't flag it),
  float `==` without `pytest.approx`, `datetime.now()` unfrozen, unseeded randomness, real network.
- **Write `pytest.raises(SomeError)` without `match=`** — it passes on the wrong instance of that
  error, including one raised by a typo in your own setup. Note `match` is `re.search`, so escape
  metacharacters.
- **Use `@pytest.mark.xfail` without `strict=True`** (or repo-level `xfail_strict`). Non-strict is
  the default and reports nothing in either direction, permanently — the most effective way to
  delete a test without deleting it.
- **Add `--reruns` or `@pytest.mark.flaky`** to make something green.
- **Regenerate a snapshot to make a diff pass** — that launders a regression into an approval.

Full catalog, with the mechanical check and severity for each of ~50 defect classes:
`~/.claude/skills/_shared/test_failure_modes/failure-modes.md`. pytest footguns that pass silently
(patch-target resolution, fixture scope, parametrize copying, `match=` as regex), the config gates
to read first, and the ruff `PT` codes worth acting on:
`~/.claude/skills/_shared/test_failure_modes/pytest-mechanics.md`. Read the catalog before writing
assertions for anything non-trivial; read the mechanics file before touching fixtures, `patch()`,
or async.

## Report

State: the **mode** you worked in; what you tested and at which rung; the sabotage results
(`file:line → detected/survived`) — **per statement, never summarized**, since that list is the only
evidence the tests do anything; every doubled dependency and which of the two questions justified
it; in legacy mode, every value pinned by observation and any you suspect is a bug; and what you
deliberately left untested and why.
