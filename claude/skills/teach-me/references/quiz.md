# Quiz: Stage 10

Optional, opt-in. The quiz is a *learning event*, not assessment. The testing effect (Roediger & Karpicke 2006, Karpicke & Blunt 2011) shows retrieval practice produces 50% better one-week retention than re-study or elaborative concept-mapping. The quiz design below maximizes that mechanism.

## When to offer

After Stage 9 (close) is complete. Ask:

> "Want to lock this in with a 7-question quiz that ramps from simple recall to designing your own application? You can change the count."

Default is 7 questions. Respect any count the user picks. If they decline, the session ends after Stage 9 — that's fine. Stage 9 by itself completes the lesson.

## Structure: 7-question Bloom ramp

Each question targets one cognitive level, building on competencies the prior questions established.

| Q | Bloom level | Cognitive task | Format | Notes |
|---|---|---|---|---|
| 1 | Remember | Identify or define a core term | MC, 4 options | Misconception distractors |
| 2 | Understand | Explain in own words or classify | MC, 4 options | Misconception distractors |
| 3 | Apply | Use the concept in a direct case | MC, 4 options | Misconception distractors |
| 4 | Apply (transfer) | Apply to novel or off-nominal case | **Short answer** | Format pivot defeats the recognition cueing effect |
| 5 | Analyze | Compare, differentiate, diagnose error | Short answer | |
| 6 | Evaluate | Critique a claim or design choice | Constructed response | No single correct answer |
| 7 | Create | Propose a solution, design, or extension | Constructed response | Open synthesis |

**Format pivot rationale:** Q1–Q3 use multiple choice because the answer space is enumerable and misconception-based distractors make each option diagnostic. Q4 shifts to short answer to defeat the recognition cueing effect — MC lets the learner *recognize* a correct answer they couldn't *recall* (Tulving's recognition vs. recall asymmetry). At the Apply-transfer level, recall is the load-bearing skill. Q5–Q7 use constructed response because forcing a choice among options at Evaluate/Create levels would invalidate the measurement.

The Bloom ramp covers all six revised levels (Anderson & Krathwohl 2001) across 7 items, with Apply spread across Q3 (direct case) and Q4 (transfer case) — not seven distinct levels.

## Distractor design (Q1–Q3)

Each MC distractor must map to a specific *named misconception*. If you can't describe the misconception that would lead a learner to choose it, replace it.

Avoid:
- "All of the above" (lowers reliability — only need to identify two correct options)
- "None of the above" (acceptable on calculation items; problematic on conceptual)
- Length asymmetry (longest option is chosen above chance regardless of content)
- More than three real distractors (beyond three, distractors become implausible)

## Pretesting opener

Q1 may target a concept not explicitly taught in the session — the **pretesting effect** (Richland, Kornell & Kao 2009). Failed retrieval primes the learner to encode the corrective information. The learner will likely get this one wrong, and that failure is productive. Provide the correct answer immediately after the attempt.

## Per-item feedback (immediate, structured)

Use the wrong-answer response template from [feedback-and-tone.md](feedback-and-tone.md):

**Acknowledge → Diagnose → Correct → Re-engage**

> "That's not correct. You picked B, which is the natural choice if you're thinking of [misconception]. The correct answer is C, because [process-level explanation]. Notice how this connects to [principle from session]."

For correct answers: brief acknowledgment + a process-level note that names what they got right.

> "Correct. The key move you made was applying [rule] without confusing it with [adjacent rule] — that's the trap most people fall into here."

## Re-test loop

This is the highest-leverage design choice in the whole quiz. After Q7:

1. Identify all questions the learner got wrong.
2. Re-present those items at the end, in randomized order.
3. Provide immediate feedback again.

Frame the re-test as locking-in, not failure:

> "Two questions to lock in before we wrap up — these are the ones we're going to make stick."

This pattern provides three benefits simultaneously:
- **Effortful retrieval** (must produce answer again)
- **Spacing** (other items intervened — micro-spacing within session)
- **Correction consolidation** (right answer was just seen; second retrieval cements the corrected trace)

## Item ordering rules

- Span the session's content in **non-sequential order** — don't follow the lesson outline. Force mental context-switching between items (interleaving's mechanism within a single-topic quiz).
- Place a moderately hard question at position 3–4, after initial confidence is established. Not at position 1 (discouraging) or position 7 (anti-climactic).
- No two items on the exact same micro-concept appear back-to-back.

## Format mix

For a 7-question quiz, the mix should be roughly:

- 3 MC (positions 1–3)
- 3 short answer (positions 4–5; sometimes 6 if the topic doesn't lend itself to constructed response)
- 1–2 constructed response (positions 6–7)

≥4 items must require *production*, not recognition. The generation effect (Slamecka & Graf 1978) shows produced answers are better remembered even when the produced answer is wrong. Multiple choice should not dominate.

## Worked example: 7-question quiz on linear regression

**Q1 (Remember, MC):** What does the slope coefficient in a simple linear regression represent?
- A) The value of y when x is zero (misconception: intercept/slope confusion)
- B) The average change in y for a one-unit increase in x **(correct)**
- C) The proportion of variance in y explained by x (misconception: R²/slope confusion)
- D) The correlation between x and y (misconception: correlation/regression conflation)

**Q2 (Understand, MC):** A model has R² = 0.85. Which best describes what this means?
- A) The slope is statistically significant at p < 0.05 (significance/fit confusion)
- B) 85% of the variance in the outcome is explained by the model **(correct)**
- C) The model predicts outcomes within 15% of their true value (R² as precision)
- D) There is an 85% probability the relationship is causal (causation from correlation)

**Q3 (Apply, MC):** A regression of exam score on study hours gives: score = 40 + 5(hours). Predict the score for a student who studies 6 hours.
- A) 46 (forgot the slope multiplier)
- B) 70 **(correct)**
- C) 240 (multiplied everything)
- D) 30 (subtracted instead of added)

**Q4 (Apply+, short answer):** You fit a linear regression and notice that residuals systematically increase in magnitude as fitted values increase. What does this pattern indicate, and what transformation might address it?

> Expected: heteroscedasticity; log-transform on the outcome (or weighted least squares).

**Q5 (Analyze, short answer):** A classmate argues: "My model has a very low p-value on the slope, so the model fits the data well." Identify the flaw.

> Expected: statistical significance of the slope does not indicate goodness of fit; R² or RMSE would. Conflates inferential and descriptive statistics.

**Q6 (Evaluate, constructed):** A data scientist uses a regression model trained on 2018–2019 sales data to forecast 2024 sales. An analyst objects that the model is unreliable. Evaluate the objection — what assumptions does it rest on, and are they justified?

> Expected: the regression assumes stable underlying relationships (stationarity); the objection is well-grounded if market conditions changed (COVID, competition, pricing shifts). The learner should articulate the distributional-shift concern.

**Q7 (Create, constructed):** You're modeling whether a customer will churn (yes/no) based on usage and demographic features. A colleague suggests using ordinary linear regression. Propose a better-suited approach, explain your reasoning, and describe one limitation of your proposed approach that the colleague's method would not have.

> Expected: logistic regression; bounded [0,1] outputs, log-odds interpretation; limitation might be linearity in log-odds, calibration assumptions, or interpretability cost of decision-threshold selection.

## What kills the testing effect

Avoid these — each one undoes the learning benefit:

- Recognition-only items with no feedback (entrenches wrong answers as false memories)
- Feedback withheld until end-of-quiz (learners can't self-correct during the quiz)
- Quiz immediately after content with zero gap (reduces effortful reconstruction)
- All items from one difficulty band (too easy = fluency illusion; too hard = discouragement)
- No re-test of missed items (one retrieval failure with no follow-up is just forgetting)
- Score-shaming on missed re-test items (frame as "lock this in," not "second failure")
