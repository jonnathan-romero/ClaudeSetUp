# Brief Interview

Before writing a brief, **interview the user properly** — a relentless, grill-me-style interrogation, not a quick questionnaire. The brief is a contract an unattended agent executes with no human to correct it; it is only as sound as the understanding pinned down here. Skip the interview only when the conversation (or, for an offloaded step, `.plan/00-interview.md` + the plan's `Decisions Made`) has already surfaced this material — then interview only for the gaps.

This interview differs from rolling-plan's in one decisive way: rolling-plan can leave things vague and resolve them at the next step with a human present. **A brief cannot.** Every vagueness you tolerate here becomes a guess an unattended agent makes alone. So this interview drives harder toward concreteness, and it has one output it must not compromise on: **acceptance criteria a different agent can mechanically verify.**

## How to interview

- **One question at a time.** Never batch. Each answer shapes the next.
- **AskUserQuestion.** When a question has a small set of discrete answers, ask it with AskUserQuestion — recommended option first, labelled `(Recommended)`; use option descriptions or previews for the pro/cons breakout.
- **Always recommend an answer.** State your best guess and reasoning; the user corrects or confirms.
- **Follow the branches.** Chase the consequences of each answer before moving on.
- **Push back hard on vagueness** — harder than rolling-plan, because there's no human downstream to catch it. "It should work well" is not a criterion; drive it to a command and an expected result.
- **Prefer a `[NEEDS CLARIFICATION]` marker over a guess.** If a decision genuinely can't be resolved now, record it as a marker in the brief — do not silently pick. A brief with open markers is not ready to offload, and that's the honest state.

## Territory to cover

Resolve these into the brief's sections. Weave through them in whatever order the conversation dictates.

1. **Objective — what and why.** One sharp sentence of what done delivers, plus the *why* behind it. The why is load-bearing: it's what keeps the agent aligned when the implementation diverges from the letter of the brief. → **Objective**.
2. **Non-goals.** What is explicitly out of scope? Push for this — it's where an unattended agent's scope creep hides. → **Non-goals**.
3. **Blast radius.** Which files/modules should the agent touch, and which must it not? Drive to an **exact file list** where you can. → **Context & blast radius**.
4. **Acceptance criteria — the heart.** For each thing that must be true when done, get a **runnable gate**: the command to run (or observation to make) and the expected result. See the gate test below. Number them `SC-###`, phrase them `WHEN/THEN/AND`, keep them measurable and ideally technology-agnostic. → **Acceptance criteria**.
5. **One-way doors.** Which decisions are expensive/impossible to reverse? These get **decided now** and locked. Separate them from reversible decisions, which can be delegated (Mutability) or left to the agent. → locked decisions + **Mutability** tags.
6. **Guardrails.** What must the agent *always* do, *ask first* about, and *never* do? Plus a stop condition (max iterations / wall-clock). → **Guardrails** (3-tier) + stop conditions.
7. **The dials.** Operating Mode — Converge (default; **forced** if this is offloaded from a rolling-plan step), Continuous (standalone only), or Supervised (where are the checkpoints)? And per locked decision: Locked / Split / Open? → **Operating Mode + Mutability**.
8. **Verification protocol.** Confirm the reviewer runs in a fresh context against the criteria, requires evidence (command output / artifact paths), and builds a scenario→evidence compliance matrix. → **Verification protocol**.

## The acceptance-criterion gate test — do not skip this

This is the one place the interview must not yield. For **every** acceptance criterion, apply the test:

> **Can a fresh agent, seeing only the diff and this criterion, decide PASS/FAIL by running a command or making a defined observation — with no judgment call?**

If no, the criterion isn't done. Drive it down:

| Vague (reject) | Machine-checkable (accept) |
|----------------|----------------------------|
| "Auth should work" | `WHEN POST /login with valid creds, THEN 200 + a `session` cookie; `pytest -k test_login_valid` green` |
| "The page looks right" | `WHEN the dev server is up, THEN `curl -s localhost:3000/health` returns `{"status":"ok"}` exit 0` |
| "Performance is acceptable" | `WHEN `wrk -d10s http://localhost:8080/api`, THEN p99 < 200ms in the report` |
| "Tests pass" | `WHEN `pytest -q`, THEN exit 0 and 0 failures` |

Criteria that genuinely resist a command (visual polish, subjective UX) are a signal the work may be a poor fit for an unattended agent — surface that to the user rather than papering over it with a vibe-criterion. If it must stay, define the most concrete observation possible (a screenshot path + an explicit checklist) and flag it as the weak point.

## When the source is a rolling-plan step

For an `offload`, much of the above is already on disk:

- **Why** → `.plan/00-interview.md` (the durable shared understanding).
- **Locked decisions / one-way doors** → the plan's `Decisions Made` and the master's `Architecture & Key Bets`.
- **Blast radius / seams** → the step's `Needs`/`Seams` and adjacent steps.

Read those first and interview **only for the gaps** — chiefly the acceptance criteria (rolling-plan steps state a `Goal`, which is intentionally looser than a runnable gate) and the guardrails. Don't re-litigate what the plan already settled.

## After the interview — write the brief

Fill [`template.md`](template.md) and write it through the diff-review script (substantive). Before handing off, check: **no open `[NEEDS CLARIFICATION]` markers, and every `SC-###` passes the gate test.** If either fails, the brief isn't ready to offload — resolve with the user or leave it parked.
