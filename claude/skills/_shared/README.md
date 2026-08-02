# `_shared/` — helpers used by more than one skill

Not a skill. There is no `SKILL.md` here, so Claude Code never loads or triggers this
directory; it is a plain folder that `install.sh` mirrors to `~/.claude/skills/_shared/`
along with everything else under `skills/`.

Put something here when **two or more** skills use it. An asset used by exactly one skill
belongs in that skill's own folder.

**One folder per helper**, named after the helper, holding its script plus any files it
needs. Keeps the tree readable as more shared code lands here.

| Folder | Used by | What it does |
|---|---|---|
| `review_diff/` — `review-diff.sh` | `handoff`, `rolling-plan`, `realign-plan`, `agent-brief` | Opens an editable side-by-side diff in VS Code (`code --wait --diff`), blocks until the tab closes, then writes the right (editable) pane to the destination. Emptying the right pane cancels (exit 2). Falls back to a plain write when the `code` CLI is absent. |
| `verify_logging_only/` — `verify-logging-only.sh` (+ `test-verify-logging-only.sh`) | `add-logging`, `@logging-plumber` (agent) | Proves an edit to a **Python** file changed only logging statements. Four channels: (1) **containment** — resolved log statements (receiver bound exactly once at module level to `logging.getLogger`, direct/imported/aliased, never shadowed; `self.logger`, loguru, structlog rejected as unresolvable) are deleted from both ASTs, suites pass-filled, trees compared, proving no non-log statement changed; (2) an **argument gate** on changed logs — walrus, await/yield, comprehensions, subscripts, f-string interpolation, and non-allowlisted calls exit `2` (pure re-levels are exempt: identical argument tuple, no new evaluation risk); (3) a **context-keyed inventory** that catches a log hoisted across a block boundary — a move *within* one suite is invisible by design, pinned as a LIMITATION harness case; (4) **docstring presence** — a log inserted above a docstring is a `+`-only diff that silently sets `__doc__` to `None`. Sanctions `import logging` + a module logger binding as setup, guarded so deleting an import that surviving code references stays UNSAFE. Exit `0` proves **containment, not behaviour** — argument purity is undecidable beyond literals, and tests/alerts/filters that observe logs live outside the file. Exit `0` contained · `1` unsafe, revert · `2` unprovable, revert + queue/hand-review. **Run `./test-verify-logging-only.sh` (35 cases) after any edit to the script.** |
| `verify_comments_only/` — `verify-comments-only.sh` (+ `test-verify-comments-only.sh`) | `comment-cleanup`, `@comment-janitor` (agent) | Proves an edit changed **only** comments and docstrings. Two-part, because either half alone is insufficient: (1) Python ASTs compared with docstring statements **dropped** (not blanked — blanking makes every full docstring *deletion* read as a code change), then a token stream with comments, docstrings and `pass` filtered out, which catches what an AST normalizes away (`1_000`→`1000`, collapsed implicit string concat, quote style); (2) every directive-shaped comment in the original must survive byte-identically and stay on its line where position matters — comments are not AST nodes, so an AST check alone passes while every comment is mangled. Also rejects an empty docstring left behind (ruff `D419` is on by default) and catches whitespace-level directive breakage such as `// go:build`, which silently stops being a build constraint. Falls back to `cloc --strip-comments` diffing outside Python — where exit `0` is **necessary, not sufficient**, since cloc lexes `#`/`//` inside heredocs and strings as comments. By policy it *accepts* an added docstring and a bare `pass` replacing a sole-statement docstring; `@comment-janitor`'s stricter "never add / never touch code" rules are its own prose, not enforced here. Exit `0` verified · `1` unsafe, revert · `2` unprovable, revert. **Run `./test-verify-comments-only.sh` (32 cases) after any edit to the script.** |

Skills reference these by absolute installed path, e.g.:

```bash
~/.claude/skills/_shared/review_diff/review-diff.sh "$dest" "$proposed"
```

Because the path is shared, a change here changes every calling skill — grep for the
file name across `claude/skills/` before editing, and update the table when you add or
remove a helper.
