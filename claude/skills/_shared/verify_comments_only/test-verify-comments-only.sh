#!/usr/bin/env bash
# Regression harness for verify-comments-only.sh.
#
# Run it after ANY edit to the verifier:
#
#   ./test-verify-comments-only.sh              # everything
#   SKIP_CLOC=1 ./test-verify-comments-only.sh  # skip the 3 cases that shell out to npx cloc
#
# Each case writes a before/after pair to a temp dir, runs the verifier on it, and
# asserts the exit code (and, where the distinction matters, a stderr substring).
#
# Two case labels are not ordinary passes:
#   SEMANTICS  -- a deliberate policy choice, not an obvious truth. Changing the
#                 verdict here is a policy change; see the header of the verifier.
#   LIMITATION -- a known hole that this harness pins so it cannot be mistaken for
#                 coverage. The expected result is the WRONG answer, recorded on
#                 purpose. Do not "fix" the expectation without fixing the hole.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VERIFIER=${VERIFIER:-$SCRIPT_DIR/verify-comments-only.sh}
SKIP_CLOC=${SKIP_CLOC:-0}

[[ -x $VERIFIER ]] || { echo "no executable verifier at $VERIFIER" >&2; exit 2; }

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

n=0 passed=0 failed=0 skipped=0
FAILED_NAMES=()

# check <label> <name> <expected-exit> <ext> [expected-stderr-substring]
# Reads the case payloads from the globals BEFORE and AFTER.
check() {
    local label=$1 name=$2 expect=$3 ext=$4 want=${5:-}
    n=$((n + 1))
    local id
    id=$(printf '%02d' "$n")

    if [[ $label == CLOC && $SKIP_CLOC == 1 ]]; then
        skipped=$((skipped + 1))
        printf 'SKIP  %s %s (SKIP_CLOC=1)\n' "$id" "$name"
        return
    fi

    local dir="$work/$id"
    mkdir -p "$dir"
    printf '%s\n' "$BEFORE" >"$dir/before.$ext"
    printf '%s\n' "$AFTER" >"$dir/after.$ext"

    local out rc
    out=$("$VERIFIER" "$dir/before.$ext" "$dir/after.$ext" 2>&1)
    rc=$?

    if [[ $rc == "$expect" ]] && [[ -z $want || $out == *"$want"* ]]; then
        passed=$((passed + 1))
        printf 'PASS  %s %-10s %s (exit %s)\n' "$id" "$label" "$name" "$rc"
    else
        failed=$((failed + 1))
        FAILED_NAMES+=("$id $name")
        printf 'FAIL  %s %-10s %s -- expected exit %s' "$id" "$label" "$name" "$expect"
        [[ -n $want ]] && printf ' containing %q' "$want"
        printf ', got exit %s\n' "$rc"
        printf '%s\n' "$out" | sed 's/^/          | /'
    fi
}

# =============================================================================
# Part 1 -- Python: docstrings
# =============================================================================

# C1: the bug this harness was written for. A DELETED docstring removes an Expr
# node, so a verifier that blanks docstrings in place sees the body length change.
BEFORE=$(cat <<'EOF'
def _normalize_key(key: str) -> str:
    """Normalize the key."""
    return key.strip().lower()
EOF
)
AFTER=$(cat <<'EOF'
def _normalize_key(key: str) -> str:
    return key.strip().lower()
EOF
)
check CORE "docstring deleted (not sole statement)" 0 py

BEFORE=$(cat <<'EOF'
def load(path: str) -> bytes:
    """Read the file at path and return its bytes.

    Args:
        path (str): The path.

    Returns:
        bytes: The bytes.
    """
    with open(path, "rb") as fh:
        return fh.read()
EOF
)
AFTER=$(cat <<'EOF'
def load(path: str) -> bytes:
    """Read the file at path and return its bytes."""
    with open(path, "rb") as fh:
        return fh.read()
EOF
)
check CORE "docstring compressed" 0 py

BEFORE=$(cat <<'EOF'
"""Small helpers for the widget subsystem."""

VALUE = 1
EOF
)
AFTER=$(cat <<'EOF'
VALUE = 1
EOF
)
check CORE "module docstring deleted" 0 py

# The module is the one DOC_OWNER whose body may legally end up empty, so the
# `pass` fallback must NOT apply to it. Routine for __init__.py and namespace
# stubs, and missed by the case above, which leaves VALUE = 1 behind.
BEFORE=$(cat <<'EOF'
"""Small helpers for the widget subsystem."""
EOF
)
AFTER=""
check CORE "sole module docstring -> empty file" 0 py

# ... and the same asymmetry from the other side: a def body needs the `pass`,
# a module body does not, so adding one at module level is a real code change.
BEFORE=$(cat <<'EOF'
"""Small helpers for the widget subsystem."""
EOF
)
AFTER=$(cat <<'EOF'
pass
EOF
)
check CORE "sole module docstring -> module-level pass" 1 py

# The empty-body footgun: deleting a sole-statement docstring outright.
BEFORE=$(cat <<'EOF'
def stub() -> None:
    """Does nothing yet."""
EOF
)
AFTER=$(cat <<'EOF'
def stub() -> None:
EOF
)
check CORE "sole-statement docstring deleted -> SyntaxError" 1 py "no longer parses"

# SEMANTICS: `pass` substitution is the sanctioned way out of the footgun
# (comment-cleanup/SKILL.md permits it explicitly), so the verifier accepts it
# even though it is, strictly, a code edit. comment-janitor's own prose still
# forbids it -- that rule is no longer mechanically enforced here.
BEFORE=$(cat <<'EOF'
def stub() -> None:
    """Does nothing yet."""
EOF
)
AFTER=$(cat <<'EOF'
def stub() -> None:
    pass
EOF
)
check SEMANTICS "sole-statement docstring -> pass" 0 py

# SEMANTICS: adding a docstring passes. comment-cleanup re-adds minimal
# docstrings by design; comment-janitor's "never add a comment" is prose only.
BEFORE=$(cat <<'EOF'
def bump(x: int) -> int:
    return x + 1
EOF
)
AFTER=$(cat <<'EOF'
def bump(x: int) -> int:
    """Return x incremented, saturating at the configured cap."""
    return x + 1
EOF
)
check SEMANTICS "docstring added" 0 py

# ruff D419: a blanked-out docstring fails lint where a removed one would not.
BEFORE=$(cat <<'EOF'
def _normalize_key(key: str) -> str:
    """Normalize the key."""
    return key.strip().lower()
EOF
)
AFTER=$(cat <<'EOF'
def _normalize_key(key: str) -> str:
    """"""
    return key.strip().lower()
EOF
)
check CORE "empty docstring left behind (D419)" 1 py "empty docstring"

# =============================================================================
# Part 2 -- Python: code changes must be caught
# =============================================================================

BEFORE=$(cat <<'EOF'
def bump(x: int) -> int:
    y = x + 1  # bump it
    return y
EOF
)
AFTER=$(cat <<'EOF'
def bump(x: int) -> int:
    return y
EOF
)
check CORE "line of real code deleted" 1 py

BEFORE=$(cat <<'EOF'
# Step 1: start the counter at zero
counter = 0
counter += 1  # increment the counter
EOF
)
AFTER=$(cat <<'EOF'
counter = 0
counter += 1
EOF
)
check CORE "plain comments deleted, code untouched" 0 py

# L4 -- changes that ast.dump normalizes away and a token signature catches.
BEFORE=$(cat <<'EOF'
LIMIT = 1_000  # the cap
EOF
)
AFTER=$(cat <<'EOF'
LIMIT = 1000
EOF
)
check TOKENS "numeric literal respelled (1_000 -> 1000)" 1 py

BEFORE=$(cat <<'EOF'
NAME = 'widget'  # the name
EOF
)
AFTER=$(cat <<'EOF'
NAME = "widget"
EOF
)
check TOKENS "quote style changed" 1 py

BEFORE=$(cat <<'EOF'
MSG = "hello " "world"  # greeting
EOF
)
AFTER=$(cat <<'EOF'
MSG = "hello world"
EOF
)
check TOKENS "implicit string concatenation collapsed" 1 py

# The token stream must survive a comment-only line, which emits NL rather than
# NEWLINE -- the caveat the research flags explicitly.
BEFORE=$(cat <<'EOF'
values = [
    1,  # one
    # a whole-line comment inside the brackets
    2,
]
EOF
)
AFTER=$(cat <<'EOF'
values = [
    1,
    2,
]
EOF
)
check TOKENS "comment-only line inside brackets (NL vs NEWLINE)" 0 py

BEFORE=$(cat <<'EOF'
def broken(
EOF
)
AFTER=$(cat <<'EOF'
def broken() -> None:
    pass
EOF
)
check CORE "original does not parse" 2 py "UNVERIFIED"

# =============================================================================
# Part 3 -- directive comments (all languages, checked before the language split)
# =============================================================================

BEFORE=$(cat <<'EOF'
import os  # noqa: F401
# a narration comment
VALUE = 1
EOF
)
AFTER=$(cat <<'EOF'
import os
VALUE = 1
EOF
)
check CORE "# noqa lost" 1 py "directive"

# M1: flake8 documents noqa as case-insensitive.
BEFORE=$(cat <<'EOF'
import os  # NOQA
VALUE = 1
EOF
)
AFTER=$(cat <<'EOF'
import os
VALUE = 1
EOF
)
check DIRECTIVE "# NOQA (uppercase) lost" 1 py "directive"

# coverage.py: "differences in spacing and letter case are also recognized".
BEFORE=$(cat <<'EOF'
def risky() -> None:  # PRAGMA: NO COVER
    raise SystemExit(1)
EOF
)
AFTER=$(cat <<'EOF'
def risky() -> None:
    raise SystemExit(1)
EOF
)
check DIRECTIVE "# PRAGMA: NO COVER (uppercase) lost" 1 py "directive"

BEFORE=$(cat <<'EOF'
value = compute()  # pyright: ignore[reportUnknownMemberType]
EOF
)
AFTER=$(cat <<'EOF'
value = compute()
EOF
)
check DIRECTIVE "# pyright: ignore lost" 1 py "directive"

# H1: notebook cell markers look exactly like the decorative separators the
# delete lane targets.
BEFORE=$(cat <<'EOF'
# %%
import os

# %% Load the data
VALUE = 1
EOF
)
AFTER=$(cat <<'EOF'
import os

VALUE = 1
EOF
)
check DIRECTIVE "# %% cell markers deleted" 1 py "directive"

# H1: PEP 723 inline script metadata -- deleting it breaks `uv run`.
BEFORE=$(cat <<'EOF'
# /// script
# dependencies = ["requests"]
# ///
import requests
EOF
)
AFTER=$(cat <<'EOF'
import requests
EOF
)
check DIRECTIVE "PEP 723 # /// script block deleted" 1 py "directive"

BEFORE=$(cat <<'EOF'
VALUE = 1
# vim: set ts=4 sw=4 et:
EOF
)
AFTER=$(cat <<'EOF'
VALUE = 1
EOF
)
check DIRECTIVE "vim modeline lost" 1 py "directive"

# Position-sensitive: the text survives but line 1 no longer holds it.
BEFORE=$(cat <<'EOF'
#!/usr/bin/env python3
# a narration comment
VALUE = 1
EOF
)
AFTER=$(cat <<'EOF'

#!/usr/bin/env python3
VALUE = 1
EOF
)
check CORE "shebang displaced off line 1" 1 py "position-sensitive"

# M1: GCC matches the fallthrough comment body against a regex, case-insensitively
# across several spellings.
BEFORE=$(cat <<'EOF'
switch (n) {
case 1:
    handle();
    /* FALLTHRU */
case 2:
    other();
}
EOF
)
AFTER=$(cat <<'EOF'
switch (n) {
case 1:
    handle();
case 2:
    other();
}
EOF
)
check DIRECTIVE "/* FALLTHRU */ (uppercase) lost" 1 c "directive"

# M1: clippy's undocumented_unsafe_blocks turns this into a build failure.
BEFORE=$(cat <<'EOF'
// SAFETY: the pointer is non-null for the lifetime of the arena.
unsafe { ptr.read() }
EOF
)
AFTER=$(cat <<'EOF'
unsafe { ptr.read() }
EOF
)
check DIRECTIVE "// SAFETY: lost" 1 rs "directive"

# M1: Oracle optimizer hints. Silent plan regression, zero build signal.
BEFORE=$(cat <<'EOF'
SELECT /*+ INDEX(t idx_created) */ id
FROM events t
WHERE created > SYSDATE - 1;
EOF
)
AFTER=$(cat <<'EOF'
SELECT id
FROM events t
WHERE created > SYSDATE - 1;
EOF
)
check DIRECTIVE "Oracle /*+ hint lost" 1 sql "directive"

# M1: in a --require-pragma repo, dropping the lone-tag docblock unformats the file.
BEFORE=$(cat <<'EOF'
/** @format */
export const x = 1;
EOF
)
AFTER=$(cat <<'EOF'
export const x = 1;
EOF
)
check DIRECTIVE "prettier @format pragma lost" 1 js "directive"

BEFORE=$(cat <<'EOF'
/* globals process, Buffer */
const x = process.env.HOME;
EOF
)
AFTER=$(cat <<'EOF'
const x = process.env.HOME;
EOF
)
check DIRECTIVE "/* globals */ inline config lost" 1 js "directive"

BEFORE=$(cat <<'EOF'
package main

//extern malloc
func malloc(n uintptr) unsafe.Pointer
EOF
)
AFTER=$(cat <<'EOF'
package main

func malloc(n uintptr) unsafe.Pointer
EOF
)
check DIRECTIVE "//extern lost" 1 go "directive"

BEFORE=$(cat <<'EOF'
# check=error=true
FROM alpine:3.20
EOF
)
AFTER=$(cat <<'EOF'
FROM alpine:3.20
EOF
)
check DIRECTIVE "Dockerfile # check= lost" 1 dockerfile "directive"

# =============================================================================
# Part 4 -- the non-Python (cloc) path
# =============================================================================

BEFORE=$(cat <<'EOF'
#!/usr/bin/env bash
# Narrate the thing we are about to do
echo hi
EOF
)
AFTER=$(cat <<'EOF'
#!/usr/bin/env bash
echo hi
EOF
)
check CLOC "shell comment deleted" 0 sh

BEFORE=$(cat <<'EOF'
#!/usr/bin/env bash
# Narrate the thing we are about to do
echo hi
EOF
)
AFTER=$(cat <<'EOF'
#!/usr/bin/env bash
echo bye
EOF
)
check CLOC "shell code changed" 1 sh

# LIMITATION (H3): cloc lexes a `#` line inside a heredoc as a comment on both
# sides, so deleting DATA that looks like a banner passes. Exit 0 on the cloc
# path is NECESSARY, NOT SUFFICIENT. The agent-side mitigation is a rule, not a
# check: never delete a comment-looking line inside a heredoc or quoted context.
BEFORE=$(cat <<'EOF'
#!/usr/bin/env bash
cat <<'EOT'
# ---- section marker in DATA ----
payload
EOT
EOF
)
AFTER=$(cat <<'EOF'
#!/usr/bin/env bash
cat <<'EOT'
payload
EOT
EOF
)
check LIMITATION "heredoc data deleted -- FALSE PASS, known hole" 0 sh

# =============================================================================

printf '\n%d cases: %d passed, %d failed, %d skipped\n' "$n" "$passed" "$failed" "$skipped"
if ((failed)); then
    printf 'failed:\n'
    printf '  %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi
exit 0
