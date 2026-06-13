# Planning Interview

Before writing the first plan or master plan, **interview the user properly** — a real, relentless, grill-me-style interrogation, not a quick questionnaire. The plan is only as sound as the understanding behind it, and a fresh agent later inherits whatever you pin down now. Skip the interview only when the conversation has already surfaced this material, or the user handed you a concrete plan/spec and told you what to do.

## How to interview

- **One question at a time.** Never batch. Ask, get the answer, let it shape the next question.
- **AskUserQuestion.** When a question has a small set of discrete answers, ask it with AskUserQuestion — recommended option first, labelled `(Recommended)`; use option descriptions or previews for the pro/cons breakout.
- **Always recommend an answer.** State your best guess and reasoning with each question; the user corrects or confirms. Don't ask open questions into a void.
- **Follow the branches.** This is not a fixed list — each answer opens or closes paths. Chase the consequences of an answer before moving on; resolve each branch of the decision tree until the shape is genuinely settled, not just acknowledged.
- **Push back.** If an answer is vague, contradictory, or smells like premature commitment, say so. If a simpler scope exists, propose it. Surface assumptions and get them confirmed or killed.
- **Know when to stop.** Stop when you understand the effort well enough to write a coherent spine — not when some question count is hit. If the ask is small or the user signals impatience, go light (see below). Deeper, multi-plan efforts earn a deeper grill.

## Territory to cover

These are the areas to resolve, not a script — weave through them in whatever order the conversation dictates, going deep where there's uncertainty and skipping what's already clear.

1. **North-star goal.** What does the whole effort deliver when done? Drive to one sharp sentence. → becomes the master/child **Goal**.
2. **Chunk boundaries.** The rough major chunks (future child plans) — coarse shape, 2-5 chunks. Probe whether a chunk is really one chunk or several. → drives **tier** (one chunk → master plan) and the master **Plans** table.
3. **Scary unknowns.** What's most likely to be wrong, hard, or not work? Dig for the real risk, not the comfortable one. → become early **research/spike** steps.
4. **One-way doors.** Which decisions are expensive/impossible to reverse? Separate these from reversible ones — they get different treatment. → one-way doors go in the master's **Architecture & Key Bets**; reversible decisions get **deferred**.
5. **Out of scope.** What are you explicitly **not** doing? Push for this — it's where scope creep hides. → bounds the plan; note in Goal/Notes.
6. **Seams (multi-plan only).** What does each chunk hand the next — file, interface, data shape? Pin the contract firmer than the implementation. → master's **Seams Between Plans** and each child's **Seams**.

When the ask is small or the user is impatient, collapse to the essentials — goal, chunks, scary unknowns — and **defer** one-way doors and seams to when the work reaches them. That is the last-responsible-moment principle applied to the interview itself: "I don't know yet" is a fine answer that becomes a deferred decision, not a reason to keep pressing.

## After the interview — save the findings, then capture progressively

You will usually learn **more than belongs in the plan right now.** Don't lose the surplus and don't cram it into the plan. Two destinations:

1. Write the full findings to `.plan/00-interview.md` (through diff-review — substantive). This is the durable record of the shared understanding: everything the interview surfaced, **including** the far-term unknowns, the one-way doors, the deferred "I don't know yet" answers, the out-of-scope list, and the assumptions you confirmed. It is the counterpart to the lean plan — the place the "why" and the "not-yet" live so they survive a context reset. A later session re-orienting reads this alongside the plan files and treats these as the preliminary vision that needs to be confirmed. Keep it updated if the understanding materially changes (e.g. after a re-interview).

2. **Capture into the plan only what the near-term needs.** Rolling-wave applies to the interview's output too: detail what's imminent, keep the far term coarse, draw from `00-interview.md` as the work reaches it.

Map what you keep **in the plan now** to its home:

| What you learned | Where it goes now |
|------------------|-------------------|
| North-star goal | Goal (master and/or the first child plan) |
| Chunk boundaries | master **Plans** table (one row per chunk); create child files only as you reach them — not all upfront |
| Scary unknowns (near-term) | concrete early **research/spike steps** in the active plan |
| Scary unknowns (far-term) | a coarse line in **Open Questions / Deferred Decisions**, not a fleshed-out step |
| One-way-door decisions | master **Architecture & Key Bets** |
| Reversible decisions not yet forced | **Open Questions / Deferred Decisions**, with the trigger that forces them |
| Out of scope | a line under Goal or Notes |
| Seams (multi-plan) | master **Seams Between Plans**; echo in each child's Seams |

Concretely: write the **master plan** (if multi-plan) and **only the first child plan**, with its **near-term steps detailed** and later steps/chunks left coarse. Don't pre-write every child plan from the interview — create each when the work reaches it, refining with what you know by then. Route plan-file creation through the diff-review script (a substantive change).
