#!/usr/bin/env bash
# Regression harness for verify-logging-only.sh. Run after ANY edit to the
# verifier. Every case is a before/after pair with a pinned expected exit code;
# the SEMANTICS cases pin deliberate policy choices, the LIMITATION case pins a
# known hole so a future "fix" that silently changes it has to notice.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERIFY=$HERE/verify-logging-only.sh
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
check() { # check <expected-exit> <name> [before] [after]
    local want=$1 name=$2 before=${3:-$WORK/before.py} after=${4:-$WORK/after.py}
    "$VERIFY" "$before" "$after" >/dev/null 2>&1
    local got=$?
    if [[ $got == "$want" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL [$name]: want exit $want, got $got"
        "$VERIFY" "$before" "$after" 2>&1 | sed 's/^/    /'
    fi
}

B=$WORK/before.py A=$WORK/after.py
PRE='import logging
logger = logging.getLogger(__name__)
'

# ---------- exit 0: contained and gated ----------

cat >"$B" <<EOF
${PRE}def f(x):
    y = x + 1
    return y
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    y = x + 1
    logger.info("computed %s", y)
    return y
EOF
check 0 add-plain-log

cat >"$B" <<EOF
${PRE}def f(x):
    logger.debug("start %s", x)
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    logger.info("start %s", x)
    return x
EOF
check 0 relevel-debug-to-info

cat >"$B" <<EOF
${PRE}def f(x):
    logger.info("entering f")
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    return x
EOF
check 0 remove-constant-arg-log

cat >"$B" <<EOF
${PRE}def f(x):
    if x:
        logger.debug("branch taken")
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    if x:
        pass
    return x
EOF
check 0 sole-log-in-if-becomes-pass

cat >"$B" <<EOF
${PRE}def f(x):
    try:
        return x
    finally:
        logger.debug("done")
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    try:
        return x
    finally:
        pass
EOF
check 0 sole-log-in-finally-becomes-pass

cat >"$B" <<EOF
${PRE}def f(items):
    return sorted(items)
EOF
cat >"$A" <<EOF
${PRE}def f(items):
    logger.debug("sorting %d items", len(items))
    return sorted(items)
EOF
check 0 add-log-with-len-arg

cat >"$B" <<EOF
${PRE}def f(x):
    logger.info("x %s", x)
    return x
EOF
cp "$B" "$A"
check 0 identical-files

cat >"$B" <<EOF
${PRE}def f(x):
    logger.warn("legacy %s", x)
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    logger.warning("legacy %s", x)
    return x
EOF
check 0 warn-to-warning

cat >"$B" <<EOF
from logging import getLogger as gl
log = gl(__name__)
def f(x):
    log.debug("d %s", x)
    return x
EOF
cat >"$A" <<EOF
from logging import getLogger as gl
log = gl(__name__)
def f(x):
    log.info("d %s", x)
    return x
EOF
check 0 import-alias-getLogger

cat >"$B" <<EOF
import logging
logger: logging.Logger = logging.getLogger(__name__)
def f(x):
    logger.info("x %s", x)
    return x
EOF
cat >"$A" <<EOF
import logging
logger: logging.Logger = logging.getLogger(__name__)
def f(x):
    logger.debug("x %s", x)
    return x
EOF
check 0 annassign-logger

# SEMANTICS: instrumenting a logger-less file requires the setup statements, so
# adding `import logging` + a module logger binding alongside the log passes.
cat >"$B" <<EOF
def f(x):
    y = x + 1
    return y
EOF
cat >"$A" <<EOF
import logging

logger = logging.getLogger(__name__)

def f(x):
    y = x + 1
    logger.info("computed %s", y)
    return y
EOF
check 0 add-logger-setup

# SEMANTICS: removing the last log may drop the now-unused setup too.
cat >"$B" <<EOF
${PRE}def f(x):
    logger.info("entering f")
    return x
EOF
cat >"$A" <<EOF
def f(x):
    return x
EOF
check 0 remove-last-log-and-setup

# SEMANTICS: a pure re-level carries no new evaluation risk even when the
# arguments would fail the gate -- the argument tuple is byte-identical.
cat >"$B" <<EOF
${PRE}def f(d):
    logger.info("k %s", d["k"])
    return d
EOF
cat >"$A" <<EOF
${PRE}def f(d):
    logger.debug("k %s", d["k"])
    return d
EOF
check 0 relevel-exempt-from-arg-gate

# LIMITATION (pinned): moving a log WITHIN one suite is invisible by design --
# the inventory is index-free so siblings' keys stay stable. Exit 0 here even
# though the log now reads different program state.
cat >"$B" <<EOF
${PRE}def f(d, k, v):
    logger.debug("d %s", d)
    d[k] = v
    return d
EOF
cat >"$A" <<EOF
${PRE}def f(d, k, v):
    d[k] = v
    logger.debug("d %s", d)
    return d
EOF
check 0 LIMITATION-move-within-suite-invisible

# ---------- exit 1: unsafe ----------

cat >"$B" <<EOF
${PRE}def f(x):
    y = x + 1
    return y
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    return x + 1
EOF
check 1 delete-non-log-line

cat >"$B" <<EOF
${PRE}def f(conn):
    do(conn)
    return True
EOF
cat >"$A" <<EOF
${PRE}def f(conn):
    logger.info("did %s", do(conn))
    return True
EOF
check 1 smuggle-code-into-log

cat >"$B" <<EOF
${PRE}def f(x):
    if logger.isEnabledFor(logging.DEBUG):
        logger.debug("detail %s", x)
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    return x
EOF
check 1 guard-removed-with-log

cat >"$B" <<EOF
${PRE}def f(x):
    """Return x."""
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    logger.debug("f %s", x)
    """Return x."""
    return x
EOF
check 1 insertion-demotes-docstring

cat >"$B" <<EOF
class AuditTrail:
    def error(self, msg):
        pass
log = AuditTrail()
def f():
    log.error("charge failed")
    return 1
EOF
cat >"$A" <<EOF
class AuditTrail:
    def error(self, msg):
        pass
log = AuditTrail()
def f():
    return 1
EOF
check 1 lookalike-receiver-delete

cat >"$B" <<EOF
${PRE}class S:
    def run(self, evt):
        self.log.info(evt)
        return evt
EOF
cat >"$A" <<EOF
${PRE}class S:
    def run(self, evt):
        return evt
EOF
check 1 self-log-delete

cat >"$B" <<EOF
${PRE}def f(logger):
    logger.info("shadowed")
    return 1
EOF
cat >"$A" <<EOF
${PRE}def f(logger):
    return 1
EOF
check 1 shadowed-param-delete

cat >"$B" <<EOF
from __future__ import annotations
def f(x):
    return x
EOF
cat >"$A" <<EOF
import logging
from __future__ import annotations
logger = logging.getLogger(__name__)
def f(x):
    return x
EOF
check 1 insert-above-future-import

cat >"$B" <<EOF
${PRE}def f(x):
    """Return x unchanged."""
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(x):
    """Return x, unchanged and logged."""
    return x
EOF
check 1 docstring-edited

# The setup sanction must NOT excuse deleting an import that surviving
# non-log code still references.
cat >"$B" <<EOF
import logging
logging.basicConfig(level=logging.INFO)
def f(x):
    return x
EOF
cat >"$A" <<EOF
logging.basicConfig(level=logging.INFO)
def f(x):
    return x
EOF
check 1 remove-import-still-used

# ...nor deleting a logger binding that surviving non-log code still uses.
cat >"$B" <<EOF
${PRE}logger.setLevel(10)
def f(x):
    return x
EOF
cat >"$A" <<EOF
import logging
logger.setLevel(10)
def f(x):
    return x
EOF
check 1 remove-binding-still-used

# ---------- exit 2: cannot prove ----------

cat >"$B" <<EOF
${PRE}def f(stack):
    return stack
EOF
cat >"$A" <<EOF
${PRE}def f(stack):
    logger.debug("popped %s", stack.pop())
    return stack
EOF
check 2 added-log-stack-pop

cat >"$B" <<EOF
${PRE}def f(it):
    return it
EOF
cat >"$A" <<EOF
${PRE}def f(it):
    logger.debug("next %s", next(it))
    return it
EOF
check 2 added-log-next-it

cat >"$B" <<EOF
${PRE}def f():
    logger.debug("n %s", (n := compute()))
    return 1
EOF
cat >"$A" <<EOF
${PRE}def f():
    return 1
EOF
check 2 removed-log-walrus

cat >"$B" <<EOF
${PRE}def f(d):
    return d
EOF
cat >"$A" <<EOF
${PRE}def f(d):
    logger.debug("k %s", d["k"])
    return d
EOF
check 2 added-log-subscript

cat >"$B" <<EOF
${PRE}def f(d):
    return d
EOF
cat >"$A" <<EOF
${PRE}def f(d):
    logger.debug(f"computed {compute(d)}")
    return d
EOF
check 2 added-log-fstring-call

cat >"$B" <<EOF
${PRE}def f(cond, x):
    if cond:
        prep(x)
        logger.info("m %s", x)
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(cond, x):
    if cond:
        prep(x)
    logger.info("m %s", x)
    return x
EOF
check 2 hoist-out-of-nonempty-if

cat >"$B" <<EOF
${PRE}def f(cond, x):
    if cond:
        prep(x)
    logger.info("m %s", x)
    return x
EOF
cat >"$A" <<EOF
${PRE}def f(cond, x):
    if cond:
        prep(x)
        logger.info("m %s", x)
    return x
EOF
check 2 demote-into-if

printf '# not python\necho hi\n' >"$WORK/before.sh"
printf '# not python\necho hi there\n' >"$WORK/after.sh"
check 2 non-python-file "$WORK/before.sh" "$WORK/after.sh"

cat >"$B" <<EOF
def f(:
EOF
cat >"$A" <<EOF
def f(x):
    return x
EOF
check 2 before-does-not-parse

check 2 missing-before-file "$WORK/nonexistent.py" "$A"

echo
echo "$pass passed, $fail failed ($((pass + fail)) cases)"
[[ $fail == 0 ]]
