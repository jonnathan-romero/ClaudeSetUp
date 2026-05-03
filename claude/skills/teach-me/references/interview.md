# Interview Protocols: Stages 1 & 4

Two distinct conversations: the **goal probe** (what they want to *do*) and the **diagnostic interview** (what they already *know*). Don't conflate them — they happen at different stages and serve different purposes.

## Stage 1 — Goal probe

### Primary question

> "What's the first thing you'd want to *do* with this knowledge — or what situation would you want to be ready for?"

This single question is the highest-leverage probe in the session. The answer maps directly onto Bloom's revised taxonomy and Webb's Depth of Knowledge without asking the learner to use either:

- "Explain it to my team" → Understand / DOK 2 — conceptual depth, factual+conceptual knowledge type
- "Build a small project" → Apply / DOK 2-3 — procedural
- "Operate it in production" → Apply-Analyze / DOK 3-4 — procedural+strategic
- "Audit our current setup and fix problems" → Analyze-Evaluate / DOK 3-4 — strategic
- "Decide whether to adopt it at all" → Evaluate / DOK 4 — strategic + judgment

### Follow-ups when the answer is vague

If the learner says "I just want to learn it" or "I'm curious," try the stakes probe:

> "Is this for a conversation, a task you have coming up, a personal project, or operating something where the stakes are real?"

If still vague, the boundary probe:

> "Is there a point where you'd be comfortable saying 'I know enough, I'll look up the rest' — or do you want no gaps?"

If the learner claims existing knowledge, the expert calibration probe:

> "Walk me through the last time you actually used this — what did you do, where did you get stuck?"

This is a structural-complexity diagnostic. A learner who lists separate facts without integration is at the multi-structural plateau (SOLO taxonomy); one who describes coherent end-to-end reasoning is at the relational plateau. They need different sessions.

### What to record from Stage 1

- **Depth target** — internally categorize into Bloom × DOK, but do not show this jargon to the learner.
- **Motivation hook** — the concrete situation or outcome the learner named. Refer back to it at the close.
- **Domain to hug examples to** — if they mentioned a project, technology stack, or context, use it for examples throughout.

## Stage 4 — Diagnostic interview

### Goal

Locate the learner on the prerequisite chain for the topic. Identify any active misconceptions. Stop when the next question wouldn't change the lesson plan.

### Standard sequence

**Question 1 — Open probe** (free response):

> "What do you already know about X? Tell me in your own words."

Do not offer answer choices. Listen for the *vocabulary* the learner uses — it tells you their reference frame (practitioner / student / complete novice) and often reveals a misconception in the phrasing itself before any explicit probe is needed.

**Question 2 — Mid-chain structured question:**

Pick a concept that sits in the middle of the topic's prerequisite chain. Pose a question whose plausible wrong answers each map to a specific named misconception. A correct answer means probe upward (toward more advanced prerequisites) on the next question; a wrong answer means probe downward (toward more foundational prerequisites). Each answer roughly halves the candidate space of "where the learner is."

Example for recursion:

> "If a recursive function calls itself ten times, how many stack frames exist at the moment of the deepest call?"
>
> A) 10 (correct — frames are not collapsed)
> B) 1 (misconception: thinks only the current call exists; iteration confusion)
> C) 5 (misconception: thinks frames are reused or merged)
> D) Depends on the input (partial understanding)

A wrong answer of B and a wrong answer of C call for completely different follow-up. That is the diagnostic value.

**Question 3 — Two-tier reasoning probe** (always, after any answer):

> "What made you say that? Walk me through how you got there."

Most "wrong reasoning" responses come from learners who answered the surface question correctly. Never skip the reasoning probe on a confident correct answer.

**Question 4 — Misconception-targeted question** (only if needed):

If Q2 and Q3 didn't surface a clear active misconception, pose a question whose wrong answer is the single most common misconception at the apparent level. This isolates whether to plan a misconception-repair branch into the teaching session.

**Question 5 — Optional muddiest-point close:**

> "Before we start, is there a specific part of this you already know you find confusing or want to make sure we cover?"

This is a metacognitive prompt, not a diagnostic question. It surfaces what the learner *thinks* they don't understand, which often differs from what the diagnostic questions revealed. It also signals collaboration rather than evaluation — reduces performance anxiety.

### Stop rule (PSER criterion)

After each answer, ask internally: "Would a different answer to the next question change where I start the lesson, or which misconceptions I address first?"

- If yes — ask the next question.
- If no — every plausible remaining state of the learner leads to the same teaching plan. Stop the diagnostic and proceed to Stage 5.

In practice, three questions usually suffice. Seven is the hard ceiling — beyond that, learner fatigue dominates diagnostic return.

### "I don't know" gaming defense

If the learner gives **two consecutive non-answers** — "idk", "no idea", a single character, "just teach me", or any response that contains no actual content — end the diagnostic immediately and start teaching at State 0 (direct explanation, no generative prompts) until the learner re-engages.

The diagnostic exists to inform the lesson plan. If the learner is non-responsive, the safe default for the lesson plan is "start from scratch" — better to teach a beginner what they already know than to interrogate a checked-out learner. The diagnostic stop rule is fundamentally about minimum information gain; non-answers contribute zero, so the rule kicks in immediately on a second one.

This is also a respect-for-autonomy move. A learner who's been asked three questions and answered "idk" twice is telling you they don't want to do diagnostic theater — honor it.

### Designing diagnostic items

Every wrong answer should reveal a specific named misconception, not just be incorrect. Before posing a question, identify two or three misconceptions common at this level and write the question so each plausible distractor maps to exactly one.

If you cannot describe the misconception that would lead a learner to choose a distractor, replace that distractor.

## Worked example: opening a session on Bayesian statistics

**User invocation:** "I want to learn Bayesian statistics. I've taken intro stats but it never really clicked."

**Goal probe (Stage 1):**

> "What's the first thing you'd want to do with Bayesian stats — interpret a paper, run an analysis on your own data, decide whether to use it for a project, something else?"

User: "I want to be able to set up a Bayesian model for an A/B test at work."

→ Depth target: Apply / DOK 2-3, procedural+conceptual. Domain to hug: A/B testing.
→ Motivation hook: "the A/B test at work."

**Stage 2 — Length offer:**

> "Working understanding (~25 turns) or deep dive (~40+)? For an applied A/B test setup, working understanding is usually enough — you can come back for the deeper theory later."

User: "Working understanding."

**Stage 4 — Diagnostic interview:**

Q1 (open): "When you've heard 'Bayesian' before, what do you think the core idea is — in your own words?"

User: "Something about updating probabilities based on new data?"

→ Vocabulary suggests practitioner-adjacent reference frame. Has a partially correct verbal model.

Q2 (mid-chain structured): "Suppose I tell you a coin lands heads 7 out of 10 times. A frequentist gives you a confidence interval; a Bayesian gives you a posterior distribution. What's the most important conceptual difference between those two outputs?"

A) The frequentist tells you what the true rate is; the Bayesian tells you what to bet on
B) The frequentist describes the procedure's long-run behavior; the Bayesian describes your current belief about the true rate (correct)
C) They're the same thing computed two different ways
D) The Bayesian needs more data to converge

User: A

→ Misconception located: confused about what each output is *about*. Missing the prior + likelihood → posterior structure.

Q3 (reasoning probe): "What made you pick A over B?"

User: "I always thought confidence intervals tell you where the true value is."

→ Confirmed: the misconception is in the frequentist side, not the Bayesian side. The "what does CI mean" misconception is documented and well-named.

Stop check: do I know enough to plan? Yes. The session needs to (a) repair the CI-tells-you-the-truth misconception, (b) introduce prior + likelihood → posterior, (c) walk through one A/B-flavored example, (d) end with the user setting up a real model. Three more diagnostic questions wouldn't change that plan.

→ End diagnostic; proceed to Stage 5.

**Stage 5 — Confirm exit criterion:**

> "By the end of this, you'll be able to set up a Bayesian model for a simple A/B test, explain what the posterior tells you that a confidence interval doesn't, and decide whether more data is worth collecting based on the posterior. Sound right?"

User: "Yes."

→ Begin teaching with method picker: conceptual+procedural at intermediate level → analogy + worked example + Socratic probing as the learner gains ground.
