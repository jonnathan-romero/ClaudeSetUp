# Teaching Engine: Stage 6 Internals

Read this before entering Stage 6. The engine is a state machine, not free-form conversation. Most LLM-tutor failures come from running Socratic-shaped scripts that ignore what the learner said; the rules below prevent that.

## Method-picker matrix

Auto-select per session based on topic type × learner level. Layer in secondary methods as the session progresses. Don't surface this choice to the learner.

| Topic type | Novice | Intermediate | Advanced |
|---|---|---|---|
| **Declarative** ("what is X") | Direct explanation → Feynman check | Narrative + Feynman | Feynman only; fill gaps on demand |
| **Conceptual** ("how does X work / why") | Analogy → direct → check | Analogy → case → Socratic | Case → PBL → inquiry |
| **Procedural** ("how to do X") | Worked example → backward fading → mastery gate | Faded example → coached practice | Problem-first; coaching on demand |
| **Strategic** ("when and why to use X") | Guided case (scaffolded) → debrief | Case + Socratic → reflection | PBL or project + cognitive apprenticeship |

**Composition rule:** lead with the highest-support method for the learner's level, then step down the scaffold as the session progresses. For a single 25-turn session, two methods is the practical ceiling.

**Common stacks:**
- I Do / We Do / You Do (gradual release): direct → worked example → faded example → independent problem.
- Case + Socratic: present case → probe → extract principle → name it.
- Mastery + Worked Example: diagnostic → worked example → practice with feedback → recheck.
- Narrative + Analogy + Direct: story to motivate → analogy to bridge → direct to lock in.

## Per-chunk loop

Maximum 3–4 chunks per session (working-memory ceiling for novel concepts). Each chunk runs five sub-stages:

1. **Explore** (1–2 turns) — pose a problem or thought experiment before giving the mechanism. Let the learner attempt or reason first. Encountering a problem before the mechanism is named encodes the explanation more durably (5E model; pretesting effect).
2. **Explain** (2–3 turns) — introduce the concept. Use concrete examples; use an analogy if abstract. **One concept at a time. Do not stack.**
3. **Model** (1–2 turns) — walk through a worked example explicitly, narrating each step. Show the thing; don't just describe it.
4. **Guided practice** (2–3 turns) — give the learner a problem; they attempt it. Provide targeted feedback. Do not give the answer until an attempt is made. **After any correct attempt, ask "why does this work?" — not "what was the answer?"** The self-explanation effect (Chi et al. 1994; Bisra et al. 2018 meta-analysis, d ≈ 0.55–0.61) is one of the strongest interventions in the literature. Requiring the learner to articulate the *principle* behind a procedure produces transferable knowledge; confirming the procedure alone produces only procedural recall. The "why" prompt also catches correct-answer-wrong-reason states that "what" prompts miss.
5. **Check** (1 turn) — confirm understanding before moving to the next chunk. Use teach-back: "Can you explain that back to me in your own words?"

If the learner is not tracking after Check: drop to a simpler analogy, request teach-back, or defer the next chunk and mark it explicitly ("we'll come back to X").

## Socratic state machine

Track the learner's state per concept. Default on every new concept is **State 0**. Promotion is *earned*, never assumed from session history.

| State | Meaning | Mode |
|---|---|---|
| 0 | No schema (cannot recall) | **Pure explainer.** Direct explanation with worked example. No generative questions. Comprehension checks only. |
| 1 | Partial schema (can recall, can't explain) | **Faded scaffolding.** Partially completed examples; tightly constrained Socratic prompts with built-in scaffolds. If the learner stalls after one exchange, give the answer. |
| 2 | Functional schema (can explain, hasn't applied) | **Struggle-then-consolidate.** Pose a novel application problem, let the learner attempt, withhold the answer for one exchange, then consolidate by explaining against their attempt. |
| 3 | Applied schema (has solved correctly with explanation) | **Full Socratic.** Open-ended questions, devil's advocate challenges, edge cases, transfer problems. Only deliver direct explanation on confident wrong answers — that triggers misconception mode. |

**Promotion criteria:**
- 0 → 1: learner can recall the concept correctly when prompted.
- 1 → 2: learner can explain *why* in their own words.
- 2 → 3: learner has applied the concept to a novel problem successfully.

**Demotion criteria:**
- Confident wrong answer → switch to misconception-repair branch (see [misconception-repair.md](misconception-repair.md)) for *that concept only*; other concepts keep their state.
- Learner expresses frustration or asks for the answer → drop to State 0 for *that concept only*; explain directly, then re-attempt.

## Signal → action table

Apply per turn. Each row is independent.

| Signal | Action | Rationale |
|---|---|---|
| Correct + clear reasoning | Acknowledge briefly; remove one scaffold; advance | Contingent shift principle (Wood et al.). Success means decrease support. |
| Correct, no reasoning | Reasoning probe before advancing | Correct-answer-wrong-reason will fail any transfer task. |
| Wrong once | Single targeted diagnostic question; **do not** intervene yet | The error may be a slip, a misconception, or a missing prerequisite. Diagnose first. |
| Wrong twice on same concept | Hint level 1 (direction-only). Reduce degrees of freedom — narrow to the failing sub-step | Repeated failure is the clearest signal the learner is outside their ZPD. |
| Very short response ("idk") | Constrained sub-question or binary choice | Bottom-of-ZPD signal. Don't repeat the same question louder. |
| Long, effortful, but wrong response | Mark **one** critical feature; not all errors | Productive struggle. Full correction dumps cognitive load. |
| "Just tell me the answer" | Acknowledge; offer hint level N+1 (one step closer, not the answer) | Frustration approaching unproductive. Concrete partial scaffold beats motivational speech. |
| 3 correct in a row, no hints | Raise difficulty; remove an existing scaffold | Common ITS mastery threshold. Continuing easy questions produces boredom — more damaging than confusion. |
| Long silence / time-out | Lowest-level hint, **not** a re-statement of the question | Repeating the question adds no information. |
| Same error across different problems | **Halt forward progress.** Diagnose underlying prerequisite gap directly: "It looks like we might be shaky on X — want to do a quick check on that first?" | Persistent error patterns signal a missing prerequisite, not a ZPD challenge. Surface scaffolding will not fix it. |
| Confident wrong answer | Trigger misconception-repair branch (see [misconception-repair.md](misconception-repair.md)) | Direct explanation gets mapped onto the existing wrong schema. |

## Hint hierarchy

Each level reveals slightly more of the solution path. After the bottom-out hint, immediately give an **isomorphic** problem (same skill, different surface) — the generation effect requires retrieval before the answer fades.

**Worked example: Python list indexing**

Learner asked: "Print the last element of `colors = ['red', 'green', 'blue']`."

- **Level 0 — Wait.** 30–60 seconds. If no response or blank attempt, give Level 1.
- **Level 1 — Direction without content.** "In Python, you can access any element using its position. Think about what position the last item occupies."
- **Level 2 — Structural hint.** "Python lists use zero-based indexing. A list with 3 items has positions 0, 1, and 2. Which position is the last? Also: Python has a shortcut for 'last element' that doesn't require counting."
- **Level 3 — Bottom-out.** "The last element is `colors[2]` (position 2 in a zero-indexed list of 3 items), or more idiomatically `colors[-1]` (negative indexing counts from the end). So `print(colors[-1])` prints `'blue'`."

Immediately after Level 3: "Now write a line that prints the last element of `nums = [10, 20, 30, 40]`." This is the isomorphic re-test.

## Scaffold fading

Fading is contingent on demonstrated competence, not elapsed time.

**Triggers to fade:**
- N consecutive correct responses without requesting hints (N=3 is the standard ITS threshold)
- Learner self-corrects mid-response (evidence of internalized monitoring)
- Learner asks meta questions about strategy rather than surface answers

**Order of fading:**
1. Remove confirmatory sub-step feedback first
2. Then remove structural hints from problem framing
3. Then increase problem complexity
4. Then introduce interleaving (mix problem types)

Do not remove all scaffolds simultaneously. When the problem format becomes harder, the response style should become *more* supportive, not also harder.

## Productive vs. unproductive struggle

| Signal | Likely state | Action |
|---|---|---|
| Long response, wrong but engaged | Productive confusion | Mark one critical feature; let them self-repair |
| Very short or null response | Possible overload or disengagement | Constrain the question; offer Level 1 hint |
| Same error, third occurrence | Missing prerequisite | Halt; diagnose the gap explicitly |
| Explicit "I give up" | Frustration threshold crossed | Acknowledge, offer hint N+1, reduce scope |
| Correct + unprompted self-explanation | High engagement, in ZPD | Increase difficulty; fade scaffolding |
| Correct, but only after cycling all hints | Scaffolding-dependent, not mastered | Repeat isomorphic problem without hints before advancing |
| Boredom markers (minimal elaboration, sarcasm) | Below ZPD | Increase difficulty immediately |

Confusion that resolves into correct answers is productive. Confusion that persists for three turns with no forward movement is a signal to intervene. Boredom is more damaging than frustration — it is more persistent and self-reinforcing.
