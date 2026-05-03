# Heterogeneous Model Routing

How to decide which model goes where in a multi-agent setup. Tier-routing (Opus orchestrator + Sonnet/Haiku workers), cross-family panels for bias decorrelation, and the cases where mixing models loses more than it gains.

## Contents

- [When to consult this](#when-to-consult-this)
- [Anthropic pricing as of 2026](#anthropic-pricing-as-of-2026)
- [Tier-routing pattern (strong orchestrator + cheaper workers)](#tier-routing-pattern-strong-orchestrator--cheaper-workers)
- [Cross-family panels for bias decorrelation](#cross-family-panels-for-bias-decorrelation)
- [Mixture-of-Agents](#mixture-of-agents)
- [Panel of LLM Judges (PoLL)](#panel-of-llm-judges-poll)
- [Model families for cross-family work](#model-families-for-cross-family-work)
- [Role-to-tier assignment quick reference](#role-to-tier-assignment-quick-reference)
- [When NOT to mix models](#when-not-to-mix-models)
- [Routing frameworks](#routing-frameworks)
- [Concrete failure modes](#concrete-failure-modes)
- [Cost math worked examples](#cost-math-worked-examples)
- [Prompt caching as a routing lever](#prompt-caching-as-a-routing-lever)
- [Decision triggers (ranked)](#decision-triggers-ranked)
- [Sources](#sources)

## When to consult this

Read this when designing any multi-agent setup with more than one model in play, picking the orchestrator vs worker tier, building a critic/judge/debate role, deciding whether to introduce a cross-family panel, or sizing the cost envelope of a fan-out workload. Skip for single-agent calls where only the prompt content is in question.

Heterogeneity is a tool, not a default. Use it when (a) tasks decompose into bounded sub-jobs that don't need the strongest model, or (b) variance reduction / bias decorrelation is the explicit goal. Otherwise, one strong model is usually cheaper, faster, and more deterministic than a mix.

## Anthropic pricing as of 2026

From the [Claude API pricing page](https://platform.claude.com/docs/en/about-claude/pricing) (verified May 2026).

| Tier | Latest | Input $/MTok | Output $/MTok | Cache hit $/MTok | Cache write $/MTok | Batch input $/MTok | Batch output $/MTok | Role |
|------|--------|--------------|---------------|------------------|--------------------|--------------------|---------------------|------|
| **Opus** | 4.7 (4.5, 4.6 supported) | $5.00 | $25.00 | $0.50 | $6.25 | $2.50 | $12.50 | Orchestrator, hard reasoning, synthesis, novel planning |
| **Sonnet** | 4.6 (4.5, 4) | $3.00 | $15.00 | $0.30 | $3.75 | $1.50 | $7.50 | Default worker, balanced cost/quality, coding |
| **Haiku** | 4.5 | $1.00 | $5.00 | $0.10 | $1.25 | $0.50 | $2.50 | Cheap classification, routing, mechanical extraction, high-volume filtering |

**Numbers to keep front of mind:**

- **Tier ratio is 5 : 3 : 1** for both input and output across Opus / Sonnet / Haiku.
- **Output costs 5× input** within every tier — fan-out cost is dominated by output tokens.
- **Cache hits cost 0.1× input** — when an orchestrator broadcasts the same context to N workers, the per-worker prefix collapses to a tenth of the published rate.
- **Batch API gives 50% off** in both directions on every tier — use it for non-interactive worker fan-out.
- **Cache-hit input is 10× cheaper than fresh input on every tier.** An Opus cache-hit input token ($0.50/MTok) costs less than a Haiku *output* token ($5/MTok) — the cheap-cache lever is what makes Opus-as-orchestrator affordable when shared context dominates the workload.
- **Opus 4.7 ships a new tokenizer that can produce up to ~35% more tokens for the same text.** Real per-request cost can rise even though the rate card didn't ([pricing page note](https://platform.claude.com/docs/en/about-claude/pricing)).
- **Fast mode for Opus 4.6 is 6× standard rates ($30/$150)** — only use it when latency is dominant.
- **Anthropic's recommended slotting** (from the pricing page): "Use appropriate models: Choose Haiku for simple tasks, Sonnet for complex reasoning" — Opus for maximum intelligence, Sonnet for balanced default, Haiku for speed-critical high-volume workloads.

## Tier-routing pattern (strong orchestrator + cheaper workers)

**Canonical example.** Anthropic's published research-agent system uses **Claude Opus 4 as lead agent and Claude Sonnet 4 as subagents**, and reports it "outperformed single-agent Claude Opus 4 by 90.2%" on their internal research evaluation. The architecture is described as an "orchestrator-worker pattern, where a lead agent coordinates the process while delegating to specialized subagents that operate in parallel" ([Anthropic Engineering, "How we built our multi-agent research system," 2025](https://www.anthropic.com/engineering/built-multi-agent-research-system)).

**Why it works:**

- The hard bottleneck is **planning + synthesis**, not execution. Quote from the same post: *"When a user submits a query, the lead agent analyzes it, develops a strategy, and spawns subagents to explore different aspects simultaneously… The LeadResearcher synthesizes these results and decides whether more research is needed."*
- Subagent tasks are **bounded and verifiable** — each gets "an objective, an output format, guidance on the tools and sources to use, and clear task boundaries." Bounded outputs make a cheaper model's failure easy to detect and re-spawn.
- Cost asymmetry justifies it. Anthropic reports "agents typically use about 4× more tokens than chat interactions, and multi-agent systems use about 15× more tokens than chats." With a 5× tier gap, pushing high-volume worker calls down a tier is the only way the math works.
- Counter-quote on when *not* to bother: *"upgrading to Claude Sonnet 4 is a larger performance gain than doubling the token budget on Claude Sonnet 3.7."* Translation: tier upgrade beats orchestration complexity for many workloads — only fan out when the work is genuinely parallelizable.

**Decision triggers:**

- **If sub-agents do bounded, verifiable work with clear output schemas → use one tier below the orchestrator** because failure is detectable and a re-spawn is cheaper than over-provisioning every call.
- **If sub-work is open-ended judgment that the orchestrator would do better itself → don't fan out** because the cheaper worker will produce inconsistent inputs and the orchestrator will burn its context reconciling them.
- **If you're picking the orchestrator → never go cheaper than the workers** because an underprovisioned orchestrator decomposes badly and the smart workers waste cycles on poorly-scoped subtasks.
- **If a tier upgrade is available and the work isn't truly parallelizable → upgrade the single agent first** because routing complexity has real ops cost that the upgrade doesn't.

## Cross-family panels for bias decorrelation

Same-model critic loops produce **correlated errors** — the critic shares the generator's blind spots, so the critique is theater.

**Evidence:**

- **Self-preference / family bias is measured and significant.** Wataoka et al., ["Self-Preference Bias in LLM-as-a-Judge"](https://arxiv.org/abs/2410.21819) (arXiv:2410.21819, Oct 2024): "GPT-4 exhibits significant self-preference bias," with the proposed mechanism being lower perplexity on familiar styles. Spiliopoulou et al., ["Play Favorites"](https://arxiv.org/abs/2508.06709) (2025) extend this: "models like GPT-4o and Claude 3.5 Sonnet systematically assign higher scores to their own outputs, and also display family-bias by systematically assigning higher ratings to outputs from other models of the same family."
- **CriticGPT shows critique works — but the design uses a *separately trained* critic, not naive self-critique.** OpenAI's [LLM Critics Help Catch LLM Bugs](https://cdn.openai.com/llm-critics-help-catch-llm-bugs-paper.pdf) reports CriticGPT "caught about 85 percent of bugs, while qualified humans paid for code review caught only 25 percent." The lesson is that a different training signal (or different model entirely) is what makes the critic useful — vanilla "Claude critiques Claude" doesn't get this.
- **Multi-agent debate often fails when agents share a model.** Zhang et al., ["Stop Overvaluing Multi-Agent Debate — We Must Rethink Evaluation and Embrace Model Heterogeneity"](https://arxiv.org/abs/2502.08788) (arXiv:2502.08788, Feb 2025), studied 5 MAD methods × 9 benchmarks × 4 models, and found "MAD often fail to outperform simple single-agent baselines such as Chain-of-Thought and Self-Consistency, even when consuming significantly more inference-time computation." Their proposed fix: model heterogeneity "as a universal antidote to consistently improve current MAD frameworks."
- **Survey of 12 distinct biases** in [Justice or Prejudice? Quantifying Biases in LLM-as-a-Judge](https://llm-judge-bias.github.io/) catalogs position bias, self-preference, verbosity bias, etc., and recommends cross-family judges as mitigation.

**Decision triggers:**

- **If the role is adversarial — critique, debate, judging, red-teaming — require the critic to be from a different model family than the generator** because self-preference and family-bias are measured and material.
- **If you must use same-family critique → give the critic external grounding** (compiler output, unit tests, web search, ground-truth dataset) because shared blind spots are otherwise undetectable from inside the family.
- **If the panel is for variance reduction → require ≥2 model families** because a panel of three Sonnets is one model's blind spots, three times.

## Mixture-of-Agents

Wang et al., ["Mixture-of-Agents Enhances Large Language Model Capabilities"](https://arxiv.org/abs/2406.04692) (arXiv:2406.04692, Jun 2024): a **layered architecture** of LLM agents where each layer's agents take "all the outputs from agents in the previous layer as auxiliary information."

**Reported result:** **65.1% on AlpacaEval 2.0 versus 57.5% for GPT-4 Omni** using only open-source models. Together AI's open-source implementation publishes the same number; their **MoA-Lite configuration "can match GPT-4o cost while achieving higher quality"** ([Together AI blog](https://www.together.ai/blog/together-moa), [GitHub](https://github.com/togethercomputer/MoA)).

**Shape:**

- Layer 1: N proposer models generate independent drafts.
- Layer 2: same or different N proposers refine, conditioning on Layer 1 outputs.
- Final: one aggregator (typically the strongest available) synthesizes.

**Decision triggers:**

- **If quality at fixed cost is the goal and you have ≥3 proposers from distinct families → run a 2-layer MoA with a strong aggregator** because cross-family proposers reduce correlated errors more than adding depth with one family.
- **If you're tempted to use one family at multiple temperatures as a "panel" → it's just sampling** because the blind spots are shared.
- **If aggregator latency dominates the SLO → flatten to one layer** because each MoA layer adds a serial wait for the slowest proposer.

## Panel of LLM Judges (PoLL)

Verga et al., ["Replacing Judges with Juries: Evaluating LLM Generations with a Panel of Diverse Models"](https://arxiv.org/abs/2404.18796) (arXiv:2404.18796, Apr 2024).

**Core finding:** "using a PoLL composed of a larger number of smaller models outperforms a single large judge."

**Reported numbers:**
- **>7× cheaper than a GPT-4 single judge.**
- Less intra-model bias "due to its composition of disjoint model families."
- Tested across 6 datasets.

The juries used disjoint families (e.g., Command-R, Haiku, GPT-3.5) — **the diversity is what does the work**, not the count.

**Decision triggers:**

- **If you're judging model output at scale → replace the single GPT-4 judge with a PoLL of 3 smaller cross-family judges** because cost drops by an order of magnitude and intra-family bias drops with it.
- **If your jury must be one family for ops reasons → at least vary tier (Opus + Sonnet + Haiku)** because tier diversity catches some failure modes that within-tier sampling misses, though it does not address family bias.
- **If aggregation is by majority vote → ensure the family count is odd** to avoid ties resolved by an arbitrary tie-break that re-introduces bias.

## Model families for cross-family work

When the brief calls for "different family," these are the operating definitions. Same-family means trained on similar data, by the same lab, with overlapping post-training pipelines — and therefore correlated blind spots.

| Family | Representative models | Hosting | Notes |
|--------|----------------------|---------|-------|
| **Anthropic Claude** | Opus 4.5/4.6/4.7, Sonnet 4/4.5/4.6, Haiku 4.5 | Anthropic API, AWS Bedrock, GCP Vertex | Constitutional-AI lineage; strong on instruction-following and refusal calibration. |
| **OpenAI GPT** | GPT-4o, GPT-4 Turbo, GPT-4.1, o-series | OpenAI API, Azure | RLHF-heavy lineage; strong on tool-use and code interpreter affordances. |
| **Google Gemini** | Gemini 2.0 Pro, Gemini 1.5 Pro, Flash | Google AI Studio, Vertex | Long-context (1M+), strong on multimodal video. |
| **Meta Llama** | Llama 3.3 70B, Llama 3.1 405B | Together, Fireworks, Bedrock, self-host | Open weights; differential post-training across hosts. |
| **Mistral** | Mistral Large 2, Mixtral 8x22B | Mistral, AWS, self-host | European-trained; different RLHF priors. |
| **Cohere** | Command-R+, Command-R | Cohere, Bedrock | RAG-tuned; cited in PoLL. |

**Decision triggers:**

- **If you need adversarial cross-family pairing on a budget → Claude Haiku + GPT-4o-mini + Gemini Flash** because each is the cheap tier of its family and the family diversity does the variance-reduction work.
- **If hosting is on one cloud (e.g., all Bedrock) → that's not provider-diverse for outage purposes** because a Bedrock regional outage takes down all three. True reliability diversity requires distinct hosting.
- **If the workload needs a tool only one family has (Computer Use, code interpreter, native video) → that family becomes mandatory** and the panel works around it instead of replacing it.

## Role-to-tier assignment quick reference

A lookup table for "which tier for which role." Defaults assume Anthropic stack; substitute equivalents from other families as needed.

| Role | Default tier | Why |
|------|--------------|-----|
| Lead orchestrator / planner | **Opus 4.7** | Bottleneck is decomposition quality; never underprovision the head. |
| Synthesis / final write-up | **Opus 4.7** | Coherence across worker outputs needs the strongest reasoning. |
| Bounded research worker | **Sonnet 4.6** | Quality matches Opus on bounded tasks at 60% of input cost. |
| Code-edit worker (single file, scoped) | **Sonnet 4.6** | Sonnet is the published coding default. |
| JSON extraction / schema-fill | **Haiku 4.5** | Mechanical; Sonnet is overkill. |
| Intent classification / routing | **Haiku 4.5** | Cheap, fast, good enough for a 3–8 class problem. |
| Adversarial critic on Claude output | **GPT-4 or Gemini** | Cross-family is non-negotiable for honest critique. |
| Judge in eval harness | **PoLL of 3 cross-family** | PoLL is 7× cheaper and less biased than single-large judge. |
| High-volume filter (spam, safety) | **Haiku 4.5 batch** | 50% batch discount + Haiku tier = ~$0.50 / MTok input. |
| Latency-critical interactive turn | **Sonnet 4.6** (or **Opus Fast** if budget allows) | Sonnet is the latency/quality knee; Opus Fast at 6× rate only if the SLO demands it. |
| Long-context document QA | **Sonnet 4.6 + cache** | Cache the document once; subsequent queries collapse to cache-hit pricing. |
| Self-consistency sampling (n=5+) | **Same model, varied temperature** | This is sampling, not a panel — heterogeneity adds nothing if you're averaging your own draws. |

## When NOT to mix models

1. **Tool-affordance lock-in.** If the work needs a capability only one provider has (Claude's Computer Use, OpenAI's code interpreter / web tools, Gemini's long-context video, a fine-tune you only have on one platform), forcing heterogeneity loses the affordance you actually came for.
2. **Determinism / reproducibility.** Eval harnesses, regression suites, anything where you need byte-stable behavior across runs → pick one model and pin the version.
3. **Auth / ops complexity isn't worth it.** N providers = N keys, N rate limits, N retry budgets, N legal reviews, N billing reconciliations. For a small project, the marginal quality from mixing is dwarfed by the marginal ops cost.
4. **Latency floor = slowest model.** A panel that aggregates 5 providers waits for the slowest. If p99 latency is a SLO, panels are out.
5. **Coherent narrative outputs.** Long-form writing, code in a single file, anything where stylistic consistency matters → mixing models produces stitched-together artifacts with detectable seams.
6. **Anthropic's own caveat on multi-agent itself:** *"Some domains that require all agents to share the same context or involve many dependencies between agents are not a good fit for multi-agent systems today. For instance, most coding tasks involve fewer truly parallelizable tasks than research."* ([Anthropic, multi-agent research post](https://www.anthropic.com/engineering/built-multi-agent-research-system))

**Decision triggers:**

- **If a single provider has the affordance you need → don't mix** because losing the affordance costs more than the marginal panel quality gains.
- **If p99 latency is an SLO → no panels** because aggregation waits for the slowest member.
- **If the output is a single coherent artifact (one file, one narrative) → use one model** because mixed-style stitching shows.
- **If the project is small (one engineer, <10K queries/day) → use one provider** because per-provider ops overhead doesn't amortize.

## Routing frameworks

- **RouteLLM** (Ong et al., [arXiv:2406.18665](https://arxiv.org/abs/2406.18665), [LMSYS blog](https://www.lmsys.org/blog/2024-07-01-routellm/), [GitHub](https://github.com/lm-sys/RouteLLM)): trains routers from preference data to pick between a strong and weak LLM. Reported cost reductions vs GPT-4-only: **>85% on MT-Bench, 45% on MMLU, 35% on GSM8K**, with no quality loss on those benchmarks. Use when you have a very high-volume workload and a meaningful price gap between two pinned models.
- **OpenRouter** ([provider routing docs](https://openrouter.ai/docs/guides/routing/provider-selection), [model fallbacks](https://openrouter.ai/docs/guides/routing/model-fallbacks)): unified API across 500+ models / 60+ providers, with **automatic fallback on provider error** and ~25 ms routing overhead. Use when you want provider redundancy without writing N SDK integrations.
- **LangGraph supervisor pattern** ([LangChain docs](https://docs.langchain.com/oss/python/langgraph/workflows-agents), [langgraph-supervisor-py](https://github.com/langchain-ai/langgraph-supervisor-py)): explicit graph where a supervisor node (LLM) routes to specialized agent nodes via `Command`. Supports per-node model assignment — the canonical place to encode "Opus supervisor → Sonnet workers → Haiku for trivial nodes" in code.
- **Mixture-of-routing.** Combine: a Haiku classifier picks between (a) direct answer, (b) Sonnet single-agent, (c) Opus orchestrator + worker fan-out. Each tier handles its band; the router itself is essentially free.

**When a routing layer is worth it vs hardcoding tier choice:**

- **Worth it:** workload distribution is bimodal/multimodal (most queries trivial, a few hard), cost gap between tiers is large, you serve >10K queries/day, you can measure router accuracy and budget the false-route cost.
- **Not worth it:** workload is uniform (all queries are similar difficulty), you don't have eval data, the router itself is non-trivial to build/maintain. Just pin to the right tier.

**Decision triggers:**

- **If routing decisions are themselves cheap to make → put Haiku at the front** because routing overhead must be cheaper than the routing gain.
- **If routing decisions are themselves hard → don't route, just call the strong model** because router error compounds and a wrong cheap-route can cost more than a right expensive one.
- **If you need provider redundancy more than cost optimization → use OpenRouter fallbacks** because the ~25 ms overhead is the cheapest insurance against provider outages.
- **If you have preference data and a stable two-model gap → train RouteLLM** because the published cost reductions only materialize with router training data.

## Concrete failure modes

1. **Underprovisioned orchestrator.** Haiku coordinating Opus workers — the orchestrator can't reason about the workers' outputs, decomposes badly, and the "smart" workers spend their cycles on poorly-scoped subtasks. Anthropic's design puts the strongest model at the top for a reason.
2. **Overprovisioned worker.** Opus doing trivial extraction (pulling a date out of a string). At Opus's 25× output price vs Haiku, doing 10K such tasks costs $625 instead of $25. Audit fan-out for tasks that don't need the cycles.
3. **Same-family critic theater.** Claude critiquing Claude, GPT critiquing GPT — produces glowing self-reviews and misses shared blind spots (e.g., both agreeing on a hallucinated API). Documented in the self-preference and family-bias papers above.
4. **Model-mismatched handoffs.** When workers produce intermediate artifacts in different formats / reasoning styles, the aggregator gets inconsistent inputs. Anthropic warns: without clear task descriptions, "subagents duplicate work, leave gaps, or fail to find necessary information." Mitigate with strict output schemas at every hand-off boundary.
5. **Coordination explosion.** Anthropic reports early systems where lead agents "spawned 50 subagents for simple queries" and were "distracting each other with excessive updates." The orchestrator needs explicit budget caps on fan-out width and depth.
6. **Provider-correlated outage.** A panel that's "diverse" but all hosted on one cloud (e.g., all Bedrock) shares an outage failure mode. True provider diversity for reliability requires distinct hosting.

## Cost math worked examples

These illustrate why tier-routing and prompt caching dominate naive single-tier scaling. All numbers use the table above, no batch discount unless noted.

### Example 1: 10K mechanical extractions (date-from-string)

Per call: 200 input tokens, 50 output tokens.

| Setup | Input cost | Output cost | Total |
|-------|-----------|-------------|-------|
| Opus 4.7 only | 10K × 200 × $5/1M = **$10** | 10K × 50 × $25/1M = **$12.50** | **$22.50** |
| Sonnet 4.6 | 10K × 200 × $3/1M = **$6** | 10K × 50 × $15/1M = **$7.50** | **$13.50** |
| Haiku 4.5 | 10K × 200 × $1/1M = **$2** | 10K × 50 × $5/1M = **$2.50** | **$4.50** |
| Haiku batch | $1 | $1.25 | **$2.25** |

Opus-vs-Haiku is **10×** here. The brief's earlier claim of "Opus $625 vs Haiku $25" used a higher per-call output budget; the ratio holds.

### Example 2: 100 fan-out workers with 50K shared-context prefix

Per worker: 50K cached prefix + 2K unique input + 5K output. Shared prefix loaded once into cache (write at $6.25/MTok for Opus, $3.75 Sonnet, $1.25 Haiku).

| Worker model | Cache write (once) | Cache hit (per worker × 100) | Unique input | Output | Total |
|--------------|--------------------|--------------------------------|--------------|--------|-------|
| Opus 4.7 | 50K × $6.25/1M = $0.3125 | 100 × 50K × $0.50/1M = **$2.50** | 100 × 2K × $5/1M = **$1.00** | 100 × 5K × $25/1M = **$12.50** | **$16.31** |
| Sonnet 4.6 | $0.1875 | 100 × 50K × $0.30/1M = **$1.50** | 100 × 2K × $3/1M = **$0.60** | 100 × 5K × $15/1M = **$7.50** | **$9.79** |
| Haiku 4.5 | $0.0625 | 100 × 50K × $0.10/1M = **$0.50** | 100 × 2K × $1/1M = **$0.20** | 100 × 5K × $5/1M = **$2.50** | **$3.26** |

**Without caching**, the Opus column would be 100 × 50K × $5/1M = $25 just for the prefix re-reads — caching is an 8× lever for the orchestrator's broadcast.

### Example 3: Anthropic-style Opus orchestrator + Sonnet workers

10 worker fan-out, orchestrator does 20K input + 10K output of planning/synthesis, each worker does 5K input + 8K output.

| Component | Cost |
|-----------|------|
| Opus orchestrator input | 20K × $5/1M = **$0.10** |
| Opus orchestrator output | 10K × $25/1M = **$0.25** |
| Sonnet workers input (10 × 5K) | 50K × $3/1M = **$0.15** |
| Sonnet workers output (10 × 8K) | 80K × $15/1M = **$1.20** |
| **Total** | **$1.70** |

Same workload all-Opus: $0.10 + $0.25 + 50K × $5/1M ($0.25) + 80K × $25/1M ($2.00) = **$2.60**. Tier-routing saves **35%** on this shape.

Same workload all-Sonnet: $0.06 + $0.15 + $0.15 + $1.20 = **$1.56**. Cheaper than tier-routed — **but loses Opus's planning quality at the orchestrator**, which is what the 90.2% Anthropic uplift comes from. The premium for the Opus head is $0.14 / call.

**Rule of thumb:** Tier-routing wins on cost vs single-tier-Opus when worker fan-out output dominates total token spend. It loses on cost vs single-tier-Sonnet but should win on quality at the orchestration bottleneck.

### Example 4: PoLL judge (3 small judges) vs single GPT-4 judge

Judging 1000 model outputs, each ~3K input + 200 output per judge.

| Setup | Calculation | Total |
|-------|-------------|-------|
| Single GPT-4 judge (~$30/$60 contemporary) | 1000 × (3K × $30/1M + 200 × $60/1M) = $90 + $12 | **$102** |
| 3-family PoLL (Haiku 4.5 + GPT-3.5 + Command-R, average ~$1/$5) | 3 × 1000 × (3K × $1/1M + 200 × $5/1M) = 3 × ($3 + $1) | **$12** |

Roughly **8.5× cheaper**, consistent with PoLL's reported >7× factor.

## Prompt caching as a routing lever

Caching changes the math on which tier wins, not just absolute cost. Treat it as a routing input, not an afterthought.

- **Cache-write costs 1.25× input** (one-time per prefix), then **cache-hit reads cost 0.10× input** (subsequent reads while the cache is warm).
- **Break-even is 2 reads:** writing to cache then reading once costs 1.35× a single uncached read; reading twice costs 1.45× vs 2.0× — caching pays after the second worker.
- **Ephemeral cache TTL is 5 minutes by default**, with longer-lived options on some configs. Worker fan-out should complete inside the TTL or pay re-write costs.
- **Cache scope is exact-prefix.** Workers must share an identical leading context (system prompt + shared docs) for cache hits to land. Per-worker variation goes after the shared block.

**Decision triggers:**

- **If you fan out ≥2 workers with shared context → cache the prefix** because the break-even is at the second call.
- **If the orchestrator broadcasts a 50K+ token context to 10+ workers → caching is mandatory, not optional** because uncached the prefix dominates worker cost by 10×.
- **If you can't make workers share a prefix exactly → restructure the prompt** so per-worker variation goes after a shared block. Cache hits are exact-prefix only.
- **If your fan-out runs longer than the cache TTL → split into TTL-sized waves or upgrade to extended-cache pricing** because re-writes erase the savings.

## Decision triggers (ranked)

Encode these in priority order — earlier rules win on conflict.

1. **If sub-agents do bounded, verifiable work → use a cheaper model than the orchestrator** (Anthropic Opus-lead / Sonnet-worker pattern).
2. **If the panel is for variance reduction → require ≥2 model families** (PoLL / "Stop Overvaluing MAD"). A panel of homogeneous models is just expensive sampling.
3. **If the critic will be the same model as the generator → its critique is theater unless given external tools/signal** (compiler, unit tests, search, ground-truth dataset). Otherwise route the critique to a different family.
4. **If the routing decision itself is cheap → use Haiku as the router. If the routing decision itself is hard → don't route, just use the strong model.** Routing must be cheaper than the routing gain.
5. **If you can't articulate why two models are better than one for this task → use one.** Heterogeneity has real ops cost (auth, latency, debugging, billing) that must be paid for by a concrete quality or cost gain.
6. **If the task is genuinely sequential / shared-context (most coding tasks) → don't fan out.** Anthropic explicitly warns multi-agent doesn't fit here.
7. **If latency p99 is a hard SLO → no panels.** A panel waits for the slowest member.
8. **If a panel needs reliability against outages → spread across distinct hosting providers**, not just distinct model names on one platform.
9. **If you fan out N workers with shared context → cache the shared prefix** (Anthropic prompt caching at 0.1× input cost). Heterogeneity is often justified only when this lever is also pulled.
10. **If you're picking the orchestrator → never go cheaper than the workers.** Underprovisioned orchestrator is the most common multi-agent failure mode.

## Sources

Primary research and documentation cited.

- [Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system) (2025)
- [Anthropic — Claude API Pricing](https://platform.claude.com/docs/en/about-claude/pricing) (verified May 2026)
- [Wang et al., Mixture-of-Agents Enhances Large Language Model Capabilities (arXiv:2406.04692)](https://arxiv.org/abs/2406.04692) — Jun 2024
- [Verga et al., Replacing Judges with Juries: Evaluating LLM Generations with a Panel of Diverse Models (arXiv:2404.18796)](https://arxiv.org/abs/2404.18796) — Apr 2024
- [Zhang et al., Stop Overvaluing Multi-Agent Debate — We Must Rethink Evaluation and Embrace Model Heterogeneity (arXiv:2502.08788)](https://arxiv.org/abs/2502.08788) — Feb 2025
- [Wataoka et al., Self-Preference Bias in LLM-as-a-Judge (arXiv:2410.21819)](https://arxiv.org/abs/2410.21819) — Oct 2024
- [Spiliopoulou et al., Play Favorites: A Statistical Method to Measure Self-Bias in LLM-as-a-Judge (arXiv:2508.06709)](https://arxiv.org/abs/2508.06709) — 2025
- [Justice or Prejudice? Quantifying Biases in LLM-as-a-Judge](https://llm-judge-bias.github.io/)
- [OpenAI, LLM Critics Help Catch LLM Bugs (CriticGPT paper PDF)](https://cdn.openai.com/llm-critics-help-catch-llm-bugs-paper.pdf)
- [Ong et al., RouteLLM: Learning to Route LLMs with Preference Data (arXiv:2406.18665)](https://arxiv.org/abs/2406.18665)
- [LMSYS — RouteLLM blog post](https://www.lmsys.org/blog/2024-07-01-routellm/)
- [Together AI — Together MoA blog](https://www.together.ai/blog/together-moa) and [GitHub repo](https://github.com/togethercomputer/MoA)
- [OpenRouter — Provider Routing docs](https://openrouter.ai/docs/guides/routing/provider-selection) and [Model Fallbacks](https://openrouter.ai/docs/guides/routing/model-fallbacks)
- [LangChain — Workflows and agents docs](https://docs.langchain.com/oss/python/langgraph/workflows-agents) and [langgraph-supervisor-py](https://github.com/langchain-ai/langgraph-supervisor-py)
