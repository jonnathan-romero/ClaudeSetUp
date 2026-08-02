#!/usr/bin/env bash
# Shared by the `add-logging` skill and the `@logging-plumber` agent: prove that an
# edit to a Python file changed ONLY logging statements, and that every changed
# log draws its arguments from a small provable subset.
#
# LIMITS OF PROOF -- read before trusting exit 0.
#
# Exit 0 proves exactly ONE theorem: no statement other than a RESOLVED logging
# call changed, and every log statement that changed either is a pure re-level
# (identical receiver + arguments, so no new evaluation risk) or draws its
# arguments from a syntactic allowlist. That is CONTAINMENT, not behaviour
# preservation. It does NOT prove, and cannot prove:
#   * ARGUMENT PURITY. Nothing in Python beyond a literal constant is provably
#     inert -- len(x) dispatches __len__, x.attr may be a @property, "%s" % x
#     calls __str__ at format time. The allowlist bounds blast radius only.
#   * That argument evaluation is free. Log args evaluate EAGERLY even when the
#     level is disabled -- %-formatting defers formatting, not evaluation -- so
#     removing a log removes its argument side effects unconditionally.
#   * That a broken format string will be noticed. Format/emit errors are
#     swallowed by Handler.handleError and are completely silent at a disabled
#     level. Gate edited files with `ruff --select PLE1205,PLE1206,G`.
#   * CALLER ATTRIBUTION. ASTs are compared with include_attributes=False, so
#     this check is blind to line numbers by construction. Inserting any line
#     renumbers %(lineno)d for every log below it.
#   * NON-LOCAL EFFECTS. Stateful logging.Filters make emission order-dependent;
#     a Handler whose emit() feeds program state makes the call load-bearing.
#     Both live outside the edited file.
#   * OBSERVATION. Tests (caplog / assertLogs / assertNoLogs / LogCapture) break
#     on additions and removals alike; alerts and dashboards keyed on a message
#     or level live outside the repo entirely.
#   * ORDER WITHIN A SUITE. The log inventory is keyed index-free, so moving a
#     log WITHIN one suite passes at exit 0 even though it now logs a different
#     program state. Hoisting ACROSS a block boundary is caught (exit 2).
# A GREEN TEST SUITE IS NOT EVIDENCE either way: mutation-testing tools exclude
# logging lines by default (pitest FLOGCALL) precisely because tests don't kill
# logging mutants. Run the suite anyway; never report its passing as proof.
#
# Receiver resolution accepts ONLY a name bound exactly once at module level to
# logging.getLogger(...) (direct, imported, or aliased import) and never
# shadowed by a parameter or local. self.logger, injected loggers, structlog and
# loguru are all REJECTED as unresolvable -- an edit to one of those reads as a
# non-log code change (exit 1), which is the safe direction.
#
# Usage:
#   verify-logging-only.sh <before> <after>
#     <before>  path to the ORIGINAL content (e.g. a pre-edit copy; prefer
#               `cp` over `git show` -- git diff/show are blind to untracked files)
#     <after>   path to the edited file
#
# Exit codes:
#   0  VERIFIED-CONTAINED -- only resolved logging statements changed, and every
#                            change is provably gated; keep the edit
#   1  UNSAFE             -- non-log code changed, a docstring was demoted or
#                            altered, the file stopped compiling, or an edited
#                            receiver could not be proven to be a logger; REVERT
#   2  UNVERIFIED         -- contained but outside the provable subset (an
#                            argument off the allowlist, a log that changed
#                            enclosing structure, a non-Python file, unreadable
#                            input); treat as unsafe: revert, then queue or
#                            hand-review the hunk
#
# Both files are read-only to this script. It never edits or reverts anything --
# acting on the verdict is the caller's job.
#
# Regression harness: ./test-verify-logging-only.sh (run it after ANY edit here).

set -uo pipefail

BEFORE=${1:?usage: verify-logging-only.sh <before> <after>}
AFTER=${2:?usage: verify-logging-only.sh <before> <after>}

for f in "$BEFORE" "$AFTER"; do
    [[ -r $f ]] || { echo "UNVERIFIED: cannot read $f" >&2; exit 2; }
done

case $AFTER in
*.py | *.pyi) ;;
*)
    echo "UNVERIFIED: only Python can be verified -- a logging call in any other" \
         "language is an executed statement this script cannot reason about." >&2
    exit 2
    ;;
esac

python3 - "$BEFORE" "$AFTER" <<'PY'
import ast
import sys
from collections import Counter

LEVELS = frozenset(
    {"debug", "info", "warning", "warn", "error", "exception", "critical", "fatal", "log"}
)
# Calls permitted inside a CHANGED log's arguments. Everything here can still
# dispatch to user code via a dunder; the gate bounds blast radius, it does not
# decide purity (nothing beyond a Constant provably could).
ALLOWED_CALLS = frozenset({"len", "repr", "str", "int", "float", "bool", "type", "id"})
DOC_OWNERS = (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)
# Block types recorded in a log's enclosing-structure tuple. ExceptHandler is
# included so a log sliding between a try body and its except reads as a move.
BLOCKS = (
    ast.If,
    ast.For,
    ast.AsyncFor,
    ast.While,
    ast.Try,
    ast.TryStar,
    ast.With,
    ast.AsyncWith,
    ast.ExceptHandler,
)


# ---------- receiver resolution ----------
def getlogger_aliases(tree):
    """Module-level names that `from logging import getLogger [as x]` bound."""
    out = set()
    for stmt in tree.body:
        if isinstance(stmt, ast.ImportFrom) and stmt.module == "logging":
            for a in stmt.names:
                if a.name == "getLogger":
                    out.add(a.asname or a.name)
    return out


def is_getlogger(node, aliases):
    if not isinstance(node, ast.Call):
        return False
    f = node.func
    if isinstance(f, ast.Attribute) and f.attr == "getLogger":
        return isinstance(f.value, ast.Name) and f.value.id == "logging"
    return isinstance(f, ast.Name) and f.id in aliases


def module_logger_names(tree):
    """Names bound EXACTLY ONCE at module level, and to logging.getLogger(...)."""
    aliases = getlogger_aliases(tree)
    binds = {}
    for stmt in tree.body:
        targets, value = [], None
        if isinstance(stmt, ast.Assign):
            targets, value = stmt.targets, stmt.value
        elif isinstance(stmt, ast.AnnAssign) and stmt.value is not None:
            targets, value = [stmt.target], stmt.value
        for t in targets:
            if isinstance(t, ast.Name):
                binds.setdefault(t.id, []).append(is_getlogger(value, aliases))
    return {n for n, kinds in binds.items() if len(kinds) == 1 and kinds[0]}


def shadowed(tree, names):
    """Names rebound as a parameter or local anywhere -- disqualified entirely."""
    bad = set()
    for fn in ast.walk(tree):
        if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        a = fn.args
        params = [*a.posonlyargs, *a.args, *a.kwonlyargs] + [
            x for x in (a.vararg, a.kwarg) if x
        ]
        for p in params:
            if p.arg in names:
                bad.add(p.arg)
        for n in ast.walk(fn):
            if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store) and n.id in names:
                bad.add(n.id)
    return bad


def resolved_log_stmts(tree):
    """id() of every Expr statement PROVEN to be a logging call on a module logger."""
    names = module_logger_names(tree)
    ok = names - shadowed(tree, names)
    out = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Expr) or not isinstance(node.value, ast.Call):
            continue
        f = node.value.func
        if (
            isinstance(f, ast.Attribute)
            and f.attr in LEVELS
            and isinstance(f.value, ast.Name)
            and f.value.id in ok
        ):
            out.add(id(node))
    return out


# ---------- channel 1: containment ----------
FILL = ("body",)  # suites that syntactically cannot be empty
FREE = ("orelse", "finalbody")  # empty means the clause is simply absent


def setup_candidates(tree, logger_names):
    """Module-level statements sanctioned as logging SETUP: `import logging`,
    `from logging import getLogger [as x]`, and a resolved logger binding.
    Instrumenting a previously logger-less file requires adding these, so both
    sides normalize them away -- BUT only when nothing that remains references
    them (see strip), so deleting an import other code still uses stays UNSAFE.
    """
    out = set()
    for stmt in tree.body:
        if isinstance(stmt, ast.Import) and all(a.name == "logging" for a in stmt.names):
            out.add(id(stmt))
        elif (
            isinstance(stmt, ast.ImportFrom)
            and stmt.module == "logging"
            and all(a.name == "getLogger" for a in stmt.names)
        ):
            out.add(id(stmt))
        elif isinstance(stmt, (ast.Assign, ast.AnnAssign)):
            targets = stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]
            if targets and all(
                isinstance(t, ast.Name) and t.id in logger_names for t in targets
            ):
                out.add(id(stmt))
    return out


def strip(tree):
    """Normalize away resolved log statements, bare `pass`, and unreferenced
    logging setup statements.

    Pass-fill only suites that cannot be empty, and never the module body -- an
    empty module is legal, so a module whose content was one log call must
    normalize to an empty body. MUTATES the tree; call last.
    """
    live = resolved_log_stmts(tree)
    logger_names = module_logger_names(tree)
    for node in ast.walk(tree):
        for field in FILL + FREE:
            body = getattr(node, field, None)
            if not isinstance(body, list):
                continue
            kept = [s for s in body if id(s) not in live and not isinstance(s, ast.Pass)]
            if not kept and field in FILL and not isinstance(node, ast.Module):
                kept = [ast.Pass()]
            setattr(node, field, kept)

    # Setup statements are dropped only while unreferenced by everything that
    # survives phase 1. Bindings decide first (a kept binding's own references
    # count toward keeping its import).
    cands = setup_candidates(tree, logger_names)
    used = set()
    for stmt in tree.body:
        if id(stmt) in cands:
            continue
        for n in ast.walk(stmt):
            if isinstance(n, ast.Name):
                used.add(n.id)
    for stmt in list(tree.body):
        if id(stmt) not in cands or not isinstance(stmt, (ast.Assign, ast.AnnAssign)):
            continue
        targets = stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]
        if {t.id for t in targets} & used:
            for n in ast.walk(stmt):
                if isinstance(n, ast.Name):
                    used.add(n.id)
        else:
            tree.body.remove(stmt)
    for stmt in list(tree.body):
        if id(stmt) not in cands or not isinstance(stmt, (ast.Import, ast.ImportFrom)):
            continue
        provided = (
            {"logging"}
            if isinstance(stmt, ast.Import)
            else {a.asname or a.name for a in stmt.names}
        )
        if not provided & used:
            tree.body.remove(stmt)
    return tree


# ---------- channel 2: argument gate ----------
def arg_violations(call):
    bad = []
    for node in ast.walk(call):
        if node is call:
            continue
        if isinstance(node, ast.NamedExpr):
            bad.append("walrus binds a name")
        elif isinstance(node, (ast.Await, ast.Yield, ast.YieldFrom)):
            bad.append(f"{type(node).__name__.lower()} in a log argument")
        elif isinstance(node, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
            bad.append("comprehension iterates its source")
        elif isinstance(node, ast.FormattedValue):
            bad.append("f-string formats eagerly at the call site (ruff G004)")
        elif isinstance(node, ast.Subscript):
            bad.append("subscript dispatches to __getitem__")
        elif isinstance(node, ast.Call):
            fn = node.func
            name = fn.id if isinstance(fn, ast.Name) else None
            if name not in ALLOWED_CALLS:
                bad.append(f"call {ast.unparse(fn)}() is not in the allowlist")
    return bad


# ---------- channel 3: context-keyed inventory ----------
def inventory(tree):
    """Key = (qualname, enclosing blocks, receiver, level, argument signature).

    Index-free, so adding or removing one log does not perturb its siblings'
    keys -- the accepted cost is that a move WITHIN one suite is invisible.
    Receiver and keywords are in the key, so renaming the logger a call goes
    through, or dropping exc_info=/extra=/stacklevel=, reads as a change.
    """
    live = resolved_log_stmts(tree)
    keys, by_node = [], {}

    def args_sig(c):
        probe = ast.Call(func=ast.Name(id="_", ctx=ast.Load()), args=c.args, keywords=c.keywords)
        return ast.unparse(probe)

    def walk(node, qual, struct):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, ast.Expr) and id(child) in live:
                c = child.value
                key = (qual, struct, c.func.value.id, c.func.attr, args_sig(c))
                keys.append(key)
                by_node[id(child)] = key
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                walk(child, f"{qual}.{child.name}" if qual else child.name, ())
            elif isinstance(child, BLOCKS):
                walk(child, qual, struct + (type(child).__name__,))
            else:
                walk(child, qual, struct)

    walk(tree, "", ())
    return keys, by_node


# ---------- channel 4: docstring presence ----------
def docstrings(tree):
    """Containment is blind to a log inserted ABOVE a docstring -- once the log
    is stripped the trees are identical, yet __doc__ became None."""
    out = []
    for node in ast.walk(tree):
        if isinstance(node, DOC_OWNERS):
            out.append((getattr(node, "name", "<module>"), ast.get_docstring(node, clean=False)))
    return sorted(out, key=lambda t: (t[0], t[1] or ""))


# ---------- driver ----------
def verify(before_src, after_src, before_path, after_path):
    try:
        a_tree = ast.parse(after_src, filename=after_path)
        compile(a_tree, after_path, "exec")
    except SyntaxError as exc:
        return 1, [f"{after_path} no longer compiles: {exc.msg} (line {exc.lineno})"]
    try:
        b_tree = ast.parse(before_src, filename=before_path)
        compile(b_tree, before_path, "exec")
    except SyntaxError as exc:
        return 2, [f"original did not compile, nothing to compare: {exc.msg}"]

    if docstrings(b_tree) != docstrings(a_tree):
        return 1, [
            "a docstring was demoted, lost, or altered -- a log inserted above a "
            "docstring silently sets __doc__ to None"
        ]

    b_keys, b_by = inventory(b_tree)
    a_keys, a_by = inventory(a_tree)
    bc, ac = Counter(b_keys), Counter(a_keys)
    b_extra, a_extra = bc - ac, ac - bc

    # A pure re-level -- same receiver, same arguments, different level -- adds
    # no new evaluation risk (the argument tuple is byte-identical), so it is
    # exempt from the argument gate.
    relevel = set()
    for k in b_extra:
        for j in a_extra:
            if (k[0], k[1], k[2], k[4]) == (j[0], j[1], j[2], j[4]) and k[3] != j[3]:
                relevel.add(k)
                relevel.add(j)
    gate_keys = (set(b_extra) | set(a_extra)) - relevel

    notes = []
    for tree, by_node, side in ((b_tree, b_by, "before"), (a_tree, a_by, "after")):
        for node in ast.walk(tree):
            key = by_node.get(id(node))
            if key is None or key not in gate_keys:
                continue
            for v in arg_violations(node.value):
                notes.append(f"[{side}] {ast.unparse(node)[:60]} -- {v}")

    contained = ast.dump(strip(b_tree), include_attributes=False) == ast.dump(
        strip(a_tree), include_attributes=False
    )
    if not contained:
        return 1, [
            "non-log code changed -- this edit touched statements other than "
            "resolved logging calls (or a receiver could not be proven to be a logger)"
        ] + notes
    if notes:
        return 2, [
            "contained, but changed log arguments are outside the provable subset "
            "-- review each flagged hunk"
        ] + notes
    moved = [k for k in b_extra if any(j[2:] == k[2:] and j[:2] != k[:2] for j in a_extra)]
    if moved:
        return 2, [
            f"contained, but {len(moved)} log statement(s) changed enclosing "
            "structure (hoisted into or out of a block) -- placement is control "
            "flow; review"
        ]
    return 0, [f"log statements {sum(bc.values())} -> {sum(ac.values())}"]


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


before_path, after_path = sys.argv[1], sys.argv[2]
code, msgs = verify(read(before_path), read(after_path), before_path, after_path)
tag = {0: "VERIFIED-CONTAINED", 1: "UNSAFE", 2: "UNVERIFIED"}[code]
out = sys.stdout if code == 0 else sys.stderr
print(f"{tag}: {msgs[0]}", file=out)
for m in msgs[1:]:
    print(f"  {m}", file=out)
sys.exit(code)
PY
exit $?
