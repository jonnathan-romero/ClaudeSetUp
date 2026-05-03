# Reasoning models

Reasoning models (Claude with extended thinking, OpenAI o-series, GPT-5/5.1, DeepSeek-R1, Gemini 2.5 Thinking) invert several long-standing rules. The model already does chain-of-thought internally; the prompt's job changes from *teaching it to think* to *stating the goal cleanly and getting out of the way*.

## Rules that flip

| Rule | Non-reasoning | Reasoning |
|---|---|---|
| "Think step by step" / CoT scaffolding | Helps on math/logic | Redundant or harmful — drop it |
| Few-shot examples | Often helps | Try zero-shot first; R1: "consistently degrades" |
| Procedural micromanagement | Often helps | Hurts — state the goal, let the model plan |
| Conflicting / vague instructions | Tolerated | GPT-5 burns reasoning tokens reconciling |
| Persona for cognitive ability | Sometimes noise | Always noise — internal reasoning already engaged |
| "Be thorough / exhaustive" tone | Often helps | GPT-5: backfires (causes redundant tool loops) |
| Long context with irrelevant info | Tolerated | Larger overthinking penalty (Anthropic inverse-scaling) |

## Rules that stay

- Clear delimiters (XML/markdown/sections).
- Explicit output format spec — but don't over-constrain (rigid templates can interfere with the reasoning trace).
- Role / context up front.
- Persona for *tone*.
- Static prefix → variable suffix for caching.

## Per-model quirks

### Claude with extended thinking
- Adaptive budget on Sonnet 4.6 / Opus 4.7+ — manual `budget_tokens` deprecated, may 400.
- Tool use restricted to `tool_choice: auto` or `none`. Forced selection forbidden.
- Thinking blocks must round-trip with tool calls (pass them back unchanged).
- Don't say "think step by step" — extended thinking handles it. Anthropic explicitly: avoid asking to "think step by step" when extended thinking is on.

### OpenAI o-series (o1, o3, o4-mini)
- Use **developer messages** instead of system messages.
- Skip CoT scaffolding. Skip few-shot when possible.
- Markdown is suppressed by default — add "Formatting re-enabled" on line 1 of the developer message to re-enable.
- `reasoning_effort`: `low` / `medium` / `high`.

### GPT-5 / GPT-5.1
- `reasoning_effort` (`minimal` / `low` / `medium` / `high`) and `verbosity` API parameters.
- GPT-5.1 adds `none` mode (forces zero reasoning tokens — useful for retrieval/formatting).
- Disproportionately damaged by contradictory instructions. Audit aggressively.

### DeepSeek-R1
- **Avoid system prompt.** Put all instructions in the user turn.
- **Do not provide examples.** Consistently degrades performance.
- Temperature 0.5–0.7 (0.6 recommended), top_p 0.95.
- Drop CoT scaffolding completely.

### Gemini 2.5
- 2.5 Pro: dynamic thinking by default (128–32768), can't be disabled.
- 2.5 Flash: 0–24576 tokens (set 0 to disable).
- 2.5 Flash Lite: doesn't think by default — treat as classic non-reasoning.

## Failure modes specific to reasoning models

1. **Overthinking on easy tasks.** Anthropic 2025 study: extended reasoning shows "inverse scaling in test-time compute" — accuracy *degrades* with more thought, especially with irrelevant context. Mitigation: lower effort or switch to non-reasoning model.
2. **Endless thought loops on missing-premise questions.** When the user's question lacks information needed to answer, reasoning models often generate dramatically long responses without abstaining.
3. **Thought-trace leakage.** The reasoning channel can leak sensitive context. Don't put secrets in any input the model sees.
4. **Contradiction reconciliation.** GPT-5 in particular burns budget reconciling conflicting rules. Single-source instructions.

## When to use a reasoning model

Use reasoning when:
- Multi-step math, formal logic, or proofs.
- Code that requires planning across files / debugging non-trivial bugs.
- Research synthesis where multiple constraints must be jointly satisfied.
- High-stakes decisions where accuracy >> latency.
- Non-reasoning model has demonstrably failed.

Use non-reasoning when:
- Retrieval, lookup, classification, tagging.
- Summarization, translation, rewrites, formatting.
- Bulk / streaming workloads with tight latency SLOs.
- Simple Q&A from provided context.
- Cost is the binding constraint.

Hybrid pattern: reasoning model plans, non-reasoning model executes.

## How to rewrite a prompt for a reasoning model

If the prompt was written for GPT-4-class and is being ported to a reasoning model:

1. Strip "let's think step by step", "first do X then Y then Z", numbered procedural plans.
2. Drop few-shot examples unless the desired output format is unusual.
3. Compress the system message; reasoning models don't need scaffolding.
4. Replace "be thorough" / "be exhaustive" tone with concrete success criteria.
5. Audit for instruction contradictions — reasoning tokens are expensive.
6. For DeepSeek-R1, additionally: move everything into the user turn, drop all examples, set temperature 0.6.
7. For o-series, additionally: convert to a developer message, add "Formatting re-enabled" if markdown output is wanted.

## What to leave alone

Reasoning models still benefit from:
- Clear role / context block.
- Explicit output format / schema.
- Tagged delimiters between content types.
- Tool definitions in the API field (not inline).
- Static-prefix / variable-suffix layout for caching.
