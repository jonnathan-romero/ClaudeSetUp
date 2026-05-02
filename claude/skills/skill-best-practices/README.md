# skill-best-practices

A Claude Code skill that codifies the quality bar for authoring,
reviewing, and debugging Skills. Pairs with `skill-creator`:
skill-creator runs the build/eval workflow, this skill supplies the
principles, structural conventions, frontmatter reference, and
failure-mode catalog.

## Dates

- **Created:** 2026-05-02
- **Last modified:** 2026-05-02

## Source research

Authoritative URLs:

- Skills spec — https://code.claude.com/docs/en/skills
- Skill authoring best practices — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- Agent Skills overview — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- Plugins reference — https://code.claude.com/docs/en/plugins-reference
- Best practices — https://code.claude.com/docs/en/best-practices
- Hooks — https://code.claude.com/docs/en/hooks
- Debug your config — https://code.claude.com/docs/en/debug-your-config
- Anthropic engineering blog (Skills) — https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Anthropic skills repo — https://github.com/anthropics/skills
- Anthropic plugins repo — https://github.com/anthropics/claude-plugins-official
- Agent Skills standard — https://agentskills.io
- Claude Code JSON Schema — https://github.com/hesreallyhim/claude-code-json-schema

Community write-ups (current as of 2026-05-02):

- "Why Claude Code Skills Don't Trigger" — https://dev.to/lizechengnet/why-claude-code-skills-dont-trigger-and-how-to-fix-them-in-2026-o7h
- "Measuring Claude Code Skill Activation With Sandboxed Evals" — https://scottspence.com/posts/measuring-claude-code-skill-activation-with-sandboxed-evals
- "How to Activate Claude Skills Automatically: 2 Fixes for 95% Activation" — https://dev.to/oluwawunmiadesewa/claude-code-skills-not-triggering-2-fixes-for-100-activation-3b57

Known issues to track:

- anthropics/claude-code#17283 — Skill tool not honoring `context: fork` / `agent:` in some paths
- anthropics/claude-code#25380 — SKILL.md validator rejecting Claude Code-extended frontmatter fields

## Changelog

- **2026-05-02** — initial version. SKILL.md plus five reference
  files (frontmatter, descriptions, anti-patterns, debugging,
  primitives). No bundled scripts; defers eval/lint tooling to
  `skill-creator`.
