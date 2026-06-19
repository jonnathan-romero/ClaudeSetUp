# AGENTS.md interop


`AGENTS.md` is an open standard (stewarded by the Agentic AI Foundation
under the Linux Foundation; 60K+ repos as of 2026) parallel to
CLAUDE.md. Codex (the reference impl), Cursor, and Cline read it
natively; Gemini CLI reads it only if you set `context.fileName`;
Copilot/Windsurf/Aider keep their own files and are listed as
supporters. **Claude Code does NOT read AGENTS.md natively** and has no
settings flag for it (as of 2026-06-18; tracking issue:
https://github.com/anthropics/claude-code/issues/6235). A repo with
*only* AGENTS.md loads zero instructions in Claude Code, silently —
blogs claiming a "fallback read" are wrong.

## When this matters

If the project uses Claude Code AND any other AI coding tool, make
**AGENTS.md the single source of truth** and point CLAUDE.md at it.
Don't dual-maintain — drift is inevitable. Two officially-documented
patterns (https://code.claude.com/docs/en/memory):

## Pattern A — `@AGENTS.md` import (recommended)

```markdown
@AGENTS.md

## Claude Code
<!-- Claude-only additions go here, e.g. plan-mode / path rules -->
```

Claude loads the imported file at session start, then appends the rest.
Works on Windows without admin rights, and lets you add Claude-specific
sections the other tools won't see. (First external import triggers a
one-time approval dialog; imports do not reduce context.)

## Pattern B — symlink (zero divergence, no Claude-only content)

```bash
mv CLAUDE.md AGENTS.md
ln -s AGENTS.md CLAUDE.md
```

Editing either edits both. Commit the symlink — git tracks it as a
symlink, not a duplicate. On Windows this needs Admin/Developer Mode and
`git config core.symlinks true`, so prefer Pattern A there.

Note: `/init` reads an existing AGENTS.md (and `.cursorrules`,
`.windsurfrules`) once at scaffold time — that's a one-time import, not
runtime reading.

## When to skip AGENTS.md entirely

- Solo projects with only Claude Code → keep CLAUDE.md, skip
  AGENTS.md.
- Personal `~/.claude/CLAUDE.md` → no need (other tools have their
  own global file conventions).

## When AGENTS.md should be the source of truth

- Open-source projects expecting contributors using mixed tooling.
- Teams already on Codex / Cursor with new Claude Code adopters.
- Anything aiming for cross-tool portability.

## Watch for

- Claude Code may add native `AGENTS.md` support; if so, drop the
  symlink and use AGENTS.md directly.
- The `agents.md` open standard may add fields CLAUDE.md doesn't
  use; document what's intentional.

## References

- https://agents.md
- https://code.claude.com/docs/en/memory (official AGENTS.md interop section)
- https://developers.openai.com/codex/guides/agents-md
- https://github.com/anthropics/claude-code/issues/6235
