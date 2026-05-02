# claude-md-architect

A Claude Code skill for authoring, auditing, and improving CLAUDE.md
files — and routing new rules to the right Claude Code primitive
(CLAUDE.md vs Skill vs hook vs slash command vs subagent).

## Dates

- **Created:** 2026-05-02
- **Last modified:** 2026-05-02

## Source research

Authoritative URLs:

- Memory spec — https://code.claude.com/docs/en/memory.md
- Skills spec — https://code.claude.com/docs/en/skills.md
- Best practices — https://code.claude.com/docs/en/best-practices
- Skill authoring — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- AGENTS.md standard — https://agentskills.io
- Anthropic skills repo — https://github.com/anthropics/skills
- Awesome CLAUDE.md examples — https://github.com/josix/awesome-claude-md

CVE references (current as of 2026-05-02):

- CVE-2025-59536 — RCE / API token exfiltration via malicious project files
- CVE-2025-54794 / CVE-2025-54795 — supply chain via poisoned config

## Changelog

- **2026-05-02** — initial version. Three modes (author, audit, route),
  five reference files, no evals.
