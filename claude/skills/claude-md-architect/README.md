# claude-md-architect

A Claude Code skill for authoring, auditing, and improving CLAUDE.md
files — and routing new rules to the right Claude Code primitive
(CLAUDE.md vs Skill vs hook vs slash command vs subagent).

## Dates

- **Created:** 2026-05-02
- **Last modified:** 2026-06-18

## Source research

Authoritative URLs:

- Memory spec — https://code.claude.com/docs/en/memory.md
- Skills spec — https://code.claude.com/docs/en/skills.md
- Best practices — https://code.claude.com/docs/en/best-practices
- Skill authoring — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- AGENTS.md standard — https://agents.md
- Primitive routing (official) — https://code.claude.com/docs/en/features-overview
- Context-window / token costs — https://code.claude.com/docs/en/context-window
- Anthropic skills repo — https://github.com/anthropics/skills
- Awesome CLAUDE.md examples — https://github.com/josix/awesome-claude-md

CVE references (current as of 2026-06-18):

- CVE-2025-59536 — code execution before trust dialog (fixed 1.0.111)
- CVE-2026-21852 — API-key exfil via repo ANTHROPIC_BASE_URL (fixed 2.0.65)
- CVE-2026-33068 — trust-dialog bypass via settings.json (fixed 2.1.53)
- CVE-2026-25725 — hook injection via settings.json (fixed 2.1.2)
- CVE-2025-54794 / CVE-2025-54795 — supply chain via poisoned config

## Changelog

- **2026-06-18** — research refresh (10-agent web study). Corrected the
  precedence model (files concatenate, not override; fixed load order to
  managed→user→project→local), size target (300→200, + MEMORY.md
  distinction), import depth (5→4 hops). Split/expanded CVEs with fix
  versions and added the HTML-comment stripping nuance. Reworked
  AGENTS.md interop (@import recommended; agentskills.io→agents.md;
  native-read list corrected). Added emphasis-dial guidance, auto-memory
  awareness, and the slash-command→skill merge.
- **2026-05-02** — initial version. Three modes (author, audit, route),
  five reference files, no evals.
