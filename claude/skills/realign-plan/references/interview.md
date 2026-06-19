# Reconciliation Interview

This is **not** a planning interview (that is rolling-plan's `init`). It does not elicit a new plan — it walks an *existing*, drifted plan corpus and reconciles it with the user's current intent and with the code. Run it only after the surface pass (SKILL.md step 2) has produced the bounded item list.

## How to interview

- **One question at a time.** Never batch. Each answer shapes the next.
- **AskUserQuestion** for discrete choices — recommended option first, labelled `(Recommended)`; use option descriptions for the pro/con breakout.
- **Always recommend an answer.** State your read and reasoning; the user confirms or corrects. Don't ask into a void.
- **Push back** on a relabel that contradicts the code or another plan — surface the conflict instead of accepting it silently.
- **Bounded, not exhaustive.** You are walking the four surfaced buckets, never the whole corpus. A confirmed, uncontradicted Decision is not a question.

## Order — highest signal first

Walk the buckets in this order so the long tail never blocks the load-bearing fixes:

### 1. Contradictions

For each contradiction (plan ↔ plan ↔ master ↔ interview), present both sides verbatim with their locations and ask which holds. Resolving one often dissolves several downstream items — do these first. Recommended resolution: the more recent / more grounded side, but say why and let the user overrule.

### 2. Code drift

For each `missing`/`contradicts` row from the drift-check digest, show the recorded claim and the code evidence. **Precedence rule: never auto-resolve.** Ask the user to call it:

- plan was right, code is wrong → record "code change needed" (do **not** rewrite the plan to match the code);
- code is right, plan is stale → rewrite the plan claim;
- both stale → re-open the decision.

Never rewrite a plan into a claim the code contradicts on the user's say-so alone — they may be misremembering; the code evidence is on the table for exactly this.

### 3. Unconfirmed / untraceable

For each item that is `Source: assumed`, or whose stated grounding is a plan/step not yet `done`, present it as: "this reads as settled, but I can't find where it was confirmed — it's grounded in `<plan NN>`, which is still `⬜`." The user **labels** each:

- **confirmed** — they affirm it now → set `Source: confirmed` (and, if it's a cross-cutting choice, keep it in Decisions Made).
- **assumed** — still a working assumption → move it to `Open Questions / Deferred Decisions` (or `00-interview.md`'s Assumptions), out of Decisions Made, with the trigger that will force it.
- **stale** — no longer holds → remove it; if it will tempt a future session, record it in the relevant child's `What Didn't Work` with the reason.

### 4. Stale far-term Goals

For a not-yet-executed step whose Goal upstream work has invalidated, confirm the Goal is stale and either rewrite it or mark it provisional (rolling-plan already treats not-yet-executed Goals as provisional on resume — don't over-specify here).

### 5. Intent re-confirmation

Finally, read back the **north-star goal** and the **scope (in / out)** as they now stand and confirm they still match what the user is building. A goal/scope pivot surfaces here → update `00-master-plan.md` Goal and `00-interview.md` (substantive → diffed). This is the "after the history is cleaned up, is this still your vision?" check.

## Then: opt-in future-step refinement

After the buckets are reconciled, for each not-started coarse stub plan whose `Consumes` seams are all `done`, offer to detail its steps with the user (SKILL.md step 4). Default to leaving it coarse. Detailing is per-plan and opt-in — never a sweep.

## Closing

Confirm the change set with the user, then run the **compaction** pass (SKILL.md step 5 — collapse the Log, tighten prose, slim ✅ done plans, correctness-preserving) and apply everything through the diff review (SKILL.md step 6), Log-first and crash-safe. Every compaction cut is shown in the diff, so the user approves each drop. If the user stops partway, the in-progress Log marker + what-got-written is the resume signal — report it plainly.
