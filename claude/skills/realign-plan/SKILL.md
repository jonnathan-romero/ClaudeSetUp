---
name: realign-plan
description: Reconcile a whole multi-session rolling-plan effort — sweep every `.plan/` file + `.research/` + the actual code to surface cross-plan contradictions, assumptions that hardened into decisions, and plan-vs-code drift, then interview to re-confirm intent, refine now-near-term steps, and compact accreted history — rewriting the plan files in place. ALWAYS trigger when a `.plan/` exists and the user says "realign the plan", "reconcile my plans", "find contradictions between the plans", "the plans have drifted", "plan and code are out of sync", "make the plan history more concise", or "audit the whole plan effort" (/realign-plan); also offer it when resuming an effort with lots of accreted history or after a big arc change. Do NOT use to create or orient/resume/status a plan (use rolling-plan), to rewrite one step's downstream after a single research finding (rolling-plan's re-plan), for session snapshots (handoff), or for autonomous agent briefs (agent-brief). Requires an existing `.plan/`.
argument-hint: "What prompted the realign? (optional)"
---

# realign-plan

Run one **reconciliation pass** over a whole rolling-plan effort, then clean the plan files up in place. As an effort runs across many sessions, each session writes notes, and some of those were *assumptions* that the next session reads as settled *decisions*; plans drift apart, and the written record drifts from what the user actually intends. realign is the deliberate, periodic pass that catches that drift before it compounds — the formalization of a manual "plan cleanup + future-plan review" (the kind a careful user already writes by hand into the master `## Log`).

This is **human-in-the-loop**, like [`rolling-plan`](../rolling-plan/SKILL.md). It surfaces, proposes, and interviews; the user decides every change, through the diff review.

## What realign is — and is NOT

realign does only what the other planning skills don't:

- **NOT `rolling-plan status`** (read-only orient/resume — realign reconciles and rewrites).
- **NOT `rolling-plan re-plan`** (rewrites *one* step's downstream after *one* research finding — realign is whole-effort, cross-plan).
- **NOT `rolling-plan init`/`next`** (create a plan / work a step). realign requires an existing `.plan/`; it never creates one.
- **NOT `handoff`** (volatile session snapshot) or **`agent-brief`** (autonomous contract).

Its two genuinely-new jobs are **cross-plan contradiction detection** and **plan-vs-code drift detection**; around them it does a **bounded** assumption-sort, an **intent re-confirmation**, an **opt-in** refinement of steps that have now become near-term, and a **compaction** pass that restores the conciseness the templates intend (a concise record aligns future sessions better than a verbose one). Where rolling-plan already owns a behavior (re-orienting, reading the interview, the diff-review discipline, the plan templates), realign reuses it rather than re-implementing it.

## When it runs

- **User-invoked** (primary): the trigger phrases above / `/realign-plan`.
- **Suggested at milestones**: when a child plan just finished and the next becomes near-term, after a big arc change, or on resume with lots of accreted history. rolling-plan points here; realign never auto-runs — the user always confirms.

## The corpus

Read inline (these are small markdown — one context holds them): `00-interview.md`, `00-master-plan.md`, every child plan (Decisions Made + their `Source`, Outcomes, Open Questions, What Didn't Work, Goals), and the `.research/` findings the plans link to. For **plan-vs-code drift**, check the `done` steps' claims — mostly inline `Glob`/`Grep`, escalating to one lightweight `Explore` subagent only for claims that need judgment (step 1 below), so the repo dump stays out of realign's context. Do **not** ingest `.handoffs/` or `.briefs/` — handoffs are volatile/regenerated; briefs are reconciled through their own reviewer gate.

## The operation

### 1. Ingest

Read the corpus. Then run the **plan-vs-code drift check**, scoped to **steps marked `done` only** (a `⬜`/in-progress step whose code is absent is not drift — the code *shouldn't* exist yet). Keep it light — most of it is mechanical, no subagent:

1. From the `done` steps, build a short checklist: the concrete artifacts they claim (files, paths, symbols, config keys) and the Decisions whose subject is in the code.
2. **Check those inline with `Glob`/`Grep`** — does the named file/path/symbol exist? Cheap, and it catches the "marked done but the artifact isn't there" class instantly.
3. **Only** for the residual claims that need judgment — "does the code *contradict* a recorded Decision?", not just "does it exist?" — spawn **one lightweight `Explore` subagent** with that short checklist (not a whole-repo map; `codebase-explorer` is too heavy for a verify pass). **Skip the subagent entirely** when the mechanical pass already settled everything.

Record results as a compact table — `| plan | step | claim | verdict (present | missing | contradicts) | evidence |` — and take only that digest into the interview. **If there is no git repo / no code yet** (a plan still all `⬜`), skip the drift leg, say so, and run the plan-only sweep.

### 2. Surface — bounded, not "everything"

Do **not** walk every statement in the corpus — on a large effort that is a hundred-question interview no one finishes. Surface **only** items in these four buckets:

- **Contradictions** — a claim that conflicts with another claim across plan ↔ plan ↔ master ↔ interview.
- **Code drift** — the drift check's `missing`/`contradicts` rows.
- **Unconfirmed / untraceable** — anything whose `Source` is `assumed`, plus the checkable proxy: **a claim whose stated grounding is a plan/step that is not yet `done`.** (Example: a master that calls a pipeline "ratified by the bake-offs" while the bake-off plans are still `⬜` — the grounding hasn't happened, so the claim is an assumption wearing a decision's clothes.) Grep the status glyphs; don't judge by confident tone.
- **Stale far-term Goals** — a not-yet-executed step whose Goal upstream work has since invalidated.

A Decision whose `Source` is `confirmed` or `research-Outcome` **and** that nothing contradicts stays silent. That bound is the whole point — it turns the sort into "review the contested and the unconfirmed," which is the cleanup the user wants, not a re-litigation of everything.

### 3. Interview — reconciliation-shaped

Run the relentless, one-question-at-a-time interview in [`references/interview.md`](references/interview.md). **Contradiction-first** (highest signal), then code drift, then unconfirmed/untraceable (user labels each **confirmed / assumed / stale**), then stale Goals, then a final **intent re-confirmation** of the north-star + scope. House style: recommend an answer to every question; use AskUserQuestion for discrete choices.

**Code-vs-user conflicts are never auto-resolved.** When the drift check says the code does X and the user says intent is Y, present the code evidence and let the user call it; if they choose intent-over-code, record "code change needed" rather than silently rewriting the plan into a claim the code contradicts.

### 4. Reassess future steps — opt-in, rolling-wave-safe

For a not-started plan that is a coarse stub (`Step 1 — plan out this plan`), offer to detail it **only when every plan it `Consumes` (per its Seams) is `done`** — otherwise its steps can't be known yet, and detailing them violates rolling-plan's core principle (detail the near term, leave the far term coarse). Default to leaving it coarse; detail only what the user opts into, drawing on the plan's research pointers.

### 5. Compact — restore conciseness

A concise plan aligns future sessions better than a verbose one, and the templates already ask for it (the master is meant to stay "short," Log entries "one-line") — but conciseness erodes as sessions accrete. Restore it. **Aggressive by default, but correctness-preserving** — apply the conciseness test to every cut:

> **Would a future session lose any load-bearing fact if this text were cut?** A decision, its rationale + `Source`, a one-way-door, a seam, a deferred decision + its trigger, a dead-end (`What Didn't Work`). If yes → keep it. If no (redundant, superseded, or just verbose) → cut it.

What to compact:

- **Master `## Log`** — fold or drop entries whose decision now lives in the durable layer (`Architecture & Key Bets`, `Decisions Made`, the Plans table). A milestone already captured there is redundant in the Log. Keep recent/active milestones and anything not reflected elsewhere.
- **Prose everywhere** — tighten verbose `Architecture & Key Bets`, Decisions, Seams, and Notes wording; split compound bullets only if it aids clarity. Preserve every decision/rationale/provenance/tag.
- **✅ done child plans** — slim to their essentials: Goal, step `Outcome`s, dead-ends, and Seams. Drop step-level in-progress narration (the "how it went" chatter) once the durable Outcome captures what it delivered and any divergence. This is the biggest conciseness lever on a long effort.
- **Resolved Open Questions / stale items** — already removed by the reconciliation sort; don't re-litigate, just don't carry them forward.

Every compaction edit is **substantive → goes through the diff** (step 6), so the user sees and approves each cut. When unsure whether something is load-bearing, **keep it and let the diff decide** — don't guess away signal.

### 6. Rewrite in place

Apply accepted changes (reconciliation from steps 2–4 **and** the compaction from step 5) to the plan files **through the diff review** (below). Inherit rolling-plan's discipline verbatim ([rolling-plan "Reviewing changes to plan files"](../rolling-plan/SKILL.md)): substantive → diff, trivial → write-through. `00-interview.md`, Decisions, and step-text rewrites are **always** substantive → diffed.

Make the pass crash-safe and resumable:

1. **Log-first marker** — before editing, append an in-progress line to the master `## Log`: `realign pass started <date> — N items pending`. This is the resume signal and is itself a substantive (diffed) edit.
2. Apply file edits one at a time through the diff, sequencing so a mid-pass cancel never leaves two files contradicting (edit the master and the child that share a contradiction together, or not at all). On cancel of any single file, **report what got written and what didn't** — don't leave a half-reconciled `.plan/` unexplained.
3. On completion, replace the marker with a one-line summary of what changed (an arc-change summary is substantive → diffed). A **rejected** option that will tempt a future session goes into the relevant child's `What Didn't Work` (co-located where it recurs), not just the Log.

A resumed realign reads the in-progress marker and continues from the pending items.

## Red flags — don't rationalize past these

- **"I'll just surface everything to be safe."** — That is the unusable hundred-question pass. Surface only the four buckets in step 2; a confirmed, uncontradicted Decision is not an interview question.
- **"This reads confident, so it's a decision."** — Tone is not provenance. Check the `Source` and whether its grounding plan/step is actually `done`.
- **"The code is missing, so the plan drifted."** — Only for `done` steps. A `⬜` step with no code is on schedule, not drifted.
- **"I'll detail the later plans while I'm here."** — Only when their `Consumes` seams are all `done`. Otherwise you're imputing today's guesses onto work you don't understand yet.
- **"The user said X, I'll rewrite the plan to X."** — Not when the code says not-X. Surface the conflict; never encode a claim the code contradicts.
- **"I'll re-plan this one drifted step inline."** — A single post-research step rewrite is rolling-plan's `re-plan`. realign is the whole-effort pass; don't duplicate the narrow operation.
- **"Concise means I can summarize this away."** — Compaction is correctness-preserving, not lossy. Never cut a decision, its rationale/`Source`, a one-way-door, a seam, a deferred decision + its trigger, or a dead-end. If you're unsure a line is load-bearing, keep it and let the diff decide.

## Reviewing changes to plan files

Substantive plan-file changes go through the editable side-by-side diff, exactly as in the triad. Write the proposed content to a temp file **with the Write tool** (not a heredoc — plan files contain backticks, `$`, and ``` fences that a heredoc mangles) and run:

```bash
~/.claude/skills/_shared/review_diff/review-diff.sh "$dest" "$proposed"
```

It opens `code --wait --diff`, blocks until the tab closes, saves whatever is in the right (editable) pane (emptying it cancels, exit 2). On cancel, stop and ask what the user wants different — don't push a reconciliation they didn't accept. If `code` isn't available it writes `$dest` directly.

## References

- [`references/interview.md`](references/interview.md) — the reconciliation interview: contradiction-first walk, labeling, code-vs-user precedence, intent re-confirmation.
