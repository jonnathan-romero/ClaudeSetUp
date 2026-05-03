# Advanced techniques

Beyond example-based TDD: property-based testing, mutation testing, snapshot/approval testing, fuzzing-adjacent tools, characterization tests. Each has a "when to / when not to" and an integration story with the red-green-refactor loop.

**Contents**
- [Property-based testing (Hypothesis)](#property-based-testing-hypothesis)
- [Mutation testing (mutmut)](#mutation-testing-mutmut)
- [Snapshot / approval testing (syrupy)](#snapshot--approval-testing-syrupy)
- [Fuzzing-adjacent tools](#fuzzing-adjacent-tools)
- [Characterization tests](#characterization-tests)
- [Decision matrix](#decision-matrix)
- [Sources](#sources)

## Property-based testing (Hypothesis)

Example-based tests check inputs you thought of. Property-based tests describe *invariants that hold for all inputs* and let Hypothesis generate them — including edge cases (empty strings, `sys.maxsize`, NaN, Unicode surrogates).

Scott Wlaschin's taxonomy from [Choosing properties for property-based testing](https://fsharpforfunandprofit.com/posts/property-based-testing-2/):

- **Round-trip / inverse** — `decode(encode(x)) == x`
- **Invariant** — sorting a list preserves length
- **Idempotence** — `normalize(normalize(x)) == normalize(x)`
- **Oracle** — compare a fast implementation to a slow but obviously-correct one
- **Metamorphic** — `sorted(xs + [y])` contains the same elements as `sorted(xs) + [y]`

David MacIver's [What is property-based testing?](https://hypothesis.works/articles/what-is-property-based-testing/) argues the real value is **shrinking** — Hypothesis minimizes a failing input to the smallest counterexample before reporting.

### When to reach for it

- Pure functions with mathematical or structural invariants (serializers, parsers, sort/search, financial math)
- Anywhere you've written three or more example-based tests that are structurally identical with different values
- After a production bug caused by an edge case — retrofit a property to prevent the whole class

### When NOT to

- Side-effectful code where inputs can't be safely generated
- Tests whose intent is to document specific known-good behavior
- Prototype code where invariants aren't yet articulable

### Examples

```python
# Round-trip
import json
from hypothesis import given
import hypothesis.strategies as st

@given(st.dictionaries(st.text(), st.integers()))
def test_json_round_trips(data: dict) -> None:
    assert json.loads(json.dumps(data)) == data
```

```python
# Composite for dependent data
from hypothesis import given
from hypothesis.strategies import composite, integers

@composite
def date_range(draw):
    start = draw(integers(min_value=0, max_value=3650))
    end = draw(integers(min_value=start, max_value=start + 365))
    return start, end

@given(date_range())
def test_range_is_non_negative_duration(range_):
    start, end = range_
    assert end >= start
```

```python
# Stateful — model-based testing of a stack
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant
import hypothesis.strategies as st

class StackMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self._stack = []

    @rule(value=st.integers())
    def push(self, value):
        self._stack.append(value)

    @rule()
    def pop_when_non_empty(self):
        if self._stack:
            self._stack.pop()

    @invariant()
    def length_is_non_negative(self):
        assert len(self._stack) >= 0

TestStack = StackMachine.TestCase
```

### Integration with the TDD loop

Same RED → GREEN cycle. The difference is that GREEN means "no counterexample found in N examples," not "these specific values pass." Use `@settings(max_examples=500)` for critical paths in CI.

## Mutation testing (mutmut)

Mutation testing injects small syntactic changes — flipping `>` to `>=`, replacing `+` with `-`, deleting a `return` — and runs the test suite against each mutant. A surviving mutant means your tests wouldn't have caught that class of bug.

100% line coverage tells you every line executed. It does *not* tell you whether your assertions are strong enough to catch errors. Mutation score does.

### When

- After a coverage-passing suite ships a regression — as a post-mortem audit
- On critical business logic (billing, auth, data integrity) where weak assertions are high-risk
- As a *periodic* CI check (weekly, not per-commit) on modules with complex branching

### When NOT

- On every commit — mutmut is slow (O(mutants × suite-runtime))
- I/O-heavy code where mutants cause hangs
- As a substitute for thinking — surviving mutants are clues, not requirements

### Running

```bash
pip install mutmut
mutmut run                  # runs all mutants against pytest
mutmut browse               # interactive review
```

```toml
[tool.mutmut]
source_paths = ["src/"]
pytest_add_cli_args_test_selection = "tests/"
mutate_only_covered_lines = true
```

### Integration with the TDD loop

Mutation testing is a **periodic audit**, not part of the per-cycle loop:

1. Finish a feature with the normal red-green-refactor loop.
2. Run `mutmut run` against the new module.
3. For each surviving mutant, write a targeted test that kills it (RED → GREEN cycle).
4. Re-run.

Don't use mutmut as a per-save tool — it destroys the inner-loop rhythm.

For a lightweight version of this idea per cycle, see "Mutation spot-check" in `SKILL.md`'s verification rituals.

## Snapshot / approval testing (syrupy)

[syrupy](https://syrupy-project.github.io/syrupy/) serializes a value to disk on first run, then asserts equality against the stored snapshot on every subsequent run.

```python
def test_api_response(snapshot, api_client):
    response = api_client.get("/users/1")
    assert response.json() == snapshot
```

First run creates `__snapshots__/test_users.ambr`. Update with `pytest --snapshot-update`.

### When

- Complex nested output where writing assertions by hand would be 40 lines of `assert response["data"]["items"][0]["id"] == ...`
- Generated configuration, rendered templates, CLI output
- Regression-proofing a large structure you can read-verify once visually

### When NOT (the curse)

- Blindly running `--snapshot-update && git add .` without reading the diff — this is how bugs get committed as "correct"
- Highly volatile output (timestamps, UUIDs, random ordering) unless you mask dynamic fields with syrupy's `matcher`
- Snapshots so large they're never read in PRs — if no one reads it, it's not a test, it's a liability

### Integration with the TDD loop

Snapshot tests bend the "one test at a time" rule slightly. The first run does not fail in the normal RED sense — it passes by *creating* the snapshot. Treat it like:

```
FIRST RUN:    test passes, snapshot created — this is GREEN
SUBSEQUENT:   change behavior → mismatch → RED; fix or intentionally update
```

Discipline: never run `--snapshot-update` without reading the diff. Snapshot review is part of code review, not an afterthought.

## Fuzzing-adjacent tools

**[atheris](https://github.com/google/atheris)** — Google's coverage-guided fuzzer for Python, built on libFuzzer. Mutates byte strings guided by coverage feedback. Suited for parsers, deserializers, security-sensitive input handling. Use when Hypothesis strategies are too hard to write for an input domain.

**[schemathesis](https://schemathesis.io/)** — reads your OpenAPI (or GraphQL) schema and generates property-based tests against your live API. Catches the case where your API silently violates its own schema.

```bash
pip install schemathesis
st run http://localhost:8000/openapi.json
```

```python
import schemathesis

schema = schemathesis.from_uri("http://localhost:8000/openapi.json")

@schema.parametrize()
def test_api_does_not_crash(case):
    response = case.call()
    case.validate_response(response)
```

Once you've built an endpoint example-test-first, run schemathesis to find the inputs your hand-written tests missed.

## Characterization tests

Tests that capture *what code currently does*, not what it should do — a safety net for refactoring untested code. Lives in [legacy-code.md](legacy-code.md) since characterization is fundamentally a legacy-code technique; the full playbook (seams, sprout method, wrap method, characterization) is there.

## Decision matrix

| If you find yourself doing this... | Reach for... |
|---|---|
| Writing the same test 3× with different values | Hypothesis `@given` |
| Tests pass but a production bug slipped through | mutmut periodic audit |
| Asserting deeply nested dict/object structure | syrupy snapshot |
| Blindly running `--snapshot-update` | Stop — read the diff |
| Need to test a parser with wild input | atheris |
| API live and you want schema contract validation | schemathesis |
| Touching legacy code with no tests | Characterization tests (see legacy-code.md) |
| Copy-pasting test setup blocks | Test data builder (see pytest-craft.md) |
| Coverage is 90%+ but you don't trust the assertions | mutmut audit |
| Writing a new feature from scratch | Example-based TDD; add property tests for invariants after GREEN |

## Sources

- [Hypothesis docs](https://hypothesis.readthedocs.io/)
- [What is property-based testing? — David MacIver](https://hypothesis.works/articles/what-is-property-based-testing/)
- [Choosing properties for property-based testing — Scott Wlaschin](https://fsharpforfunandprofit.com/posts/property-based-testing-2/)
- [mutmut docs](https://mutmut.readthedocs.io/)
- [syrupy docs](https://syrupy-project.github.io/syrupy/)
- [atheris GitHub](https://github.com/google/atheris)
- [schemathesis docs](https://schemathesis.readthedocs.io/)
- Michael Feathers, *Working Effectively with Legacy Code* (Pearson, 2004)
