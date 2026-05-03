# Eval playbook

If the user wants to know whether a prompt edit actually helped, set up an eval. Vibes don't measure anything.

## Contents

- [The minimum eval that beats vibes](#the-minimum-eval-that-beats-vibes)
- [When to scale up](#when-to-scale-up)
- [Error analysis FIRST, evals second](#error-analysis-first-evals-second)
- [LLM-as-judge — the rules](#llm-as-judge--the-rules)
- [Pairwise comparison (when scoring is unstable)](#pairwise-comparison-when-scoring-is-unstable)
- [Statistical sanity](#statistical-sanity)
- [Production rollout](#production-rollout)
- [Tools](#tools)
- [What this skill does at the end of generate / improve](#what-this-skill-does-at-the-end-of-generate--improve)
- [Cap self-critique loops](#cap-self-critique-loops)
- [Date-gated holdouts (avoid contamination)](#date-gated-holdouts-avoid-contamination)
- [Quick rubric template](#quick-rubric-template)

## The minimum eval that beats vibes

5 minutes, 5–10 input/output pairs hand-graded in a markdown table:

| # | Input | Old prompt output | New prompt output | Better? (Y/N/Tie) | Notes |
|---|-------|-------------------|-------------------|-------------------|-------|

If new beats old on ≥7/10 with no obvious regressions, ship. If results split, you need a bigger eval.

## When to scale up

| Eval tier | When to use | What it looks like |
|---|---|---|
| **Ad-hoc** (5–10 cases, hand-graded) | Quick "did this help?" check | Markdown table in a notebook |
| **Tracked** (50 cases, in git) | Iterating over multiple prompts on same task | promptfoo YAML, evals/evals.json |
| **CI-gated** (100–500 cases, automated) | Production prompt; team uses it | Braintrust / promptfoo in CI; blocks merges on regression |
| **Production A/B** (live traffic) | High-stakes, can't fully test offline | Stable user_id hashing, 1→10→25→50→100% canary |

## Error analysis FIRST, evals second

Hamel Husain's framing: "Eval-driven development creates more problems than it solves." LLM failure modes are not predictable — write evals for the failures you observe, not the ones you imagine.

Workflow:
1. **Read 50–100 real outputs.** Open-code each into a failure category.
2. **Stop when ~20 new outputs add no new category.**
3. **Build judges/assertions for the failures you saw.**
4. *Then* iterate on the prompt.

Reading the outputs is the work. Skip it and the eval suite measures the wrong things.

## LLM-as-judge — the rules

If you use an LLM to grade outputs:

1. **Different model class as judge than as generator.** Self-preference bias is real and measured.
2. **Binary > Likert.** Pass/fail forces clarity. Likert hides variance.
3. **Calibrate against human labels.** Aim for high TPR + TNR or κ ≥ 0.6 vs human on a 100-item set.
4. **Discard the reasoning.** Anthropic-recommended pattern: ask the judge to think in `<thinking>` then output `<result>correct|incorrect</result>`. Throw away the trace.
5. **One dimension per judge.** Multi-criteria rubrics in one call confound. Run separate judges for accuracy, tone, safety, etc.
6. **Pin the judge model version.** When you upgrade the judge, you've changed the ruler.

## Pairwise comparison (when scoring is unstable)

When absolute scoring drifts, switch to pairwise: "Is A better than B?"

- **Always randomize position.** Run both A-first and B-first.
- If results flip, position bias dominates. Fix the eval.
- Control for length to neutralize verbosity bias.

## Statistical sanity

- ≥30–50 items for a directional read.
- ≥100–200 for a stable kappa.
- Bootstrap for confidence intervals.
- McNemar / paired-bootstrap for binary outcomes when comparing two prompts on the same items.

## Production rollout

- Hash on `user_id` for stable A/B assignment (one user always sees one variant).
- Canary at 1% → 10% → 25% → 50% → 100%. Watch guardrail metrics at each step.
- For asymmetric impact, use Thompson sampling instead of fixed split.

## Tools

| Tool | Strength | When to pick |
|---|---|---|
| **promptfoo** | OSS CLI, YAML test cases, CI/CD-native, red-teaming | Engineers who want git-tracked evals |
| **Anthropic Console Evals** | Native Claude integration, browser UI | Already on Claude; want fastest iteration |
| **Inspect (UK AISI)** | 200+ pre-built evals, sandboxing, agent-bridge | Agent eval, safety/capability research |
| **Braintrust** | End-to-end: playground → CI gates → prod tracing; auto-blocks regressing PRs | Teams that need eval to gate deploys |
| **LangSmith** | Native LangChain/LangGraph hooks | LangChain users |
| **Helicone** | One-line proxy → automatic logging + experiments | Want observability first |
| **Langfuse** | OSS observability + prompt mgmt + A/B | OSS-preferring teams |

## What this skill does at the end of generate / improve

When the skill outputs a prompt, it should also output:

1. **3 test inputs** the user can run against the prompt.
2. **A judge rubric** — one binary criterion per dimension that matters (accuracy, format, tone). Calibrate later.
3. **A pointer to this playbook** if the user wants to scale up.

If the user asks "is this better than the old one?", run the 5–10-case ad-hoc eval first. Don't propose Braintrust until they've done at least that.

## Cap self-critique loops

Same-model self-improvement degrades after 1 iteration without external signal. The skill never runs more than 1 critique pass on its own. If the user wants more iterations, require:

- **A different model class as critic**, OR
- **An external eval set / metric** to break out of the loop, OR
- **Human approval** between rounds.

Otherwise stop.

## Date-gated holdouts (avoid contamination)

Public benchmarks (MMLU, HumanEval, HellaSwag, GSM8K) are effectively retired due to training contamination. For any benchmark you care about:

- Keep a private holdout dated *after* the model's training cutoff (LiveCodeBench pattern).
- Rotate it.
- Don't post the holdout publicly.

## Quick rubric template

For a generic prompt review, the eval might be:

```yaml
prompts:
  - id: pricing-extractor
    input: "Sample receipt text..."
    expected:
      total: 42.31
      currency: USD
      line_items: 3
    assertions:
      - type: contains-json
        path: total
        value: 42.31
      - type: latency-under
        ms: 5000
      - type: token-budget-under
        tokens: 800
```

Concrete, mechanical, reproducible. Always better than "the new prompt feels nicer."
