# agent-best-practices

A Claude Code skill that codifies the quality bar for authoring,
reviewing, and operating Claude Code **subagents** (the `.md` definition
files under `.claude/agents/`). Sibling to `skill-best-practices`: that
skill governs SKILL.md authoring, this one governs subagent definitions —
frontmatter fields, system-prompt structure, tool boundaries, model
choice, and the delegation mechanics that decide whether a subagent is
the right tool at all.

## Dates

- **Created:** 2026-06-12
- **Last modified:** 2026-06-12

## Source research

Built from four research syntheses in this repo's `.research/`
(`subagent_anatomy.md`, `subagent_ideas.md`, `subagent_novel_ideas.md`,
`subagent_operations.md`), which draw on:

Authoritative URLs:

- Create custom subagents — https://code.claude.com/docs/en/sub-agents
- How and when to use subagents — https://claude.com/blog/subagents-in-claude-code
- How we built our multi-agent research system — https://www.anthropic.com/engineering/multi-agent-research-system

Community collections & write-ups (current as of 2026-06-12):

- wshobson/agents (192 agents) — https://github.com/wshobson/agents
- VoltAgent/awesome-claude-code-subagents (154+ agents) — https://github.com/VoltAgent/awesome-claude-code-subagents
- Builder.io — Claude Code Subagents — https://www.builder.io/blog/claude-code-subagents
- ksred — What They Actually Unlock — https://www.ksred.com/claude-code-agents-and-subagents-what-they-actually-unlock/
- Tembo — A 2026 Practical Guide — https://www.tembo.io/blog/claude-code-subagents

Known issues referenced:

- anthropics/claude-code#5688 — proactive directive ignored (auto-delegation unreliable)
- anthropics/claude-code#34645 — parallel worktree `.git/config.lock` contention

## Layout

- `SKILL.md` — quality bar: pre-publish checklist, top mistakes, core
  design principles, frontmatter quick reference, when-not-to-delegate.
- `references/anatomy.md` — dissecting a definition file (description,
  tools, model, system-prompt archetypes, output contracts).
- `references/operations.md` — how subagents behave (model resolution,
  proactive-trigger unreliability, context isolation, no-nesting, hooks,
  parallelization).
- `references/ideas.md` — what's worth building and the
  subagent-vs-skill-vs-hook decision.

## Changelog

- **2026-06-12** — initial version. SKILL.md plus three reference files.
  No bundled scripts; this is a knowledge/quality-gate skill.
