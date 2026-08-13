#!/usr/bin/env bash
# Regression harness for test-census.sh. Run after ANY edit to the census.
# Every case pins a classification, not just an exit code, because the census
# returns 0 for "ran" regardless of what it found -- the findings ARE the
# contract. SEMANTICS cases pin deliberate policy choices; LIMITATION cases pin
# known holes so a future "fix" that silently changes one has to notice.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CENSUS=$HERE/test-census.sh
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0

fixture() { # fixture <relpath> ; body on stdin
    mkdir -p "$(dirname "$WORK/t/$1")"
    cat >"$WORK/t/$1"
}

reset() { rm -rf "$WORK/t"; mkdir -p "$WORK/t"; }

run() { "$CENSUS" "$WORK/t" "${1:-}" "${2:-}" 2>&1; }

# want_section <section> <needle> -- assert <needle> appears under <section>
want_section() { # <name> <section-regex> <needle> <want: yes|no>
    local name=$1 section=$2 needle=$3 want=$4
    local out block got
    out=$(run "${5:-}" "${6:-}")
    block=$(awk "/$section/{f=1;next} /^[A-Z].*\(|^$/{if(f&&NF==0)f=0} f" <<<"$out")
    if grep -qF -- "$needle" <<<"$block"; then got=yes; else got=no; fi
    if [[ $got == "$want" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL [$name]: wanted $needle under $section = $want, got $got"
        sed 's/^/    /' <<<"$out"
    fi
}

want_exit() { # <name> <want-exit> [args...]
    local name=$1 want=$2
    shift 2
    "$CENSUS" "$@" >/dev/null 2>&1
    local got=$?
    if [[ $got == "$want" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL [$name]: want exit $want, got $got"
    fi
}

want_grep() { # <name> <needle> <want: yes|no> [vocab] [dump]
    local name=$1 needle=$2 want=$3 got
    if run "${4:-}" "${5:-}" | grep -qF -- "$needle"; then got=yes; else got=no; fi
    if [[ $got == "$want" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL [$name]: wanted '$needle' present=$want, got $got"
        run "${4:-}" "${5:-}" | sed 's/^/    /'
    fi
}

# ---------------------------------------------------------------- ASSERTING
reset
fixture tests/test_ok.py <<'EOF'
import pytest
from unittest import mock

def test_plain_assert():
    x = 1
    assert x == 1

def test_raises():
    with pytest.raises(ValueError, match="nope"):
        raise ValueError("nope")

def test_mock_assert():
    m = mock.Mock()
    m(1)
    m.assert_called_once_with(1)

async def test_async_asserts():
    assert True
EOF
want_section "plain assert not flagged"  "ASSERTION-FREE" "test_plain_assert" no
want_section "pytest.raises counts"      "ASSERTION-FREE" "test_raises"       no
want_section "mock assert_* counts"      "ASSERTION-FREE" "test_mock_assert"  no
want_section "async test scanned"        "ASSERTION-FREE" "test_async_asserts" no

# ------------------------------------------------------- HELPER RESOLUTION
reset
fixture tests/test_helpers.py <<'EOF'
def _leaf(x):
    assert x

def _mid(x):
    _leaf(x)

def go(x):
    _mid(x)

def test_one_hop():
    _leaf(1)

def test_three_hops():
    go(1)

def test_external_helper():
    left = 1
    right = 1
    eq_(left, right)
EOF
want_section "helper one hop resolved"    "ASSERTION-FREE" "test_one_hop"    no
want_section "fixpoint over 3 hops"       "ASSERTION-FREE" "test_three_hops" no
want_section "unknown helper still flagged" "ASSERTION-FREE" "test_external_helper" yes
# SEMANTICS: a helper defined outside the scanned tree is invisible; the vocab
# argument is the documented escape hatch and must fully suppress the finding.
want_section "vocab arg resolves external" "ASSERTION-FREE" "test_external_helper" no "eq_"

# ------------------------------------------------------------ TRUE POSITIVE
reset
fixture tests/test_bad.py <<'EOF'
def compute():
    return 1

def test_no_oracle():
    result = compute()
    other = result + 1
    final = other
EOF
want_section "assertion-free flagged" "ASSERTION-FREE" "test_no_oracle" yes

# ---------------------------------------------------- REVIEW CLASSIFICATION
reset
fixture tests/test_review.py <<'EOF'
import pytest
from contextlib import catch_warnings

def compute():
    return 1

def test_benchmark_carried(benchmark):
    benchmark(compute)

@pytest.mark.function_call_count
def test_decorator_carried():
    compute()

@pytest.mark.parametrize("n", [1, 2])
def test_inert_mark_only(n):
    value = compute()
    other = value
    third = other

def test_delegator():
    compute()

def test_warnings_config():
    with catch_warnings():
        compute()
EOF
want_section "benchmark fixture -> REVIEW"   "REVIEW" "test_benchmark_carried" yes
want_section "custom decorator -> REVIEW"    "REVIEW" "test_decorator_carried" yes
want_section "catch_warnings -> REVIEW"      "REVIEW" "test_warnings_config"   yes
want_section "single-call delegator -> REVIEW" "REVIEW" "test_delegator"       yes
# SEMANTICS: parametrize/skip/xfail/usefixtures carry no assertion, so a test
# wearing only those is a real finding, not a REVIEW deferral.
want_section "inert mark stays a finding" "ASSERTION-FREE" "test_inert_mark_only" yes

# ------------------------------------------------------------ NEAR-DUPLICATE
reset
fixture tests/test_dupes.py <<'EOF'
def test_a():
    x = 1
    y = x + 1
    assert y == 2

def test_b():
    p = 1
    q = p + 1
    assert q == 2

def test_different_literal():
    p = 9
    q = p + 1
    assert q == 10

def test_short_a():
    z = 1
    assert z == 1

def test_short_b():
    w = 1
    assert w == 1
EOF
want_section "renamed locals group"          "NEAR-DUPLICATE" "test_a" yes
# SEMANTICS: literals are KEPT in the fingerprint. Blanking them collapsed every
# single-assert test into one bucket (36 bogus groups on httpx).
want_section "differing literals do NOT group" "NEAR-DUPLICATE" "test_different_literal" no
# LIMITATION: the MIN_STMTS=3 floor means genuinely identical 2-statement tests
# go undetected. Pinned so a future lowering of the floor is a deliberate act.
want_section "2-stmt identical undetected"  "NEAR-DUPLICATE" "test_short_a" no

# --------------------------------------------------------- COLLECTION GAP
reset
fixture tests/test_gap.py <<'EOF'
def test_collected():
    assert True

def test_parametrized():
    assert True

def test_never_runs():
    assert True
EOF
printf 'tests/test_gap.py::test_collected\ntests/test_gap.py::test_parametrized[1-2]\n' >"$WORK/dump.txt"
want_section "uncollected test found"    "NEVER COLLECTED" "test_never_runs"  yes "" "$WORK/dump.txt"
want_section "collected test absent"     "NEVER COLLECTED" "test_collected"   no  "" "$WORK/dump.txt"
want_section "parametrize IDs stripped"  "NEVER COLLECTED" "test_parametrized" no "" "$WORK/dump.txt"
# SEMANTICS: a dump made without -o addopts="" prints per-file COUNTS, not node
# IDs, which would make every test look uncollected. Must warn, not lie.
printf 'tests/test_gap.py: 3\n' >"$WORK/bad.txt"
want_grep "counts-only dump warns" "dump contained no node IDs" yes "" "$WORK/bad.txt"

# ------------------------------------------------------------- ROBUSTNESS
reset
fixture tests/test_good.py <<'EOF'
def test_fine():
    assert True
EOF
fixture tests/test_broken.py <<'EOF'
def test_syntax_error(:
EOF
want_grep "unparseable file counted"   "parse failures:        1" yes
want_grep "sibling still scanned"      "test functions:        1" yes

reset
fixture tests/test_all_broken.py <<'EOF'
def oops(:
EOF
want_exit "all files unparseable -> 2" 2 "$WORK/t"
want_exit "missing dir -> 2"           2 "$WORK/nope"
want_exit "no args -> 2"               2
want_exit "unreadable dump -> 2"       2 "$WORK/t" "" "$WORK/nonexistent-dump.txt"

reset
fixture tests/conftest.py <<'EOF'
def assert_shape(obj):
    assert obj is not None
EOF
fixture tests/test_conftest_helper.py <<'EOF'
def test_uses_conftest_helper():
    assert_shape(1)
EOF
want_section "conftest helper resolved" "ASSERTION-FREE" "test_uses_conftest_helper" no

echo "----"
echo "test-census: $pass passed, $fail failed ($((pass + fail)) cases)"
[[ $fail == 0 ]]
