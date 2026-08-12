#!/usr/bin/env bash
# Regression harness for sabotage-check.sh. Run after ANY edit to the checker.
#
# The exit codes ARE the contract, and they are inverted relative to the other
# _shared/ verifiers (0 = sabotage detected = tests work; 1 = sabotage survived
# = the finding; 2 = could not run). Every case pins one.
#
# The "test command" is a plain python3 runner, not pytest: the guardrail cases
# must be fast, and the checker is agnostic about what runs the suite. Two cases
# use a bare `bash -c` to pin behaviour when the suite is trivially green/red.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SAB=$HERE/sabotage-check.sh
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
REPO=$WORK/repo

build_repo() { # fresh git repo with a known-good module + runner
    rm -rf "$REPO"
    mkdir -p "$REPO/src"
    cat >"$REPO/src/calc.py" <<'EOF'
def clamp(value, low, high):
    if value < low:
        value = low
    if value > high:
        value = high
    return value


def normalize(text):
    text = text.strip()
    return text.lower()


def shout(text):
    result = text.upper()
    return result + "!"
EOF
    # Runner asserts clamp's low branch only. normalize's strip and shout's
    # upper() are deliberately unchecked -- those are the SURVIVED and
    # bound-name cases.
    cat >"$REPO/run_tests.py" <<'EOF'
import sys
sys.path.insert(0, "src")
from calc import clamp, shout

assert clamp(-5, 0, 10) == 0, "clamp low"
shout("hi")
EOF
    git -C "$REPO" init -q .
    git -C "$REPO" config user.email t@t.t
    git -C "$REPO" config user.name t
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm init
}

line_of() { grep -n "$1" "$REPO/src/calc.py" | head -1 | cut -d: -f1; }

check() { # check <want-exit> <name> <mode> <line> [test-cmd...]
    local want=$1 name=$2 mode=$3 line=$4
    shift 4
    local cmd=("$@")
    [[ ${#cmd[@]} -gt 0 ]] || cmd=(python3 run_tests.py)
    local out got
    out=$(cd "$REPO" && "$SAB" "$mode" src/calc.py "$line" "${cmd[@]}" 2>&1)
    got=$?
    if [[ $got == "$want" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL [$name]: want exit $want, got $got"
        sed 's/^/    /' <<<"$out"
    fi
    # Every case must leave the file byte-identical, whatever the verdict.
    if [[ -n $(git -C "$REPO" status --porcelain -- src/calc.py) ]]; then
        fail=$((fail + 1))
        echo "FAIL [$name]: src/calc.py was NOT restored"
        git -C "$REPO" checkout -- src/calc.py
    else
        pass=$((pass + 1))
    fi
}

# ------------------------------------------------------------- THE VERDICTS
build_repo
check 0 "covered statement -> DETECTED"   delete "$(line_of 'value = low')"
check 1 "unchecked statement -> SURVIVED" delete "$(line_of 'text = text.strip')"
# SEMANTICS: deleting an assignment whose name is read later kills the suite
# with NameError. That is the CODE breaking, not the tests working -- an
# assertion-free smoke test "detects" it equally loudly. Must NOT report 0.
check 2 "unbound name -> UNVERIFIED"      delete "$(line_of 'result = text.upper')"
check 0 "negated condition -> DETECTED"   negate "$(line_of 'if value < low')"

# --------------------------------------------------------- TARGET REFUSALS
build_repo
check 2 "negate on non-conditional"  negate "$(line_of 'value = low')"
check 2 "no statement on that line"  delete 999
check 2 "line 0 is not a statement"  delete 0

cat >"$REPO/src/imports.py" <<'EOF'
import os
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm imports
imp_out=$(cd "$REPO" && "$SAB" delete src/imports.py 1 python3 run_tests.py 2>&1)
if [[ $? == 2 ]] && grep -q "refusing to delete an import" <<<"$imp_out"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL [import refused]: want exit 2 + message"
    sed 's/^/    /' <<<"$imp_out"
fi

# ------------------------------------------------------------- GUARDRAILS
build_repo
echo "# dirty" >>"$REPO/src/calc.py"
dirty_out=$(cd "$REPO" && "$SAB" delete src/calc.py 2 python3 run_tests.py 2>&1)
dirty_rc=$?
git -C "$REPO" checkout -- src/calc.py
if [[ $dirty_rc == 2 ]] && grep -q "uncommitted changes" <<<"$dirty_out"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL [dirty file refused]: want exit 2 + message, got $dirty_rc"
fi

build_repo
cp "$REPO/src/calc.py" "$REPO/src/untracked.py"
untracked_out=$(cd "$REPO" && "$SAB" delete src/untracked.py 2 python3 run_tests.py 2>&1)
if [[ $? == 2 ]] && grep -q "untracked" <<<"$untracked_out"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL [untracked file refused]"
fi

mkdir -p "$WORK/nogit/src"
cp "$REPO/src/calc.py" "$WORK/nogit/src/calc.py"
cp "$REPO/run_tests.py" "$WORK/nogit/run_tests.py"
nogit_out=$(cd "$WORK/nogit" && "$SAB" delete src/calc.py 2 python3 run_tests.py 2>&1)
if [[ $? == 2 ]] && grep -q "not inside a git repository" <<<"$nogit_out"; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL [non-git refused]"
fi

# SEMANTICS: a suite that is already red before sabotage makes every verdict
# meaningless, so the check refuses rather than reporting a false DETECTED.
build_repo
check 2 "already-red baseline refused" delete "$(line_of 'value = low')" bash -c 'exit 1'

# A trivially-green command that ignores the source cannot detect anything;
# that is a genuine SURVIVED, and pins that exit 1 needs no pytest.
check 1 "green-regardless command -> SURVIVED" delete "$(line_of 'value = low')" bash -c 'exit 0'

# SEMANTICS: a sabotaged loop guard hangs forever without this. 141 and other
# signal codes must not leak through as a verdict.
build_repo
timeout_out=$(cd "$REPO" && SABOTAGE_TIMEOUT=1 "$SAB" delete src/calc.py "$(line_of 'value = low')" bash -c 'sleep 30' 2>&1)
if [[ $? == 2 ]]; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL [timeout -> 2]"
fi

# ---------------------------------------------------------------- ARG CHECKS
build_repo
argcheck() { # <name> <want> <args...>
    local name=$1 want=$2
    shift 2
    (cd "$REPO" && "$SAB" "$@" >/dev/null 2>&1)
    local got=$?
    if [[ $got == "$want" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL [$name]: want exit $want, got $got"
    fi
}
argcheck "bad mode"          2 rewrite src/calc.py 2 python3 run_tests.py
argcheck "missing file"      2 delete src/nope.py 2 python3 run_tests.py
argcheck "non-integer line"  2 delete src/calc.py abc python3 run_tests.py
argcheck "no test command"   2 delete src/calc.py 2
argcheck "no args at all"    2

echo "----"
echo "sabotage-check: $pass passed, $fail failed ($((pass + fail)) cases)"
[[ $fail == 0 ]]
