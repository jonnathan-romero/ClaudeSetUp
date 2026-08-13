#!/usr/bin/env bash
# Shared by the `write-tests` skill and the `@test-suite-auditor` agent: prove a
# test suite actually FAILS when the code it covers is broken.
#
# EXIT CODES ARE INVERTED RELATIVE TO THE OTHER _shared/ VERIFIERS. Read this.
#   0  sabotage DETECTED -- the suite went red. This is the GOOD outcome.
#   1  sabotage SURVIVED -- the suite stayed green with broken code. THE FINDING.
#   2  could not run -- dirty file, no such statement, timeout, collection error,
#      or the suite was already red before sabotage. Not a verdict either way.
# verify-logging-only.sh and verify-comments-only.sh use 0 = safe. Here 0 means
# "your tests work". Getting this backwards inverts every conclusion.
#
# WHY STATEMENT DELETION: statement-block removal is 72% of the mutants Google
# generates and is among the three operators most coupled to real faults (Just
# et al., FSE 2014). mutmut 3 ships NO statement-deletion operator -- its
# dispatch table has no such entry -- so this check covers precisely the gap the
# tool leaves, at the cost of one scoped pytest run and zero dependencies.
#
# LIMITS OF PROOF -- read before trusting exit 0.
#   * Exit 0 proves only that SOME test fails when THIS ONE statement dies. It
#     says nothing about any other line, and nothing about whether the failing
#     assertion is meaningful. It is a floor, not a certificate.
#   * Exit 1 is not automatically a defect. The statement may be logging, a
#     debug aid, a defensive branch, or genuinely dead code -- in which case the
#     finding is about the CODE, not the tests.
#   * Boundary faults (`<` vs `<=`) survive deletion-only checking. Those need
#     the `negate` mode, or a real mutation run (mutmut ships ROR/LCR).
#   * A green suite after restore is NOT evidence the restore was clean; the
#     script checksums it instead. See RESTORE below.
#
# SAFETY. The target file is edited IN PLACE and restored from a byte-exact
# backup by an EXIT/INT/TERM trap, then verified by checksum. Two independent
# recovery paths are required before any edit is made:
#   1. the file must be tracked and CLEAN in git (so `git checkout --` restores)
#   2. a backup copy is written to a temp dir first
# If the checksum after restore does not match, the script says so loudly and
# exits 2 -- never silently. `mutmut apply`'s open(path,"w") with no backup is
# the failure mode this exists to avoid.
#
# Usage: sabotage-check.sh <mode> <file> <line> <test-command...>
#   <mode>          delete | negate
#                   delete -- replace the statement at <line> with `pass`
#                   negate -- wrap an if/while condition at <line> in `not (...)`
#   <file>          Python source file to sabotage (NOT a test file)
#   <line>          1-indexed line of the statement to target
#   <test-command>  how to run the scoped suite, e.g.
#                   pytest tests/test_target.py -x -q -p no:randomly
#
# Env: SABOTAGE_TIMEOUT  wall-clock seconds for the test run (default 120).
#      A suite with no timeout hangs forever on a sabotaged loop guard, which is
#      exactly the statement most worth sabotaging.
set -uo pipefail

MODE=${1:-}
FILE=${2:-}
LINE=${3:-}
shift 3 2>/dev/null || { echo "UNVERIFIED: usage: sabotage-check.sh <delete|negate> <file> <line> <test-command...>" >&2; exit 2; }
TEST_CMD=("$@")
TIMEOUT=${SABOTAGE_TIMEOUT:-120}

[[ $MODE == delete || $MODE == negate ]] || { echo "UNVERIFIED: mode must be delete or negate, got '$MODE'" >&2; exit 2; }
[[ -n ${TEST_CMD[0]:-} ]] || { echo "UNVERIFIED: no test command given" >&2; exit 2; }
[[ -r $FILE && -w $FILE ]] || { echo "UNVERIFIED: cannot read/write $FILE" >&2; exit 2; }
[[ $LINE =~ ^[0-9]+$ ]] || { echo "UNVERIFIED: line must be an integer, got '$LINE'" >&2; exit 2; }
command -v timeout >/dev/null || { echo "UNVERIFIED: coreutils 'timeout' not found" >&2; exit 2; }

# --- Guardrail 1: the file must be clean in git, so git is a second undo path.
if ! git -C "$(dirname "$FILE")" rev-parse --git-dir >/dev/null 2>&1; then
    echo "UNVERIFIED: $FILE is not inside a git repository -- refusing to sabotage" >&2
    exit 2
fi
if ! git ls-files --error-unmatch "$FILE" >/dev/null 2>&1; then
    echo "UNVERIFIED: $FILE is untracked -- commit it before sabotaging" >&2
    exit 2
fi
if [[ -n $(git status --porcelain -- "$FILE") ]]; then
    echo "UNVERIFIED: $FILE has uncommitted changes -- refusing to sabotage" >&2
    echo "            (a failed restore would take your in-flight work with it)" >&2
    exit 2
fi

# Deterministic, un-colourised output. Python 3.13+ colourises tracebacks, which
# puts ANSI escapes INSIDE "NameError: name 'x'" and defeats any grep for it.
# Belt and braces: forced off here, and stripped again before matching below.
export NO_COLOR=1 PYTHON_COLORS=0 PY_COLORS=0

WORK=$(mktemp -d) || exit 2
BACKUP=$WORK/backup
cp -p "$FILE" "$BACKUP" || { rm -rf "$WORK"; exit 2; }
BEFORE_SUM=$(cksum <"$BACKUP")

restore() {
    local rc=$?
    if [[ -f $BACKUP ]]; then
        cp -p "$BACKUP" "$FILE" 2>/dev/null
        if [[ $(cksum <"$FILE") != "$BEFORE_SUM" ]]; then
            echo "!! RESTORE FAILED for $FILE -- recover with: git checkout -- '$FILE'" >&2
            rm -rf "$WORK"
            exit 2
        fi
    fi
    rm -rf "$WORK"
    exit $rc
}
trap restore EXIT INT TERM

# --- Guardrail 2: the suite must be GREEN before sabotage, or the result is noise.
if ! timeout "$TIMEOUT" "${TEST_CMD[@]}" >"$WORK/baseline.log" 2>&1; then
    echo "UNVERIFIED: the test command is not green before sabotage -- fix that first" >&2
    tail -20 "$WORK/baseline.log" >&2
    exit 2
fi

# --- Apply the sabotage. AST-guided so the target is a whole statement, and
#     line-based so the diff stays minimal and the restore stays trivial.
python3 - "$FILE" "$LINE" "$MODE" "$WORK/bound" <<'PY' || exit 2
"""Replace one statement with `pass`, or negate one if/while condition."""

import ast
import logging
import sys
from pathlib import Path

logging.basicConfig(format="sabotage: %(message)s", stream=sys.stderr)
logger = logging.getLogger(__name__)

path, line, mode = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
src = path.read_text(encoding="utf-8")
try:
    tree = ast.parse(src, filename=str(path))
except SyntaxError as exc:
    logger.error("%s does not parse: %s", path, exc)
    sys.exit(2)

target = None
for node in ast.walk(tree):
    if not isinstance(node, ast.stmt) or node.lineno != line:
        continue
    # Prefer the innermost statement starting on this line.
    if target is None or node.end_lineno <= target.end_lineno:
        target = node
if target is None:
    logger.error("no statement starts on line %d of %s", line, path)
    sys.exit(2)

lines = src.splitlines(keepends=True)

if mode == "negate":
    if not isinstance(target, (ast.If, ast.While)):
        logger.error(
            "negate needs an if/while on line %d, found %s",
            line, type(target).__name__,
        )
        sys.exit(2)
    test = target.test
    if test.lineno != test.end_lineno:
        logger.error("negate does not support a multi-line condition on line %d", line)
        sys.exit(2)
    row = test.lineno - 1
    text = lines[row]
    lines[row] = (
        text[: test.col_offset]
        + "not ("
        + text[test.col_offset : test.end_col_offset]
        + ")"
        + text[test.end_col_offset :]
    )
else:
    if isinstance(target, (ast.Import, ast.ImportFrom)):
        logger.error("refusing to delete an import on line %d -- that is a collection error, not a sabotage", line)
        sys.exit(2)
    indent = " " * (target.col_offset)
    lines[target.lineno - 1 : target.end_lineno] = [f"{indent}pass\n"]
    # Names this statement BOUND. If the suite later dies with NameError on one
    # of them, the deletion broke the code rather than changing its behaviour,
    # and the "failure" proves nothing about the assertions. See BOUND below.
    bound = {
        n.id
        for node in ast.walk(target)
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store)
        for n in [node]
    }
    Path(sys.argv[4]).write_text("\n".join(sorted(bound)), encoding="utf-8")

path.write_text("".join(lines), encoding="utf-8")
PY

# --- Run the scoped suite against the sabotaged source.
timeout "$TIMEOUT" "${TEST_CMD[@]}" >"$WORK/sabotaged.log" 2>&1
rc=$?

if [[ $rc == 124 ]]; then
    echo "UNVERIFIED: test command exceeded SABOTAGE_TIMEOUT=${TIMEOUT}s" >&2
    exit 2
fi

# Strip ANSI once; every match below runs against the plain copy.
sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$WORK/sabotaged.log" >"$WORK/plain.log"

if grep -qE '^(ERROR|E  ) .*(ImportError|CollectionError|errors during collection)' "$WORK/plain.log" \
   || grep -q 'Interrupted: .* error' "$WORK/plain.log"; then
    echo "UNVERIFIED: sabotage caused a COLLECTION error, not a test failure" >&2
    echo "            the suite never ran, so this proves nothing" >&2
    exit 2
fi
if [[ $rc == 0 ]]; then
    echo "SURVIVED: $FILE:$LINE was replaced and the suite still passed."
    echo "          Either the tests do not check this behaviour, or the statement is dead."
    exit 1
fi

# BOUND-NAME GUARD. Deleting `result = f(x)` leaves later lines referencing an
# unbound `result`, so the suite dies with NameError/UnboundLocalError. That is
# the code breaking, not the tests working -- an assertion-free smoke test
# "detects" it just as loudly. Reporting it as DETECTED would hand back exactly
# the false green this check exists to prevent.
if [[ -s $WORK/bound ]]; then
    # `|| [[ -n $name ]]` is required: the bound file has no trailing newline,
    # and plain `read` returns false on the final line even after setting it.
    while IFS= read -r name || [[ -n $name ]]; do
        [[ -n $name ]] || continue
        if grep -qE "(NameError: name '$name'|UnboundLocalError.*'$name')" "$WORK/plain.log"; then
            echo "UNVERIFIED: deleting $FILE:$LINE unbound '$name', and the suite died with" >&2
            echo "            NameError/UnboundLocalError rather than a failed assertion." >&2
            echo "            This proves the code broke, NOT that the tests check it." >&2
            echo "            Retry with: negate mode, or target the last USE of '$name'." >&2
            exit 2
        fi
    done <"$WORK/bound"
fi

echo "DETECTED: $FILE:$LINE sabotage made the suite fail (exit $rc)."
exit 0
