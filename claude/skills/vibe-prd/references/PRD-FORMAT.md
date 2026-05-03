# PRD Format

PRDs are published to the issue tracker — a GitHub issue (when `docs/agents/issue-tracker.md` configures GitHub) or a markdown file under `.scratch/<feature-slug>/PRD.md` (when configured for local markdown). The body uses the template below regardless of tracker.

Use this exact section ordering. Sections marked **omittable** can be left out entirely if there's nothing meaningful to put there — don't institutionalize "N/A" filler.

## Template

```markdown
## Problem Statement
The problem the user is facing, from the user's perspective.

## Solution
The solution from the user's perspective.

## User Stories
A LONG, numbered list. Format:

1. As a <actor>, I want <feature>, so that <benefit>

Example: "As a mobile bank customer, I want to see balances on my accounts, so that I can make better-informed decisions about my spending."

This list should be extensive and cover all aspects of the feature.

## Implementation Decisions
A list. Can include:
- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They go stale before the work is picked up. Type signatures and schema shapes are fine — they belong to the spec.

## Testing Decisions
- What makes a good test for this feature (test external behavior, not implementation details)
- Which modules will be tested (from the user's checkpoint in step 3)
- Prior art for the tests (similar tests in the codebase)

## Success Criteria
Falsifiable, feature-level checks for the integrated whole — separate from per-issue acceptance criteria, which `vibe-issues` will produce on each slice. Use measurable IDs (SC-001…SC-N).

Two rules:
- **Must be falsifiable.** If you can't write a test (or run a measurement) that distinguishes "passing" from "failing", don't include it.
- **Must not restate user stories.** Success Criteria capture *emergent properties* of the integrated feature, not the per-user-story intent that "so that…" already encodes.

Example:
- SC-001: A 50-page report exports as a PDF in under 10s at p95
- SC-002: Failed exports retry 3× then surface a user-visible error
- SC-003: All exported PDFs pass WCAG AA contrast

## Assumptions & Dependencies (omittable)
PRD-specific external APIs, preconditions, and environmental requirements that downstream consumers (AFK agents picking up issues weeks later) need for orientation.

Rules:
- **Only PRD-specific items.** If it applies repo-wide (Python version, Postgres version, the standard auth pattern), it belongs in `pyproject.toml`, the repo README, `CONTEXT.md`, or an ADR — not here.
- **Omit the section entirely if nothing PRD-specific exists.** No "N/A" filler.

Example:
**Assumes:**
- User session is already authenticated when reaching this flow
- Cart data fits in memory at this scope (no pagination needed)

**Depends on:**
- Stripe Subscriptions API v2024-04+
- Internal `auth-service` ≥ 2.3.0 (provides the new `verified` claim from ADR-0042)
- Feature flag `pdf_export` exists before this work starts

## Out of Scope
A description of the things that are out of scope for this PRD.

## Further Notes
Any other notes about the feature that don't fit elsewhere.
```
