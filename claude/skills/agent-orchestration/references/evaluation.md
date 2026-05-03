# Evaluating Multi-Agent Systems

How to validate and measure multi-agent designs without lying to yourself. End-state metrics, judge biases, variance control, cost-aware comparison, and the equal-budget test that decides whether multi-agent earns its keep.

## Contents

- [When to consult this](#when-to-consult-this)
- [Why multi-agent eval is harder](#why-multi-agent-eval-is-harder)
- [End-state vs path eval](#end-state-vs-path-eval)
- [The "20 queries is enough" lesson](#the-20-queries-is-enough-lesson)
- [End-state metrics that work](#end-state-metrics-that-work)
- [Process metrics that don't work](#process-metrics-that-dont-work)
- [LLM-as-judge](#llm-as-judge)
- [Judge biases and mitigations](#judge-biases-and-mitigations)
- [Variance reduction](#variance-reduction)
- [Cost-aware evaluation](#cost-aware-evaluation)
- [Equal-budget comparison](#equal-budget-comparison)
- [Public benchmarks](#public-benchmarks)
- [Internal eval design](#internal-eval-design)
- [Tracing as eval input](#tracing-as-eval-input)
- [Human evaluation](#human-evaluation)
- [Decision triggers](#decision-triggers)
- [Anti-patterns](#anti-patterns)
- [Sources](#sources)

## When to consult this

Read this when validating that a multi-agent design is worth shipping, comparing single-agent vs multi-agent at fair cost, designing an LLM-as-judge harness, picking a public benchmark, choosing variance-reduction tactics, or auditing why an existing eval gives noisy/contradictory results. Skip for pure prompt-engineering loops with no second agent involved.

## Why multi-agent eval is harder

Single-agent eval is tractable: input X → predictable trajectory → output Y. You can check intermediate steps, validate the trajectory, and assert on the final answer.

Multi-agent shatters this. From Anthropic's [How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system) (June 2025):

> "Agents make dynamic decisions and are non-deterministic between runs, even with identical prompts. This makes evaluation tricky."

Specific failure modes that compound under multi-agent:

- **Combinatorial trajectory space.** N agents × K tools each → trajectories explode. You cannot enumerate "correct paths."
- **Inter-agent coupling.** Agent A's output is Agent B's input. Small perturbations in A cascade through B and C, amplifying variance.
- **Emergent behaviors.** Coordination patterns appear that no single agent's prompt explicitly encoded — root-cause analysis is nontrivial.
- **Partial credit ambiguity.** A 70%-correct answer: subagent 2 hallucinated, or orchestrator didn't task subagent 4? Both, neither, and "depends on the seed" are all valid answers.

## End-state vs path eval

The framing that determines whether your eval will work at all. From the same Anthropic post:

> "Our state-of-the-art evals usually look like this: given input X, the system should follow path Y to produce output Z. But multi-agent systems don't work this way. Even with identical starting points, agents might take completely different valid paths to reach the same goal. One agent might search three sources while another searches ten, or they might use different tools to find the same answer."

**Path-based eval breaks on dynamic agents** because the system is *designed* to choose paths dynamically. Asserting on tool order, subagent count, or specific URLs visited punishes the system for doing its job.

**End-state eval is the only viable ground truth.** Did the output satisfy intent? At what cost? At what latency? Path data is still useful — but as **diagnostics**, not as pass/fail gates.

If X, do Y because Z:

- **If you cannot define an end-state quality metric**, do not ship the multi-agent system, because you will not be able to detect regressions.
- **If a stakeholder demands "the agent must call tool X first"**, push back, because that constraint converts a dynamic system into a brittle pipeline and forfeits the reason to use agents.

## The "20 queries is enough" lesson

From the Anthropic post:

> "Many AI evaluations assume you need large sample sizes for statistical significance. But with our agents, we found that you can often get clear signal with much smaller sample sizes — sometimes as few as 20 queries — when you're iterating on prompts that produce dramatically different behaviors. With effect sizes this large, you can spot changes with just a few test cases."

Why small N works during early development:

- Effect sizes are huge during prompt iteration (a fix moves success 30% → 70%); small N is enough to reject the null.
- Per-task costs are high — multi-agent runs burn many tokens and minutes — so 1000-task evals are economically infeasible early.
- Hand-curated tasks reveal failure modes that random sampling misses.
- Fast iteration loops (run → tweak → rerun in 30 minutes) compound faster than slow comprehensive evals.

When to scale up:

- Effect sizes shrink (changes now move success by 2–3pp, not 40pp). Statistical power matters.
- Shipping to production and need confidence intervals, not directional signal.
- Comparing two viable architectures within noise on the small set.
- Regression detection across many subtasks (per-domain breakdowns).
- External validity — small curated sets get overfit; you need held-out, freshly-collected tasks.

Recommended progression: **20 (dev) → 100–200 (pre-launch) → 1000+ (continuous regression)**.

## End-state metrics that work

These all assert on the *final output* without caring how the system got there.

| Metric | What it measures | When to use |
|---|---|---|
| **Factual accuracy** | Does the answer match ground truth? | Closed-form QA, lookup tasks |
| **Citation accuracy** | Does each citation actually support the claim it's attached to? | Research, summarization, RAG |
| **Completeness** | Did the answer cover all required points / sub-questions? | Multi-part questions, briefs |
| **Source quality** | Are the cited sources authoritative (not SEO spam)? | Research, due diligence |
| **Tool efficiency** | Tokens / tool calls used vs minimum sufficient | Cost control, latency |
| **Pass@k for code** | Probability ≥1 of k samples passes tests (k=1 strict, k=10 generous) | Code generation, SWE-bench |
| **Task completion rate** | Binary: did the agent finish the assigned task? | End-to-end agentic flows |
| **Calibration** | Does stated confidence (e.g. "I'm 80% sure") match empirical accuracy? | Decision-support, research |

Notes:

- **Citation accuracy** deserves a dedicated subagent for research systems — hallucinated citations are a dominant failure mode and trivial for an LLM judge to grade.
- **Calibration** is undermeasured. Brier score or expected calibration error (ECE) on confidence judgments tells you whether the agent knows when it doesn't know — essential for any system humans defer to.
- **Completeness** typically requires a rubric: enumerate the 5–10 facts/claims/sections a correct answer must contain, then have the judge mark each as present/absent.

## Process metrics that don't work

Do not assert on:

- Exact tool-call sequences (`["search", "search", "fetch", "synthesize"]`)
- Specific intermediate state values
- Number of subagents spawned
- Specific search queries issued
- Order of operations
- Specific URLs visited

Why they fail:

1. **Design intent conflict.** The whole point of an agentic system is dynamic decision-making.
2. **False negatives dominate.** A system that solves the task via a different path gets marked wrong, polluting your signal.
3. **Brittleness to model updates.** A new model with better priors picks different (better) trajectories; your eval breaks even though quality improved.
4. **Overfitting risk.** Optimizing toward a specific path discourages exploration and generalization.
5. **Non-stationarity.** Tool outputs change (web content updates, APIs return different data); the "correct" path drifts.

The exception: process metrics make sense as **diagnostics**, not gates. "On failures, what fraction skipped the planning step?" is a useful debugging signal, not a regression test.

## LLM-as-judge

The dominant pattern: a separate LLM scores outputs against a written rubric, returning **a 0.0–1.0 score plus a binary pass/fail plus a written justification**.

Why this scales:

- Thousands of evaluations without humans
- Consistent application of a written rubric
- Cheap (judge cost ≪ generation cost for multi-agent)
- Fast iteration loops
- Grades open-ended outputs that exact-match cannot

Required hygiene:

- **Rubric per task.** Decompose the score into specific criteria (factuality 0–1, completeness 0–1, citation quality 0–1) rather than holistic "how good is this." Forces the judge to look at substance.
- **Anchor examples.** Show the judge 1–2 calibration examples (known-good and known-bad with scores) in-context.
- **Chain-of-thought first, score second.** Reasoning before the score; scores produced first are post-hoc rationalizations.
- **Reference-based when possible.** "Compare candidate to this reference answer" is more reliable than "Is this answer good?"
- **Validate the judge.** Spot-check a sample with humans; measure judge–human agreement (Cohen's kappa, Krippendorff's alpha) before trusting at scale.

## Judge biases and mitigations

LLM judges have well-documented systematic biases. Budget for them or eliminate them.

| Bias | Description | Source | Mitigation |
|---|---|---|---|
| **Position bias** | Judges prefer the first (or last) of two options | Zheng et al. ([arXiv:2306.05685](https://arxiv.org/abs/2306.05685)) | Randomize A/B order across runs; average across positions |
| **Self-preference / family bias** | Judge prefers outputs from its own model family | Panickssery et al. ([arXiv:2404.13076](https://arxiv.org/abs/2404.13076)) | Use a different-family judge (Claude candidate → GPT/Gemini judge) |
| **Length bias** | Judges prefer longer, more verbose answers | Zheng et al. ([arXiv:2306.05685](https://arxiv.org/abs/2306.05685)) | Penalize length explicitly in rubric; cap candidate length |
| **Verbosity / authority bias** | Confident-sounding but wrong answers score higher | Multiple | Require citation-grounded rubric items |
| **Format bias** | Bulleted/structured answers preferred regardless of substance | — | Score substance separately from formatting; use reference comparisons |
| **Sycophancy** | Judge agrees with framing in the prompt | — | Strip framing from judge prompt; show only candidate + rubric |
| **Lost-in-the-middle** | Judge under-weights mid-context content in long outputs | Liu et al. ([arXiv:2307.03172](https://arxiv.org/abs/2307.03172)) | Keep judge inputs short; chunk long outputs |

The single highest-leverage mitigation is the **Panel of LLM Judges (PoLL)** — Verga et al., [Replacing Judges with Juries](https://arxiv.org/abs/2404.18796) ([arXiv:2404.18796](https://arxiv.org/abs/2404.18796)). Use 3+ smaller judges from different families and aggregate (mean, median, or majority vote). Often outperforms a single large judge AND is cheaper.

If X, do Y because Z:

- **If your candidate is Claude and your judge is Claude**, switch to a different-family judge (or PoLL with mixed families), because self-preference inflates scores 5–15%.
- **If you only run pairwise comparisons in one A/B order**, randomize across runs, because position bias systematically favors one slot.
- **If your judge produces a score before its reasoning**, flip the order, because scores written first become anchors that the reasoning rationalizes.

## Variance reduction

Multi-agent eval has variance from **two independent sources**: candidate stochasticity and judge stochasticity. Both need taming.

Candidate-side:

- **Run N times per task.** N=3 minimum; N=5–10 if cost permits. Report mean ± std.
- **Fix random seeds where possible** (caveat: most LLM APIs do not honor seed reliably).
- **Block on tasks.** Do not compare "Method A on tasks 1–50 vs Method B on tasks 51–100" — run both methods on the same tasks (paired comparison).
- **Pass@k aggregation** for code: report pass@1 and pass@10 to separate "best-effort" from "lucky."

Judge-side:

- **Multi-judge averaging (PoLL):** 3 judges' mean is far less noisy than 1.
- **Bootstrap resampling** of (task, run, judge) triples to compute confidence intervals.
- **Inter-rater reliability monitoring:** if two judges disagree wildly, your rubric is underspecified — fix it before scaling.

Statistical design:

- **Paired comparisons** beat independent samples by 2–4× in power.
- **Stratified sampling** across task difficulty / domain so a hard subdomain does not dominate.
- **Sequential testing** (always-valid p-values) to stop early when significance is reached and save tokens.
- **Use effect-size thresholds**, not just p-values. A statistically significant 0.3pp improvement is operationally meaningless.

If X, do Y because Z:

- **If you report a single point estimate without std/CI**, add N≥3 runs per task, because point estimates with std ~5pp falsely make 2pp differences look meaningful.
- **If two judges in your panel disagree by >0.3 on identical inputs**, rewrite the rubric, because the disagreement is rubric ambiguity, not judge noise.

## Cost-aware evaluation

A multi-agent system can win on accuracy and lose catastrophically on economics. From the Anthropic post:

> "Multi-agent systems use about 15× more tokens than chats. For economic viability, multi-agent systems require tasks where the value of the task is high enough to pay for the increased performance."

Per-task metrics to log:

- **Input + output tokens** (and cache reads — prompt caching changes economics)
- **Total tool calls** (browser fetches, code executions, API hits)
- **Wall-clock latency** (p50, p95, p99) — important for UX
- **Total dollar cost** at posted API prices
- **Subagent count** spawned per query
- **Cost-per-correct-answer (CPCA)** = total cost / number of tasks the system got right

CPCA is the killer metric. Worked example:

- Multi-agent system: 80% accuracy, $1.00/query → CPCA = $1.25
- Single agent: 70% accuracy, $0.10/query → CPCA = $0.143
- The single agent is **8.7× more economically efficient per correct answer**, even though multi-agent is "better" on raw accuracy.

Plot accuracy on Y, cost on X, look at the **Pareto frontier**. Anything off the frontier is dominated.

Latency is its own thing. Multi-agent often parallelizes, so wall-clock latency may be acceptable even when token count is huge. But serial coordination (orchestrator → wait → synthesize) compounds tail latency badly. Always report p95, not just mean.

If X, do Y because Z:

- **If you report accuracy without CPCA**, add it before shipping, because architectures that look "better" often lose by 5–10× on cost-per-correct.
- **If you only report mean latency**, add p95, because serial coordination patterns hide in the tail and surface as user complaints.

## Equal-budget comparison

The most important and most-often-skipped comparison in the multi-agent literature.

Reference: *Single-Agent LLMs Outperform Multi-Agent Systems on Multi-Hop Reasoning Under Equal Thinking Token Budgets* ([arXiv:2604.02460](https://arxiv.org/abs/2604.02460)). Key finding: when a single agent gets the same number of "thinking tokens" (chain-of-thought / extended thinking) that a multi-agent system would consume, the single agent often matches or beats the multi-agent system on multi-hop reasoning tasks.

Most multi-agent papers compare a multi-agent system using N tokens to a single agent using N/k tokens. That is not a fair fight — you are comparing more compute to less compute and attributing the win to "multi-agent" when it is actually "more compute."

How to do equal-budget comparison:

1. Measure total tokens (input + output, all calls) consumed by your multi-agent system on the eval set.
2. Run a single agent with **extended thinking budget** or **best-of-N sampling** scaled to the same total token count.
3. Compare end-state quality.
4. If single-agent matches or beats multi-agent at equal budget → **do not multi-agent**. The complexity is not earning its keep.

When multi-agent legitimately wins:

- **Parallelizable subtasks** where wall-clock latency matters (research with many independent sub-queries).
- **Specialization** where different subagents need genuinely different tools or contexts.
- **Context-window limits** where a single agent literally cannot fit the work.
- **Diversity-of-perspective** tasks (debate, critique) where independent runs catch different errors.

If none of these apply, single-agent at equal budget will likely win on cost AND complexity AND debuggability.

If X, do Y because Z:

- **If you have not run a single-agent baseline at equal token budget**, run it before shipping, because the multi-agent win may evaporate and you will have spent complexity for nothing.
- **If your task has none of the four legitimate-win conditions above**, default to single-agent + extended thinking, because the equal-budget literature ([arXiv:2604.02460](https://arxiv.org/abs/2604.02460)) says it usually wins.

## Public benchmarks

Use for sanity-checking and external comparison. Do not use for shipping decisions — always build your own internal eval too.

| Benchmark | What it measures | What it misses | Transfer to your domain |
|---|---|---|---|
| **GAIA** ([arXiv:2311.12983](https://arxiv.org/abs/2311.12983)) | General AI assistant tasks: tool use, multi-step reasoning, web browsing. 466 questions, 3 difficulty levels. | Long-horizon planning; closed-domain expertise; collaborative writing. Unambiguous scoring masks real-use ambiguity. | High for general research/assistant agents; low for code or domain-specific. |
| **SWE-bench** ([arXiv:2310.06770](https://arxiv.org/abs/2310.06770)) | Resolving real GitHub issues from 12 Python repos. Hidden test suites. | Test-driven bias; Python-only; assumes the test suite captures correctness. | Good for code-fix agents; misses greenfield design, multi-language, frontend. |
| **SWE-bench Verified** ([OpenAI](https://openai.com/index/introducing-swe-bench-verified/)) | 500-task subset validated by humans for solvability and test correctness. | Same as SWE-bench but smaller. Better signal per task. | Currently the gold standard for code agents; widely reported in model releases. |
| **AgentBench** ([arXiv:2308.03688](https://arxiv.org/abs/2308.03688)) | 8 environments (OS, DB, KG, card games, web shopping, etc.) testing reasoning + decision-making. | Each env is narrow; no cross-environment transfer test. | Useful for breadth signal; weak for deep domain expertise. |
| **BrowseComp** ([OpenAI](https://openai.com/index/browsecomp/)) | Hard web-research questions requiring persistent browsing and synthesis (~1,266 questions). | Heavy English/web bias; tests retrieval more than reasoning. | High for research/browsing agents; irrelevant for code. |
| **WebArena** ([arXiv:2307.13854](https://arxiv.org/abs/2307.13854)) | Realistic web tasks across 4 self-hosted sites (e-commerce, GitLab, Reddit, maps). | Simulated environments diverge from real production sites; no login/captcha/payment flows. | Best public benchmark for browser agents; results modestly transfer. |
| **τ-bench** ([arXiv:2406.12045](https://arxiv.org/abs/2406.12045)) | Tool-agent-user interaction in airline / retail customer service domains. Conversational tool use with policy compliance. | Two domains only; English; turn-based not real-time. | Excellent for customer-service or policy-following agents; less for research. |

Cross-cutting cautions:

- **Contamination.** Most of these are now in pretraining sets. Treat absolute numbers skeptically; trust *relative* comparisons between methods you control.
- **Saturation.** SWE-bench is climbing toward saturation; differences between top systems are small and within noise.
- **Domain mismatch.** A system that wins GAIA might lose on your internal eval because the failure modes are different.

## Internal eval design

From the Anthropic post:

> "Start small with about 20 queries that represent real usage patterns. As you iterate on your agents, you can identify failure modes systematically and refine your evaluation accordingly."

Recommended structure:

1. **~20 hand-curated tasks** representing real user queries. Stratify across:
   - Easy / medium / hard
   - Each top-level use case (research, code, browsing, writing…)
   - Known failure modes (long-tail entities, ambiguous queries, conflicting sources)
2. **Frozen ground truth** — written reference answers, expected citations, expected facts.
3. **Rubric per task** — completeness checklist, factual claims to verify.
4. **Run on every prompt change.** No exceptions. Cheap discipline that catches regressions immediately.
5. **Report:** per-task pass/fail, aggregate score with std, cost per task, latency, list of regressions vs previous version.
6. **Version the eval** in git alongside the agent code. The eval IS part of the system.

Growth path:

- 20 (dev) → catches gross errors during prompt iteration
- 100–200 (pre-ship) → confidence intervals tight enough to make ship/no-ship calls
- 1000+ (continuous, sampled from production logs) → drift detection and long-tail coverage

If X, do Y because Z:

- **If you observe a production failure not represented in eval**, add it that day, because eval drift is the #1 cause of regressions slipping through.
- **If your eval set is >500 tasks but signal per task is low**, trim to 50 high-signal tasks, because iteration speed beats sample size early on.

## Tracing as eval input

Metrics tell you **what** broke; traces tell you **why**.

What to log (OpenTelemetry, LangSmith, Arize Phoenix, or Anthropic's own tracing):

- Decision points (which branch the orchestrator chose, with reasoning)
- Agent boundaries (when subagents spawn, complete, fail)
- Tool invocations: name, latency, success/error, token usage
- Token counts per LLM call
- Inter-agent message **structure** (sender, receiver, timestamp) — **NOT message bodies if PII risk**
- Error stack traces and retries
- Final-answer assembly steps

What NOT to log without explicit policy:

- Raw user query content (PII risk)
- Raw model outputs (may contain user data)
- Tool input/output bodies (often contain user data)
- API credentials in tool args

The pattern Anthropic describes: trace decision patterns and interaction structure in production, not the conversation contents. This gives you debuggability without privacy exposure.

Use traces to:

- **Cluster failures** by trajectory shape ("80% of failures take this branch in step 3")
- **Find efficiency wins** (subagent N is always called but never used)
- **Detect coordination bugs** (two subagents do the same work)
- **Compute path-frequency statistics** as diagnostics, not as gates
- **Reconstruct individual failures** for root-cause analysis

Traces are an input to *understanding*, not a substitute for end-state metrics.

If X, do Y because Z:

- **If your trace logger captures message bodies**, switch to structure-only logging, because contents leak PII and create compliance burden without adding diagnostic value over structure.
- **If two subagents repeatedly do redundant work in traces**, simplify the topology before re-evaluating, because you will otherwise just be evaluating waste.

## Human evaluation

LLM-as-judge plateaus when the task is **subjective**, **multi-objective**, or **outside the judge's competence**.

Use humans when:

- **Subjective quality.** Writing tone, humor, persuasiveness, design taste.
- **Multi-objective tradeoffs.** "Is this better — more concise but less complete?" Humans synthesize tradeoffs in ways rubrics struggle to.
- **Novel domains.** Judge model lacks expertise (specialized medicine, legal nuance, current events post-cutoff).
- **High-stakes decisions.** Production launch, safety review, regulatory compliance.
- **Calibrating the judge itself.** Periodic spot-checks to verify judge–human agreement is not drifting.
- **Ground-truth construction.** Reference answers and rubrics for new evals should be human-authored.

Practical setup:

- 2–3 raters per item; report inter-rater agreement (Cohen's kappa, Krippendorff's alpha).
- Blind raters to which system produced which output.
- Randomize order.
- Budget for it: ~1–5 minutes per rating × hundreds of items = real money. Reserve human eval for the questions LLM judges genuinely cannot answer.
- Use it to **train and validate** the LLM judge, then switch to LLM judge for scale once agreement is high (>0.7 kappa).

[LMSYS Chatbot Arena](https://lmsys.org/blog/2023-05-03-arena/) is the canonical example of pairwise human judgment at scale, using Bradley-Terry / Elo to aggregate noisy pairwise preferences into rankings — a useful pattern for in-house systems too.

## Decision triggers

Mechanical rules. Apply in order.

1. **If you cannot define an end-state quality metric**, do not ship the multi-agent system, because you cannot detect regressions.
2. **If single-agent at equal token budget matches multi-agent on your eval**, use single-agent, because the complexity is not earning its keep ([arXiv:2604.02460](https://arxiv.org/abs/2604.02460)).
3. **If using LLM-as-judge**, use ≥3 judges from different model families (PoLL — [arXiv:2404.18796](https://arxiv.org/abs/2404.18796)) OR randomize position across runs, because otherwise self-preference and position bias are systematic error.
4. **If a prompt change is being evaluated**, run it on a fixed eval set, repeated N≥3 times per task, and report mean AND std, because point estimates lie.
5. **If costs are not measured per-task**, add token + dollar + latency tracking before shipping, because you are flying blind on the swarm tax.
6. **If the end-state metric is fuzzy** ("did the user like it?"), invest in rubric design before scaling agent count, because vague metric × more agents = more confusion.
7. **If your eval set is >500 tasks but signal per task is low**, trim to 50 high-signal tasks, because iteration speed beats sample size early.
8. **If you observe a failure mode in production not represented in eval**, add it that day, because eval drift is the #1 cause of regressions slipping through.
9. **If two subagents do redundant work in traces**, simplify before evaluating, because you will just be evaluating waste.
10. **If your judge agrees with itself <90% of the time on identical inputs**, lower temperature or tighten the rubric, because rubric ambiguity is masquerading as judge noise.
11. **If shipping a customer-facing system**, require human eval on a sampled subset for 2 weeks post-launch, because LLM judges miss UX failures.
12. **If comparing to published benchmarks**, reproduce the baseline yourself first, because reported numbers are often inflated by contamination, prompt tuning, or different eval harnesses.

## Anti-patterns

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| **Path-based eval on dynamic systems** | Punishes the system for its own design; false negatives dominate | End-state eval only; use traces for diagnostics |
| **Single judge in same family as candidate** | Self-preference inflates scores 5–15% ([arXiv:2404.13076](https://arxiv.org/abs/2404.13076)) | Different-family judge or PoLL panel of 3+ |
| **Comparing multi-agent to single-agent at unequal budgets** | Attributes "more compute" win to "multi-agent" architecture | Equal-budget comparison with extended thinking / best-of-N ([arXiv:2604.02460](https://arxiv.org/abs/2604.02460)) |
| **Massive eval set with low signal per task** | Slow iteration, weak signal, often overfit to easy cases | 20–50 high-signal tasks during dev, scale later |
| **Eval only on accuracy, ignoring cost/latency** | Ships systems that work in lab and bankrupt in production | CPCA, p95 latency, dollar cost per task |
| **No variance reporting** | Point estimates with std ~5pp falsely look like 2pp differences are meaningful | N≥3 runs, report mean ± std with CIs |
| **Frozen eval, drifting production** | Eval scores climb while user complaints rise | Sample fresh tasks from production into the eval monthly |
| **Judge sees the candidate's name/version** | Halo / framing effects | Blind the judge to system identity |
| **Aggregating only the headline number** | Hides per-domain regressions ("up 2pp overall, down 15pp on code") | Always report per-stratum breakdowns |
| **Optimizing eval score directly** | Goodhart's law; system gets gamed to the rubric | Hold out a secondary "trust" eval the team never optimizes against |
| **No retry / no error handling in eval harness** | One flaky API call kills 4 hours of eval; results biased toward early-completing tasks | Idempotent retries with logging; track error rates as their own metric |
| **Treating LLM judge scores as cardinal** | They are ordinal at best; differences of 0.05 on 0–1 are noise | Rank-based stats or large effect-size thresholds |
| **Logging full message bodies in production traces** | PII exposure, compliance burden, no added diagnostic value | Log structure only (sender, receiver, timestamp, decision branch) |

## Sources

- Anthropic, *How we built our multi-agent research system* (June 2025) — primary source for the 20-query lesson, end-state vs path framing, and 15× token-cost figure: <https://www.anthropic.com/engineering/built-multi-agent-research-system>
- GAIA — Mialon et al., [arXiv:2311.12983](https://arxiv.org/abs/2311.12983)
- SWE-bench — Jimenez et al., [arXiv:2310.06770](https://arxiv.org/abs/2310.06770)
- SWE-bench Verified — OpenAI: <https://openai.com/index/introducing-swe-bench-verified/>
- AgentBench — Liu et al., [arXiv:2308.03688](https://arxiv.org/abs/2308.03688)
- WebArena — Zhou et al., [arXiv:2307.13854](https://arxiv.org/abs/2307.13854)
- τ-bench — Yao et al., [arXiv:2406.12045](https://arxiv.org/abs/2406.12045)
- BrowseComp — OpenAI: <https://openai.com/index/browsecomp/>
- PoLL (Replacing Judges with Juries) — Verga et al., [arXiv:2404.18796](https://arxiv.org/abs/2404.18796)
- LLM-as-a-Judge biases — Zheng et al., *Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena*, [arXiv:2306.05685](https://arxiv.org/abs/2306.05685)
- Self-preference bias — Panickssery et al., *LLM Evaluators Recognize and Favor Their Own Generations*, [arXiv:2404.13076](https://arxiv.org/abs/2404.13076)
- Lost-in-the-Middle — Liu et al., [arXiv:2307.03172](https://arxiv.org/abs/2307.03172)
- Equal-budget comparison — *Single-Agent LLMs Outperform Multi-Agent Systems on Multi-Hop Reasoning Under Equal Thinking Token Budgets*, [arXiv:2604.02460](https://arxiv.org/abs/2604.02460)
- LMSYS Chatbot Arena methodology: <https://lmsys.org/blog/2023-05-03-arena/>
