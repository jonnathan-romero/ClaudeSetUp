# vibe-issues

A Claude Code skill that decomposes a published PRD into independently-grabbable vertical-slice issues on the project's issue tracker. Sits between `vibe-prd` (writes the parent PRD) and `vibe-issue-triage` (moves issues through the triage state machine).

Slash command: `/vibe-issues`. Auto-triggers on slicing phrases (see frontmatter).

## Dates

- **Created:** 2026-05-03

## Source

Adapted from Matt Pocock's `to-issues` (https://github.com/mattpocock/skills).

The body — vertical-slice rules, HITL/AFK tagging, the 5-step process, the issue template, the "do not close or modify the parent" rule — is **full parity with Pocock**.

The single substantive deviation:

1. **Sharpened description with negative triggers.** Our skill ecosystem is denser than Pocock's repo (we have `vibe-prd`, `vibe-issues`, and `vibe-issue-triage` with overlapping potential triggers). Without explicit `Do NOT use for…` routing, Claude picks one essentially at random. Pocock's repo doesn't have this density problem.

Other small adjustments are forced by the framework rename (`/vibe-init` instead of `/setup-matt-pocock-skills`) and clarifications that don't change behavior:

- The `Parent` section is marked **explicitly optional** in the template. Pocock's "(omit otherwise)" was already optional; just clearer phrasing.
- The "user stories covered" item in the quiz is annotated as **quiz metadata only** — it doesn't go into the published issue body. Pocock implies this (his template has no user-stories field); we make it explicit.

What we deliberately did NOT add (after a debate pass):

- No `Category` (bug/enhancement) field or label at publish — categorization is `vibe-issue-triage`'s job, and the category labels aren't in `docs/agents/triage-labels.md`'s mapping anyway
- No per-issue `Out of scope` field — PRD owns global scope, drift risk
- No `Key interfaces` field — interfaces belong in the PRD's Implementation Decisions
- No asymmetric AFK/HITL acceptance-criteria rule — the falsifiability rule belongs at `vibe-issue-triage`'s Agent Brief layer
- No horizontal-slice carve-outs — Pocock's strictness is the feature
- No idempotency-on-re-run detection — adds complexity for a rare case

## Files

- `SKILL.md` — main skill instructions, including the issue template inline (parity with Pocock)
