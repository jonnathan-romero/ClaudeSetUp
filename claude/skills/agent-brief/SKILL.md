---
name: agent-brief
description: Author a self-contained brief that an autonomous builder+reviewer agent pair executes unattended — front-load the unrecoverable decisions, make every acceptance criterion machine-checkable, and hand it off. AUTHOR — activate on an explicit request to brief, offload, or dispatch work to an agent ("write an agent brief", "brief this out for an agent to build", "hand this to an agent", "offload this to a subagent", "open a GitHub issue for an agent to pick up", "/agent-brief"). The brief can be saved locally to `.briefs/` or pushed as a GitHub issue. FROM A ROLLING-PLAN STEP — activate when the conversation asks to "offload this step", "send this step to an agent", or otherwise hand a `.plan/` step to an autonomous agent; expand the coarse step into a full brief in `.briefs/`. Do NOT use for human-in-the-loop planning across sessions (use rolling-plan); do NOT use for session handoffs / continuity snapshots (use handoff); do NOT use to actually run or babysit a long task on a schedule (this skill authors the brief and sets up the offload, it is not a scheduler).
---

# agent-brief

Author a **self-contained brief** that a separate, autonomous **builder + reviewer** pair executes with no human at the keyboard. The brief is a contract: it must resolve up front everything the agent cannot recover from alone, stay lean enough to actually be read, and state acceptance criteria a *different* agent can mechanically verify.

This is the third corner of a set:

| Skill | Role | Human |
|-------|------|-------|
| **rolling-plan** | plan a multi-session effort; defer decisions to the last responsible moment | in the loop at every step |
| **handoff** | snapshot the volatile conversation so a fresh agent resumes | hands off between sessions |
| **agent-brief** (this) | compile a unit of work into a brief an agent builds unattended | front-loads, then steps away |

rolling-plan explicitly refuses this job ("not for fully-specified autonomous agent briefs — this skill is human-in-the-loop"). agent-brief is where that work goes, and it plugs back into rolling-plan at the step level (the `offload` operation below).

## The core philosophy — and its one inversion of rolling-plan

rolling-plan defers decisions because a human resolves them at each step. An autonomous agent has **no human at the decision points.** So the brief inverts rolling-plan's stance for exactly the decisions the agent can't undo: front-load those. But don't over-correct into a 2,000-line spec — large briefs degrade because agents don't read all of them.

The rule, from the research, is **"right altitude"**: front-load the *unrecoverable*, keep the document *lean*. Four non-negotiables fall out of it:

- **Front-load the unrecoverable, keep the doc lean.** One-way-door decisions get decided in the brief. Reversible ones can be delegated to the agent (see Mutability) or left as a runtime choice — don't pre-decide every keystroke.
- **No self-grading.** A builder verifying its own work is self-confirmation, not review. Verification is an **independent reviewer in a fresh context that sees only the diff + the acceptance criteria** — never the builder's reasoning.
- **Every acceptance criterion ends in a runnable gate.** `pytest -k auth` green, `app --health` exits 0, endpoint returns 200 + schema. A criterion the reviewer cannot mechanically check ("auth should work") is theater — it lets anything pass. **This is the load-bearing constraint of the whole skill.**
- **Stop-and-log is the default on surprise.** When a brief assumption turns out false and it's not a checkpoint, the agent halts and writes what it found — it does not barrel through a falsified assumption. (Reversible tool failures it may adapt around; see Mutability.)

## The brief artifact

Lives at `.briefs/NN-name.md` (local) or as a GitHub issue body (see Destinations). Full template in [`references/template.md`](references/template.md). Sections:

| Section | Purpose |
|---------|---------|
| **Objective** | what + **why** (the why is what keeps the agent aligned when the how diverges) |
| **Non-goals** | explicit out-of-scope — where scope creep hides |
| **Context & blast radius** | repo conventions, related files, and the **exact file list** the agent should touch |
| **Acceptance criteria** | numbered `SC-###`, `WHEN/THEN/AND`, measurable, **each ending in a runnable gate** |
| **How to implement** | the elastic section — sub-instructions the agent may expand on within one bounded run |
| **Guardrails** | 3-tier **Always / Ask-first / Never** + stop conditions (max iterations) |
| **Operating Mode + Mutability** | the autonomy dials (below) |
| **`[NEEDS CLARIFICATION: …]`** | anything the interview did not resolve — a brief with open markers is **not ready to offload** |
| **Verification protocol** | reviewer builds a scenario→evidence compliance matrix; evidence required, no self-grading |

## The two dials

**Operating Mode** — how long the agent runs:

- **Converge** *(default; forced for from-step briefs)* — build until the criteria pass, then stop. One bounded session.
- **Continuous** *(standalone briefs only)* — loop until a machine-checkable stopping condition (`score ≥ 90`, `5 iterations no improvement`). Unbounded; never from a single plan step.
- **Supervised** — run autonomously but pause at predefined checkpoints for a human, then continue.

**Mutability** — per locked decision, what the agent may do if it turns out wrong:

- **Locked** — halt and stop-and-log (the safe default for one-way doors).
- **Split** — adapt within the guardrails, log the override, continue (reversible operational fixes).
- **Open** — the agent decides freely (genuinely reversible, low-stakes choices).

## Destinations — where the brief goes

The brief *content* is identical either way; the destination is only **transport**. User chooses at author/offload time; **default is `local`.**

### `local` (default)

Write the brief to `.briefs/NN-name.md` (git-ignored). The `.briefs/` folder is the queue; write-back goes to the plan/result file (see `write-back`). Use for in-repo, in-session offload.

### `github` — push the brief as a GitHub issue

Use when the brief should be a **durable, shareable record other agents (or people) can pick up**, rather than local scratch. Requires `gh` authenticated **and** a repo remote; if either is missing, fall back to `local` and say so.

```bash
# pickup label, created idempotently
gh label create agent-brief --description "Brief for an autonomous agent" 2>/dev/null || true
gh issue create --title "<Objective, one line>" --label agent-brief --body-file "$brief"
```

- The accepted brief markdown is the issue body. Render the **acceptance criteria as a GitHub task list** (`- [ ] SC-001 …`) so progress is visible and tickable.
- **Pickup contract (single label, state via open/closed):** every brief-issue carries the one `agent-brief` label; **open = to-do, closed = done, assignee = claimed.** A pickup process polls `gh issue list --label agent-brief --state open --search "no:assignee"`, self-assigns one, and works it.

**Write-back on the `github` route is via PR** (not the plan file):

- The builder pushes its branch and opens a PR whose body says `Closes #<N>`.
- The independent reviewer's verdict **gates the merge**: PASS → merge (GitHub auto-closes the issue = done); FAIL → `gh pr review --request-changes` with the compliance matrix, leave the issue open. The reviewer gate still holds — no merge without a passing independent review.
- Needs push rights + whatever branch protection / CI you run on the PR.
- For a **rolling-plan step offloaded to an issue**: link the step to the **issue URL** (not a local file); the **PR merge / issue close is the write-back signal** — on merge, flip the step `[x]` and fill `Outcome` from the PR; a failed review leaves the step in-progress.

## Operations

The skill is description-triggered; these verbs are matched from natural language, not typed.

### author — write a standalone brief

1. **Interview** ([`references/interview.md`](references/interview.md)) — relentless, one question at a time, recommend an answer. Its job is to extract a brief whose every acceptance criterion ends in a runnable gate, and to surface every unresolved choice as a `[NEEDS CLARIFICATION]` marker rather than a silent guess.
2. **Draft and review** the brief through the editable diff (below) — the user accepts the contract before it goes anywhere.
3. **Set the dials** — Operating Mode + per-decision Mutability.
4. **Send to a destination** — local `.briefs/NN-name.md` file (default) or a GitHub issue (see Destinations).
5. **Hand off** — see execution model.

### offload — hand a rolling-plan step to an agent

1. **The step is the unit.** A from-step brief is **Converge, one bounded session.** The elasticity lives *inside* the brief's How-to-implement section, not in the run length.
2. **Expand** the coarse step into a full brief, drawing the "why" from `.plan/00-interview.md` and the locked choices from the plan's `Decisions Made`. Run the interview to confirm all previous decisions and for what isn't already settled.
3. **Send to a destination** — write `.briefs/NN-step.md` and link it from the step, **or** push it as a GitHub issue and link the issue URL from the step (see Destinations).
4. **If it won't fit one session** — that is rolling-plan's **PROMOTE** signal, not a license to grow the brief unbounded. Promote the step to its own plan first.
5. **Hand off**, then reconcile via write-back.

### execute — the builder + reviewer model (harness-agnostic)

The brief names roles, not a harness. Run it any of three ways without changing the artifact:

- **Workflow** — builder phase → reviewer phase → loop-until-criteria.
- **Two subagents** — a builder agent and a separate reviewer agent.
- **One fresh session** — reads the brief, builds, spawns its own reviewer subagent.

In all three:

```
brief (.briefs/NN.md)
  ├─ builder  — implements within guardrails; stop-and-log on a falsified assumption
  └─ reviewer — FRESH context, sees only diff + acceptance criteria
        PASS → write-back
        FAIL → stop-and-log to .briefs/NN-result.md (+ handoff), nothing written back
```

### write-back — reconcile an offloaded step (from-step only)

The one sanctioned exception to rolling-plan's "a human diff-reviews substantive plan edits" — and it is **gated, not unattended self-certification**. The mechanism depends on the destination:

- **`local`** — Reviewer PASS → the agent flips the step `[x]` and fills its `Outcome` line. Reviewer FAIL → stop-and-log to `.briefs/NN-result.md` (+ a handoff); the step is left untouched.
- **`github`** — Reviewer PASS gates the merge of the `Closes #N` PR; the merge/issue-close is the signal to flip the step `[x]` and fill `Outcome` from the PR. Reviewer FAIL → `request-changes`, issue stays open, step stays in-progress.

Either way the human sees the result on the next rolling-plan `status`, and the agent never flips a step on its own say-so — an independent reviewer gates it.

## Red flags — don't rationalize past these

- **"This criterion is basically testable."** — If it doesn't end in a command/observation a reviewer can run, it isn't. Rewrite it until it does, or the reviewer is grading on vibes.
- **"The reviewer can peek at the builder's notes to save time."** — No. Fresh context, diff + criteria only. Shared context turns review into self-confirmation.
- **"I'll let the agent pick the architecture."** — Front-load one-way doors. Only genuinely reversible calls get `Mutability: Open`.
- **"This step really needs two sessions, but I'll offload it as one big brief."** — That's PROMOTE, not a bigger brief. The step invariant holds.
- **"It built and the build is green, mark the step done."** — Only after the *independent reviewer* passes it against the criteria. Builder-green is not done.
- **"I'll leave the NEEDS CLARIFICATION markers, the agent will figure it out."** — An open marker is an unmade decision handed to an unattended agent. Resolve it or don't offload.

## `.briefs/` layout

```
.briefs/
  01-data-layer.md          # the brief (the contract the reviewer checks against)
  01-data-layer-result.md   # the agent's outcome / stop-and-log report
```

Parallel to `.research/` and `.handoffs/`. `.briefs/` is **local working memory, git-ignored** — add it on first use (whole folder), the same way rolling-plan ignores `.plan/`:

```bash
if git rev-parse --git-dir >/dev/null 2>&1; then
  grep -qsF '.briefs/' .gitignore 2>/dev/null || echo '.briefs/' >> .gitignore
fi
```

When you want a brief to be **durable, shareable, and pickup-able by other agents** rather than local scratch, don't commit the file — push it as a **GitHub issue** instead (see Destinations). The issue is then the shared record.

## Reviewing changes to brief files

Writing or rewriting a brief is **substantive** — route it through the editable side-by-side diff so the user stays in control of the contract before an agent runs with it:

```bash
~/.claude/skills/agent-brief/scripts/review-diff.sh "$dest" "$proposed"
```

It opens `code --wait --diff`, blocks until the tab closes, and saves whatever is in the right (editable) pane (emptying it cancels, exit 2). On cancel, stop and ask what the user wants different — don't offload a brief they didn't accept. If `code` isn't available it writes `$dest` directly.

## References

- [`references/interview.md`](references/interview.md) — the brief-shaped interview; forces machine-checkable criteria.
- [`references/template.md`](references/template.md) — the brief artifact template, ready to fill in.
