---
name: vibe-issues
description: Breaks a published PRD or plan into independently-grabbable vertical-slice issues on the project's issue tracker — each issue cuts through ALL layers (schema + API + UI + tests) end-to-end, not horizontal layers. Tags issues HITL or AFK, publishes in dependency order with the `needs-triage` label. ALWAYS trigger when the user has a PRD or plan ready to decompose into implementation issues, says "break this into issues", "create the issues for this PRD", "split this into vertical slices", "turn this into tickets", or references a published PRD by issue number for slicing. Do NOT use to write the PRD itself — that's `vibe-prd`. Do NOT use to move existing issues through the triage state machine — that's `vibe-issue-triage`.
allowed-tools: Bash(gh issue create:*)
---

# vibe-issues

Decomposes a published PRD or plan into independently-grabbable vertical-slice issues on the project's issue tracker. The step that comes after `vibe-prd` (which writes the parent PRD) and before `vibe-issue-triage` (which moves issues through the triage state machine).

## What you produce

A set of issues, each one a thin **vertical slice** — a path that cuts through every layer end-to-end (schema, models, API, UI, tests), not a horizontal slice of one layer. A completed slice is independently demoable.

```
WRONG (horizontal):                  RIGHT (vertical):
  Issue 1: schema migrations           Issue 1: user submits one report
  Issue 2: models                      Issue 2: user edits that report
  Issue 3: API endpoints               Issue 3: user deletes that report
  Issue 4: UI                          (each cuts through schema + model
  Issue 5: tests                        + endpoint + UI + tests)
```

## Vertical slice rules

- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones

## HITL vs AFK tagging

Each issue is tagged either:

- **HITL (Human-In-The-Loop)** — needs a person for an architectural decision, design review, or judgment call
- **AFK (Away-From-Keyboard)** — fully specifiable; an agent can pick it up and merge unattended

Prefer AFK where possible.

## Process

### 1. Gather context

If the user passes an issue reference (`#42`), fetch it using the conventions in `docs/agents/issue-tracker.md`. Otherwise, use the conversation context.

If **all** of `CONTEXT.md`/`CONTEXT-MAP.md`, `docs/adr/`, AND `docs/agents/` are absent, mention that running `/vibe-init` would set up the framework, then offer to proceed regardless.

### 2. Explore the codebase (optional)

Use the project's domain glossary (`CONTEXT.md`) and respect existing ADRs. Use the glossary's vocabulary in slice titles and descriptions.

### 3. Draft vertical slices

Decompose the work into thin vertical slices. Apply the slice rules above. For each slice, decide HITL vs AFK.

### 4. Quiz the user

Present the slices as a numbered list. For each slice, show:

- Title
- Type: HITL or AFK
- Blocked by (other slices, by their position in the list)
- User stories from the PRD this slice covers (this is **quiz metadata only** — it does not go into the published issue body)

Ask the user:

- Is the granularity right?
- Are the dependencies correct?
- Should any be merged or split?
- Are the HITL/AFK tags right?

Iterate until approved.

### 5. Publish in dependency order

Publish slices that block others **first**, so the blocking issue numbers exist when downstream slices reference them in their `Blocked by` sections.

For each issue:

- Use the issue body template below
- Apply the `needs-triage` label using the string from `docs/agents/triage-labels.md`
- Use the conventions from `docs/agents/issue-tracker.md`

**Do NOT close or modify the parent issue (the PRD).** It stays as the umbrella reference.

## Issue body template

```markdown
## Parent
A reference to the parent issue (if any). Omit this section entirely if there is no parent.

## What to build
A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

## Acceptance criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by
- A reference to the blocking ticket
Or "None — can start immediately" if no blockers.
```
