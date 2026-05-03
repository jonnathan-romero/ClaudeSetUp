---
name: vibe-tdd
description: Test-driven development with the red-green-refactor loop for Python/pytest. ALWAYS trigger when the user says "TDD", "red-green-refactor", "test-first", "failing test", or "tracer bullet"; wants to build a feature or fix a bug via tests; asks to write pytest tests before implementation; or needs characterization tests before refactoring legacy code. Skip for spikes/prototypes, exploratory data analysis, cosmetic UI changes, performance tuning of already-correct code, one-shot scripts, or when the interface is still being explored.
---

# Test-Driven Development

**Contents**
- [Philosophy](#philosophy)
- [Anti-Pattern: Horizontal Slices](#anti-pattern-horizontal-slices)
- [When this skill should NOT activate](#when-this-skill-should-not-activate)
- [LLM failure modes](#llm-failure-modes)
- [Workflow](#workflow)
- [Verification rituals](#verification-rituals)
- [Checklist per cycle](#checklist-per-cycle)
- [Supplementary files](#supplementary-files)

## Philosophy

**Core principle**: tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style. They exercise real code paths through public APIs. They describe *what* the system does, not *how* it does it. A good test reads like a specification — `test_user_can_checkout_with_valid_cart` tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (querying a database directly instead of using the public interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and tests fail, those tests were testing implementation, not behavior.

See [tests.md](references/tests.md) for examples and [mocking.md](references/mocking.md) for mocking guidelines.

## Anti-Pattern: Horizontal Slices

**Do not write all tests first, then all implementation.** This is "horizontal slicing" — treating RED as "write all tests" and GREEN as "write all code."

This produces *crap tests*:

- Tests written in bulk verify *imagined* behavior, not *actual* behavior.
- You end up testing the *shape* of things (data structures, function signatures) rather than user-facing behavior.
- Tests become insensitive to real changes — they pass when behavior breaks, fail when behavior is fine.
- You outrun your headlights, committing to test structure before understanding the implementation.

**Correct approach**: vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1 → impl1
  RED→GREEN: test2 → impl2
  RED→GREEN: test3 → impl3
  ...
```

LLM agents are *especially* prone to horizontal slicing because bulk generation feels like "completing the task." Resist it — see "LLM failure modes" below.

## When this skill should NOT activate

Concrete signals (not "use judgment") that test-first will cost more than it earns:

- **Spike or throwaway code.** Time-boxed exploration whose purpose is to discard the code once you understand the problem. Signal: you've rewritten or discarded more than 30% of your code in the last hour.
- **Exploratory data analysis or notebooks.** EDA is iterative and visually driven; tests impose structure on work that exists to *discover* structure.
- **Cosmetic UI changes.** Pixel layout, color values, copy. The change verifies in under ten minutes by eye and contains zero business logic.
- **Performance tuning of already-correct code.** The interface is correct; you're changing implementation for throughput. Use a benchmark harness, not TDD.
- **One-shot scripts.** Code with no operational lifetime; test infrastructure is overhead with no return.
- **Interface genuinely unknown.** You can't name the unit under test in one noun phrase without hedging — write a prototype first, then TDD the production version.
- **Characterization phase in legacy code.** You need to *understand* current behavior before driving new behavior. See [legacy-code.md](references/legacy-code.md).

For deeper discussion (DHH/Hickey/Coplien/Cooper critiques, the limits of TDD as a design discipline), see [when-not-to-tdd.md](references/when-not-to-tdd.md).

## LLM failure modes

The most dangerous failure modes are unique to LLMs writing tests. Each entry has a detection signal and a countermeasure. If you notice the signal, apply the countermeasure before continuing — these are not optional refinements; each one breaks the integrity of the red-green-refactor loop.

**1. Rationalized TDD theater.** Writing the implementation first, then "tests" that confirm what the code already does. Tests pass on first run with no red phase observed.
- *Signal:* the test suite passes immediately after being written.
- *Countermeasure:* paste the failing test runner output in context before writing any implementation.

**2. Context-polluted tests.** When the same context handles test writing and implementation, the test gets unconsciously designed around the planned code. The test then proves the code does what the code does — a tautology.
- *Signal:* tests mirror the implementation's shape exactly — same parameter names, same return structure, no independent derivation of expected values.
- *Countermeasure:* enumerate behaviors and write each test name *before* opening any implementation file.

**3. Horizontal slicing in bulk.** Writing N tests in a batch before any implementation. (See "Anti-pattern" above.)
- *Signal:* a complete test file appears covering N behaviors before any implementation cycle.
- *Countermeasure:* one test → one implementation → run → next test. Refuse to write test #2 before test #1 is green.

**4. Skipping the red step.** Asserting "the test fails" in prose without actually running the test runner. Without execution, you cannot tell whether the failure mode you intended is the failure that actually occurs.
- *Signal:* a test is written and implementation begins without any test execution between.
- *Countermeasure:* the gate is machine-checkable — paste the runner output showing the expected failure message before implementing.

**5. Mock-heavy, assertion-light tests.** Loading up on mocks and asserting `mock.assert_called_once_with(...)`. The test exercises the mock, not the system.
- *Signal:* every test has a mock setup block and a call-count assertion with no behavioral outcome verified.
- *Countermeasure:* assert on observable outcomes through the public interface — see [mocking.md](references/mocking.md) for boundary rules.

**6. Hallucinated APIs.** Tests calling non-existent methods, renamed parameters, or version-incorrect signatures. The red phase fails for the wrong reason — the test never reaches the behavior under test.
- *Signal:* red phase fails with `AttributeError`, `TypeError`, or `ModuleNotFoundError` rather than an assertion failure naming the missing behavior.
- *Countermeasure:* the red step is only valid when the failure message names the *behavior*. Any other error means fix the test first.

**7. Catching exceptions to make tests pass.** Wrapping the implementation in a broad `try/except` to suppress the failure that should be fixed at its source.
- *Signal:* implementation gains a `try/except` block in the same change that turns a test green, with no other logic change.
- *Countermeasure:* exception handling is a refactor-phase concern, not a green-phase shortcut.

**8. Modifying the test instead of the code.** When red, weakening the assertion or deleting the test rather than fixing the implementation. Kent Beck specifically calls out this failure for AI agents.
- *Signal:* a previously-written test is edited or deleted in the same turn that resolves a red failure.
- *Countermeasure:* tests written in RED are frozen until GREEN. If the test really must change, that's a planning step — restart the cycle with explicit user confirmation.

**9. Over-mocking your own code.** Mocking internal collaborators to keep tests "fast" — defeating the integration-style preference and producing tests that pass without verifying behavior.
- *Signal:* internal classes/functions you control appear in the mock setup.
- *Countermeasure:* mock at system boundaries only. See [mocking.md](references/mocking.md).

For published research on LLM-TDD failure modes (Beck, Willison, Sobocinski, alexop, Salehpour, Meta), see [llm-pitfalls.md](references/llm-pitfalls.md).

## Workflow

### 1. Planning

Before writing any code:

- [ ] Confirm with the user what interface changes are needed
- [ ] Confirm with the user which behaviors to test (prioritize)
- [ ] Identify opportunities for [deep modules](references/deep-modules.md) (small interface, deep implementation)
- [ ] Design interfaces for [testability](references/interface-design.md)
- [ ] List behaviors *by name* before any test code
- [ ] Each behavior maps to one test name (not one file → one test)
- [ ] Get user approval on the plan

Ask: "What should the public interface look like? Which behaviors are most important to test?"

**You can't test everything.** Confirm with the user exactly which behaviors matter most. Focus testing effort on critical paths and complex logic, not every possible edge case.

For pytest-specific planning (fixtures, parametrize design, async setup), see [pytest-craft.md](references/pytest-craft.md). For deciding which *level* of test (unit / integration / contract / E2E), see [test-strategy.md](references/test-strategy.md).

### 2. Tracer bullet

Write ONE test that confirms ONE thing about the system:

```
RED:    write the test → run pytest → observe and paste the failure
GREEN:  write minimal code to pass → run pytest → observe and paste the pass
```

This is your tracer bullet — it proves the path works end-to-end.

### 3. Incremental loop

For each remaining behavior:

```
RED:    next test → run → paste failure
GREEN:  minimal code → run → paste pass
```

Rules:

- One test at a time
- Only enough code to pass the current test
- Don't anticipate future tests
- Keep tests focused on observable behavior
- Re-run after every file change — don't batch

### 4. Refactor

After all tests pass, look for [refactor candidates](references/refactoring.md):

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what new code reveals about existing code
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

For the full Fowler refactoring catalog adapted to TDD context, see [refactoring.md](references/refactoring.md).

## Verification rituals

LLM-specific rituals that keep the workflow honest:

1. **Paste the failure, don't assert it.** A valid red step looks like:
   ```
   FAILED tests/test_checkout.py::test_order_confirmed
       AssertionError: assert None == 'confirmed'
   ```
   Asserting "the test will fail" without running it is not a red step.

2. **Explicit RED/GREEN markers per cycle.** Tag each phase: `[RED: test_name]` ... `[GREEN: test_name]` ... `[REFACTOR]`. Creates an audit trail you and the user can both scan.

3. **Re-run after every file change.** Don't batch multiple edits, then test. Each edit gets a run. This catches regressions immediately and prevents the "I'll fix it at the end" failure mode.

4. **Refuse to claim done without a green run.** Paste the final `N passed` output before declaring a behavior complete.

5. **Mutation spot-check.** After green, delete one meaningful line from the implementation (a conditional, a key assignment) and confirm a test fails. If no test catches the deletion, the tests are not verifying the behavior. For systematic mutation testing as a periodic audit, see [advanced-techniques.md](references/advanced-techniques.md).

6. **Run the full suite before and after refactor.** Establishes a baseline and catches regressions immediately.

## Checklist per cycle

```
Test design
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive an internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added

LLM-specific
[ ] Wrote the test BEFORE opening any implementation file
[ ] Ran the test and observed it FAIL with a message that names the missing behavior
    (not an import error, not a wrong API)
[ ] Did NOT modify the test to make it pass — only modified implementation
[ ] Test asserts on observable output through the public interface, not on mock call counts
[ ] No new broad exception handling added just to suppress a test failure
[ ] After GREEN: deleted one key implementation line, confirmed a test caught it
[ ] After GREEN: ran the full suite and confirmed it stayed green
[ ] REFACTOR completed and suite re-run; no new behavior added during refactor
```

## Supplementary files

Read each only when the relevant scenario arises. None are required up front.

**Testing fundamentals (preserved from the base, Python-flavored):**
- [tests.md](references/tests.md) — examples of good vs. bad tests in pytest
- [mocking.md](references/mocking.md) — when to mock, where to patch, dependency injection in Python
- [interface-design.md](references/interface-design.md) — designing for testability with `Protocol`
- [deep-modules.md](references/deep-modules.md) — small interface, deep implementation
- [refactoring.md](references/refactoring.md) — Fowler catalog adapted to TDD context

**Python/pytest craft:**
- [pytest-craft.md](references/pytest-craft.md) — fixtures, parametrize, conftest, async, builders, watch loop

**Strategy and advanced techniques:**
- [test-strategy.md](references/test-strategy.md) — pyramid / trophy / honeycomb, London vs. Detroit, "what level should the next test be?"
- [advanced-techniques.md](references/advanced-techniques.md) — Hypothesis (property-based), mutmut (mutation testing), syrupy (snapshots), schemathesis

**Context-specific:**
- [legacy-code.md](references/legacy-code.md) — Feathers seams, sprout/wrap method, characterization tests for untested code
- [when-not-to-tdd.md](references/when-not-to-tdd.md) — TDD critiques (DHH, Hickey, Coplien, Cooper) and concrete skip signals
- [llm-pitfalls.md](references/llm-pitfalls.md) — published research and citations behind each LLM failure mode, plus harness-design patterns (sub-agent separation, hook-enforced gates)
