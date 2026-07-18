---
name: rolling-plan
description: Progressive (rolling-wave) planning across sessions — maintain a `.plan/` folder of a master plan plus numbered child plans whose steps each fit one session under ~150K tokens, deferring decisions to the last responsible moment. COLD START (no plan yet) — activate ONLY on an explicit request to plan ("make a plan to build X across sessions", "plan out this repo", "start a rolling plan", "/rolling-plan"). ONGOING — when a plan already exists, or the conversation references a `.plan/` file, a plan step, plan status, or asks to "split that step", "promote that step to its own plan", or "what's next in the plan", stay engaged and keep plan files current. Do NOT self-start planning the user did not ask for; do NOT use for a single-session task with no unknowns; do NOT use for native plan mode (Shift+Tab); do NOT use for fully-specified autonomous agent briefs (this skill is human-in-the-loop); do NOT use for session handoffs (use the handoff skill); do NOT use to reconcile a whole multi-plan effort — cross-plan contradictions, assumptions that hardened into decisions, plan-vs-code drift, re-confirming intent across all plans (use the realign-plan skill).
---

# rolling-plan

Maintain a durable, file-based plan that survives context resets. The plan lives on disk in `.plan/`; the context window is volatile, the filesystem is not. Anything that must outlast this session gets written to a plan file.

Plan at two resolutions: **detail the near term, keep the far term coarse**, and make decisions concrete only as the work reaches them (the last responsible moment). The plan is a stripped-down spine with suggestions, not a fully-specified blueprint — over-specifying early imputes the first session's guesses onto work it cannot yet understand. The guiding principle is that we only know the full specifications after finishing all prior steps in a plan, only then do we have the full picture.

**Write plan files terse.** Short, complete sentences; every line earns its place. The plan is working memory scanned on resume, not prose to read — supporting detail belongs in linked files (e.g. `.research/`), not in the plan itself. Compacting history that has already accreted across the whole effort is [`realign-plan`](../realign-plan/SKILL.md)'s periodic job; the discipline here is to write tight in the first place so less accretes.

This skill is **human-in-the-loop** first. It advises, sizes, and proposes; the user decides. It is not for producing a fully-specified, decide-everything-up-front brief for an autonomous agent to execute alone — that is a different kind of plan, and it has its own skill: [`agent-brief`](../agent-brief/SKILL.md). When a step is understood well enough to specify fully, **offload** it to an autonomous agent rather than work it in-session (see the `offload` operation below).

## When this skill is and isn't active

- **Cold start (no `.plan/` exists):** activate **only** when the user explicitly asks to plan. Never decide unprompted that a task "looks big" and start planning.
- **A `.plan/` already exists:** stay engaged while working against it — keep step status current, write step summaries, and watch for split/promote signals — without being re-invoked each turn. (Triggering is matched against the conversation, not the filesystem, so this engages when the conversation references the plan — a plan file, a step, plan status, or a split/promote request. If you know a `.plan/` exists but it hasn't come up, mention it to bring it into scope.)
- **Skip planning entirely** when the work fits one focused session and has no real unknowns. There is nothing to survive a reset and nothing to defer, so a plan is just ceremony. If the user invoked the skill anyway, plan — invocation is their signal.

## The four tiers (vocabulary)

| Tier | What it is | Lives as | Invariant |
|------|------------|----------|-----------|
| **master-plan** | the whole multi-plan effort | `.plan/00-master-plan.md` | one north-star goal; **never contains steps** |
| **plan** (child) | one major chunk | `.plan/NN-name-plan.md` | one file (or one folder once it needs scratch) |
| **phase** | a group of steps within a plan | `## / ###` heading inside the plan | optional |
| **step** | **one session of work (under ~150K tokens)** | a checklist item | **always one session — if it isn't, it was misclassified** |

A step is either **build** (produces code/artifacts) or **research** (produces a decision or finding; may throw away any code). The step invariant is load-bearing: every other tier is just grouping, but a step must equal one session. When it doesn't, **split** or **promote** it (see below) — never invent a sub-step tier.

## `.plan/` layout

```
.plan/
  00-interview.md       # durable record of the planning interview (the full "why")
  00-master-plan.md     # only when >1 plan exists or is clearly coming
  01-scaffold-plan.md   # flat child plan (default)
  02-data-layer-plan/   # promoted to a folder once it needed scratch
    02-data-layer-plan.md  # SAME filename, now inside the folder
    notes.md
    spike-results.md
```

- Child plans are numbered `NN-name-plan.md`. Numbering gives free ordering; `ls .plan/` shows the tier at a glance.
- A child stays a **flat file** by default. Promote it to a **folder** `NN-name/` only when it needs scratch/notes — the plan file keeps its exact name inside the folder.
- **Handoffs, research, and agent briefs are NOT stored in `.plan/`.** They reuse existing conventions: handoffs → `.handoffs/` (owned by the `handoff` skill), research → `.research/`, agent briefs → `.briefs/` (owned by the `agent-brief` skill). Plan files link to them by relative path (e.g. `../.research/02-auth-options.md`, `../.briefs/02-data-layer.md`).
- `.plan/` is **local working memory, git-ignored.** If the project is a git repo and `.plan/` is not already ignored, add `.plan/` to `.gitignore` (whole folder).

```bash
if git rev-parse --git-dir >/dev/null 2>&1; then
  grep -qsF '.plan/' .gitignore 2>/dev/null || echo '.plan/' >> .gitignore
fi
```

## When to create the master plan

Create `00-master-plan.md` only when there is **more than one child plan**, OR when multiple plans are clearly coming (e.g. "build this whole repo" — scaffold the master up front so you don't write plan 01, immediately split, then retro-create a master). A lone, self-contained effort is just `01-name-plan.md` with no master.

## Operations

The skill is description-triggered: these "verbs" are matched from natural language, not typed as sub-commands.

### init — start a plan

1. **Interview first (unless already covered).** Before writing the first plan or master plan, run the planning interview in [`references/interview.md`](references/interview.md) — a relentless, grill-me-style interrogation (one question at a time, recommend an answer, follow the branches, push back on vagueness), scaled to the effort. Then capture **only what the near-term needs** into the plan; defer the rest. **Skip the interview** when the conversation has already surfaced the goal/scope/decisions, or when the user handed you a concrete plan/spec and told you what to do.
2. Decide tier (see "When to create the master plan").
3. **Add `.plan/` to `.gitignore` first** (before writing any plan file, so it never shows up as untracked). If a repo. This is a write-through — no diff, just the `grep -qsF` guard above.
4. **Save the interview findings to `.plan/00-interview.md`** — the full shared understanding at the beginning of the process, including the deferred and far-term material that won't go in the plan yet (use the interview reference). Skip if no interview was run (the user gave a ready spec) — but if the effort is more than one chunk, still capture a one-paragraph chunk-map (the rough arc) and any known seams into the plan before detailing step 1, so the rolling wave keeps a spine and doesn't become "never plan the arc."
5. Write the plan file(s) from the templates in [`references/templates.md`](references/templates.md), through the diff review (below) — capturing only what the near-term needs.

### next — work the next step

1. Identify the in-progress / next step in the active plan.
2. Do the work (build or research) with user in the loop or if the next step has an agent-brief see offload instructions below.
3. **Flip a step to done only after its Goal's completion check actually holds** — for a build step, that means verified (tests pass / the behavior works), not merely written. Then **fill in the step's `Outcome` sub-line** (what it actually produced and any divergence from its Goal — usually a line or two, longer only if needed).
4. For a **research** step, the conclusion lives in the step's `Outcome` line. Also write the supporting detail to `.research/NN-*.md` and link it from `Outcome` — **never skip the file writing**. Capture the conclusion in the plan **before** moving on; an unwritten finding evaporates at the next reset. If the finding is a cross-cutting choice, also record it in `Decisions Made` — with its `Source` (`confirmed` / `research-Outcome` / `assumed`), so a later `realign-plan` pass can tell a real decision from a hardened assumption.
5. If a research step changed what later steps should be, **re-plan the affected downstream steps** (only when it actually makes sense — not a forced ceremony).

### offload — hand a step to an autonomous agent

When a step is understood well enough to specify fully, offload it to an autonomous agent instead of working it in-session. This is the seam to the [`agent-brief`](../agent-brief/SKILL.md) skill.

1. **Hand off to `agent-brief`'s `offload`** — it expands the coarse step into a full brief, drawing the "why" from `.plan/00-interview.md` and locked choices from `Decisions Made`, and writes it to `.briefs/NN-step.md` (through its own diff review). Interview only fills the gaps those don't already settle — chiefly the machine-checkable acceptance criteria, since a step's `Goal` is intentionally looser than a runnable gate.
2. **Link and mark** — add `Brief: ../.briefs/NN-step.md` to the step and set it in-progress.
3. **Write-back is reviewer-gated.** The agent runs builder → independent reviewer. Only after the reviewer passes the brief's acceptance criteria does the agent flip the step `[x]` and fill its `Outcome`; on failure it stops and logs to `.briefs/NN-step-result.md`, leaving the step for the user. This is the one sanctioned exception to "a human diff-reviews substantive plan edits" — gated by an independent reviewer, not unattended self-certification — so a resuming `status` reads a trustworthy result.

`.briefs/` is owned by `agent-brief` and git-ignored like `.plan/`. (When a brief should be a durable, shareable record instead of local scratch, `agent-brief` can push it as a GitHub issue and link the step to the issue URL rather than a local file.)

### split / promote — a step that won't fit one session

When a step is accreting sub-tasks, has been in-progress past its one session, or research revealed hidden scope, **propose** the fix and let the user confirm (they may also trigger it directly). Decide which by: **fits in one session after splitting → SPLIT; needs its own phases/seams/multiple sessions → PROMOTE.** Full mechanics and worked examples in [`references/operations.md`](references/operations.md).

- **SPLIT** — same plan. `Step 4` → `Step 4a`, `4b` (letter-suffix so later steps don't renumber). The finished part is marked done; the remainder continues.
- **PROMOTE** — lift the step into its own new child plan. Number it **one greater than the highest existing `NN` in `.plan/`** (`ls .plan/` first — numbers are unique IDs, not execution order, so the new plan may land out of arc; record the real order in the master Plans table). Mark the old step resolved with a pointer — `- [x] Step 4 → promoted to Plan NN` (counts as resolved, not pending, for status) — and **create `00-master-plan.md` if it doesn't yet exist** (you now provably have >1 plan), adding a row to its Plans table.

### status — orient

Report where things stand, at the right altitude:

- **Lone plan (no master):** read the active child plan and report its phase/step position.
- **Part of a master plan:** read `00-master-plan.md`'s Plans table first, then orient the active plan **within the whole arc** — not just in isolation:
  - **Upstream (done/in-progress) plans** that the active plan **consumes**: what they delivered and the seams they hand over. The current work builds on those, so surface anything already-decided that constrains it.
  - **The active plan:** its phase/step position and next step.
  - **Downstream (not-started) plans** that **consume** the active plan, when relevant: so current decisions don't foreclose what's coming (check the master's Seams Between Plans). Pull in upstream/downstream detail only when it bears on the current work — don't recite the whole tree for its own sake.

**Resuming after a context reset** is this operation's big job: when a `.plan/` exists and the user is picking the work back up, run `status` to re-orient in the durable plan + read `.plan/00-interview.md` if you need the "why" behind it (deferred decisions, far-term context, assumptions). (The `handoff` skill covers the **volatile conversation** — uncommitted reasoning, what was mid-edit — by snapshotting it at session end; the plan files themselves are re-read here. If a recent handoff exists, read it first for that conversation context, then run `status`.)

On resume, treat the Goals of **not-yet-executed** steps as provisional — guesses to re-confirm against current reality, not settled spec. By this skill's own principle (we only know the full spec after finishing all prior steps), a downstream Goal written earlier may now be stale.

If the effort has accreted many sessions of notes, or you spot cross-plan contradictions or plan-vs-code drift, **suggest a [`realign-plan`](../realign-plan/SKILL.md) pass** (whole-effort reconciliation) rather than reconciling inline here — `status` orients, it doesn't rewrite. realign is also worth offering when a child plan just finished and the next becomes near-term, or after a big arc change.

## Sizing steps

Aim each step at **one focused session, comfortably under context limits** (well under the window — degradation sets in long before it is full). This is advice, not enforcement: flag a step that smells like more than one session and suggest splitting, but the user decides.

## Red flags — don't rationalize past these

The invariants are easy to talk yourself out of. When you catch one of these thoughts, stop and do the disciplined thing instead:

- **"This step is basically one session."** — If it isn't comfortably one session, it's two. **Split or promote it**; don't let it run over.
- **"I'll write the finding up later."** — Later is a fresh context that won't have it. A research step isn't done until its conclusion is **in the plan**.
- **"I'll just decide this now to keep moving."** — If the decision isn't forced yet and you'd be guessing on partial information, **defer it** to the Open Questions section; deciding early on partial information is how plans go wrong. (A one-way door is the exception only when it **blocks downstream work** — pin it early as a Key Bet; otherwise even one-way doors defer to a research/spike at their last responsible moment.)
- **"I'll flesh out all the steps while I'm here."** — Detail the near term; leave the far term coarse. Over-specifying imputes today's guesses onto work you don't understand yet.
- **"It's basically done, I'll mark it complete."** — Flip to done only after the Goal's completion check actually holds (verified, not just written).
- **"I'll start a plan, this task looks big."** — Not on a cold start the user didn't ask to plan. Planning is theirs to invoke.

## Reviewing changes to plan files

**Substantive** plan-file changes go through an editable side-by-side diff so the user stays in control. Write the proposed file content to a temp file (use the **Write tool**, not a bash heredoc — plan files contain backticks, `$`, and ``` fences that a heredoc mangles) and run the bundled script:

```bash
~/.claude/skills/rolling-plan/scripts/review-diff.sh "$dest" "$proposed"
```

It opens `code --wait --diff`, blocks until the user closes the tab, and saves whatever they leave in the right (editable) pane (emptying it cancels). If `code` isn't available it writes `$dest` directly.

On **cancel** (exit 2), don't silently proceed — stop and ask the user what they want different, then re-propose. During a multi-file init, a cancel aborts only that file; report what got written and what didn't rather than leaving a half-built `.plan/` unexplained.

- **Diff-review these (substantive):** creating a child plan, master plan, or `00-interview.md`; split/promote rewrites; writing or changing a Decision; rewriting or re-planning existing step text.
- **Write straight through (trivial), no diff:** flipping a checkbox `[ ]→[x]`, updating the `Current: Phase/Step` line, adding `.plan/` to `.gitignore`, and **filling a step's `Outcome` line on completion** (append-only narration, kept to a line or two — not a rewrite). Diffing every status tick would be pure friction.

## Templates and detail

- [`references/templates.md`](references/templates.md) — the child-plan and master-plan markdown templates, ready to fill in.
- [`references/operations.md`](references/operations.md) — split/promote worked examples, step kinds, and the re-plan-after-research flow.
- [`references/interview.md`](references/interview.md) — the planning interview questions.
