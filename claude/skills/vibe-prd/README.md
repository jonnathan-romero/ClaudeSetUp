# vibe-prd

A Claude Code skill that synthesizes the current conversation context into a published PRD on the project's issue tracker. The thing that comes after a design conversation (typically `vibe-grill`) and before `vibe-issues` (which breaks the PRD into vertical slices).

Auto-triggers on PRD-synthesis phrases (see frontmatter). Slash command: `/vibe-prd`.

## Dates

- **Created:** 2026-05-03

## Source

Adapted from Matt Pocock's `to-prd` (https://github.com/mattpocock/skills).

Intentional deviations from the original:

1. **Sharpened description** with explicit negative triggers — claims the *synthesis* niche and routes interviewing/grilling to `vibe-grill` / `grill-me` / `process-interviewer`, and slicing to `vibe-issues`.
2. **Explicit "Do NOT interview the user — synthesize" guardrail** at the top of the body. Matt has this; FRAMEWORK_SUMMARY undersold it.
3. **`/vibe-init` suggestion** when the repo is fully green-field for the framework (none of `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/`, or `docs/agents/` exist). Otherwise lazy-create artifacts silently.
4. **Two new template sections (with strict rules to prevent bloat):**
   - **Success Criteria** — falsifiable, feature-level checks (SC-001…SC-N) for the integrated whole. Distinct from per-issue acceptance criteria (which `vibe-issues` produces). Rules: must be testable; must not restate user stories.
   - **Assumptions & Dependencies (omittable)** — PRD-specific external APIs, preconditions, environmental requirements. Rules: PRD-specific only (repo-wide items belong in ADRs/CONTEXT.md/pyproject.toml); omit entirely if nothing PRD-specific.

Everything else is parity with Matt: the synthesize-not-interview rule, the two-step module check (expectations + tests), the `CONTEXT.md` vocabulary discipline throughout, the `needs-triage` label on publish, the no-file-paths/no-code-snippets rule for Implementation Decisions.

## Files

- `SKILL.md` — main skill instructions
- `references/PRD-FORMAT.md` — PRD template + per-section rules (read inline by the skill at write-time)

## Skipped during research

- **Per-story Given-When-Then sub-bullets** — `vibe-issues` produces per-issue acceptance criteria when slicing; PRD-level G-W-T duplicates that and drifts.
- **3-tier Boundaries (Never / Ask-first / Always-safe)** — "ask first" is repo-wide policy, not per-PRD; HITL/AFK tagging in `vibe-issues` already encodes it at the right layer. To address visibility for AFK agents, we'll have `vibe-issue-triage` propagate repo-wide policies into Agent Briefs when we build that skill.
