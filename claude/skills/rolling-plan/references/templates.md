# Plan Templates

Fill these in and write through the diff-review script (substantive edits). Keep them lean — unused sections should be dropped, not left empty.

## Contents

- [Child plan — `NN-name-plan.md`](#child-plan)
- [Master plan — `00-master-plan.md`](#master-plan)
- [Interview findings — `00-interview.md`](#interview-findings)

---

## Child plan

`NN-name-plan.md`. The everyday working file. **Seams** appears only when a master plan exists (i.e. a multi-plan effort). **Phases** are optional — a small plan is just a flat step list.

```markdown
# Plan NN: <name>

## Goal
<One sentence — what this child plan delivers. Local north star.>

## Status
<not-started | in-progress | done> · Current: Phase 2 / Step 3

## Seams                          <!-- only when a master plan exists -->
- Consumes: <what upstream plans hand this one — file, signature, data shape>
- Produces: <what this plan hands downstream>

## Phases & Steps                 <!-- Phases optional; a flat step list is fine -->
### Phase 1: <name>
- [x] Step 1 — <what this step is for, in a phrase> · kind: build · done
    Goal: <what done looks like — the outcome / how you'll know it's complete.
          Color on intent, not a dictated to-do list; leave the how open.>
    Outcome: <written when finished — what it actually produced, and any way it
             diverged from the Goal. Succinct: usually a line or two, expand if
             the result genuinely needs it.>
- [ ] Step 2 — <what this step is for> · kind: research · in-progress
    Needs: Step 1                 <!-- optional; only when not obvious from order -->
    Goal: <the question to answer / decision to reach, and what settles it>
### Phase 2: <name>
- [ ] Step 3 — <what this step is for> · kind: build
    Goal: <what done looks like>  <!-- optional; omit for a self-evident step -->

## Decisions Made
| Decision | Source | Rationale |
|----------|--------|-----------|
| <choice made> | confirmed / research-Outcome / assumed | <why> |
<!-- Source = provenance, so a later realign-plan pass can tell a real decision from a hardened assumption:
     `confirmed` (the user confirmed it) · `research-Outcome` (settled by a research step — link the .research file) ·
     `assumed` (a working assumption, NOT yet confirmed — this is a smell; prefer Open Questions over this table).
     Tag a genuinely irreversible choice: "<choice> (one-way door)". -->

## Open Questions / Deferred Decisions
- <decision deliberately deferred> — defer until <trigger / the point it can't wait (e.g. before/after Step NN)>

## What Didn't Work
| Approach | Why it failed |
|----------|---------------|
| <abandoned approach> | <reason — so it isn't retried> |

## Notes
- Research: ../.research/NN-<topic>.md
- <other links / reminders>
```

Notes on use:
- **Step line format:** `- [ ] Step N — <what it's for> · kind: build|research · <status>`, with up to three optional indented sub-lines, in order:
  - **Needs** — prerequisite step(s)/plan(s); include only when the dependency isn't obvious from ordering or phases.
  - **Goal** — forward: color on the intent and what **done** looks like; not a dictated to-do list, leave the how open. Omit for a self-evident step.
  - **Outcome** — backward: written on completion — what it actually produced and any divergence from the Goal.

  When done, flip the checkbox and fill in Outcome.
- **Keep Outcome (and every line) tight.** Outcome is what accretes most across sessions, so write a clause or two, not a recap:
  - ❌ `Outcome: Implemented the authentication middleware — it validates incoming bearer tokens against the session store, returns a 401 when a token is expired or malformed, logs failed attempts, and is covered by three new unit tests.`
  - ✅ `Outcome: Validates bearer tokens against the session store and returns 401 on expired/malformed tokens. Tests cover the happy path and two failures.`
- **Decisions** records choices already made, each with a `Source` (provenance): `confirmed` / `research-Outcome` / `assumed`. The optional `(one-way door)` tag marks an irreversible one that deserved more deliberation. Reversible choices need no tag. Recording the `Source` is what lets a later `realign-plan` pass catch assumptions that quietly hardened into decisions — an `assumed` row is a flag, not a settled call.
- **Open Questions / Deferred Decisions** is where "defer to the last responsible moment" becomes a written commitment — name the decision and the trigger that forces it. Unconfirmed working assumptions live here (or in `00-interview.md`'s Assumptions), **not** in Decisions Made — a Decision is something actually confirmed or settled by research.
- **What Didn't Work** is the durable, plan-level dead-end record (permanently abandoned approaches for this chunk). These are notes that will be useful across future steps or explain important decisions made in prior steps that affects future steps. Session-level "what just happened" belongs in the handoff.

---

## Master plan

`00-master-plan.md`. The durable, slow-changing layer above the child plans. Keep it **short** — if it grows past a screen or two it is absorbing detail that belongs in a child. It **never contains steps**; if you are tempted to write a step here, a child plan is missing.

```markdown
# Master Plan: <project>

## Goal
<The one north-star goal for the whole effort.>

## Architecture & Key Bets
<The few big, durable, cross-cutting decisions that constrain all child plans, so children
inherit constraints instead of re-deciding. Keep it to the load-bearing ones.>

## Plans
| # | Plan | Status | Delivers |
|---|------|--------|----------|
| 01 | scaffold | ✅ done | project skeleton |
| 02 | data-layer | 🔨 in-progress | models + storage |
| 03 | api | ⬜ not-started | endpoints |

## Seams Between Plans
<The authoritative contract map: what 01 hands 02, what 02 hands 03 — the joints between
chunks. Each child's own Seams section is a local echo of this; if they disagree, this wins.>

## Log
- <date> — <one-line master-level milestone / what changed>
```

Notes on use:
- The **Plans table** is the orienting element — the first thing to read for "where are we." Status glyphs: ⬜ not-started, 🔨 in-progress, ✅ done.
- **Architecture & Key Bets** is the home for one-way-door, cross-cutting decisions only. Resist turning it into a dump — per-plan detail goes in the child.
- **Seams Between Plans** is authoritative over the per-child `Seams` sections.

---

## Interview findings

`00-interview.md`. The durable record of the planning interview — the full shared understanding, especially the parts that **don't** belong in the lean plan yet (far-term unknowns, deferred decisions, assumptions). The plan files draw from this; a resuming session reads it for the "why". Keep it honest about what's still unknown or could change based on future findings — "don't know yet" or "not sure yet" entries are the point.

```markdown
# Planning Interview — <project>

_Captured: <date>_

## Goal
<the north-star, in one sentence>

## Shape / Chunks
<the coarse breakdown into chunks (future plans); note which are near-term vs later>

## Scary Unknowns
- <unknown> — <near-term spike, or deferred until …>

## One-Way-Door Decisions
- <irreversible decision> — <the call made, or what it's waiting on>

## Deferred / Don't-Know-Yet
- <open question> — <the trigger that will force it>

## Out of Scope
- <explicitly not doing>

## Seams (multi-plan)
<contracts between chunks, as understood now>

## Assumptions
- <assumption confirmed in the interview — flag if unvalidated>
```
