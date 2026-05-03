# Misconception Repair

Triggered by a confident wrong answer during teaching. Stating the correct answer does not repair a misconception — the wrong model isn't deleted, it gets suppressed and resurfaces under cognitive load. Different misconception *types* need different repair strategies.

## Why direct correction fails

Post-instruction, the old conception persists alongside the new one and must be actively inhibited each time the correct model is used. ERP studies show intuitive misconceptions are still recruited during the initial stage of reasoning even in successfully-instructed learners. The new knowledge wins only when slow, deliberative cognition overrides automatic retrieval of the prior model. Reversion is the default — anchoring the new model requires building retrieval cues that compete with the old ones.

## Three types (Chi 2008)

| Type | What it is | Example |
|---|---|---|
| **1. False Belief** | Isolated incorrect factual claim; surrounding model intact | "The heart oxygenates blood" |
| **2. Flawed Mental Model** | Coherent but systematically wrong internal simulation; multiple beliefs hang together wrongly | "Electric current is consumed by a resistor, so less arrives downstream" |
| **3. Ontological Miscategorization** | Concept assigned to the wrong fundamental category | "`x = x + 1` has no solution" (treating `=` as math equality, not an assignment command) |

## Decision tree

```
Detected misconception
        |
        v
Is the wrong belief isolated (single false fact)?
  YES → Use Refutation Text strategy.
  NO  →
        |
        v
Does the learner have a coherent but wrong internal model
(several mutually-consistent false beliefs that hang together)?
  YES → Use Holistic Model Confrontation.
  NO  →
        |
        v
Is the learner assigning the concept to the wrong category
(treating a process as a thing, a relation as a property, etc.)?
  YES → Use Ontological Recategorization.
```

If you can't classify, default to Holistic Model Confrontation — it works for both Type 1 and Type 2.

## Strategy 1 — Refutation Text (Type 1: false belief)

Structure:
1. Name the misconception explicitly.
2. Acknowledge why it seems reasonable.
3. Refute it with evidence.
4. State the correct view.
5. Verify with 2–3 follow-up cases.

Refutation texts outperform plain expository text by g ≈ 0.41 in meta-analysis (Tippett 2022). The mechanism: by explicitly naming the misconception, you create an *interference memory* that catches automatic reversion. Silently teaching past the error doesn't.

## Strategy 2 — Holistic Model Confrontation (Type 2: flawed model)

Structure:
1. **Elicit the full model.** "Walk me through your reasoning end-to-end. What happens at step A, then step B, then step C?" Draw it out explicitly. Do not refute prematurely.
2. **Present the correct model side-by-side.** Make structural divergences visible. Do not just refute one belief — refuting individual beliefs within a flawed model produces patch repairs that break elsewhere.
3. **Have the learner identify divergences.** "Where do these two models predict different things?"
4. **Engineer dissatisfaction with Predict-Observe-Explain (POE).** Have the learner predict from their model, surface a contradiction, name it explicitly. Vague acknowledgment that "some people think X" is weaker than a learner committing to a specific failed prediction.
5. **Apply the corrected model to 2–3 new cases the learner cares about** (fruitfulness — Posner condition 4). The new model must solve more problems than the old one before it sticks.

## Strategy 3 — Ontological Recategorization (Type 3: category error)

Surface-level correction is incoherent here — the misconception and the correct concept live in different ontological trees. The fix is two-step:

1. **Name the category error explicitly.** "You're treating this as a [category A — e.g., a thing]; it's actually a [category B — e.g., a process]. They look similar but they're different *kinds* of things."
2. **Build the correct category from scratch using bridging analogies.** Find a domain where the learner's intuition is already correct (an *anchor*). Construct a chain of intermediate analogies from anchor to target. Each step small enough to be accepted.
3. **Repeated retrieval in varied contexts.** Because the old category is suppressed, not deleted, retrieval cues in new surface contexts can re-activate it. Vary surface features so the new category fires automatically across cue patterns.
4. **Make the category label a salient check.** Train the learner to ask "Is this a [thing or process]?" — that question becomes the inhibitory trigger that catches automatic reversion before it completes.

## Posner et al.'s four conditions, operationalized

For Type 2 and Type 3 (Type 1 only requires direct refutation), engineer all four:

1. **Dissatisfaction** — POE loop. Make the learner commit to a prediction from the wrong model, then surface the contradiction.
2. **Intelligibility** — bridging analogies from a correct anchor.
3. **Plausibility** — refutation framing acknowledges *why* the wrong view seemed reasonable. Don't make the learner feel foolish.
4. **Fruitfulness** — apply the new model to 2–3 cases the learner cares about. Successes encode the new model with strong retrieval cues.

## Worked examples

### Example 1: "Heavier objects fall faster" (Type 1 → Type 2)

Most novices hold this as a false belief tied to friction experience (feathers vs. rocks). The p-prim is "more stuff → more of the effect."

**Move:**

1. **POE.** "If you drop a heavy textbook and a pencil from the same height in a vacuum, which hits first? Commit to an answer."
2. **Galileo thought experiment** (engineers contradiction). "Imagine tying a heavy object to a light one. By your model, the heavy one drags the light one — making the system fall faster than the light one alone. But the light one also drags the heavy one — making the system fall *slower* than the heavy one alone. Both can't be true. The model produces a contradiction."
3. **Refutation:** "Many people believe heavier objects fall faster because in everyday experience, they do — feathers fall slower than rocks. That's because air resistance affects light objects more. Without air resistance, all objects fall at the same rate regardless of mass."
4. **Apply:** "What about a bowling ball vs. a soccer ball, dropped from 2 feet in regular air? Why does mass barely matter there too?"

### Example 2: `x = x + 1` is impossible (Type 3 — ontological)

Novice programmers transfer `=` from math (a symmetric *predicate*) to programming (a *command*). The misconception and the correct meaning live in different ontological categories — math operators describe truth, programming operators describe actions.

**Move:**

1. **Name the category error.** "In math, `=` asks a question — *is this true?* In Python, `=` is a command — *do this action.* They look the same but they're different kinds of things."
2. **Anchor analogy.** "A counter at a coffee shop currently shows 5. The barista says: 'new count = old count + 1.' They're not solving an equation; they're overwriting a value in a box. The right mental model is *box*, not *equation*."
3. **POE.** "Predict the value of `x` after these three lines: `x = 1`, `x = x + 1`, `x = x * 2`. Write it down before we trace it."
4. **Defuse the false cognate.** "In math, `x = x + 1` has no solution — that's true and irrelevant. The Python interpreter doesn't check truth; it performs a step. Math `=` and Python `=` are spelled the same but mean different things."
5. **Vary surface to train the new category.** `count += 1`, `score = score - penalty`, `total = total + item`. Each variant makes "command, not equation" fire more automatically.
6. **Salient check.** "When you see `=` in code, the inhibition trigger is: *am I asking a question, or am I issuing a command?* In Python it's almost always a command."

## What anchors the new model against reversion

- **Explicit retrieval practice across varied contexts.** The old model is suppressed, not deleted; new-context cues can re-activate it. Vary surface features to train inhibition broadly.
- **Naming the misconception creates interference memory.** Refutation works because it doesn't silently teach past the error.
- **The new model must be applied, not just stated.** Three successful applications during the session encode the new model with its own retrieval cues.
- **For ontological errors, make the category label a check.** "Is this a thing or a process?" as an explicit prompt catches automatic reversion.
