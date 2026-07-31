---
name: comment-cleanup
description: Strip redundant comments and docstrings from a specified source file and re-add only minimal, succinct ones where they earn their place. ALWAYS trigger when the user says "clean up the comments", "remove redundant comments", "tidy the docstrings", "the comments here are noise / too verbose", "minimize the comments", "declutter this file's comments", "rewrite the docstrings to be concise", or names a file and asks to fix/trim/thin its comments. Reads the file plus one or two hops of surrounding code to judge what is self-evident, preserves functional directives (shebangs, lint and type-checker pragmas like `# noqa`, license headers, runtime-load-bearing docstrings), and changes comments only — never code. Do NOT use to write new API docs or a README from scratch, for general code review / bug-hunting (use code-review), or to edit prose/markdown. For a whole repo or many files at once, use the `@comment-janitor` agent instead — this skill is the one-file, watch-the-diff pass.
argument-hint: "Path to the file whose comments to clean up"
---

Clean up the comments and docstrings in the file the user names (`$ARGUMENTS`). Work on that **one file** only; read around it but edit nothing else.

**Mental model:** every explanatory comment and docstring is guilty until proven necessary. Evaluate each from scratch and default to removing it, then add back only the minimal set that earns its place. But this is a judgment pass, not a blind strip — the guardrails below are non-negotiable, because a naive "delete all comments" corrupts files.

## Never delete these (functional, not documentation)

Removing any of these changes behavior, tooling, or legal standing. Carry them through untouched:

- **Shebangs** (`#!/usr/bin/env python`) and **encoding declarations** (`# -*- coding: utf-8 -*-`).
- **Tool directives:** `# noqa`, `# type: ignore`, `# pragma: no cover`, `# pylint: disable=`, `# mypy:`, `# pyright: ignore`, `# fmt: off` / `# fmt: on`, `# ruff: noqa`; and in other languages `// eslint-disable`, `// @ts-ignore`, `// prettier-ignore`, `//go:generate` / `//go:embed` (no space — a compiler directive), `#pragma`, `// nolint`, `// SAFETY:`.
- **`# %%` cell markers and PEP 723 `# /// script` … `# ///` blocks.** These two are the ones that will fool you: both look exactly like a decorative separator, and both are executable configuration. Deleting the PEP 723 block breaks `uv run` on a single-file script; deleting `# %%` destroys the file's cell structure.
- **SQL executable comments and hints:** `/*! … */` (MySQL — it *runs*, and it reads as commented-out code), `/*+ … */` and `--+ …` (optimizer hints, position-sensitive).
- **License / copyright headers** — legally load-bearing; keep unless the user says to remove them.
- **Runtime-load-bearing docstrings** — ones the program actually reads: `doctest` examples, `argparse`/`click`/Typer help pulled from docstrings, FastAPI/pydantic field or endpoint descriptions, anything introspected via `__doc__` or `inspect.getdoc`. Removing these is a code change, not a cleanup. **A docstring containing `>>>` is never deleted** — it is a doctest whether or not this repo runs `--doctest-modules` today.
- **Markdown table blocks inside docstrings** — the schema/sample "peeks" kept on functions returning a dataframe (polars, pandas, Snowpark, any tabular return). Never delete, compress, reflow, or rewrite one; the table says what the columns are, which `-> pl.DataFrame` cannot. Prose elsewhere in the same docstring is still fair game.
- **TODO / FIXME / HACK / XXX** notes, and any comment recording a bug workaround, an issue/spec link, or a non-obvious assumption or invariant.

## The empty-body footgun

In Python, deleting a docstring that is the **sole statement** in a `def` or `class` body produces an empty block → `SyntaxError`. Never strip a sole-statement docstring unless you replace it: either keep a minimal docstring or leave a `pass`. (Module-level docstrings are safe to drop — an empty module is valid.)

## Process

1. **Understand the file.** Read it top to bottom — what it does, its public surface, the existing comments and docstrings.
2. **Read one or two hops of surrounding code**, in service of the keep/drop call and nothing more: the callers/importers upstream and the functions/modules it calls downstream. The point is to judge what a reader already knows from context (drop the comment) versus what is genuinely non-obvious (keep it, or write a tight one). Do not map the whole repo.
3. **Rewrite comments and docstrings only.** Apply the retention rubric below. Touch no code — not logic, not ordering, not the formatting of code lines.
4. **Verify** (see below), then let the user review the diff.

## Retention rubric

Defer to the project's `CLAUDE.md` / `AGENTS.md` for docstring **style** and whether public APIs require docstrings — match the house convention, don't impose a foreign one. (For this user: Google-style docstrings, type hints live on the signature so the docstring never repeats types, comments only for tricky logic / TODOs / assumptions / non-obvious design choices.)

**Keep or write** a comment/docstring when it: explains *why* rather than *what*; records a non-obvious assumption, invariant, or edge case; warns about a footgun; documents a public API contract. Keep it to one or two lines.

**Drop** it when it: restates what the code plainly says; narrates obvious steps; is commented-out code (git already has it); is a decorative separator banner; or is a docstring that merely echoes the signature.

## Verify

The requirement is a **comments-and-docstrings-only diff** — prove you changed nothing else. A syntax check is necessary but not sufficient: a file can still parse after you accidentally delete a line of real code.

Run the shared verifier rather than hand-rolling the check:

```bash
git show "HEAD:<file>" > /tmp/before          # or keep a copy before you edit
~/.claude/skills/_shared/verify_comments_only/verify-comments-only.sh /tmp/before <file>
```

Exit `0` means only comments and docstrings changed. Exit `1` means the edit is unsafe — code
changed, a directive comment was lost, the file stopped parsing, or a docstring was left empty
(`""""""` fails ruff `D419`, which is enabled by default even with no docstring config). Exit `2`
means it could not be proven; treat that as unsafe too. On `1` or `2`, revert and try again.

It compares ASTs with docstrings dropped, which catches a deleted line of real code that a plain
syntax check would miss; then compares a token stream with comments, docstrings and `pass` filtered
out, which catches what an AST normalizes away (`1_000` → `1000`, a collapsed implicit string
concat, a changed quote style); *and* asserts every directive-shaped comment survived
byte-identically — necessary because comments are not AST nodes, so an AST check alone passes while
every comment in the file has been mangled. Outside Python it falls back to `cloc --strip-comments`
diffing.

Two limits worth knowing, because a `0` does not cover them:

- **Outside Python, exit `0` is necessary but not sufficient.** `cloc` lexes a `#`/`//` line inside a heredoc or string as a comment on both sides, so deleting a banner-styled line of *data* compares byte-identical. Never delete a comment-looking line in quoted context; read the enclosing context first.
- If the file has doctests or its docstrings feed `--help`/introspection, re-run those — a removed docstring there *is* a behavior change.

Then show the diff and report what was removed, rewritten, and deliberately kept.
