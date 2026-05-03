# Cost and Latency Engineering

How to budget and optimize a multi-agent design before spawning anything. The 15× token multiplier is real; caching, tier-routing, and batching are the levers that make it survivable.

## Contents

- [When to consult this](#when-to-consult-this)
- [The 15× token reality](#the-15-token-reality)
- [Pricing tables (May 2026)](#pricing-tables-may-2026)
- [Prompt caching basics](#prompt-caching-basics)
- [How parallel sub-agents break caching](#how-parallel-sub-agents-break-caching)
- [Model-tier routing](#model-tier-routing)
- [Batching](#batching)
- [Time-to-first-token (TTFT)](#time-to-first-token-ttft)
- [Slowest-of-N tail latency](#slowest-of-n-tail-latency)
- [Streaming as a UX patch](#streaming-as-a-ux-patch)
- [Cost-per-correct-answer (CPCA)](#cost-per-correct-answer-cpca)
- [Per-task cost math](#per-task-cost-math)
- [Caching across sub-agents](#caching-across-sub-agents)
- [Pre-fetching shared data](#pre-fetching-shared-data)
- [Decision triggers](#decision-triggers)
- [Anti-patterns](#anti-patterns)
- [Sources](#sources)

## When to consult this

Read this when budgeting a multi-agent design, choosing topology under a cost cap, deciding model tier per role, sizing fan-out N, evaluating whether to use the Batch API, debugging unexpectedly high token spend, or chasing tail latency in parallel fan-out. Skip for single one-shot agent calls or pure UX-latency questions that don't involve fan-out.

## The 15× token reality

From Anthropic's June 13, 2025 engineering post [How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system):

- **"multi-agent systems use about 15× more tokens than chats"**
- **"agents typically use about 4× more tokens than chat interactions"**
- **"token usage by itself explains 80% of the variance"** on Anthropic's internal BrowseComp eval. The remaining ~20% splits between tool-call count and model choice.
- The winning topology: **"a multi-agent system with Claude Opus 4 as the lead agent and Claude Sonnet 4 subagents outperformed single-agent Claude Opus 4 by 90.2% on our internal research eval."**
- Anthropic's gating rule: **"For economic viability, multi-agent systems require tasks where the value of the task is high enough to pay for the increased performance."**

Translate the multiplier: a query that costs $0.10 as a chat costs ~$1.50 as a multi-agent run. The multiplier needs >15× headroom on value, latency reduction, or accuracy — otherwise multi-agent loses on economics regardless of how clever the topology is. Anthropic explicitly says multi-agent shines on **"valuable tasks that involve heavy parallelization, information that exceeds single context windows, and interfacing with numerous complex tools"** and names coding as a poor fit because **"most coding tasks involve fewer truly parallelizable tasks than research."**

## Pricing tables (May 2026)

All prices per million tokens. Source: [Claude API pricing](https://platform.claude.com/docs/en/about-claude/pricing).

| Model | Input | Output | 5-min Write | 1-hr Write | Cache Hit | Batch In | Batch Out |
|---|---|---|---|---|---|---|---|
| Opus 4.7 | $5.00 | $25.00 | $6.25 | $10.00 | $0.50 | $2.50 | $12.50 |
| Opus 4.6 | $5.00 | $25.00 | $6.25 | $10.00 | $0.50 | $2.50 | $12.50 |
| Opus 4.5 | $5.00 | $25.00 | $6.25 | $10.00 | $0.50 | $2.50 | $12.50 |
| Sonnet 4.6 | $3.00 | $15.00 | $3.75 | $6.00 | $0.30 | $1.50 | $7.50 |
| Sonnet 4.5 | $3.00 | $15.00 | $3.75 | $6.00 | $0.30 | $1.50 | $7.50 |
| Haiku 4.5 | $1.00 | $5.00 | $1.25 | $2.00 | $0.10 | $0.50 | $2.50 |

Notes:
- Opus 4 / 4.1 are legacy at $15/$75; the 4.5+ generation dropped to $5/$25.
- **Tokenizer caveat.** Opus 4.7 uses a new tokenizer that **"may use up to 35% more tokens for the same fixed text"** than prior generations. Effective Opus 4.7 cost on English text is ~1.35× the headline rate. Factor this in when comparing 4.7 to 4.6.

Multipliers stack:
- Cache hit: ×0.10 of base input
- Batch: ×0.50 of base input and output
- **Cache hit + batch: ×0.05 of base input (95% off)**

## Prompt caching basics

### Claude

From [the prompt caching docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching):

| Operation | Multiplier on base input |
|---|---|
| Base input | 1.00× |
| 5-min cache write | **1.25×** |
| 1-hour cache write | **2.00×** |
| Cache hit (read or refresh) | **0.10×** (90% discount) |

- Default TTL: **5 minutes ephemeral**, refreshed at no additional cost on each hit.
- Extended TTL: **1 hour** via `cache_control: {"type": "ephemeral", "ttl": "1h"}`.
- Up to **4 cache breakpoints** per request.
- Lookback window for prior cache entries: **20 blocks**.
- Minimum cacheable prefix:
  - Opus 4.7 / 4.6 / 4.5 / Haiku 4.5 → **4096 tokens**
  - Sonnet 4.6 / Haiku 3.5 → 2048 tokens
  - Older Opus 4.1/4, Sonnet 4/4.5 → 1024 tokens
- Caches are **isolated per organization** (per-workspace starting Feb 5, 2026).
- Cache hierarchy: `tools → system → messages`. **Changing a tool definition invalidates everything below it.**
- Break-even: a 5-min write pays off after **1 hit**; a 1-hour write pays off after **2 hits**.
- Critical placement rule: **place `cache_control` on the last block whose prefix is identical across the requests you want to share a cache.** Putting `cache_control` on a per-request block (timestamp, session ID, user message) silently fails to share — you write a fresh entry every time and never read.

### OpenAI

From [OpenAI's prompt caching announcement](https://openai.com/index/api-prompt-caching/):

- **Automatic** caching on GPT-4o and newer — no `cache_control` field.
- GPT-4o family: **50%** discount on cached input.
- GPT-5 family: **up to 90%** discount.
- Minimum prefix: **1024 tokens**, hits in **128-token increments**.
- Exact prefix match required.

### Gemini

From [Gemini context caching docs](https://ai.google.dev/gemini-api/docs/caching):

- **Implicit caching enabled by default** for Gemini 2.5 and newer.
- Cost reduction: **~90%** on cache hits.
- Explicit caching available: pay reduced input rate plus storage at **$4.50/M tokens/hour (Pro)** or $1.00/M/hr (Flash).
- Min cacheable prefix: 4096 (Pro), 1024 (Flash).

### Cross-provider summary

All three majors converge on stable-prefix → ~10% of input cost. Differentiator: Claude is **manual + explicit** (you choose breakpoints); OpenAI and Gemini are **automatic** (easier, less surgical). For multi-agent designs, manual control matters because you need to force-share prefixes across sub-agent contexts.

## How parallel sub-agents break caching

This is the most under-discussed cost trap in multi-agent design.

**Each sub-agent is its own context.** From the [Claude Code sub-agents docs](https://code.claude.com/docs/en/sub-agents): *"Each subagent runs in its own context window with a custom system prompt, specific tool access, and independent permissions."* That isolation is the feature — and the cost trap.

When you spawn N parallel sub-agents:

1. **N cache cold starts.** Each sub-agent's `tools + system` prefix is a *new prefix* the cache has never seen. You pay 1.25× write per sub-agent.
2. **No prefix sharing across sub-agents** unless you carefully arrange identical `tools → system → messages` prefixes.
3. **Tool invalidation is total.** Per Anthropic, *"adding or removing a tool invalidates the cache for the entire conversation."* A sub-agent with a different tool list cannot share the parent's cache.

### The cache-warmth tradeoff

- **Serial sub-agents through the same template** (e.g., a loop of "summarize document i" with identical system prompt and tools, only the document varying) *can* share cache. First call writes (1.25×); the next N–1 read (0.10×).
- **Parallel diverse sub-agents** with different system prompts per role ("researcher", "critic", "synthesizer") cannot share. You pay N writes.

### Forking is the exception

From [Lessons from building Claude Code: Prompt caching is everything](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything): when you *fork* an agent (compaction, branching), use *"the exact same system prompt, user context, system context, and tool definitions as the parent conversation"* to reuse the parent's cache. **Fork ≠ fresh sub-agent.** A fork inherits warmth; a sub-agent with a new system prompt does not.

### Quantitative impact

Sub-agents with 50KB system prompts (~12,500 tokens) spawned 10× in parallel: ~125,000 tokens of cache writes at 1.25× input each. On Sonnet 4.6 that's 125K × $3.75/M = **$0.47 just on writes**, before any actual work. Many of those entries complete within the 5-min TTL but never get reused — pure premium for nothing.

## Model-tier routing

The primary cost lever. Anthropic's research-system pattern: **Opus 4 orchestrator + Sonnet 4 workers.** This works because:

- Synthesis (orchestrator) is hard reasoning: needs the best model.
- Worker tasks are bounded sub-problems: cheaper model handles them.
- The orchestrator's context grows; workers' contexts stay small.

### Cost ratios

- Opus → Haiku: **5× cheaper** on input, **5× cheaper** on output.
- Opus → Sonnet: **1.67× cheaper** on input and output.
- Sonnet → Haiku: **3× cheaper** on input and output.

A multi-agent system that routes 10 worker tasks to Haiku instead of Opus saves >80% on the worker portion of cost.

### When tier-routing saves >50%

When workers do bounded execution: extract, summarize, classify, translate, format. Haiku 4.5 is sufficient. The Anthropic blog explicitly recommends *"Control costs by routing tasks to faster, cheaper models like Haiku."*

### When tier-routing backfires

- **Haiku worker can't handle the task** — multi-step reasoning, ambiguous spec, creative synthesis. Failure rate goes up; orchestrator retries. You spend more, not less.
- **Cheap orchestrator** — Sonnet or Haiku as synthesizer means worse final answers; the multi-agent payoff disappears. **Worst pattern: cheap brain, expensive limbs.**

## Batching

The [Batch API](https://platform.claude.com/docs/en/build-with-claude/batch-processing):

- **50% discount** on both input and output tokens.
- Asynchronous: **"most batches finishing in less than 1 hour"**, SLA up to 24 hours.
- **Stacks with prompt caching** — combined cache hit (90%) + batch (50%) = **95% off** standard input.

### Combined math (Sonnet 4.6 input)

| Discount | Effective rate |
|---|---|
| Standard | $3.00/M |
| Cache hit only | $0.30/M (–90%) |
| Batch only | $1.50/M (–50%) |
| **Cache hit + batch** | **$0.15/M (–95%)** |

### When to batch sub-agent invocations

Independent sub-agents and async-tolerant work: overnight evals, bulk classification, large-scale summarization, dataset enrichment. The 50% discount on **both input and output** is enormous — most other discounts only apply to input.

### When not to batch

Anything interactive. Anything where the orchestrator needs sub-agent results to plan the next step. The latency floor (median ~1 hour, SLA 24 hours) is too high for closed-loop reasoning.

## Time-to-first-token (TTFT)

**Definition.** Wall-clock time from request submission to the first output token rendered. Captures network, queue, prefill compute, and HTTP setup.

### TTFT additivity by topology

- **Serial pipeline (N stages):** `TTFT_total ≈ Σ TTFT_i + Σ generation_time_i`. Every stage adds its own prefill before the next can start. TTFTs compound.
- **Parallel fan-out (N workers, then synthesizer):** `TTFT_synthesizer = max(TTFT_i + generation_i) + TTFT_synth_prefill`. Bottlenecked by slowest worker.
- **MoA-style stacked layers:** Per the [Mixture-of-Agents paper (arXiv:2406.04692)](https://arxiv.org/html/2406.04692v1) (default config: **3 layers, 6 proposers per layer**) — *"the model cannot decide the first token until the last MoA layer is reached. This potentially results in a high Time to First Token (TTFT), which can negatively impact user experience."* TTFT scales with depth, not width.

### TTFT linearity in input length

Each additional input token adds **~0.2–0.24 ms** to TTFT under typical serving conditions ([source](https://www.codeant.ai/blogs/ai-first-token-latency)). Linear in practice despite attention's theoretical quadratic cost (FlashAttention + KV cache).

- 100K-token **uncached** prefill ≈ **20–24 seconds** of TTFT.
- 100K-token **cached** prefill ≈ a few hundred ms.

**Caching is the highest-leverage TTFT lever.**

### UX thresholds (perception literature)

| Latency | User perception |
|---|---|
| <100 ms | Instantaneous |
| 100 ms–1 s | Noticeable, flow preserved |
| 1–10 s | User is waiting |
| >10 s | User disengages |

### Implication for interactive UX

MoA-style stacking is structurally bad: you wait for the deepest layer before any token streams. For interactive products, prefer streaming single-agent or shallow pipelines (≤2 levels) where the *final* synthesizer streams to the user.

## Slowest-of-N tail latency

Parallel fan-out is bottlenecked by the slowest worker. From [Marc Brooker's tail-latency analysis](https://brooker.co.za/blog/2021/04/19/latency.html): *"we call N services in parallel, and wait for the slowest one. As N increases, it becomes more and more likely that we'll wait for a slow call."*

### Quantitative intuition

- If each worker has 1% chance of being a slow tail, with N=1 you hit it 1% of runs; N=10 → ~10%; N=100 → almost always.
- Brooker: *"the relatively rare tail increases the variance of the distribution we're converging on by a factor of 25."*
- Empirically, parallel fan-out with N=10 typically waits **~2× the median latency** just from tail variance.

### Mean vs tail under parallelism

Adding workers shifts mean latency up *modestly* but pushes p99 up *dramatically*. The ratio `p99 / p50` grows roughly with `log(N)`.

### Mitigation patterns

- **Hedged requests.** Fire k+1 sub-agents, take the first k responses. Costs a token premium for tail-latency insurance.
- **Early termination.** Stop the slowest workers once you have enough information. Per [arXiv:2507.08944](https://arxiv.org/html/2507.08944): *"running multiple teams in parallel and terminating early when the first team finishes."*
- **Bounded sub-agent budgets.** Hard token/time cap per sub-agent so the tail can't run away.

## Streaming as a UX patch

Streaming masks total latency by giving the user something to read while the model is still generating. The "progress bar effect" — UX research shows users tolerate **~3× longer** waits when there's visible progress.

### Where streaming legitimately helps

- The final synthesizer's output streams to the user.
- The orchestrator streams "I'm now going to research X..." status messages between sub-agent calls.

### Where streaming masks the underlying problem

- Streaming hides that you're spending 15× the tokens — the user perceives the system as fast and never sees the bill.
- Streaming hides slowest-of-N tail because the orchestrator's stream starts as soon as it has any output, even if 8/10 workers are still running and burning tokens.
- Streaming partial output of sub-agents that get *thrown away* by the synthesizer is pure waste.

### Decision rule

Stream the *user-visible* output. Don't stream sub-agent intermediates unless you'll surface them. **Don't let streaming let you forget cost.**

## Cost-per-correct-answer (CPCA)

API pricing is per-token; the metric that survives 15× token multipliers is **cost per correct answer** (or cost per completed task). A cheaper model that takes 2× iterations costs more per correct answer than a strong model that one-shots. A multi-agent system at 95% accuracy and 15× cost might be better or worse than a single agent at 80% and 1× cost — depending on the *value* of the marginal correct answer.

### Formula

```
cost_per_correct_answer = (mean_tokens_per_run × price_per_token) / accuracy
```

### Worked comparison

| Pattern | Tokens | Accuracy | CPCA |
|---|---|---|---|
| Single agent | 10K | 0.80 | 10K × $5/M ÷ 0.80 = **$0.0625** |
| Multi-agent | 150K | 0.95 | 150K × $5/M ÷ 0.95 = **$0.789** |

Multi-agent is **12.6× more expensive per correct answer**. If the marginal value of going 80% → 95% is < $0.73 per query, multi-agent loses. If > $0.73 (high-stakes legal/medical/financial), multi-agent wins.

### Stack discounts when scoring

| Stack | Effective cost |
|---|---|
| Cache hit | ×0.10 |
| Batch | ×0.50 |
| **Cache hit + batch** | **×0.05** |

A multi-agent system whose workers all hit cache and run via batch could plausibly drop the per-task cost ratio from 12.6× → ~1.3×, making it competitive even on routine queries.

## Per-task cost math

### Per-task back-of-envelope (Sonnet 4.6, ~80% input / 20% output)

| Pattern | Tokens | No cache | With cache hit on prefix |
|---|---|---|---|
| Single chat (~10K) | 8K in + 2K out | 8K×$3/M + 2K×$15/M = **$0.054** | 7K×$0.30/M + 1K×$3/M + 2K×$15/M = **$0.0351** |
| Single agent (~40K, 4×) | 32K in + 8K out | **$0.216** | ~$0.135 |
| Multi-agent (~150K, 15×) | 120K in + 30K out | **$0.81** | ~$0.45 (heavy reuse) |

Same comparison on Haiku 4.5: divide by ~3. Same comparison on Opus 4.7: multiply by ~1.67× (plus the ~35% tokenizer overhead).

### Mixed-tier multi-agent (Opus orchestrator + Haiku workers)

- **Orchestrator** on Opus 4.7: 30K in + 10K out → 30K×$5/M + 10K×$25/M = **$0.40**
- **9 workers** on Haiku 4.5, each 10K in + 2K out → 9 × (10K×$1/M + 2K×$5/M) = **$0.18**
- **Total: $0.58** vs $1.65 if everything ran on Opus → **65% savings**.

### Batched bulk job (Sonnet 4.6, 1000 sub-agent calls, identical 20K-token shared prefix, 5K-token unique suffix, 2K out)

- Without cache or batch: 1000 × (25K × $3/M + 2K × $15/M) = $75 + $30 = **$105**
- With cache hit on the 20K shared prefix: 1000 × (20K × $0.30/M + 5K × $3/M + 2K × $15/M) = $6 + $15 + $30 = **$51** + one $0.075 write = **$51.08**
- With batch + cache hit: 1000 × (20K × $0.15/M + 5K × $1.50/M + 2K × $7.50/M) = $3 + $7.50 + $15 = **$25.50** + one $0.075 write = **$25.58**

**$105 → $25.58 = 76% saved** by combining cache + batch.

## Caching across sub-agents

Sub-agents share parent cache only when they share `tools` array, `system` prompt prefix, and message history up to the breakpoint. From the Claude Code blog: forks must use *"the exact same system prompt, user context, system context, and tool definitions as the parent conversation."*

### Patterns that maximize cross-sub-agent cache reuse

1. **Same system prompt for all workers.** If "researcher", "critic", and "synthesizer" can share a single system prompt with role-disambiguation in the *user* message, the system prompt cache writes once and reads N times. If they need different roles, still share *as much prefix as possible*; put the role differentiator after the breakpoint.

2. **Stable tool registry.** Define the union of tools all sub-agents might need; let `tool_choice` constrain behavior per-agent. Don't pass different tool subsets — that invalidates the entire cache.

3. **Pin large shared context (CLAUDE.md, knowledge base, document being analyzed) at the front of the prompt with a cache breakpoint right after it.** Highest-leverage placement — the static block becomes a cached prefix shared by every sub-agent that processes the same document.

4. **Time-varying data goes last.** Putting a timestamp or session ID at the front destroys all caching. Per the Claude docs: *"The lookback does not find stable content behind your breakpoint and cache it. It finds entries that prior requests already wrote, and writes happen only at breakpoints."* If the breakpoint is on a per-request block, you re-write every time and never read.

5. **Use 1-hour TTL when fan-out spans more than 5 minutes.** If sub-agents take >5 min to all complete, their later cache reads will miss the 5-min TTL. The 1-hour write costs 2× upfront but pays off after just 2 reads.

### Verification

After deploying, check `cache_read_input_tokens` in the usage block of every sub-agent response. If it's 0 for sub-agents that should be sharing a prefix, your breakpoint placement is wrong.

## Pre-fetching shared data

**Pattern.** The orchestrator fetches expensive shared data *once* (search API, large document, expensive tool call) and embeds the result in the cached prefix passed to every sub-agent. Dramatically better than each sub-agent fetching independently.

### Why it works

- Tool calls cost money. Web search alone is **$10 per 1,000 searches** on the Claude API. 10 sub-agents each searching the same query = $0.10 of pure waste plus 10× the latency tail.
- Once the orchestrator has the data, embedding it in a stable prefix makes it a *write once, read N times* cache asset.
- Sub-agents focus on analysis, not retrieval.

### Anti-pattern

Each sub-agent does its own RAG retrieval, independently, in parallel. You pay retrieval N times, cache nothing across sub-agents, and slowest-of-N latency includes N retrieval calls.

### KVFlow insight

[KVFlow (arXiv:2507.07400)](https://arxiv.org/abs/2507.07400) — workflow-aware prefix caching for multi-agent workloads exploits the fact that *"all agents operate under the same application context, their prompts often share partially overlapping prefixes."* Design around this principle even without the KVFlow runtime.

## Decision triggers

### Cost / token economics

- **If estimated multi-agent token use ≥15× single-agent → require explicit justification** (high value, high stakes, latency reduction, or impossible-otherwise fan-out beyond context window). Otherwise, don't.
- **If sub-agents share a stable prefix → put `cache_control` at the end of that stable prefix and verify `cache_read_input_tokens > 0`.** Otherwise you're paying writes with no reads.
- **If sub-agents do bounded execution (classify, summarize, extract, format) → use Haiku, not Sonnet, not Opus.** Saves 3–5× on the worker tier.
- **If task is async/batch-tolerant (overnight evals, dataset enrichment, bulk classification) → use the Batch API for 50% off both input and output.** Stack with cache for 95% off.
- **If the same query repeats often within 5 min → 5-min TTL is fine. If the gap is 5–60 min → use 1h TTL.** Pays off after 2 reads.
- **If "cost per correct answer" isn't measured → measure it before scaling.** Single number; survives all multipliers.
- **If using Opus 4.7 → budget for ~35% more tokens than Opus 4.6 on the same English text** (new tokenizer).

### Latency / TTFT

- **If TTFT matters (interactive UX) → don't stack MoA layers.** Prefer streaming single-agent or shallow pipeline (≤2 levels). MoA cannot stream until the deepest layer.
- **If latency budget is tight and the task is parallelizable → fan out, accept the token cost, but cap sub-agent budgets to control tail.**
- **If you fan out N≥10 → expect tail latency ≈ 2× median.** Add hedging or early-termination, or accept the tail.
- **If you stream → only stream the *user-visible* output (the synthesizer).** Don't stream sub-agent intermediates unless you'll surface them.
- **If a sub-agent prefill is uncached and >50K tokens → expect ≥10s TTFT.** Cache the prefix or shrink the input.

### Topology choice

- **If parallel sub-agents all use the same prompt-shape (same system, same tools, only the input varies) → consolidate to self-consistency in a single agent.** N samples from one warmed cache > N sub-agents with N cold caches. Adaptive-Consistency further reduces sample count by ~7.9× with <0.1% accuracy drop ([arXiv:2402.13212](https://arxiv.org/abs/2402.13212)).
- **If sub-agents need divergent system prompts or tool sets → multi-agent is justified, but minimize the divergence to maximize prefix sharing.**
- **If the orchestrator must reason hard about results → orchestrator gets the strong model. Workers don't.**
- **If orchestrator only routes/concatenates → consider whether you need an orchestrator at all** vs. deterministic code.

### Caching invariants

- **Stable prefix at the start. Variable content at the end. Cache breakpoint at the boundary.**
- **Never change tool definitions mid-conversation** (invalidates entire cache).
- **Never put timestamps, session IDs, or other per-request data before the breakpoint.**
- **Pre-fetch shared data in the orchestrator. Embed it in the cached prefix passed to sub-agents.**
- **Cross-sub-agent cache sharing requires identical `tools → system → messages` up to the breakpoint.**

## Anti-patterns

1. **Multi-agent for low-value queries.** A 15× cost multiplier on a query worth $0.05 is indefensible. Use a single agent.

2. **Identical 50KB system prompt duplicated across sub-agents with no cache sharing.** If the prefix is identical, structure it for cache reuse. If it's *almost* identical (10% drift across roles), you're paying full cache writes for every sub-agent.

3. **Time-varying content at the start of the prompt.** Timestamps, request IDs, "current date is X." These destroy caching. Move them to the end, after the breakpoint.

4. **Strong model on every worker (Opus everywhere).** 5× cost increase for routine tasks Haiku handles fine. Anthropic's own recommended pattern is mixed-tier.

5. **Cheap model on the orchestrator.** Synthesis is the hardest reasoning step. Saving on the orchestrator is the worst place to economize.

6. **No latency measurement → unaware of slowest-of-N tail.** P50 looks fine; P99 is 3× worse; the user complaint rate is 5%. Measure tail latency, not just mean.

7. **Streaming to mask latency without addressing cost.** The user perceives "fast"; the bill grows 15×. Streaming is a UX patch, not a cost solution.

8. **Each sub-agent fetches the same shared data independently.** Pre-fetch once in the orchestrator, embed in cached prefix, pass to all sub-agents.

9. **Changing tool definitions mid-conversation.** Single most common cache invalidation. Define the union of tools upfront.

10. **MoA-style stacking for interactive UX.** TTFT scales with depth; user waits for the last layer before any token streams.

11. **Fan-out without cap.** "Spawn one sub-agent per item in the list" with no upper bound — runaway cost on large inputs.

12. **Sub-agent for every task.** Sub-agents have overhead — own context, own cache cold start, own setup tokens. From the Claude Code docs: *"they're worth that cost when context isolation, parallelism, or a fresh perspective actually helps."*

## Sources

- [How we built our multi-agent research system — Anthropic](https://www.anthropic.com/engineering/built-multi-agent-research-system) — June 13, 2025. The 15×, 4×, 80% variance, and Opus+Sonnet 90.2% numbers.
- [Prompt caching — Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) — TTLs, multipliers, breakpoints, lookback.
- [Pricing — Claude API Docs](https://platform.claude.com/docs/en/about-claude/pricing) — current per-million-token pricing for Opus 4.7, Sonnet 4.6, Haiku 4.5; batch pricing; tool overhead tokens.
- [Batch processing — Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/batch-processing) — 50% discount, async semantics, sub-1-hour median completion.
- [Lessons from building Claude Code: Prompt caching is everything — Claude blog](https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything) — fork cache reuse, alerts on cache hit rate.
- [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents) — sub-agent context isolation; "Control costs by routing tasks to faster, cheaper models like Haiku."
- [Mixture-of-Agents Enhances Large Language Model Capabilities (arXiv:2406.04692)](https://arxiv.org/html/2406.04692v1) — TTFT limitation of stacked MoA layers; 3 layers × 6 proposers default config.
- [KVFlow: Efficient Prefix Caching for LLM-Based Multi-Agent Workflows (arXiv:2507.07400)](https://arxiv.org/abs/2507.07400) — workflow-aware caching for multi-agent prefix sharing.
- [Tail Latency Might Matter More Than You Think — Marc Brooker](https://brooker.co.za/blog/2021/04/19/latency.html) — slowest-of-N intuition; 25× variance.
- [Optimizing Sequential Multi-Step Tasks with Parallel LLM Agents (arXiv:2507.08944)](https://arxiv.org/html/2507.08944) — parallel team latency variance; early-termination mitigation.
- [Reevaluating Self-Consistency Scaling in Multi-Agent Systems (arXiv:2511.00751)](https://arxiv.org/abs/2511.00751) — self-consistency as a cheaper alternative; diminishing returns at high N.
- [Soft Self-Consistency Improves Language Model Agents (arXiv:2402.13212)](https://arxiv.org/abs/2402.13212) — Adaptive-Consistency reducing samples ~7.9× with <0.1% accuracy drop.
- [Prompt Caching in the API — OpenAI](https://openai.com/index/api-prompt-caching/) — automatic caching, 50% on GPT-4o, up to 90% on GPT-5.
- [Context caching — Gemini API docs](https://ai.google.dev/gemini-api/docs/caching) — implicit and explicit caching, ~90% reduction.
- [Why Faster First Tokens Matter More Than Total Response Time — CodeAnt](https://www.codeant.ai/blogs/ai-first-token-latency) — TTFT UX thresholds; ~0.2–0.24 ms/input-token.
- [Anthropic API Pricing in 2026 — Finout](https://www.finout.io/blog/anthropic-api-pricing) — confirms cache + batch stacks to 95% off.
