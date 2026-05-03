# Python Debugging Tools

Opinionated Python tool defaults for each of `vibe-diagnose`'s 10 feedback-loop methods. Picking the tool deliberately beats deliberating about it.

## Contents

- [The 10 methods, mapped to Python tools](#the-10-methods-mapped-to-python-tools)
- [Performance — py-spy is the default](#performance--py-spy-is-the-default)
- [Non-determinism kit](#non-determinism-kit)
- [Regression-test idioms](#regression-test-idioms)

## The 10 methods, mapped to Python tools

| # | Method | Default Python tool(s) | Notes |
|---|---|---|---|
| 1 | Failing test | `pytest`; `pytest-asyncio` for async; `hypothesis` for property-based | Canonical agent invocation: `pytest --tb=short -x -k <test_name>` (short tracebacks, fail-fast) |
| 2 | Curl / HTTP script | `httpx` (sync+async); `respx` to mock httpx; `requests` for one-offs | httpx replaces requests as the modern default |
| 3 | CLI + stdout snapshot | `pytest` with `capsys` / `capfd`; `syrupy` for snapshot diff | Syrupy stores `__snapshots__/*.ambr`; `--snapshot-update` to refresh |
| 4 | Headless browser | `playwright` Python (`pip install playwright && playwright install`) | Bundled tracing via `page.context.tracing.start()` |
| 5 | Replay captured trace | `vcrpy` (HTTP) or `pytest-recording` (`@pytest.mark.vcr`) | Cassettes are YAML, diffable, commit-friendly |
| 6 | Throwaway harness | A `scripts/repro_<bug>.py` script that imports the target and calls it once | Use the project logger, never `print` (per project conventions) |
| 7 | Property / fuzz | `hypothesis` for structured properties; `schemathesis` for OpenAPI; `atheris` for coverage-guided fuzzing of parsers | Hypothesis is the 90% default |
| 8 | Bisection | `git bisect run pytest tests/test_bug.py::test_repro -x` | Pytest exit code drives bisect — no extra wrapper needed |
| 9 | Differential | A parametrised pytest with `assert new_fn(x) == old_fn(x)`, or `syrupy` for tree-shaped output | No specialist library required |
| 10 | HITL | The `scripts/hitl-loop.template.sh` template, or a `click` / `typer` CLI prompting the human between steps | Genuine last resort |

## Performance — py-spy is the default

For performance regressions, **py-spy is the default profiler.** Sampling profiler, no code changes, attaches to a running PID, emits flamegraphs, works across native extensions:

```bash
py-spy record -o flame.svg -- python repro.py
```

One command and you have a bottleneck. Use the rest of the perf kit only after py-spy localises the hot region:

- **scalene** — when CPU vs memory vs GPU attribution matters and you want line-level
- **cProfile + snakeviz** — when py-spy isn't installable (stdlib, zero deps)
- **line_profiler** (`@profile` decorator) — only after py-spy localises the hot function
- **memray** — for memory specifically, better than `memory_profiler` in 2026

## Non-determinism kit

For non-deterministic bugs (raising the reproduction rate from 1% to 50%):

- **`pytest-repeat`** — `pytest --count=100 tests/test_bug.py` for flake hunting
- **`pytest-randomly`** — randomises test order *and prints the seed*; the seed is essential because "ran twice, passed" is a false negative without it
- **`pytest-xdist -n auto`** — parallelism as a *bug-finder*, not just a speedup; many concurrency bugs only surface under parallel pressure
- **`hypothesis` `RuleBasedStateMachine`** — finds interleaving bugs deterministically via shrinking
- **`faulthandler`** (stdlib) — `python -X faulthandler` or `faulthandler.dump_traceback_later(30)` for hangs and segfaults

For pinning determinism in tests:

- **`freezegun`** / **`time-machine`** (faster) — pin time
- **`random.seed`** / `numpy.random.default_rng(seed=...)` — pin RNG
- **`monkeypatch.setenv`** — pin environment variables
- **`tmp_path`** (pytest fixture) — isolated per-test temp dirs
- **`vcrpy`** / **`pytest-vcr`** — freeze network

## Regression-test idioms

For Phase 5's "write the failing test before the fix":

```python
@pytest.mark.regression
def test_<bug_id>_<symptom>():
    """Bug: <one-line description>. Should fail before the fix; pass after."""
    # arrange (mirroring the minimised repro)
    ...
    # act + assert (asserting the specific symptom, not just "didn't crash")
    assert result.status == "rejected"
    assert "insufficient funds" in result.reason
```

Workflow:

1. Write the test
2. `pytest tests/test_bug.py::test_<id> --tb=short -x` — confirm it fails for the *right* reason (read the traceback; don't just check exit code)
3. Apply the fix
4. Re-run; the same test now passes
5. Commit the test and fix in **the same commit** — `git bisect` lands cleanly later

The "watch it fail first" step is what distinguishes a regression test from theater.

If you find yourself asserting only `assert not raised` or `assert result is not None`, sharpen the assertion. The signal must distinguish the bug-present world from the bug-fixed world.
