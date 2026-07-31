#!/usr/bin/env bash
# Shared by the `comment-cleanup` skill and the `@comment-janitor` agent: prove
# that an edit changed ONLY comments and docstrings, and that no load-bearing
# directive comment was lost.
#
# Why this exists: a syntax check is not enough (a file still parses after you
# delete a line of real code), and an AST check alone is not enough either --
# comments are not AST nodes, so an AST comparison passes while every comment in
# the file has been mangled or dropped. Black's own docs warn about exactly this.
# So the proof is two-part, and the second part is the one everyone forgets.
#
# Usage:
#   verify-comments-only.sh <before> <after>
#     <before>  path to the ORIGINAL content (e.g. a temp file written from
#               `git show HEAD:path/to/file.py`)
#     <after>   path to the edited file
#
# Exit codes:
#   0  VERIFIED   -- only comments and/or docstrings changed; keep the edit
#   1  UNSAFE     -- code changed, or a directive comment was lost; REVERT
#   2  UNVERIFIED -- could not prove it (unsupported language, missing tool,
#                    unparseable input); treat as unsafe and revert
#
# What "only comments and docstrings" is defined to permit -- both are policy
# choices, pinned as SEMANTICS cases in the harness:
#   * ADDING a docstring passes. `comment-cleanup` re-adds minimal docstrings by
#     design. `@comment-janitor` must not add anything, but that is its own prose
#     rule; this script does not enforce it.
#   * Replacing a SOLE-STATEMENT docstring with a bare `pass` passes, even though
#     it is strictly a code edit. It is the only safe way out of the empty-suite
#     SyntaxError, and `comment-cleanup` sanctions it explicitly.
#
# LIMIT OF PROOF, non-Python path: cloc lexes `#`/`//` inside heredocs and
# strings as comments, so deleting a banner-styled line of DATA compares equal.
# Outside Python, exit 0 is NECESSARY, NOT SUFFICIENT -- the callers carry a rule
# forbidding deletion inside quoted context, because no check here can catch it.
#
# Both files are read-only to this script. It never edits or reverts anything --
# acting on the verdict is the caller's job.
#
# Regression harness: ./test-verify-comments-only.sh (run it after ANY edit here).

set -uo pipefail

BEFORE=${1:?usage: verify-comments-only.sh <before> <after>}
AFTER=${2:?usage: verify-comments-only.sh <before> <after>}

for f in "$BEFORE" "$AFTER"; do
    [[ -r $f ]] || { echo "UNVERIFIED: cannot read $f" >&2; exit 2; }
done

# Comment text that is functional rather than documentation. Losing any of these
# changes compilation, typing, linting, coverage, bundling, or legal standing --
# and most of those failures are SILENT, which is why this is a mechanical check
# and not a matter of judgement. Applied to every language: a stray match costs a
# rejected edit, a miss costs a broken build. Deliberately over-broad in a few
# places for that reason -- ` ex:` (vim modeline form) and `--+` (Oracle hint)
# will occasionally match ordinary prose and block its deletion.
DIRECTIVE_RE='(^|[^:])('
DIRECTIVE_RE+='#!|-\*-'                                     # shebang, PEP 263 / Emacs first line
DIRECTIVE_RE+='|#[[:space:]]*(type|pragma|fmt|yapf|isort|nosec|coding|pylint|ruff|mypy|pyright'
DIRECTIVE_RE+='|flake8|shellcheck|codespell|rubocop|warn_indent|shareable_constant_value'
DIRECTIVE_RE+='|SPDX|syntax=|escape=|check=)\b'             # `check=` is Dockerfile v1.8+
DIRECTIVE_RE+='|#:|#cgo[[:space:]]'                         # Sphinx doc comments, cgo build flags
DIRECTIVE_RE+='|#[[:space:]]*frozen_string_literal'
DIRECTIVE_RE+='|//[a-z0-9]+:[a-z0-9]'                       # Go's own directive definition
DIRECTIVE_RE+='|//[[:space:]]*\+build'
DIRECTIVE_RE+='|//[[:space:]]*(nolint|NOLINT|export|line |extern )'
DIRECTIVE_RE+='|//[[:space:]]*SAFETY:'                      # clippy undocumented_unsafe_blocks
DIRECTIVE_RE+='|/[/*][[:space:]]*(eslint[- ]|globals[[:space:]]|@ts-|@flow|@jsx'
DIRECTIVE_RE+='|@format|@prettier|@noprettier|prettier-ignore|istanbul |webpack'
DIRECTIVE_RE+='|noinspection|NOLINTBEGIN|NOLINTEND)'
DIRECTIVE_RE+='|//#[[:space:]]*source(MappingURL|URL)'
DIRECTIVE_RE+='|/\*[#@]__(PURE|KEY|MANGLE_PROP|INLINE|NOINLINE)__'
DIRECTIVE_RE+='|/\*!'                                       # esbuild/terser legal comment
DIRECTIVE_RE+='|/\*\+'                                      # Oracle optimizer hint, inline form
DIRECTIVE_RE+='|@license|@preserve|@generated'
DIRECTIVE_RE+='|DO NOT EDIT|AUTO-?GENERATED|Code generated'
DIRECTIVE_RE+='|[Cc]opyright|SPDX-License-Identifier|Deprecated:'
DIRECTIVE_RE+='|[[:space:]](vi|vim|Vim)[<=>0-9]*:'          # modelines
DIRECTIVE_RE+='|Local Variables:'                           # Emacs trailing block
DIRECTIVE_RE+='|\$NON-NLS-[0-9]+\$'
DIRECTIVE_RE+=')'

# Directives that are only themselves at the start of a line. Anchoring them is
# not pedantry -- unanchored, every one of these collides head-on with the
# decorative-banner deletion the callers are meant to perform: `///` matches the
# path in `'///foo'`, `--+` matches the tail of `+--------+` ASCII box art, and
# `/**` matches `/*******/`. The `[^/]`/`[^*]` guards keep the pure-rule forms
# (`//////`, `/*****`) deletable while protecting real doc comments. Accepted
# cost: a block banner opening with a bare `/**` on its own line still matches,
# so that one shape is protected rather than deletable. Rejecting a legal edit is
# the safe direction; missing a doc comment is not.
DIRECTIVE_BOL_RE='^[[:space:]]*('
DIRECTIVE_BOL_RE+='#[[:space:]]*%%'                          # notebook / IDE cell markers
DIRECTIVE_BOL_RE+='|#[[:space:]]*///([[:space:]]|$)'         # PEP 723 inline script metadata fences
DIRECTIVE_BOL_RE+='|///([^/]|$)|//!|/\*\*([^*]|$)'           # Rust / C# / Javadoc doc openers
DIRECTIVE_BOL_RE+='|--\+'                                    # Oracle optimizer hint, line form
DIRECTIVE_BOL_RE+=')'

# Directives whose own documentation promises case-insensitive matching. Kept
# separate rather than folding `-i` into the whole pattern above, which would
# make `DO NOT EDIT` and `Code generated` match ordinary prose.
DIRECTIVE_CI_RE='#[[:space:]]*noqa'                          # flake8: case-insensitive
DIRECTIVE_CI_RE+='|#[[:space:]]*pragma:[[:space:]]*no[[:space:]]*cover'  # coverage.py: spacing + case
DIRECTIVE_CI_RE+='|falls?[[:space:]-]*thr(ough|u)'           # GCC -Wimplicit-fallthrough levels 3/4
DIRECTIVE_CI_RE+='|@formatter:[[:space:]]*(off|on)'
DIRECTIVE_CI_RE+='|checkstyle:[[:space:]]*(off|on)'

is_directive() {
    grep -qaE "$DIRECTIVE_RE" <<<"$1" \
        || grep -qaE "$DIRECTIVE_BOL_RE" <<<"$1" \
        || grep -qaiE "$DIRECTIVE_CI_RE" <<<"$1"
}

# --- Part 2a (all languages): no directive comment may be lost or altered -----
# Whole lines, not just the matched span, and leading whitespace is significant:
# several directives are ^-anchored (`//# sourceMappingURL`, `// Code generated`)
# and stop working when re-indented, without any of their text changing. Compared
# as multisets, so an added or duplicated directive is caught as well as a lost
# one. A directive that merely shifts line number -- because a comment above it
# was deleted -- has identical text and passes, which is the intent.
directives() {
    {
        grep -aE "$DIRECTIVE_RE" "$1"
        grep -aE "$DIRECTIVE_BOL_RE" "$1"
        grep -aiE "$DIRECTIVE_CI_RE" "$1"
    } | sed 's/[[:space:]]*$//' | sort
}
changed=$(diff <(directives "$BEFORE") <(directives "$AFTER"))
case $? in
0) ;;
1)
    echo "UNSAFE: directive comment(s) lost, added, or altered ('<' before, '>' after):" >&2
    printf '%s\n' "$changed" | grep -E '^[<>]' >&2
    exit 1
    ;;
*)
    echo "UNVERIFIED: could not compare directive comments (diff failed)." >&2
    exit 2
    ;;
esac

# --- Part 2b: position-sensitive directives may not move ----------------------
# Shebangs must be line 1; PEP 263 encoding declarations and Ruby magic comments
# are honoured only on line 1 or 2; a Dockerfile stops looking for `# syntax=`
# after the first comment or instruction; SPDX wants the first possible line.
# Each of these fails SILENTLY when displaced -- the file still parses, the
# directive is simply ignored -- so 2a passing is not enough.
for i in 1 2 3; do
    b_line=$(sed -n "${i}p" "$BEFORE")
    [[ -n $b_line ]] || continue
    is_directive "$b_line" || continue
    if [[ $b_line != "$(sed -n "${i}p" "$AFTER")" ]]; then
        echo "UNSAFE: position-sensitive directive moved off line $i: $b_line" >&2
        exit 1
    fi
done

# --- Part 1: code must be identical ------------------------------------------
case $AFTER in
*.py | *.pyi)
    python3 - "$BEFORE" "$AFTER" <<'PY'
import ast, io, sys, tokenize

DOC_OWNERS = (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)


def read(path):
    with open(path, "rb") as fh:
        return fh.read()


def docstring_of(node):
    """The str Constant node holding node's docstring, or None."""
    body = getattr(node, "body", None)
    if not body:
        return None
    first = body[0]
    if (
        isinstance(first, ast.Expr)
        and isinstance(first.value, ast.Constant)
        and isinstance(first.value.value, str)
    ):
        return first.value
    return None


def drop_docstrings(tree):
    """Remove docstring statements outright so docstring edits are not code changes.

    Dropping the node is what makes a DELETED docstring compare equal -- blanking
    one in place (`value.value = ""`) normalizes rewrites only, and leaves the
    body one element longer than the edited file's, so every full deletion reads
    as a code change. The ast.Pass() fallback keeps a body that held nothing but
    a docstring comparable with the bare `pass` that has to replace it.

    That fallback is for SUITES ONLY. An empty module body is legal, so a module
    whose entire content was a docstring has to normalize to an empty body rather
    than to [Pass] -- otherwise emptying such a file (routine for `__init__.py`
    and namespace stubs) reads as a code change, and adding a stray module-level
    `pass` reads as a mere comment edit. Both wrong, in opposite directions.
    """
    for node in list(ast.walk(tree)):
        if isinstance(node, DOC_OWNERS) and docstring_of(node) is not None:
            node.body = node.body[1:]
            if not node.body and not isinstance(node, ast.Module):
                node.body = [ast.Pass()]
    return tree


def ast_signature(src, path):
    tree = ast.parse(src, filename=path)
    return ast.dump(drop_docstrings(tree), annotate_fields=True, include_attributes=False)


def docstring_spans(src, path):
    spans = []
    for node in ast.walk(ast.parse(src, filename=path)):
        if not isinstance(node, DOC_OWNERS):
            continue
        doc = docstring_of(node)
        if doc is not None:
            spans.append(((doc.lineno, doc.col_offset), (doc.end_lineno, doc.end_col_offset)))
    return spans


SKIP_TYPES = frozenset({tokenize.COMMENT, tokenize.NL, tokenize.ENCODING})


def token_signature(src, path):
    """Token stream with comments, docstrings and `pass` removed.

    Stronger than the AST comparison, which normalizes away literal respelling
    (1_000 -> 1000), quote style, and implicit string-concat collapsing. Comments
    emit COMMENT plus NL (never NEWLINE), so dropping both leaves the logical
    line structure intact. `pass` is dropped because substituting it for a
    sole-statement docstring is sanctioned; every other change to a `pass` still
    shows up in the AST comparison.
    """
    spans = docstring_spans(src, path)
    out = []
    drop_newline = False
    for tok in tokenize.tokenize(io.BytesIO(src).readline):
        if tok.type in SKIP_TYPES:
            continue
        is_doc = tok.type == tokenize.STRING and any(
            lo <= tok.start and tok.end <= hi for lo, hi in spans
        )
        if is_doc or (tok.type == tokenize.NAME and tok.string == "pass"):
            drop_newline = True  # ... and the logical line it terminated
            continue
        if drop_newline and tok.type == tokenize.NEWLINE:
            drop_newline = False
            continue
        drop_newline = False
        # INDENT/DEDENT carry the literal whitespace; only their presence matters.
        out.append((tok.type, "" if tok.type in (tokenize.INDENT, tokenize.DEDENT) else tok.string))
    return out


def comment_count(src):
    try:
        return sum(
            1 for t in tokenize.tokenize(io.BytesIO(src).readline) if t.type == tokenize.COMMENT
        )
    except (tokenize.TokenError, SyntaxError, IndentationError):
        return -1


before_path, after_path = sys.argv[1], sys.argv[2]
before_src, after_src = read(before_path), read(after_path)

try:
    after_sig = ast_signature(after_src, after_path)
    after_toks = token_signature(after_src, after_path)
except SyntaxError as exc:
    # The edit broke the file. The classic cause is deleting a docstring that was
    # the sole statement in a def/class body, leaving an empty suite.
    print(f"UNSAFE: {after_path} no longer parses: {exc}", file=sys.stderr)
    sys.exit(1)
except tokenize.TokenError as exc:
    print(f"UNVERIFIED: {after_path} could not be tokenized: {exc}", file=sys.stderr)
    sys.exit(2)

try:
    before_sig = ast_signature(before_src, before_path)
    before_toks = token_signature(before_src, before_path)
except (SyntaxError, tokenize.TokenError) as exc:
    print(f"UNVERIFIED: original did not parse, nothing to compare: {exc}", file=sys.stderr)
    sys.exit(2)

if before_sig != after_sig:
    print("UNSAFE: the abstract syntax tree changed -- this edit touched code, not just comments.",
          file=sys.stderr)
    sys.exit(1)

if before_toks != after_toks:
    for i, (b, a) in enumerate(zip(before_toks, after_toks)):
        if b != a:
            print(f"UNSAFE: token {i} changed, {b[1]!r} -> {a[1]!r} -- this edit touched code "
                  "(the AST normalized it away, the token stream did not).", file=sys.stderr)
            break
    else:
        print(f"UNSAFE: token count changed, {len(before_toks)} -> {len(after_toks)} -- "
              "this edit touched code.", file=sys.stderr)
    sys.exit(1)

# An empty docstring is a real hazard rather than a cosmetic one: ruff's D419 is
# on by default even in a repo with no docstring configuration at all, so a
# blanked-out docstring fails lint where a fully removed one would not.
for node in ast.walk(ast.parse(after_src, filename=after_path)):
    if not isinstance(node, DOC_OWNERS):
        continue
    doc = ast.get_docstring(node, clean=False)
    if doc is not None and not doc.strip():
        name = getattr(node, "name", "<module>")
        print(f"UNSAFE: empty docstring left on {name!r} (ruff D419 is enabled by default).",
              file=sys.stderr)
        sys.exit(1)

before_n, after_n = comment_count(before_src), comment_count(after_src)
delta = "" if -1 in (before_n, after_n) else f" comments {before_n} -> {after_n},"
print(f"VERIFIED: code identical,{delta} docstrings may differ.")
PY
    exit $?
    ;;
esac

# --- Non-Python: strip comments from both sides and require an identical body --
# cloc knows the comment syntax of ~200 languages, which is the whole reason to
# shell out rather than hand-roll a stripper per language.
#
# The pin is deliberate and counter-intuitive: on npm, the plain `cloc` versions
# are a stale wrapper (`cloc@2.10` ships upstream 1.94), while the `-cloc`-suffixed
# line is the genuine redistribution (`cloc@2.6.0-cloc` ships upstream 2.06).
# Verify with `npx --yes cloc@<v> --version` before changing it.
if ! command -v npx >/dev/null 2>&1; then
    echo "UNVERIFIED: no Python AST path for '$AFTER' and npx is unavailable." >&2
    exit 2
fi

work=$(mktemp -d) || { echo "UNVERIFIED: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
ext=${AFTER##*.}
cp "$BEFORE" "$work/before.$ext"
cp "$AFTER" "$work/after.$ext"

if ! npx --yes cloc@2.6.0-cloc --strip-comments=nc --original-dir --quiet \
        "$work/before.$ext" "$work/after.$ext" >/dev/null 2>&1; then
    echo "UNVERIFIED: cloc could not strip comments from '$AFTER'." >&2
    exit 2
fi
if [[ ! -f $work/before.$ext.nc || ! -f $work/after.$ext.nc ]]; then
    echo "UNVERIFIED: cloc does not recognise the '$ext' language." >&2
    exit 2
fi

if diff -q "$work/before.$ext.nc" "$work/after.$ext.nc" >/dev/null; then
    # Necessary, not sufficient -- see LIMIT OF PROOF in the header.
    echo "VERIFIED: comment-stripped bodies are byte-identical."
    exit 0
fi
echo "UNSAFE: code differs once comments are stripped:" >&2
diff -u "$work/before.$ext.nc" "$work/after.$ext.nc" | head -40 >&2
exit 1
