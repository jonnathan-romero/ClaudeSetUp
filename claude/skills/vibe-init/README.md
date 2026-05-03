# vibe-init

A Claude Code skill that bootstraps the vibe-* engineering framework in a new repo. Writes a `## Agent skills` block to `CLAUDE.md`/`AGENTS.md`, scaffolds `docs/agents/{issue-tracker,triage-labels,domain}.md`, and drops a `VIBE-README.md` at the repo root.

`disable-model-invocation: true` — slash-command-only (`/vibe-init`). Run once per repo.

## Dates

- **Created:** 2026-05-03

## Source

Adapted from Matt Pocock's `setup-matt-pocock-skills` (https://github.com/mattpocock/skills).

Two intentional deviations from the original:

1. **Issue tracker options** — GitHub + local-markdown only. (Pocock supports GitLab and "Other" freeform prose too.)
2. **`VIBE-README.md`** — added as a repo-root pure-static framework explainer for human contributors and other agents picking up the repo. (Pocock's version doesn't write this.)

Everything else is parity with Pocock's design (3-question flow, one-at-a-time with verbal defaults, CLAUDE.md > AGENTS.md > ask precedence, in-place update of existing `## Agent skills` blocks, no auto-detection of multi-context).

## Files

- `SKILL.md` — main skill instructions
- `assets/issue-tracker-github.md` — seed template for GitHub mode (→ `docs/agents/issue-tracker.md`)
- `assets/issue-tracker-local.md` — seed template for local-markdown mode (→ `docs/agents/issue-tracker.md`)
- `assets/triage-labels.md` — seed template (→ `docs/agents/triage-labels.md`)
- `assets/domain.md` — seed template (→ `docs/agents/domain.md`)
- `assets/vibe-readme-template.md` — pure-static framework explainer (→ `VIBE-README.md` at repo root, copied verbatim)

## Re-running

Re-running overwrites generated files (single pre-write confirmation). Git is the safety net for any customizations the user made — `git diff` to inspect, `git restore` to undo.
