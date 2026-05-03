# Legacy code

Read this when the codebase has no existing tests in the area you're touching, or when you're about to refactor untested code. The TDD inner loop assumes a safety net; this file is how you build one before swinging the hammer.

## Definition

Michael Feathers, *Working Effectively with Legacy Code* (Pearson, 2004): legacy code is **code without tests**. Age is irrelevant. Code written this morning with no tests is legacy code; code written ten years ago with full coverage is not. The distinguishing property is whether you can change it safely.

## The Legacy Code Change Algorithm

1. Identify change points (where the new behavior goes)
2. Identify seams near those change points
3. Break dependencies at those seams
4. Write characterization tests to pin current behavior
5. Make your changes via TDD
6. Refactor under the new test coverage

Steps 4 and 5 are where the normal red-green-refactor loop applies. Steps 1–3 are setup — you cannot start a clean TDD cycle until you have a safety net.

## Seams

A **seam** is a place where you can alter program behavior without editing that exact location. Every seam has an **enabling point** — where you decide which behavior executes.

- **Object seam (most useful in Python).** Substitute a dependency by injecting a different object. Constructor injection, function-argument injection, or `monkeypatch.setattr(module, "dep", fake)` in pytest. This is the primary seam type for Python.
- **Link seam.** Java/C++ concept — swap a dependency by changing what the linker resolves. Nearest Python equivalent is `sys.modules` replacement, which is fragile. Prefer object seams.
- **Preprocessing seam.** C macro concept — not applicable in Python.

Finding a seam means finding a way to substitute behavior without rewriting the legacy code. Often the legacy code constructs its own dependencies internally; introducing a seam means refactoring just enough to accept the dependency from outside, while keeping a default that preserves current behavior.

## Sprout method / class

When you need to add behavior to a method too risky to refactor whole, **sprout**: write the new logic in a fresh, independently testable function and call it from the legacy code. The legacy code changes by exactly one call site; the new logic accumulates tests immediately.

```python
# Legacy: do not touch process_order internals
def process_order(order):
    # ... 300 lines of untested code ...
    discount = apply_new_discount(order)   # sprouted — fully tested
    order.total -= discount
```

Sprout is conservative — you avoid modifying untested code while still delivering new behavior with full test coverage. The downside is the legacy method continues to grow; the technique buys time, not cleanup.

## Wrap method

When you need behavior *around* an existing method, rename the original and create a new function with the original name that calls the renamed core:

```python
# Before
def save_invoice(invoice):
    db.write(invoice)

# After wrap
def _save_invoice_core(invoice):   # renamed original
    db.write(invoice)

def save_invoice(invoice):         # new wrapper — testable
    audit_log(invoice)
    _save_invoice_core(invoice)
```

The wrapper is tested; the core is preserved. Callers don't need to change.

## Characterization tests

A characterization test pins observed behavior without requiring you to understand it. Run the code, record its output, assert on that output. These are not specifications of *correct* behavior — they are a refactor safety net.

```python
def test_characterize_legacy_format() -> None:
    # Run the legacy function; assert on what it actually returns.
    # The expected value below was captured from a live run; correctness TBD.
    result = legacy_format({"amount": 100, "currency": "USD"})
    assert result == "USD 100.00"
```

Process:

1. Write an assertion you know will fail (e.g., `assert result == "REPLACE_ME"`).
2. Run; let the failure tell you the actual return value.
3. Rewrite the assertion to match.
4. Repeat until the code under test is covered.

Characterization tests *invert* the normal TDD direction: you're not driving new behavior, you're discovering existing behavior. Treat them as scaffolding — once you understand what the code should do (vs. what it currently does), replace characterization tests with intent-expressing tests as a separate refactor.

## Where this skill should defer

The base SKILL.md's "When this skill should NOT activate" list includes "characterization phase in legacy code." That's because the red step is fundamentally different — there is no failing test you intend to make pass; the test is a snapshot of current behavior. Run characterization first; then, with a safety net in place, return to the standard red-green-refactor loop for new behavior.

## Source

- Michael Feathers, [*Working Effectively with Legacy Code*](https://www.amazon.com/Working-Effectively-Legacy-Michael-Feathers/dp/0131177052), Pearson, 2004
