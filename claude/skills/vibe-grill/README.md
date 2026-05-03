# vibe-grill

A Claude Code skill that runs a Socratic plan-interview with **persistent doc side-effects** — stress-tests a design plan against the project's `CONTEXT.md` glossary and existing ADRs, then updates those docs inline as decisions crystallize.

Slash command: `/vibe-grill`. Auto-triggers on plan-grilling phrases (see frontmatter).

## Dates

- **Created:** 2026-05-03

## Source

Adapted from Matt Pocock's `grill-with-docs` (https://github.com/mattpocock/skills).

Intentional deviations from the original:

1. **Sharpened description** with explicit negative triggers — claims the *plan-focused, doc-side-effects* niche and routes open-ended grilling to `grill-me`, fuzzy-idea extraction to `process-interviewer`. Without this, all three skills overlap.
2. **Plain markdown body** — Pocock's original wraps the body in `<what-to-do>` and `<supporting-info>` XML tags; this version uses conventional markdown headings.
3. **Explicit `docs/agents/domain.md` read step** — the skill reads `domain.md` if present so glossary/ADR-conflict guidance applies to producers as well as consumers.
4. **`/vibe-init` suggestion** when the repo is fully green-field for the framework (none of `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/`, or `docs/agents/` exist). Otherwise lazy-creates silently.

Everything else is parity with Pocock: the four during-session moves (challenge glossary / sharpen fuzzy language / concrete scenarios / cross-reference code), the no-batching rule for `CONTEXT.md` updates, the three-criteria ADR gate, and the lazy-create policy for `CONTEXT.md` and `docs/adr/`.

## Files

- `SKILL.md` — main skill instructions
- `references/CONTEXT-FORMAT.md` — format spec for `CONTEXT.md` (read inline by the skill when updating)
- `references/ADR-FORMAT.md` — format spec for ADRs (read inline by the skill when offering an ADR)
