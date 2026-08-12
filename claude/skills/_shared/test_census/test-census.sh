#!/usr/bin/env bash
# Shared by the `write-tests` skill and the `@test-suite-auditor` agent: an AST
# census of a pytest suite. Emits assertion-free tests, near-duplicate bodies,
# and (given a --collect-only dump) tests that exist in source but never run.
#
# WHY THIS EXISTS: no maintained Python test-smell detector exists. PyNose is an
# abandoned Kotlin PyCharm plugin (last commit 2022-02); tsDetect is Java/JUnit;
# ruff's PT ruleset is ~90% style by volume and is silent about every defect
# here. This is the only mechanical route to "which tests assert nothing".
#
# LIMITS OF THE COUNT -- read before quoting a number.
#
# An assertion-free count is WRONG BY MULTIPLES on any repo with a custom
# assertion idiom unless helpers are resolved first. Measured: sqlalchemy reads
# 6,804 assertion-free on a naive counter and 1,359 once helpers are resolved --
# a 5x error, stated loudly in a report. This script therefore discovers
# asserting helpers mechanically (see below) instead of hardcoding a call list.
# It still cannot see:
#   * HELPERS DEFINED OUTSIDE THE SCANNED TREE. A helper imported from the
#     installed package, or from a directory you did not pass, is invisible.
#     Pass its name via the vocab argument.
#   * DECORATOR-CARRIED ASSERTIONS. sqlalchemy's @profiling.function_call_count
#     and @emits_warning ARE the assertion and the body is legitimately empty.
#     Reported as REVIEW, never as a finding.
#   * CONFIG-AS-ASSERTION. Under `filterwarnings = error` a bare
#     `with catch_warnings():` block is a real assertion enforced by config that
#     lives in another file. Reported as REVIEW.
#   * FIXTURE-CARRIED ASSERTIONS. A `benchmark` fixture, or an autouse fixture
#     that fails at teardown (flask's app-context leak detector), asserts
#     without a visible statement. Reported as REVIEW.
#   * WHETHER AN ASSERTION IS MEANINGFUL. `assert result is not None` counts as
#     asserting here and is nearly worthless. Only sabotage-check.sh or a
#     mutation run can tell you that.
# The near-duplicate pass NOMINATES candidates; it does not prove duplication.
# Literals are kept in the fingerprint deliberately -- blanking them collapses
# every single-assert test in a repo into one bucket (36 bogus groups on httpx).
#
# HOW HELPER DISCOVERY WORKS: every function defined anywhere in the scanned
# tree is classified as asserting if its own body asserts, then the relation is
# closed to a fixpoint over call edges. A test calling `_test(...)` where
# `_test` eventually asserts is therefore counted as asserting.
#
# Usage: test-census.sh <testdir> [extra-assert-names-csv] [collect-only-dump]
#   <testdir>                 root of the test tree (recursed)
#   [extra-assert-names-csv]  helper names defined OUTSIDE the tree, e.g. eq_,is_
#                             pass '' to skip
#   [collect-only-dump]       output of
#                             `pytest --collect-only -o addopts="" -p no:randomly -q`
#                             enables the never-collected section
#
# Exit 0 census ran (findings, if any, are on stdout)
#      2 could not run -- unreadable dir, or every file failed to parse
set -uo pipefail

TESTDIR=${1:-}
VOCAB=${2:-}
DUMP=${3:-}

if [[ -z $TESTDIR || ! -d $TESTDIR ]]; then
    echo "UNVERIFIED: usage: test-census.sh <testdir> [extra-assert-names-csv] [collect-only-dump]" >&2
    exit 2
fi
if [[ -n $DUMP && ! -r $DUMP ]]; then
    echo "UNVERIFIED: cannot read collect-only dump: $DUMP" >&2
    exit 2
fi

python3 - "$TESTDIR" "$VOCAB" "$DUMP" <<'PY'
"""AST census of a pytest suite: assertion-free tests, near-duplicates, never-run tests.

Stdlib only. Called by test-census.sh, which documents the limits of the count.
"""

import ast
import hashlib
import logging
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

logging.basicConfig(format="test-census: %(message)s", stream=sys.stderr)
logger = logging.getLogger(__name__)

TESTDIR, VOCAB_CSV, DUMP = sys.argv[1], sys.argv[2], sys.argv[3]

# pytest constructs that ARE an assertion, independent of any repo idiom.
PYTEST_ASSERTING = frozenset(
    {"raises", "warns", "deprecated_call", "approx", "fail", "xfail"}
)
# Marks that never carry an assertion; anything else on a test is REVIEW,
# because a decorator can be the assertion (sqlalchemy's function_call_count).
INERT_MARKS = frozenset(
    {
        "parametrize", "fixture", "usefixtures", "skip", "skipif", "xfail",
        "asyncio", "anyio", "mark", "slow", "parametrize_with_cases",
    }
)
# Fixtures whose presence means the assertion is carried by the fixture.
ASSERTING_FIXTURES = frozenset({"benchmark", "snapshot", "capsys", "caplog"})
MIN_STMTS = 3  # near-duplicate floor; below this every one-liner collides


def _call_name(node: ast.Call) -> str:
    func = node.func
    if isinstance(func, ast.Attribute):
        return func.attr
    return getattr(func, "id", "")


class _Body(ast.NodeVisitor):
    """Collects, for one function body, whether it asserts and what it calls."""

    def __init__(self) -> None:
        self.asserts = 0
        self.calls: set[str] = set()
        self.uses_catch_warnings = False

    def visit_Assert(self, node: ast.Assert) -> None:
        self.asserts += 1
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        name = _call_name(node)
        self.calls.add(name)
        if name in PYTEST_ASSERTING or name.startswith("assert"):
            self.asserts += 1
        if name in {"catch_warnings", "simplefilter"}:
            self.uses_catch_warnings = True
        self.generic_visit(node)


def _fingerprint(fn: ast.AST) -> str | None:
    """Structural hash with local NAMES erased and literals kept.

    Blanking literals collapses every single-assert test into one bucket; the
    MIN_STMTS floor exists for the same reason.
    """
    body = [
        s
        for s in fn.body
        if not (isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant))
    ]
    if len(body) < MIN_STMTS:
        return None

    class _Blank(ast.NodeTransformer):
        def visit_Name(self, n: ast.Name) -> ast.Name:
            return ast.copy_location(ast.Name(id="_", ctx=n.ctx), n)

    module = ast.Module(body=[_Blank().visit(s) for s in body], type_ignores=[])
    return hashlib.sha256(ast.dump(module).encode()).hexdigest()[:16]


def _decorator_names(fn: ast.AST) -> list[str]:
    out = []
    for dec in fn.decorator_list:
        node = dec.func if isinstance(dec, ast.Call) else dec
        parts = []
        while isinstance(node, ast.Attribute):
            parts.append(node.attr)
            node = node.value
        if isinstance(node, ast.Name):
            parts.append(node.id)
        out.append(".".join(reversed(parts)))
    return out


def collect() -> tuple[dict, dict, list]:
    """Walk the tree once. Returns (all_functions, tests, parse_failures)."""
    functions: dict[str, _Body] = {}
    tests: dict[str, dict] = {}
    failures: list[str] = []

    paths = sorted(
        set(Path(TESTDIR).rglob("test_*.py"))
        | set(Path(TESTDIR).rglob("*_test.py"))
        | set(Path(TESTDIR).rglob("conftest.py"))
    )
    for path in paths:
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except (SyntaxError, UnicodeDecodeError) as exc:
            failures.append(f"{path}: {exc.__class__.__name__}")
            continue
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            probe = _Body()
            for stmt in node.body:
                probe.visit(stmt)
            functions.setdefault(node.name, _Body())
            functions[node.name].asserts += probe.asserts
            functions[node.name].calls |= probe.calls
            if not node.name.startswith("test"):
                continue
            params = {a.arg for a in node.args.args} | {
                a.arg for a in node.args.kwonlyargs
            }
            tests[f"{path}::{node.name}"] = {
                "probe": probe,
                "params": params,
                "decorators": _decorator_names(node),
                "fingerprint": _fingerprint(node),
                "body_len": len(node.body),
            }
    return functions, tests, failures


def asserting_helpers(functions: dict[str, _Body], seeded: set[str]) -> set[str]:
    """Close 'this function asserts' over call edges to a fixpoint."""
    known = {name for name, body in functions.items() if body.asserts} | seeded
    changed = True
    while changed:
        changed = False
        for name, body in functions.items():
            if name in known:
                continue
            if body.calls & known:
                known.add(name)
                changed = True
    return known


def review_reason(meta: dict, helpers: set[str]) -> str | None:
    """Why an assertion-free test may legitimately be asserting anyway."""
    marks = [d for d in meta["decorators"] if d.rsplit(".", 1)[-1] not in INERT_MARKS]
    if marks:
        return f"decorator may carry the assertion: {', '.join(marks)}"
    fixtures = meta["params"] & ASSERTING_FIXTURES
    if fixtures:
        return f"fixture may carry the assertion: {', '.join(sorted(fixtures))}"
    if meta["probe"].uses_catch_warnings:
        return "warnings context + `filterwarnings = error` may be the assertion"
    if meta["body_len"] == 1:
        return "single-call delegator: may exist only to execute lines for a coverage gate"
    return None


def main() -> int:
    seeded = {n.strip() for n in VOCAB_CSV.split(",") if n.strip()}
    functions, tests, failures = collect()
    if not tests and failures:
        logger.error("every file failed to parse under %s", TESTDIR)
        return 2

    helpers = asserting_helpers(functions, seeded)
    # Helpers only matter for reporting if a test actually routes through them.
    used_helpers = Counter()
    no_assert: list[str] = []
    review: list[tuple[str, str]] = []
    groups: dict[str, list[str]] = defaultdict(list)

    for nid, meta in sorted(tests.items()):
        probe = meta["probe"]
        via = probe.calls & helpers
        if probe.asserts == 0 and via:
            used_helpers.update(via)
        if probe.asserts == 0 and not via:
            reason = review_reason(meta, helpers)
            (review.append((nid, reason)) if reason else no_assert.append(nid))
        if meta["fingerprint"]:
            groups[meta["fingerprint"]].append(nid)

    discovered = {n for n in helpers & set(functions) if not n.startswith("test")}
    print(f"test functions:        {len(tests)}")
    print(f"asserting helpers:     {len(discovered)} discovered")
    print(f"parse failures:        {len(failures)}")
    for line in failures:
        print(f"  ! {line}")

    print(f"\nASSERTION-FREE ({len(no_assert)}) -- no assert, no asserting call, no helper:")
    for nid in no_assert:
        print(f"  {nid}")

    print(f"\nREVIEW ({len(review)}) -- assertion-free in body, but plausibly not a defect:")
    for nid, reason in review:
        print(f"  {nid}\n      {reason}")

    if used_helpers:
        print("\nASSERTIONS RESOLVED THROUGH HELPERS (top 15) -- confirm these really assert:")
        for name, count in used_helpers.most_common(15):
            print(f"  {count:5d}  {name}")

    dupes = {k: v for k, v in groups.items() if len(v) > 1}
    print(f"\nNEAR-DUPLICATE GROUPS ({len(dupes)}) -- candidates, not proof:")
    for fp, group in sorted(dupes.items()):
        print(f"  [{fp}]")
        for nid in group:
            print(f"      {nid}")

    if DUMP:
        declared = {(nid.split("::")[0], nid.split("::")[1]) for nid in tests}
        collected: set[str] = set()
        for line in Path(DUMP).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if "::" not in line:
                continue
            collected.add(re.sub(r"\[.*\]$", "", line.split("::")[-1]))
        missing = sorted(d for d in declared if d[1] not in collected)
        print(f"\nDECLARED BUT NEVER COLLECTED ({len(missing)}):")
        if not collected:
            print("  ! dump contained no node IDs -- rerun with -o addopts=\"\"")
        for path, name in missing:
            print(f"  {path}::{name}")

    return 0


sys.exit(main())
PY
