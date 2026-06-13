# Brief Template

Fill this in and write through the diff-review script (substantive). Keep it lean — drop unused sections rather than leaving them empty. A long brief degrades; front-load only the unrecoverable.

`NN-name.md`. The contract an autonomous builder + reviewer pair executes.

```markdown
# Brief NN: <name>

## Objective
<One sentence: what done delivers.>
**Why:** <the reason this matters — keeps the agent aligned when the how diverges>

## Non-goals
- <explicitly out of scope>

## Context & blast radius
- Repo / conventions: <stack, test command, style — point to AGENTS.md/CLAUDE.md if present>
- Touch these files: <exact list where known>
- Do NOT touch: <files/areas off-limits>
- Source: <../.plan/NN-name-plan.md#step-N and ../.plan/00-interview.md, when offloaded from a step>

## Acceptance criteria
<!-- Every item MUST end in a runnable gate. No vibe-criteria. -->
- **SC-001** — WHEN <action/condition>, THEN <observable outcome>, AND <more>.
    Gate: `<command>` → <expected result, e.g. exit 0 / 200 / green>
- **SC-002** — WHEN <…>, THEN <…>.
    Gate: `<command>` → <expected>

## How to implement
<!-- The elastic section: sub-instructions the agent MAY expand on within one bounded run.
     Guidance, not a keystroke script. Leave reversible choices open. -->
1. <step / approach>
2. <step / approach>

## Guardrails
- ✅ Always: <e.g. run the test suite before declaring done; work on branch <name>>
- ⚠️ Ask first: <e.g. schema changes, new dependencies, irreversible actions>
- 🚫 Never: <e.g. commit secrets, force-push, edit vendored code, touch <area>>
- Stop condition: <max iterations / wall-clock — a hard ceiling on the run>

## Operating Mode & Mutability
- **Operating Mode:** Converge | Continuous | Supervised
    <!-- Converge = build until criteria pass, then stop (default; REQUIRED for from-step briefs).
         Continuous = loop until a stopping condition (standalone only); state it: <e.g. score ≥ 90>.
         Supervised = pause at checkpoints; list them: <checkpoint 1, …>. -->
- **Locked decisions & their mutability:**
    | Decision | Mutability | If wrong |
    |----------|------------|----------|
    | <one-way door> | Locked | halt + stop-and-log |
    | <reversible op choice> | Split | adapt within guardrails, log override |
    | <low-stakes choice> | Open | agent decides freely |

## Open clarifications
<!-- Anything the interview did not resolve. A brief with open markers is NOT ready to offload. -->
- [NEEDS CLARIFICATION: <question>]

## Verification protocol
- Reviewer runs in a **fresh context**, seeing only the diff + the acceptance criteria above (never the builder's reasoning).
- Build a **compliance matrix**: for each SC-###, the command run, its actual output, and PASS/FAIL.
- **Evidence required** — no criterion is PASS on inspection alone; cite command output or artifact paths.
- PASS on all → write-back (flip the step `[x]` + Outcome, for an offloaded step).
- Any FAIL → stop-and-log to `NN-name-result.md`; nothing written back.
```

## Notes on use

- **Objective's `Why` is not optional.** It's the alignment anchor when the literal instructions don't fit reality.
- **Acceptance criteria are the contract.** If a `Gate:` line is missing or unrunnable, the brief isn't finished — see the gate test in [`interview.md`](interview.md).
- **Operating Mode is `Converge` for any brief born from a rolling-plan step.** Continuous/Supervised are for standalone briefs. A step that needs more than one session is a PROMOTE, not a longer-running brief.
- **Mutability defaults to `Locked`.** Only loosen a decision to Split/Open when it's genuinely reversible — an unattended agent overriding a one-way door is the worst failure mode.
- **Drop sections you don't need.** A small brief is Objective + Non-goals + Context + Acceptance criteria + Guardrails. Mode/Mutability/Clarifications appear only when they carry weight.
- **The result file is the executor's, not the author's.** `NN-name-result.md` holds the reviewer's compliance matrix on PASS, or the stop-and-log report (what was found, why the brief was wrong, proposed options) on FAIL.
