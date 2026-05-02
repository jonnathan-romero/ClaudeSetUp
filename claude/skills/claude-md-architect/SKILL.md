---
name: claude-md-architect
description: Author, audit, or improve CLAUDE.md files, and route new rules to the right Claude Code primitive (CLAUDE.md vs Skill vs hook vs slash command vs subagent). ALWAYS trigger when the user writes/updates/audits/reviews a CLAUDE.md or memory file, mentions `CLAUDE.md` or `claude.md`, asks "should this go in CLAUDE.md", "where should this rule live", or "is this a skill or a hook", or bootstraps Claude Code memory in a new repo. Covers size limits (<200 lines), structure, anti-patterns, security (malicious-CLAUDE.md / CVE-2025-59536 class), AGENTS.md interop, and Python-first language patterns.
allowed-tools: Read, Grep, Glob
---

# claude-md-architect

You help the user write, audit, or improve CLAUDE.md files, and route
new rules to the right Claude Code primitive.

CLAUDE.md is Claude Code's memory file: markdown loaded at session
start to give Claude project- or user-level context. Official spec:
https://code.claude.com/docs/en/memory.md

## Pick a mode

Detect from the user's request:

- **Author** — "write a CLAUDE.md", "init Claude Code memory", "set up CLAUDE.md for this project"
- **Audit** — "review/audit/improve our CLAUDE.md", "is this CLAUDE.md any good"
- **Route** — "should this go in CLAUDE.md", "where should this rule live", "is this a skill or a hook"

If ambiguous, ask the user which mode.

## Author mode

1. Confirm scope: global (`~/.claude/CLAUDE.md`) or project (`./CLAUDE.md`).
2. Read `references/templates.md` for the language-appropriate skeleton (Python first).
3. Read `references/checklist.md` for size/structure rules.
4. Draft a CLAUDE.md under 200 lines. Show the user. Iterate.
5. If the project ships AGENTS.md or might in future, read `references/agents-md-interop.md` and offer the symlink pattern.

## Audit mode

1. Read the target CLAUDE.md (ask for the path if not given). Use `Glob` to find `CLAUDE.md`, `CLAUDE.local.md`, and `.claude/CLAUDE.md` if the user is vague about location.
2. Read `references/checklist.md` and `references/security.md` — both, always.
3. Check, in this order, and report findings by severity:
   - **Blocker** — secrets in file; malicious-CLAUDE.md patterns (CVE class); broken `@` imports; instructions Claude can't possibly follow.
   - **Major** — over 200 lines; internally contradictory rules; vague directives; kitchen-sink content; rules that belong in hooks instead.
   - **Minor** — stylistic drift; redundant rules already in the model's defaults; prose that should be bullets.
4. Output: numbered findings with line refs, then a proposed diff.

## Route mode

1. Ask: what behavior or rule are you trying to capture? Get one sentence.
2. Read `references/decision-tree.md`.
3. Walk the tree out loud. Recommend exactly one of: CLAUDE.md, Skill, slash command, hook, subagent.
4. Give a one-line reason and a concrete next step (the file path or command to run).

## Cross-cutting

- Always cite the official source: https://code.claude.com/docs/en/memory.md
- For language-specific patterns, defer to `references/templates.md`.
- For Python projects, default to the user's globals: `uv`, pytest, type hints on signatures, ruff, Google-style docstrings, `logging` over `print()`.
