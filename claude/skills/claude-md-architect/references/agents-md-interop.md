# AGENTS.md interop


`AGENTS.md` is an open standard (Linux Foundation, 60K+ repos as of
2026) parallel to CLAUDE.md. Codex, Cursor, GitHub Copilot, Windsurf,
Gemini CLI, Aider, and Zed read it natively. Claude Code does not (as
of 2026-05-02; tracking issue:
https://github.com/anthropics/claude-code/issues/6235).

## When this matters

If the project uses Claude Code AND any other AI coding tool, you
have two options:

1. **Maintain both files.** Drift is inevitable; instructions diverge.
2. **Symlink.** One source of truth.

The symlink pattern wins. Don't dual-maintain.

## The symlink pattern

```bash
mv CLAUDE.md AGENTS.md
ln -s AGENTS.md CLAUDE.md
```

Now editing either edits both. Commit the symlink — git tracks it as a
symlink, not a duplicate file.

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
- The `agentskills.io` open standard may add fields CLAUDE.md doesn't
  use; document what's intentional.

## References

- https://agentskills.io
- https://developers.openai.com/codex/guides/agents-md
- https://github.com/anthropics/claude-code/issues/6235
