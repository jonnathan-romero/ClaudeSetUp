---
name: comment-cleanup
description: Strip redundant comments and docstrings from a specified source file and re-add only minimal, succinct ones where they earn their place. ALWAYS trigger when the user says "clean up the comments", "remove redundant comments", "tidy the docstrings", "the comments here are noise / too verbose", "minimize the comments", "declutter this file's comments", "rewrite the docstrings to be concise", or names a file and asks to fix/trim/thin its comments. Reads the file plus one or two hops of surrounding code to judge what is self-evident, preserves functional directives (shebangs, lint and type-checker pragmas like `# noqa`, license headers, runtime-load-bearing docstrings), and changes comments only — never code. Do NOT use to write new API docs or a README from scratch, for general code review / bug-hunting (use code-review), or to edit prose/markdown.
argument-hint: "Path to the file whose comments to clean up"
---

Clean up the comments and docstrings in the file the user names (`$ARGUMENTS`). Work on that **one file** only; read around it but edit nothing else.

**Mental model:** every explanatory comment and docstring is guilty until proven necessary. Evaluate each from scratch and default to removing it, then add back only the minimal set that earns its place. But this is a judgment pass, not a blind strip — the guardrails below are non-negotiable, because a naive "delete all comments" corrupts files.

## Never delete these (functional, not documentation)

Removing any of these changes behavior, tooling, or legal standing. Carry them through untouched:

- **Shebangs** (`#!/usr/bin/env python`) and **encoding declarations** (`# -*- coding: utf-8 -*-`).
- **Tool directives:** `# noqa`, `# type: ignore`, `# pragma: no cover`, `# pylint: disable=`, `# mypy:`, `# fmt: off` / `# fmt: on`, `# ruff: noqa`; and in other languages `// eslint-disable`, `// @ts-ignore`, `// prettier-ignore`, `//go:generate` / `//go:embed` (no space — a compiler directive), `#pragma`, `// nolint`.
- **License / copyright headers** — legally load-bearing; keep unless the user says to remove them.
- **Runtime-load-bearing docstrings** — ones the program actually reads: `doctest` examples, `argparse`/`click`/Typer help pulled from docstrings, FastAPI/pydantic field or endpoint descriptions, anything introspected via `__doc__`. Removing these is a code change, not a cleanup.
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

- Confirm the file still parses / imports (e.g. `python -m py_compile <file>`, or the language's equivalent).
- Prove code is untouched: for Python, parse before and after, strip docstring nodes from both, and compare the ASTs — comments never enter the AST, so equal ASTs (modulo docstrings) proves the only changes are comments and docstrings. Use the analogous check in other languages, or read the diff and confirm every hunk is a comment/docstring.
- If the file has doctests or its docstrings feed `--help`/introspection, re-run those — a removed docstring there *is* a behavior change.

Then show the diff and report what was removed, rewritten, and deliberately kept.
