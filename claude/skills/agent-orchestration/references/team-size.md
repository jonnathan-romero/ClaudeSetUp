# Team Size: How Many Sub-Agents?

How to pick `N` for a multi-agent task. Distilled from published evals on self-consistency, debate, MoA, research fan-out, and topology studies. Numbers preserved.

## Contents

- [When to consult this](#when-to-consult-this)
- [Cheat sheet (pattern → N)](#cheat-sheet-pattern--n)
- [Decision rules](#decision-rules)
- [Diminishing returns by pattern](#diminishing-returns-by-pattern)
- [Coordination overhead by N](#coordination-overhead-by-n)
- [Fan-out cost curves](#fan-out-cost-curves)
- [Failure modes when N is too large](#failure-modes-when-n-is-too-large)
- [Adaptive vs fixed-N](#adaptive-vs-fixed-n)
- [Worked picks for common task shapes](#worked-picks-for-common-task-shapes)
- [Why "3" shows up so often](#why-3-shows-up-so-often)
- [Sources](#sources)

## When to consult this

Read this when about to spawn more than one sub-agent for related work, when designing a `.claude/agents/` subagent crew, when choosing a fan-out width, or when deciding between debate / self-consistency / MoA / role triad / map-reduce. Skip for single one-shot Agent calls where only the prompt content is in question.

## Cheat sheet (pattern → N)

| Pattern | N | Why | Source |
|---|---|---|---|
| Single file edit / lookup | 1 | No parallelism payoff | [Anthropic 2025](https://www.anthropic.com/engineering/multi-agent-research-system) |
| Generator-verifier | 2 | One produces, one evaluates against criteria; loop until pass | [Anthropic coordination patterns](https://claude.com/blog/multi-agent-coordination-patterns) |
| Builder / tester / reviewer triad | 3 (exact) | Three distinct roles with unambiguous outputs (code / failing test / review). Adding a 4th creates role overlap | [CrewAI](https://docs.crewai.com/en/guides/agents/crafting-effective-agents); [Osmani](https://addyosmani.com/blog/code-agent-orchestra/) |
| Red team / blue team / judge | 2 or 3 | 2 for adversarial pressure; 3 (attacker / target / judge) for scored outcomes | PAIR; [arXiv:2506.13434](https://arxiv.org/html/2506.13434v1) |
| Self-consistency / majority vote | 5 (range 5–10; rarely >20) | Plateau by 10; >20–40 wastes tokens on redundant paths. Use odd N to break ties | [Wang 2022](https://arxiv.org/abs/2203.11171); [Loo 2025](https://arxiv.org/abs/2511.00751) |
| High-stakes self-consistency | 10 | Past plateau, for safety-critical accuracy | [Li 2024](https://arxiv.org/abs/2402.05120) |
| Multi-agent debate | 3 agents × 2–4 rounds | Du used 3×2 explicitly for cost; plateau at 4 rounds. 6+ agents drops 5–15% | [Du 2023](https://arxiv.org/abs/2305.14325); [Estornell 2025](https://arxiv.org/abs/2509.05396) |
| Mixture-of-Agents (production) | 6 proposers × 3 layers | AlpacaEval LC: 1→3→6 proposers = 47.8% → 58.0% → 61.3%; 2→3 layers = 59.3% → 65.1% | [Wang 2024 MoA](https://arxiv.org/abs/2406.04692) |
| MoA-Lite (cost-optimized) | 6 × 2 layers | Same proposer width, one fewer layer | [Wang 2024 MoA](https://arxiv.org/abs/2406.04692) |
| Research fan-out (typical) | 3–5 sub-agents | Anthropic's documented sweet spot; 2–4 for comparisons | [Anthropic 2025](https://www.anthropic.com/engineering/multi-agent-research-system) |
| Research fan-out (complex) | 5–10 sub-agents | Anthropic ceiling for one orchestrator; split-and-merge max | [Anthropic 2025](https://www.anthropic.com/engineering/multi-agent-research-system) |
| Map-reduce over K shards | N = K, cap concurrent at 4–6 | N is task-determined; concurrency cap is rate-limit driven | [LangGraph guide](https://aipractitioner.substack.com/p/scaling-langgraph-agents-parallelization); [LLMxMapReduce](https://arxiv.org/html/2410.09342v1) |
| Hierarchical (supervisor-of-supervisors) | 3–5 reports per supervisor, 2–3 levels | Once one supervisor has >5–7 direct reports, split | [LangGraph hierarchical teams](https://langchain-ai.github.io/langgraph/tutorials/multi_agent/hierarchical_agent_teams/) |
| Long-running autonomous agent team | 3–5 persistent workers | "Three focused teammates consistently outperform five scattered ones" | [Osmani](https://addyosmani.com/blog/code-agent-orchestra/) |
| Sequential planning / multi-step transformation | 1 | Every MAS variant tested degraded sequential reasoning by 39–70% | DeepMind / Kim et al. 2025 |
| Creative coherence (long-form writing, single voice) | 1 (+1 verifier max) | Multiple authors dilute voice; synthesis is "Frankenstein" prone | [Osmani](https://addyosmani.com/blog/code-agent-orchestra/) |

## Decision rules

Apply these in order. The first matching rule wins.

1. **Single concrete action (one file edit, one query, one calculation) → N=1.** Sub-agents add overhead with zero parallelism gain. Anthropic: "simple fact-finding requires just 1 agent with 3–10 tool calls."

2. **Strictly sequential reasoning (multi-step planning, dependent transformations) → N=1.** Every MAS variant in DeepMind's PlanCraft tests scored −39% to −70% vs single agent.

3. **Single-agent baseline already >70% accurate → N=1.** Multi-agent gains are largest when the single-agent baseline is below ~45% (DeepMind's "45% rule"). Above 70% the orchestration tax exceeds the accuracy upside.

4. **Sub-agent work <1 minute or <2k tokens → inline, don't fan out.** Orchestration overhead (prompt + summary + synthesis) exceeds the parallelism gain.

5. **Coherent creative output (long-form writing, design with single voice) → N=1, verifier optional (N=2 max).** Multiple authors dilute voice. Synthesis on creative outputs is Frankenstein-prone.

6. **"Produce X and verify it meets criteria Y" → N=2 (generator + verifier) in a loop.** A third verifier almost never helps unless verifiers disagree often.

7. **"Produce X, test it, review it" with three unambiguous outputs → N=3 (builder/tester/reviewer triad).** Each role has a distinct deliverable, so they don't overlap.

8. **Need adversarial pressure with a verdict → N=3 (attacker / target / judge).** N=2 only if no verdict is needed. PAIR uses exactly this triad.

9. **Hard reasoning question, want lower variance → N=5 self-consistency samples, majority vote.** Increase to 10 if cost allows and stakes are high. Stop at 20 — paying for redundant reasoning paths.

10. **Structured debate (factuality, math) → N=3 agents × 2–4 rounds.** Beyond 4 rounds plateau or drift; beyond 4 agents accuracy can drop 5–15%.

11. **Explore a research question with multiple independent angles → N = number of genuinely distinct angles, capped at 5 in one orchestrator.** If >5 angles, split into hierarchical sub-supervisors.

12. **Synthesize from K data shards (map-reduce) → N = K, cap concurrent execution at 4–6.** Concurrency cap is rate-limit driven, not accuracy driven.

13. **Top-tier benchmark accuracy and cost doesn't matter → MoA-style 6 proposers × 3 layers.** Diminishing returns above this; layer 4+ rarely pays.

14. **Sub-agent summaries would push the orchestrator >50% context utilisation → reduce N or go hierarchical.**

15. **Cannot review the parallel outputs → don't spawn them.** Human/orchestrator review bandwidth is the real ceiling, not the API.

## Diminishing returns by pattern

Multi-agent gains rise, plateau, then often reverse. Plateau location varies by pattern; the shape is universal.

### Self-consistency / sampling-and-voting

- [Wang et al. 2022](https://arxiv.org/abs/2203.11171): strong gains 5–10 paths, diminishing returns past 20–40. Plateau driven by overlap among reasoning paths — extra samples are redundant, not wrong.
- N=5 is the cost/accuracy sweet spot for most tasks; gains beyond N=20–40 rarely justify the linear token cost.
- [Li et al. 2024 "More Agents Is All You Need"](https://arxiv.org/abs/2402.05120) tested N up to 40. GSM8K: Llama2-13B 0.35 → 0.59 (+0.24); GPT-3.5 0.73 → 0.85 (+0.12). Curves keep rising but flatten markedly. Gains largest where the base model is weak on a moderately difficult task.
- [Loo 2025](https://arxiv.org/abs/2511.00751) confirms the plateau replicates across newer models — bottleneck is reasoning-path overlap, not model capability.

### Multi-agent debate

- [Du et al. 2023](https://arxiv.org/abs/2305.14325): performance increases monotonically with agents on arithmetic, but gains shrink fast. Headline experiments use 3 agents × 2 rounds explicitly because of compute cost.
- Debate rounds plateau ~4 rounds; beyond that, accuracy is flat or worse.
- [Estornell et al. 2025 "Talk Isn't Always Cheap"](https://arxiv.org/abs/2509.05396): debate sweet spot is 3–4 agents. Going from 4 → 6+ agents loses ~5–15% accuracy via three failure modes (problem drift, interference, redundancy).
- Real cost: 3 agents × 5 rounds raised arithmetic accuracy from 50% → 98% but cost ~101× more tokens.

### Mixture-of-Agents

- [Wang et al. 2024 MoA](https://arxiv.org/abs/2406.04692): production config is 6 proposers × 3 layers; cost-optimized "MoA-Lite" is 6 × 2.
- AlpacaEval 2.0 LC win rate: 1 proposer = 47.8% → 3 = 58.0% → 6 = 61.3%. Monotonic with clearly decreasing marginal gains.
- 2 layers → 3 layers: 59.3% → 65.1%. Authors call further width-scaling "future work" — no saturation plateau named, but the curve flattens.

### Anthropic research fan-out

- [Anthropic 2025](https://www.anthropic.com/engineering/multi-agent-research-system): lead-agent + Claude Sonnet 4 sub-agents outperformed single-agent Claude Opus 4 by 90.2% on internal research eval.
- Typical fan-out is 3–5 sub-agents in parallel. Scaling: simple fact-finding = 1 agent / 3–10 tool calls; comparisons = 2–4 sub-agents / 10–15 calls each; complex research = 10+ sub-agents.
- Documented over-allocation failure: early prototypes "spawned 50 sub-agents for simple queries." Required scaling heuristics in the orchestrator prompt to suppress.
- Sub-agents return only 1,000–2,000 token distilled summaries to the orchestrator, even though they may use 10,000s+ of tokens internally — synthesis bottleneck is hard-coded into the architecture.

### Topology study (DeepMind / Kim et al. 2025)

- Across 180 configurations on 4 benchmarks (BrowseComp-Plus, Finance-Agent, PlanCraft, WorkBench): performance saturation around 4 agents in most centralised configurations.
- Coordination yields highest returns when the single-agent baseline is below ~45% accuracy. If single-agent is already strong, multi-agent helps less and can hurt.
- On strictly sequential tasks (e.g., PlanCraft multi-step planning), every MAS variant degraded performance vs single agent (−39% to −70%).

### Why MAS systems fail

[Cemri et al. 2025](https://arxiv.org/abs/2503.13657) (NeurIPS 2025) evaluated 5 popular MAS frameworks across 150+ tasks; identified 14 failure modes in 3 categories: spec/design (42%), inter-agent misalignment (37%), task verification/termination (21%). Bottom line: gains over single-agent on popular benchmarks are "minimal" once failure modes are accounted for.

## Coordination overhead by N

Coordination cost grows super-linearly in N because of three compounding effects.

### Orchestrator context is the hard ceiling

- Sub-agents return distilled summaries (Anthropic: 1–2k tokens each), but the orchestrator must hold all of them simultaneously to synthesise. With Claude Sonnet 4 at 200k context, you can technically fit 100+ summaries — but orchestrator attention degrades long before that.
- Practitioner observation across LangGraph and CrewAI guides: when a single supervisor has more than ~5–7 direct reports, switch to a hierarchical supervisor-of-supervisors topology rather than widen further.

### Synthesis cost scales as N × summary + reconciliation

- DeepMind topology paper: `Work cost = N × K_agents × steps` + `Coordination cost = rounds × fan_out`. Coordination cost dominates fast in decentralised topologies.
- Anthropic identifies synchronous execution as the current bottleneck — the lead agent waits for the slowest sub-agent in each batch. Slowest-of-N latency grows as the max of N independent draws — for N=10 you typically wait 1.5–2× the median sub-agent latency just from variance.

### Conflicting sub-results

Three failure modes from "Talk Isn't Always Cheap":

- **Problem drift** — agents diverge from the question (worse with more agents).
- **Interference** — contradictory recommendations confuse the synthesiser/judge.
- **Redundancy** — extra agents repeat existing arguments, adding noise.

Cemri et al. quantify "inter-agent misalignment" as 37% of all observed failures — second-largest category.

### Error amplification in unstructured topologies

- Unstructured agent networks amplify errors up to 17.2× vs single-agent baselines. Centralised orchestration contains amplification to ~4.4×.
- Decentralised debate can be better than centralised on some tasks (+9.2% on BrowseComp-Plus) but worse on others (−35% on independent MAS for the same benchmark).
- Mechanism: each agent's small hallucination becomes the next agent's input. Without a hierarchical "fence," noise compounds.

### Three signals the orchestrator is the bottleneck

1. Orchestrator's context utilisation crosses ~50% just from sub-agent summaries.
2. Synthesis-time tokens exceed sub-agent work-time tokens.
3. Orchestrator starts dropping/ignoring sub-results in its final answer.

When any of these hit, you've over-fanned-out — split into hierarchical sub-supervisors instead of widening further.

## Fan-out cost curves

Calibrated against Anthropic's published 15× tokens vs plain chat for their orchestrator + sub-agent pattern (3–5 sub-agents typical, summaries returned). Numbers below assume each sub-agent does meaningful work (~10–20 tool calls and returns a 1–2k summary).

| N parallel sub-agents | Token multiplier vs single | Wall-clock vs single | Practical regime |
|---|---|---|---|
| 1 | 1× | 1× | Direct execution; no orchestration overhead |
| 2 | ~3–4× | ~1.1× | Generator-verifier; A/B perspective |
| 3 | ~5–6× | ~1.2× | Sweet spot for debate, MoA proposers, builder/tester/reviewer triad |
| 5 | ~10–12× | ~1.3–1.5× | Anthropic's typical research fan-out ceiling |
| 10 | ~20–25× | ~1.8–2× | Complex research; ceiling for one orchestrator |
| 20 | ~40–50× | ~2.5–3× | Requires hierarchy; orchestrator synthesis often degrades |
| 50 | ~100×+ | ~3–5× + retries | Anthropic's documented pathological case; almost never correct |

### Practical production ceilings observed in the wild

- **Anthropic Research / Claude Code:** "spin up to 10 sub-agents" is the documented split-and-merge ceiling per orchestrator session.
- **CrewAI / LangGraph community guidance:** 4–6 parallel tasks per orchestrator before hitting rate limits / coordination loss.
- **Addy Osmani's "Code Agent Orchestra":** "3–5 teammates is the sweet spot … three focused teammates consistently outperform five scattered ones." 5–20+ only for cloud-orchestrated backlog drainage with separate human review.
- **Self-consistency sampling (no orchestrator coupling):** can scale to N=20–40 because there is no synthesis — just majority vote — but accuracy plateaus.

### Cost to remember

- Multi-agent ≈ 15× tokens vs plain chat ([Anthropic 2025](https://www.anthropic.com/engineering/multi-agent-research-system)).
- Each marginal agent adds ~2–3× tokens after the first.
- Latency = max(slowest sub-agent), not mean.
- 3-agent × 5-round debate can hit 101× tokens for ~50 pp accuracy gain.

## Failure modes when N is too large

| Failure mode | Trigger | Observed impact |
|---|---|---|
| Orchestrator synthesis overflow | N × summary size > ~30–40k tokens | Orchestrator drops some sub-results from final answer. Common around N=20+ with verbose summaries. |
| Duplicate work / redundancy | Sub-agents weren't given disjoint scopes | Same files read multiple times; overlapping conclusions; inflated token cost. Cemri 2025 observed in 3 of 5 frameworks. |
| Conflicting recommendations swamp synthesis | N≥5 on creative/coherence tasks | Orchestrator hedges, picks one arbitrarily, or produces "Frankenstein" output. *Interference*: 5–15% accuracy loss going 4→6 agents. |
| Problem drift | Long debate (>4 rounds) or many agents (>5) on open-ended task | Agents move away from original question; final answer is off-topic. |
| Error amplification (17.2×) | Decentralised topology, no judge / verifier | Each agent's hallucination becomes another's input. Unstructured chains catastrophically worse than single-agent (Kim et al. 2025). |
| Slowest-of-N tail latency | N parallel calls, any one slow | Wall-clock = max(latency_i). With N=10 you wait roughly 2× the median latency just from variance. |
| Rate-limit collapse | N parallel API calls > provider quota | Throttling, retries, partial failure mid-synthesis. LangGraph guides cap practical concurrency at 4–6. |
| "Too many cooks" on creative tasks | N≥3 on coherence-critical writing | Each agent's revisions dilute voice; synthesised output is bland or contradicts itself. Single-agent usually right. |
| Pathological over-allocation | Orchestrator has no budget hint | Anthropic's "50 sub-agents for a simple query" failure. Required explicit prompt-level budget heuristics to fix. |
| Sequential reasoning degradation | Multi-step planning split across agents | Every MAS variant in DeepMind's PlanCraft tests scored −39% to −70% vs single agent. |
| Verification gap | N agents produce output, no judge | Cemri 2025: 21% of failures are task-verification failures. Adding agents without adding a verifier *increases* failure rate. |

### Hard kill-switch heuristics

- Single-agent already >70% accurate → N=1.
- Strictly sequential → N=1.
- Sub-agent work <1 min or <2k tokens → inline, don't fan out.
- Cannot review the outputs → don't spawn them.
- Orchestrator context >50% used by summaries → reduce N or go hierarchical.
- Spawning more than 10 from one orchestrator → almost always wrong; use hierarchy.

## Adaptive vs fixed-N

### Adaptive (orchestrator-decomposes-then-dispatches) — preferred default

Anthropic's pattern: lead agent reads the query, decomposes it into subtasks, and dispatches as many sub-agents as the decomposition produced (within a budget). The decomposition determines N. The orchestrator prompt encodes scaling heuristics ("simple → 1, comparison → 2–4, complex → 10+") so it can self-budget.

Use adaptive sizing as the default for research, exploration, broad question answering — anywhere the right N is data-dependent.

### Fixed-N — use when the structure is the answer

- Debate: fixed N=3 (×2–4 rounds).
- Self-consistency: fixed N=5 (or 10 for high-stakes).
- Generator-verifier: fixed N=2.
- Builder/tester/reviewer: fixed N=3.
- Red team / blue team / judge: fixed N=2 or 3.
- MoA-style ensemble: fixed N=6×3 (or 6×2).

### Adaptive or fixed?

- Task *structure* dictates N (debate, voting, role triad) → fixed.
- Task *content* dictates N (research scope, branching factor) → adaptive.
- Hybrid: adaptive at the top (orchestrator picks N research workers), fixed below (each worker uses N=3 self-consistency on its sub-question).

## Worked picks for common task shapes

Apply the decision rules to concrete shapes that come up in Claude Code work.

### "Refactor this function and make sure tests pass"

Sequential. Edit → run tests → read failures → fix. N=1. Each step depends on the previous; no independent parallel work. If you split into "edit agent" + "test agent," the test agent waits on the edit agent and the orchestrator becomes pure overhead.

### "Audit this PR for security, perf, and style"

Three genuinely independent angles, each with a distinct deliverable. N=3, one sub-agent per angle, each scoped to its own checklist. Synthesise at the end. Adding a fourth ("readability") risks overlap with style — merge it instead.

### "Find every place we call the deprecated API across this monorepo"

Map-reduce. N = number of top-level packages, capped at 4–6 concurrent for rate limits. Each shard returns a list of hits; orchestrator concatenates. No accuracy benefit from cross-shard debate.

### "Pick the best architecture for this new service"

Adversarial / debate shape. N=3 agents × 2–3 rounds: two propose competing designs, one judges against criteria you supply. Past 3 rounds you'll see drift; past 4 agents accuracy drops.

### "Solve this hard reasoning puzzle"

Self-consistency. N=5 samples, majority vote. Increase to 10 only if the puzzle is high-stakes or N=5 disagreement is high. Do not run debate here — debate adds cost without diversity gain on closed-form reasoning.

### "Research how five LLM frameworks handle X"

Adaptive research fan-out. N = number of frameworks (5), one sub-agent each, each returning a 1–2k summary. This is exactly Anthropic's documented sweet spot. Do not add a sixth "synthesis sub-agent" — synthesis is the orchestrator's job.

### "Write the next chapter of this novel"

Creative coherence. N=1. A second voice dilutes the existing voice. If you must verify (style consistency, plot continuity), N=2 with the second agent in pure verifier role — never co-author.

### "Build this whole feature: design + code + tests + docs"

If the four outputs are independent, fixed-N triad-plus: 3 (builder/tester/reviewer) + a docs writer downstream. If design must precede code, sequence design as N=1 first, then fan out the remaining three. Don't run all four in parallel — design output is an input to the others.

## Why "3" shows up so often

Three is the smallest N that gives:

- Tie-breaking for votes (odd > 1).
- Three distinct roles without overlap (producer / critic / arbiter).
- Enough diversity to reduce single-agent variance without saturating the orchestrator.
- A natural mapping to most decomposable tasks (decompose → execute → synthesise).

Five core picking heuristics:

1. **Match N to the natural decomposition of the problem — don't pad.** If the task naturally decomposes into 3 independent subqueries, use 3 agents. If into 7, use 7. Inventing extra "perspectives" for a 3-part problem is the most common failure mode.
2. **N = number of genuinely independent subqueries.** "Independent" means no agent needs another's output and they touch different files/sources. If subtask B needs A's output, sequence them or merge into one agent.
3. **For voting / debate / self-consistency: odd N ≥ 3, with diminishing returns past 5.** Odd to break ties; 3 usually enough; 5 captures most additional diversity; >7 rarely justifies cost outside high-stakes accuracy work.
4. **For breadth-first search / research fan-out: N scales with branching factor of the problem, capped by orchestrator synthesis bandwidth (~5–10).** Past ~10 direct reports, switch to hierarchical (sub-supervisors).
5. **Don't fan out below the coordination break-even.** If a sub-agent's work is <1 minute or <2k tokens, orchestration overhead exceeds the parallelism gain. Just do it inline.

## Sources

- [Anthropic — How we built our multi-agent research system (2025-06-13)](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Anthropic — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Anthropic — Multi-agent coordination patterns](https://claude.com/blog/multi-agent-coordination-patterns)
- [Anthropic — Subagents in Claude Code](https://claude.com/blog/subagents-in-claude-code)
- [Claude Code Docs — Create custom subagents](https://code.claude.com/docs/en/sub-agents)
- [Wang et al. 2022 — Self-Consistency Improves Chain of Thought (arXiv:2203.11171)](https://arxiv.org/abs/2203.11171)
- [Du et al. 2023 — Improving Factuality and Reasoning through Multiagent Debate (arXiv:2305.14325)](https://arxiv.org/abs/2305.14325)
- [Du et al. 2023 — Project page](https://composable-models.github.io/llm_debate/)
- [Wang et al. 2024 — Mixture-of-Agents Enhances LLM Capabilities (arXiv:2406.04692)](https://arxiv.org/abs/2406.04692)
- [Together AI — MoA blog post](https://www.together.ai/blog/together-moa)
- [Li et al. 2024 — More Agents Is All You Need (arXiv:2402.05120)](https://arxiv.org/abs/2402.05120)
- [Loo 2025 — Reevaluating Self-Consistency Scaling in Multi-Agent Systems (arXiv:2511.00751)](https://arxiv.org/abs/2511.00751)
- [Cemri et al. 2025 — Why Do Multi-Agent LLM Systems Fail? (arXiv:2503.13657, NeurIPS 2025)](https://arxiv.org/abs/2503.13657)
- [Estornell et al. 2025 — Talk Isn't Always Cheap (arXiv:2509.05396)](https://arxiv.org/abs/2509.05396)
- [Sean Moran (TDS) — Why Your Multi-Agent System Is Failing: 17× Error Trap](https://towardsdatascience.com/why-your-multi-agent-system-is-failing-escaping-the-17x-error-trap-of-the-bag-of-agents/)
- [Addy Osmani — The Code Agent Orchestra](https://addyosmani.com/blog/code-agent-orchestra/)
- [Simon Willison — Notes on Anthropic multi-agent post (2025-06-14)](https://simonwillison.net/2025/Jun/14/multi-agent-research-system/)
- [LangGraph — Hierarchical agent teams tutorial](https://langchain-ai.github.io/langgraph/tutorials/multi_agent/hierarchical_agent_teams/)
- [LangGraph — Scaling agents: parallelization, subgraphs, map-reduce](https://aipractitioner.substack.com/p/scaling-langgraph-agents-parallelization)
- [CrewAI — Crafting effective agents](https://docs.crewai.com/en/guides/agents/crafting-effective-agents)
- [LLM×MapReduce (thunlp, arXiv:2410.09342)](https://arxiv.org/html/2410.09342v1)
- [PAIR / red-team triad — From Promise to Peril (arXiv:2506.13434)](https://arxiv.org/html/2506.13434v1)
- [Multi-Agent Debate Literature Review (arXiv:2506.00066)](https://arxiv.org/html/2506.00066v1)
- [GroupDebate — Enhancing the Efficiency of Multi-Agent Debate (arXiv:2409.14051)](https://arxiv.org/html/2409.14051)
