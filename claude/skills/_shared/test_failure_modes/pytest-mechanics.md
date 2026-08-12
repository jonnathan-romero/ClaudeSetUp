# pytest mechanics, config gates, and the detector stack

Companion to [`failure-modes.md`](failure-modes.md). That file catalogs *what goes wrong*; this one
carries the pytest-specific facts you cannot infer, the config that invalidates an audit if
misread, and which tools are actually worth running.

Verified against **pytest 9.1.1**, **ruff 0.16.2**, **coverage 7.15.4**, 2026-08. Several entries
read as wrong against pytest 7/8 — check the version before trusting them.

---

## 1. Config gates — read these before measuring anything

Every number below is conditional on these. Getting one wrong makes the whole audit wrong.

### `[tool.pytest]` vs `[tool.pytest.ini_options]` — the 2026 gate

pytest 9 added a new `[tool.pytest]` table. **pytest 8 ignores it entirely, with no warning.**
Verified with an invalid flag: pytest 9 errors, pytest 8 passes clean.

Already live in the wild — pydantic, attrs, and fastapi have migrated; httpx, sqlalchemy, urllib3,
black, flask, and rich have not. **Grep for both table names.** An agent checking only the old one
concludes "pydantic has no pytest config" and misses `filterwarnings = error` and `strict = true`.
An agent *writing* the new table into a pytest-8 repo writes config that does nothing.

### Exactly one config file wins — and pytest tells you which

Precedence: `pytest.ini` > `pyproject.toml` > `tox.ini` > `setup.cfg`. The losers are **ignored
entirely, not merged**. You do not have to work this out — run any pytest command and read line 3:

```
configfile: pytest.ini (WARNING: ignoring pytest config in pyproject.toml, tox.ini, setup.cfg!)
```

**If that warning is present, the repo has dead config somebody believes is live.** That is a
finding in itself, and it costs nothing to detect. Also watch for a nested `tests/pytest.ini`,
which relocates rootdir and wins whenever CI runs `pytest tests/` (rich does exactly this).

### `addopts` poisons every command you run

It stacks with your CLI flags. A repo's own `-q` plus your `-q` gives verbosity −2, which turns
`--collect-only` from node IDs into **per-file counts** — silently. Verified identically on pytest
7.4.4, 8.4.2, and 9.1.1; this is verbosity-specific, not version-specific.

**Always pass `-o addopts=""` for any measurement run.** Real `addopts` seen in the wild include
`--ignore=`, `-m <marker>`, `--maxfail=250`, `-n auto`, `-p no:warnings`, and four
`--benchmark-*` flags — every one of which changes *which tests run*.

### The rest of the gate list

| Read | Why it matters if wrong |
|---|---|
| `xfail_strict` / `strict_xfail` / `strict` | Default is **off**. A fixed-but-still-marked `xfail` is invisible. Absent in 6 of 9 elite repos, including pydantic with 27 xfails |
| `--strict-markers` | Without it, a typo'd marker silently removes a test from every filtered run |
| `--strict-config` | The only thing that turns "unknown ini key" (e.g. `asyncio_mode` with no plugin) into an error |
| `filterwarnings = error` | **The config can be the assertion.** fastapi has assertion-free tests whose oracle is a warning made fatal by config. Do not "fix" them |
| `--import-mode` / `__init__.py` | Under the default `prepend`, two test files sharing a basename abort the **entire** collection. Only attrs uses `importlib` |
| `asyncio_mode` / anyio | httpx and fastapi drive async with **anyio**, not pytest-asyncio. Do not assume which knob applies |
| coverage `fail_under` | **In 4 of 5 gated repos it lives in CI, not in config.** Grepping only `pyproject.toml`/`.coveragerc` concludes "no gate" for httpx, attrs, fastapi, and urllib3 — all of which gate at 100% |
| CI workflow | In **8 of 9** repos the CI command is not `pytest` — it is `make test`, `tox`, `nox`, or `scripts/test.sh`. Follow the chain, or you will miss marker deselections, xdist, and network policy |

---

## 2. ruff `PT` — a style linter whose *silence* is the signal

Measured over the test trees of eight elite repos: **1,296 findings**, ~90% pure style. PT006 alone
fires 375 times on top-tier code. Do not treat a PT hit as a defect by default.

**PT004 and PT005 were REMOVED.** Selecting either is a hard error that aborts the entire run.

### The high-precision set — zero hits across all eight repos

```
PT002  PT010  PT016  PT020  PT021  PT023  PT024  PT025  PT026  PT028
```

Any hit here is worth reporting individually. The genuinely load-bearing ones:

| Code | Why it is a real defect |
|---|---|
| **PT010** | `pytest.raises()` with no argument — raises `ValueError` at runtime; the test *errors*, it never tests |
| **PT028** | A test function parameter with a default — pytest never fills it, so the test may silently exercise the default forever |
| **PT024 / PT025 / PT026** | Decorators that do **nothing** where they are written |
| **PT020** | Deprecated `yield_fixture` |

Also worth keeping, low-volume and genuine: **PT014** (a literally duplicated parametrize case),
**PT015** (`assert False`), **PT017** (`try/except` + assert instead of `pytest.raises` — the test
**passes when nothing raises**), plus `B011` and `B017` from flake8-bugbear, and the always-*true*
assertion shapes — **F631** (`assert (cond,)`, a trailing-comma tuple), **B015** (comparison with
the `assert` keyword missing), **PLW0129** (`assert "msg"`). All three are unconditionally green
and exactly detectable; do not conflate them with PT015, which always fails.

### Report as an aggregate count, never as individual defects

```
PT006  PT007  PT009  PT011  PT012  PT018  PT027  PT030  PT031
```

**PT011 fires in 8 of 8 repos** and attrs disables it with the comment `# broad is fine`.
**PT011 only covers 7 stdlib exception names**, so `pytest.raises(MyDomainError)` without `match=`
is *not* flagged — never assume lint covers unpinned domain exceptions.

### Run ruff twice — the delta is the point

```bash
ruff check --isolated --select PT --output-format json <testdir> > pt-all.json
ruff check            --select PT --output-format json <testdir> > pt-repo.json
```

The difference is exactly the rule set the team **consciously decided not to care about**. Flagging
something in the delta re-litigates a settled decision; flagging something outside it is new
information.

**Two output traps.** Never pass `--preview` — it replaces codes with rule names in `concise`/`json`
output and silently breaks any `PT[0-9]{3}` filter. And count `"code": null` entries **separately**:
those are syntax errors, and those files got no analysis at all (black's intentionally-invalid
`tests/data/` corpus produces 77 of them and looks perfectly clean).

### Do not bother

| Tool | Why |
|---|---|
| **flake8-mock** | v0.4, 3 years stale, and **actively harmful** — under flake8 7.3.0 it throws `E902 TokenError` on a valid file and **suppresses every other finding in the run** |
| **PyNose** | Kotlin PyCharm plugin, last commit 2022-02, pinned to sunset JCenter, not on PyPI. `pip install pynose` gets an unrelated `nose` fork. Its 15-smell taxonomy is a fine checklist; the tool is unrunnable |
| **tsDetect** | Java/JUnit. Its Python attempt is unittest-only and eight years dead |
| **flake8-pytest-style standalone** | Correct and maintained, but ~6× slower than ruff for identical findings |
| **pylint for tests** | `C0116` drowns everything; `R0801` provably finds nothing on short test bodies at any `min-similarity-lines` |
| **`--select S101` on tests** | One hit per assert. 5,672 on pydantic. Pure noise |
| **`--select B018` on tests** | Test suites legitimately evaluate bare expressions to check they don't raise. attrs: `# pointless expressions in tests aren't pointless` |

**There is no maintained, runnable, pip-installable Python test-smell detector.** The census and
sabotage scripts in `_shared/` exist because nothing off the shelf does this.

---

## 3. pytest footguns that pass silently

- **`patch()` target resolution.** Patch where the object is *looked up*, not where it is defined.
  A **nonexistent** attribute raises `AttributeError` loudly; a **valid but unused** target patches
  nothing and the test exercises the real code in silence. No linter catches this.
- **Fixture scope.** A `session`/`module`-scoped fixture returning a mutable object shares it
  across every test that requests it. Under `pytest-xdist`, session fixtures run **once per
  worker**, not once per run.
- **Fixture shadowing is silent.** A same-named fixture in a nearer conftest or test module
  overrides the parent's with no warning — tests in that directory run against a different
  fixture than their siblings. `pytest --fixtures-per-test` shows which definition each test
  actually received. A deliberate override requests the base fixture by the same name; one
  that doesn't is suspect.
- **Teardown is skipped on setup failure.** Code after `yield` never runs if the setup half raised.
- **`parametrize` values are not copied.** "Parameter values are passed as-is to tests (no copy
  whatsoever)" — a mutable param is shared across every case.
- **Non-deterministic parametrize breaks xdist.** A `set`-valued argvalues list produces a
  different order per worker and throws a collection error.
- **`pytest.raises(match=)` is `re.search`, not equality.** Unescaped `(`, `+`, `.` silently change
  the pattern; a partial match passes.
- **Asserts in non-test modules are not rewritten.** Helpers under `tests/` that aren't collected
  as test modules lose introspection unless you call `register_assert_rewrite`. Add
  `__tracebackhide__ = True` so the traceback points at the caller.
- **`conftest.py` can change every test's meaning.** pydantic's autouse fixture monkeypatches
  production code globally; flask's fails any test leaking an app context; attrs' parametrized
  `slots`/`frozen` fixtures silently **quadruple** any test naming both.
  `pytest_collection_modifyitems` can delete tests outright — sqlalchemy drops every test not in a
  class and synthesizes new ones at runtime.
- **`pytest --setup-plan`** prints fixture setup/teardown ordering **without executing anything** —
  the cheapest way to see what an autouse fixture touches.

---

## 4. The detector stack, in order

Everything through step 5 costs less than ten suite-runs. Runtimes measured on real repos.

| # | Command | Cost | What it gives |
|---|---|---|---|
| 0 | read config + CI chain (§1) | seconds | Makes every later number valid |
| 1 | `pytest --collect-only -o addopts="" -p no:randomly -q` | 0.72s / 919 tests | Ground truth for what runs |
| 1 | `pytest --fixtures`, `--setup-plan`, `--markers` | <1s | Fixture inventory, autouse effects |
| 2 | `test-census.sh <testdir> [vocab] [dump]` | 0.2s / 585 tests | Assertion-free, near-duplicates, never-collected |
| 3 | `ruff check --isolated --select PT` (and again without `--isolated`) | 0.16s / 70k LOC | Nominations + the sanctioned-exemption delta |
| 4 | `pytest -o addopts="" -p no:randomly -p no:rerunfailures -q -ra --durations=0` | 1 suite-run | Baseline **plus** the skip/xfail/XPASS census |
| 5 | `pytest -o addopts="" -p no:randomly -n 4 --dist load` | ~1 suite-run | Order dependence, **deterministically** |
| 5 | seed sweep, 8 seeds | 8 suite-runs | Order dependence the xdist split misses |
| 6 | `pytest --cov=<mod> --cov-context=test --cov-branch` | **2.3×** suite | Solo-covered lines — the best differentiator |
| 7 | `sabotage-check.sh` on suspects | 1 scoped run each | Proof a test detects anything |
| 8 | `mutmut run "<mod>*" --max-children 4` | minutes | Boundary/operator faults deletion misses |

**`-ra` is what surfaces the never-runs.** Without it a permanently-skipped test is one character
in a progress bar; with it you get `SKIPPED [1] ...: unconditional skip` and `XPASS ...` by name.

**A single random seed proves nothing** — in a planted-defect fixture only 2 of 7 seeds
(99, 12345) exposed the order dependence; seeds 1/2/3/7 caught only an unrelated flake, and
**seed 42 was completely clean**. Sweep or don't bother. Prefer
`-n 4 --dist load`, which caught the same defect on the first try; never use `--dist loadfile` or
`loadgroup` for this, since they exist to keep coupled tests together.

**Strip `pytest-rerunfailures` before measuring.** In a suite that reruns failures, every flaky
test is invisible — and the presence of `--reruns` is itself a finding.

---

## 5. Ground truth — what elite repos actually do

Measured across pydantic, httpx, attrs, rich, sqlalchemy, fastapi, urllib3, black, and flask.
Useful mainly for calibration: if the repo you are auditing differs, that is a question, not a
verdict.

- **Mocking is rare and is instrumentation, not isolation.** 0.9–2.6% of tests. **flask has zero
  `MagicMock`, zero `patch()`, zero `unittest.mock` imports** across 378 tests — all 77 mock-ish
  lines are `monkeypatch`. httpx runs a real uvicorn server; urllib3 runs real hypercorn TLS.
- **Nobody runs mutation testing.** Zero of nine. Two gate at 100% line coverage and neither ever
  checks whether a test detects anything.
- **Nobody lints tests with `PT`** except attrs, as fallout from `select = ["ALL"]` — after which
  it immediately ignores PT011 and PT012.
- **`xfail_strict` is off in 6 of 9**, and ecosystem-wide it appears in ~2% of pytest projects.
- **Branch coverage is the minority.** rich, sqlalchemy, fastapi, httpx, and urllib3 measure
  statement coverage only.
- **Coverage contexts are used by ~0.3%** of pytest-cov users — which is exactly why they surface
  things nobody has looked at.
- **Conftests are small.** rich's is 8 lines; black's test suite has exactly one fixture; fastapi
  has **593 test files and no `tests/conftest.py`**.
- **Tests assert on private attributes freely** — sqlalchemy 412, pydantic 87, rich 75.
- **Two ideas worth stealing.** fastapi's CI applies a PR's changed tests to the *base* revision and
  warns `"The changed tests already pass on the base revision"` — an automated "did this test ever
  fail?" check. And attrs runs `rm -rf src` before CI tests, so imports can only resolve against
  the built wheel.
