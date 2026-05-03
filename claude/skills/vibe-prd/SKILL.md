---
name: vibe-prd
description: Synthesizes the current conversation context into a published PRD on the project's issue tracker — does NOT interview, does NOT grill. Uses the project's `CONTEXT.md` vocabulary throughout, respects existing ADRs, sketches major modules looking for deep modules, then publishes with the `needs-triage` label. ALWAYS trigger when the user has rich conversation context they want crystallized into a tracked PRD, says "turn this into a PRD", "draft a PRD from this", "publish a PRD", "synthesize this into a spec", or wants to formalize a design discussion into a tracked artifact. Do NOT use to interview, grill, or pressure-test a plan — that's `vibe-grill`, `grill-me`, or `process-interviewer`. Do NOT use to break a PRD into vertical-slice implementation issues — that's `vibe-issues`.
allowed-tools: Bash(gh issue create:*)
---

# vibe-prd

Synthesises everything the user has already said into a published PRD on their issue tracker. The thing that comes before `vibe-issues` (which slices the PRD into work) and after `vibe-grill` or any equivalent design conversation.

## Do NOT interview the user — synthesize

This is the load-bearing rule. By the time the user invokes `vibe-prd`, the conversation has the substance. Your job is to **distill** that into the template, not to ask new design questions. If you find yourself wanting to interview, stop and route to `vibe-grill` instead.

The exceptions: you may ask the user (a) which modules need tests written for them and (b) confirm your module sketch matches their expectations. Both are checkpoints on synthesis, not new design.

## Process

### 1. Read the project's setup

Before drafting, learn how this repo is configured:

- **`docs/agents/issue-tracker.md`** — tells you whether to call `gh issue create` (GitHub) or write to `.scratch/<feature-slug>/PRD.md` (local markdown). Required.
- **`docs/agents/triage-labels.md`** — tells you the actual label string for the canonical `needs-triage` role.
- **`docs/agents/domain.md`** if present — vocabulary discipline and ADR-conflict guidance applies to PRDs as well as to consumer skills.

If any of these files don't exist, proceed silently — they'll be created lazily when needed.

### 2. Explore the repo

Use the project's domain glossary (`CONTEXT.md` or per-context `CONTEXT.md` files via `CONTEXT-MAP.md`). Read ADRs in the area being discussed. **Use this vocabulary throughout the PRD** — every domain noun should be a term defined in the glossary, or you're inventing language the project doesn't use.

If your draft contradicts an existing ADR, surface it explicitly:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_

### 3. Sketch the major modules

Identify the modules the work will create or modify. Actively look for **deep modules** — small interfaces hiding lots of behaviour. The deletion test: if you imagine deleting the module, does complexity vanish (it was a pass-through; rethink) or does complexity reappear across N callers (it was earning its keep)?

Then run two checkpoints with the user, **separately**:

1. **Do these modules match your expectations?** Confirm the sketch before going further.
2. **Which of these modules do you want tests written for?** This drives the Testing Decisions section.

### 4. Write the PRD using the format spec

Read [references/PRD-FORMAT.md](references/PRD-FORMAT.md) — it defines the section ordering, what goes in each section, and the strict rules for the `Success Criteria` section (falsifiable + no restating user stories) and `Assumptions & Dependencies` (PRD-specific only + omit if empty).

Show the user a draft. Let them edit before publishing.

### 5. Publish to the issue tracker

Use the conventions from `docs/agents/issue-tracker.md`. Apply the `needs-triage` label using the string from `docs/agents/triage-labels.md`.

## After publishing

Tell the user the issue number (or file path for local-markdown mode) and what comes next: `vibe-issues` will break the PRD into vertical-slice implementation issues. Don't run `vibe-issues` from this skill — let the user invoke it deliberately.
