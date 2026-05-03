# Folklore audit

When a prompt contains evidence-thin tactics, strip them and explain why. Each removal cites the study that refutes the tactic.

## Quick decision

| Tactic in prompt | Status on frontier models (Claude 3.5+, GPT-4o+, reasoning models) | Action |
|---|---|---|
| "I'll tip you $200 / $1000 / $X" | Doesn't replicate (Wharton 5-model study, ~5000 trials) | **Strip.** Cite Wharton GAIL. |
| "Your job depends on this" / threats | Doesn't work (Wharton refutes Brin claim) | **Strip.** |
| "You are a world-class expert / Nobel laureate" for accuracy | Hurts MMLU (71.6% → 66.3% with longer personas; Wharton 2025) | **Strip when used for accuracy.** Keep if used for *tone* (e.g., "write like a McKinsey deck"). |
| "Take a deep breath, work step by step" | Was a CoT trigger on PaLM 2 era; redundant on reasoning models | **Strip on reasoning models.** Keep as cheap CoT trigger on small/older non-reasoning models. |
| "This is very important to my career" / EmotionPrompt | Real on 2023 models; ~zero on frontier | **Strip.** Note as historical evidence. |
| Role-play "act as X" for capability | Style yes, capability no (Kong 2024: hurts 7/12 datasets on Llama-3) | **Strip when used to "unlock expertise".** Keep when used for output format/voice. |
| Grandmother / DAN role-play | Jailbreak mechanism, not capability unlock | **Strip and warn** — this is misuse. |
| Excessive politeness ("please please please") | Mixed evidence; small effect | Trim. Moderate politeness is fine. |
| Excessive rudeness | Studies disagree on direction | Trim. Default to professional. |
| "Think hard / be careful / it's important" intensifiers | Generalized EmotionPrompt; effect shrinks on reasoning models | **Strip on reasoning models.** Tolerable on non-reasoning. |
| "Let's think step by step" / zero-shot CoT | Works on non-reasoning models; redundant on reasoning | Keep on non-reasoning, strip on reasoning. |
| All-caps "CRITICAL" / "MUST" / "NEVER" | Over-triggers anti-laziness on Claude 4.5+ | Dial back to plain emphasis. |
| Repeating the same instruction 3 times | Mixed evidence | Trim. If a rule is important, *explain why* once instead of repeating. |

## What this means in practice

**Improver mode never just removes folklore silently.** Each strip:

1. Names the tactic.
2. Cites the study (one of the rows above).
3. States what the user might lose (usually: nothing measurable).
4. Offers a replacement if one exists.

Example annotation:

> Removed "I'll tip you $200 if you do this perfectly" — anti-pattern (folklore). Wharton GAIL ran ~5000 trials per condition across 5 frontier models and found no overall effect from tips or threats. Per-question swings of ±35% mean any anecdotal "it worked once" is variance. Replaced with concrete success criteria: "produce a complete answer covering A, B, and C."

## The variance trap

The reason these tactics persist: prompt outputs swing ±35% per question with no overall effect. *Anyone can confirm any folklore tactic anecdotally.* When users say "but it worked for me", the answer is: it worked for the *N* prompts you tried; controlled studies on thousands of trials show no effect.

Tell users: if they want to know whether a tactic works, set up an eval against a benchmark. See [eval-playbook.md](eval-playbook.md).

## What actually works (reliable winners)

- Clear instructions with explicit success criteria.
- Examples in the target output format.
- Structured sections (XML for Claude, markdown for GPT).
- Long context placed *before* the question.
- Explicit output schemas.
- Reasoning controls (extended thinking, `reasoning_effort`) — at the API level, not in prose.
- Decomposition for genuinely multi-step tasks.

These are the tactics to *add* when stripping folklore. Don't leave a hole.

## When users push back

If a user insists "but I read this works":

1. Acknowledge the source ("yes, that's from a 2023 paper / a popular X thread / etc.").
2. Note the date and what's changed (frontier models, replication studies).
3. Offer to A/B test it against the cleaner version per [eval-playbook.md](eval-playbook.md).
4. If they still want it, leave it in — it's their prompt. Annotate the diff so they know the tradeoff.
