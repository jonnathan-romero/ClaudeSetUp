# Topologies and Decomposition

How to choose the *shape* of an agent system and the *information-flow* pattern that runs through it. Topology answers "who can talk to whom"; decomposition answers "what depends on what." Pick the wrong topology and you pay coordination cost with no payoff. Pick the wrong decomposition and you either compound errors in a forced chain or stitch together a forced fan-out. The two views answer the same question from different angles — start with the dependency graph (decomposition), then pick the topology that fits its shape.

## Contents

- [When to consult this](#when-to-consult-this)
- [The two-axis frame](#the-two-axis-frame)
- [Topology taxonomy](#topology-taxonomy)
  - [Hierarchical / orchestrator-worker](#hierarchical--orchestrator-worker)
  - [Star / hub-and-spoke](#star--hub-and-spoke)
  - [Pipeline / sequential handoff](#pipeline--sequential-handoff)
  - [Flat / peer / group-chat](#flat--peer--group-chat)
  - [Mesh / network / swarm](#mesh--network--swarm)
  - [Blackboard](#blackboard)
- [Topology fit table](#topology-fit-table)
- [Decomposition: the dependency-graph algorithm](#decomposition-the-dependency-graph-algorithm)
- [Sequential decomposition patterns](#sequential-decomposition-patterns)
- [Parallel decomposition patterns](#parallel-decomposition-patterns)
- [Hybrid combinations](#hybrid-combinations)
- [Hidden costs of parallelism](#hidden-costs-of-parallelism)
- [Hidden costs of sequential](#hidden-costs-of-sequential)
- [Coordination cost by topology](#coordination-cost-by-topology)
- [Failure modes by topology](#failure-modes-by-topology)
- [Decision triggers](#decision-triggers)
- [Hard "do not use" rules](#hard-do-not-use-rules)
- [Production examples](#production-examples)
- [Sources](#sources)

## When to consult this

Read this when: choosing between single-agent and multi-agent for a non-trivial task, picking among orchestrator-worker / pipeline / debate / mesh / blackboard, deciding whether to fan out subagents in parallel or chain them, designing a hybrid (plan-then-execute, gather-then-synthesize, pipeline-of-orchestrators), or sanity-checking a topology against its known failure modes. Skip when: the task is small enough for one agent, or when SKILL.md's mode tables already give an unambiguous answer.

## The two-axis frame

Two questions, asked in this order, settle most architectures.

1. **Information flow (decomposition).** Does step B's prompt need information that only step A's output produces? Yes → sequential edge. No → independent. Build the dependency graph; the antichains are your parallel batches, the longest path is your inevitable sequential length.
2. **Coordination shape (topology).** Given the graph, who routes work, who synthesizes, who can talk to whom? Same dependency graph runs differently as orchestrator-worker, pipeline, or mesh — and the choice changes cost, debuggability, and failure mode.

Decomposition is the algorithm. Topology is the runtime that executes it.

## Topology taxonomy

### Hierarchical / orchestrator-worker

A central lead decomposes the request, dispatches sub-tasks to specialized workers (often in parallel), then synthesizes results. Workers do not talk to each other; all communication funnels through the orchestrator. Workers can themselves be supervisors of sub-teams (multi-level hierarchy).

**Where used.** Anthropic Research uses Claude Opus 4 as lead with Claude Sonnet 4 sub-agents and outperformed single-agent Opus 4 by **90.2%** on Anthropic's internal research eval; lead spawns 3-5 sub-agents, each uses 3+ tools in parallel, cuts research time by up to 90% on complex queries. OpenAI Deep Research wraps an orchestrator (triage / clarification / instruction / research) over an o3-class reasoning model. CrewAI's hierarchical process spins up a `manager_llm` or `manager_agent` that reviews outputs and assesses task completion. LangGraph supervisor (`langgraph-supervisor-py`) coordinates specialized agents via handoff tools and supports nested supervisors. Cursor 2.0 / 3.2 runs Architect → Planner → up to 8 parallel Implementation agents in worktrees.

**Good when.** One agent can plan the whole task; sub-tasks are independent and parallelizable; results need unified synthesis; "read-mode" work like research and data gathering.

**Bad when.** Sub-tasks have heavy interdependencies; orchestrator can't hold the planning context; tasks require coordinated *writes* (Cognition's anti-pattern).

### Star / hub-and-spoke

A degenerate hierarchical: workers exist purely to serve the hub, never see each other's outputs, never coordinate. Same as pure supervisor when the supervisor never aggregates intermediate state into worker prompts. Most "Anthropic Research" diagrams are technically star — workers only know what the orchestrator told them.

**Useful distinction.** In true hierarchical the supervisor can relay context across siblings; in star you keep workers maximally isolated. Star is cheaper per worker because each prompt stays small; true hierarchical produces better synthesis because workers benefit from each other's intermediate findings.

**Good when.** Workers must remain context-isolated for cost or safety; you want maximum parallelism without cross-contamination.

**Bad when.** Workers would benefit from each other's intermediate findings.

### Pipeline / sequential handoff

A → B → C. Each agent does its stage, then hands the artifact (or accumulated context) to the next. Information flows one direction; stages are fixed at design time.

**Where used.** CrewAI's sequential process is the default — tasks execute *"in an orderly progression"*; output of task N becomes context for task N+1. OpenAI Agents SDK `handoff()` exposes target agents as tools (e.g. `transfer_to_refund_agent`); the receiving agent inherits the full conversation history (or a filtered subset). Stripe's business-verification DAG runs as a fixed pipeline for audit-grade traceability. Anthropic's "prompt chaining" is the simplest workflow of this shape.

**Good when.** Stages are clearly ordered with one-way information flow (research → outline → draft → edit); each stage's output is well-typed; latency budget allows series execution.

**Bad when.** Late stages need to revise early-stage assumptions; stages have variable count or order; errors compound.

### Flat / peer / group-chat

N agents share a single message thread. A lightweight chat-manager (round-robin, LLM-based selector, or human) chooses who speaks next. There is no central planner deciding sub-tasks — agents react to whatever's on the thread. Used for debate, brainstorming, role-played collaboration.

**Where used.** AutoGen `GroupChat` / `SelectorGroupChat` is the flagship implementation; Microsoft's documentation explicitly calls the canonical example *"not meant to be used in real applications."* The Multi-Agent Debate (MAD) literature has agents argue tit-for-tat with a judge synthesizing. OpenAI Swarm reference (now folded into Agents SDK) implements a peer pattern via handoffs.

**Good when.** No single agent has global view; multiple perspectives genuinely improve the answer (debate, ideation, code review); small N (≤4).

**Bad when.** Simple tasks; production systems needing reliable termination; tasks with a clear "right answer" — debate adds noise.

### Mesh / network / swarm

Any agent can call any other agent based on what's discovered mid-task. There is no fixed graph and no central coordinator deciding routing. Agents themselves choose who to "ask."

**Where used.** LangGraph network architecture; LangGraph swarm (`langgraph-swarm-py`) tracks `active_agent` so subsequent turns resume with whoever's "in charge"; Anthropic's "autonomous agents" concept for open-ended problems where you can't predict the call graph.

**Good when.** Call patterns are unknowable in advance; interactive coding agents; agents need to "ask a colleague" mid-task; conversation-resumable assistants.

**Bad when.** Production reliability matters; debugging matters; budget is bounded; you cannot enumerate likely call paths. Towards Data Science reports a **17.2× error amplification** in unstructured agent meshes; centralized orchestration knocks that down to ~4.4×.

### Blackboard

Agents read and write to a shared workspace. They do not message each other directly. A control mechanism (originally explicit, now often the agents' own reasoning) decides who acts next; each "knowledge source" watches for state matching its expertise and contributes when relevant.

**Where used.** Classical: HEARSAY-II speech understanding (Erman, Hayes-Roth, Lesser, Reddy, 1980). Modern revival: "LLM-based Multi-Agent Blackboard System for Information Discovery in Data Science" (arXiv:2510.01285, Oct 2025) reports **13–57% relative improvement over master-slave baseline**, up to 9% F1 gain — key insight: *"responses are directed exclusively to the response board"* to avoid agents pulling each other off-task. LangGraph custom workflows with shared `state` schema effectively implement blackboard semantics.

**Good when.** Many agents contribute to a shared artifact; worker capabilities vary or evolve; opportunistic problem-solving (data discovery, design synthesis). Blackboard solves the master-slave coordination problem — a central controller needs accurate knowledge of every worker's capabilities to assign tasks, while with a blackboard workers self-select.

**Bad when.** Strong consistency required on the artifact; race conditions matter; you need a single linear trace for debugging.

## Topology fit table

| Topology | Good when | Bad when |
|---|---|---|
| Hierarchical / orchestrator-worker | Planner can hold the whole task; sub-tasks independent; "read-mode" work | Heavy interdependencies; coordinated *writes* |
| Star / hub-and-spoke | Workers must stay context-isolated; max parallelism | Workers would benefit from siblings' findings |
| Pipeline / sequential | Fixed ordered stages with one-way data flow | Late stages need to revise early stages |
| Flat / group-chat | Debate, ideation, code review; small N (≤4) | Production with reliable termination needed |
| Mesh / network / swarm | Unknowable call patterns; interactive coding | Production reliability; bounded budget |
| Blackboard | Heterogeneous workers contributing to one artifact | Strong consistency; single trace required |

Anthropic's rule of thumb (paraphrased from "Building Effective Agents"): orchestrator-workers for *"complex tasks where you can't predict the subtasks needed"*; pipeline for *"tasks decomposable into fixed sequential subtasks"*; parallelization (sectioning/voting) for *"subtasks parallelizable for speed, or multiple perspectives needed for higher confidence"*; autonomous agents for *"open-ended problems where it's difficult or impossible to predict the required number of steps."*

## Decomposition: the dependency-graph algorithm

The single best diagnostic question:

> **"Does step B's prompt need information that only step A's output produces?"** If yes → sequential. If no → parallel.

Run this analysis explicitly before spawning subagents — it is the same analysis classical workflow engines (Airflow DAGs, Prefect, build systems) perform.

1. **List the sub-questions / sub-artifacts** the task implies.
2. **For each pair (A, B)**, ask: can I write the prompt for B right now without referring to A's output? If yes → independent. If you find yourself writing "based on the result of A, do…" → dependent.
3. **Build the dependency graph.** Nodes = subtasks, edges = true dependencies.
4. **Identify antichains** (sets of nodes with no edges between them). Each antichain is a parallel batch. The graph's longest path is the inevitable sequential length.
5. **Insert a synthesis node** wherever a fan-out converges.

### True vs false vs preference dependencies

| Type | Example | Treatment |
|---|---|---|
| True dependency | "Implement the plan" needs the plan. | Must be sequential. |
| False dependency | "Search for X" and "search for Y" both feed a writeup but neither needs the other. | Parallel. |
| Ordering preference | "I usually research before writing" — but the section is small enough that the writer can do its own research. | Either; pick by latency/quality. |
| Synthesis dependency | N parallel results all flow into a synthesizer. | Parallel-then-sequential. |

If you can't articulate *what specific information* B needs from A, the dependency is preference, not necessity — and you can parallelize.

## Sequential decomposition patterns

### Prompt chaining

Output of step n → input of step n+1. Each step is intentionally simpler than the whole. Anthropic recommends this *"for situations where the task can be easily and cleanly decomposed into fixed subtasks,"* trading latency for accuracy. Insert programmatic gates between stages — Anthropic explicitly recommends a regex/schema/test must pass before continuing; failed gate → retry that stage, don't propagate downstream.

### Iterative refinement (Self-Refine, Reflexion)

Draft → critique → revise → critique → revise. Self-Refine (Madaan et al., 2023) reports ~20% absolute improvement using one model as generator/critic/refiner over single-pass output. Reflexion (Shinn et al., 2023) reports 91% pass@1 on HumanEval vs GPT-4's 80%. Hard-cap at 3–5 rounds; both papers observe diminishing or negative returns past ~3 iterations.

### Pipeline stages

research → plan → implement → test → review. Each stage is a different *kind* of work needing different prompts/tools/personae. Insert validation gates between every stage; a failed test stage means the implement stage gets re-invoked, not the planner. Per-stage retries (e.g. 2× retry per stage) plus a global cap.

### Conditional routing

A classifier/router LLM picks the next agent based on current output. Anthropic's "Routing" workflow; LangGraph's supervisor pattern fits here. Anti-pattern: infinite routing loops and *"progressive context loss with each transfer"* in dynamic handoffs. Cap on number of hops; force a "give up / escalate" terminal state.

### Reflexion / self-correction loops

Try → get feedback (test, error, critic) → store reflection in memory → retry with reflection in context. The external success signal IS the gate; stop on success or max trials. Ensure the "reflection" isn't just a verbose echo of the last failure.

## Parallel decomposition patterns

### Map-reduce / fan-out-fan-in

Orchestrator splits work into N independent units → N workers → synthesizer reduces. Anthropic's research orchestrator-worker is the canonical example. Beam.ai recommends fan-out when **≥4 independent subtasks** exist and wall-clock matters. Anthropic's effort heuristic: *"Simple fact-finding requires just 1 agent with 3-10 tool calls, direct comparisons might need 2-4 subagents with 10-15 calls each, and complex research might use more than 10 subagents."* The synthesizer must deduplicate, resolve conflicts, preserve attribution, and drop noise — a bad synthesizer is the hidden tax.

### Self-consistency

Run the *same* prompt N times with sampling temperature > 0, then vote / take majority. Wang et al. (2022) report +6–18% across reasoning benchmarks (GSM8K +17.9%, SVAMP +11.0%, AQuA +12.2%). Best when there's a single discrete correct answer. Empirically N = 5–40; gains saturate. Pick a budget and stop.

### Mixture-of-Agents (MoA)

L layers, each with N proposers; outputs of layer ℓ feed every agent in layer ℓ+1; final layer is a single aggregator. Wang et al. (2024) leverage the *"collaborativeness phenomenon"* — an LLM produces better output when it can see other models' attempts, even weaker ones. MoA achieves 65.1% on AlpacaEval 2.0 vs GPT-4 Omni's 57.5%. The aggregator uses a specific *"Aggregate-and-Synthesize"* prompt — critically evaluate, do not simply replicate. Default 3 layers × 6 proposers; *"the first response aggregation has the most significant boost"* — diminishing returns past 2 layers (MoA-Lite). **Hidden cost:** time-to-first-token is terrible — *"the method cannot decide the first token until the last MoA layer is reached."* Never use for interactive UX.

### Breadth-first search / Tree-of-Thoughts-style

Explore K branches in parallel at each node; prune low-value branches before next expansion. Best when the solution space is wide and most branches are dead ends. K usually small (3–5) per level; budget = K × depth.

### Sectioning

Pre-defined splits — chapters of a doc, modules of a codebase, sections of a report — each written in parallel. Best when the output structure is known up front and sections are loosely coupled. Synthesizer stitches, harmonizes voice/terminology, reconciles cross-references. Anti-pattern: dense cross-references between sections force the synthesizer into heavy post-editing.

## Hybrid combinations

Most real workflows are hybrid. The dependency graph almost never collapses to "all parallel" or "all sequential." Pure topologies are rare in production.

### Pipeline with parallel stages

*Sequential outer skeleton, parallel inner stages.* Research (parallel) → Plan (single) → Implement (parallel by file) → Test (single) → Review (parallel: security, perf, style) → Final synthesis (single). This is what Anthropic's research system effectively does, and what LangGraph's supervisor + Send API enables — *"first generate a list of tasks, and then use Send API to process them in parallel."*

### Parallel-then-sequential (gather → synthesize)

Default research pattern. Fan out to gather diverse evidence; one agent synthesizes. The synthesizer must have enough context to actually integrate, not just concatenate. Without structured aggregation, the synthesizer becomes the failure point.

### Sequential-then-parallel (plan → execute)

A planner produces a structured plan; parallel executors each take one item. This is the orchestrator-workers pattern with explicit planning. The planner provides the **shared context** the parallel workers would otherwise lack — the most important fix for the "context-less subagent" failure mode.

### Parallel-sequential-parallel

Common in large refactors: parallel scout → single architect drafts the plan → parallel implementers per module → single integrator.

### Pipeline of orchestrators

Stage 1 is an orchestrator+workers, stage 2 is another (research → drafting → review). OpenAI Deep Research is this shape.

### Single-threaded write + multi-agent read

Cognition's production pattern. Devin writes code single-threaded; a separate Devin Review agent (clean context) audits the diff. Catches ~2 bugs/PR, ~58% severe. Reconciles the Anthropic/Cognition disagreement: read-heavy parallelizes, write-heavy stays single-threaded.

### Verifier-critic loop

Generator + critic with bounded revise cycles. Hybrid of pipeline + evaluator. Always cap rounds.

## Hidden costs of parallelism

Parallelism *looks* free. It is not. These costs flip the decision toward sequential.

1. **Synthesis cost can dominate.** Combining N noisy outputs is often *harder* than producing one good iterative output. *"The aggregation step itself introduces error. LLM-based synthesis can hallucinate consensus that doesn't exist in the underlying results."*
2. **Subagents lack context.** They don't see what earlier-stage decisions would have given them. Anthropic explicitly notes multi-agent struggles in *"domains requiring all agents to share the same context or involve many dependencies between agents."* A planner stage in front of parallel workers helps.
3. **Duplicate work.** N agents researching the same topic without coordination overlap heavily.
4. **Quadratic coordination.** *"A system with N agents has N(N-1)/2 potential concurrent interactions."* Beyond fan-out/fan-in topologies, debate or peer messaging *"can start to feel closer to an n² effect."*
5. **Token blow-up.** Anthropic measured *"agents typically use about 4× more tokens than chat interactions, and multi-agent systems use about 15× more tokens than chats."* Token usage explains **80% of variance** in their browsing benchmark.
6. **Rate limits and resource contention.** *"If the Wikipedia API allows 60 requests per minute and five parallel searches run simultaneously, the quota gets consumed in 12 seconds instead of 1 minute."*
7. **Atomic failure.** *"If one parallel node fails, the entire superstep fails atomically"* — successful sibling work can be wasted.
8. **Error amplification in unstructured fan-out.** Towards Data Science reports a **17.2× error amplification** in unstructured agent meshes; centralized orchestration knocks that down to ~4.4×.
9. **Single agent often wins.** Beam.ai reports *"a single agent matched or outperformed multi-agent systems on 64% of benchmarked tasks"* at equivalent resources.

**Flip-the-decision triggers.** If synthesis is the hardest part, or subagents need shared state, or the task is state-dependent reasoning — go sequential.

## Hidden costs of sequential

These costs flip the decision toward parallel.

1. **Latency is linear in chain length.** N steps of T seconds each = N·T wall-clock; N parallel = T.
2. **Error compounding.** *"If an error occurs early in the chain, it can cascade through subsequent steps, compounding the mistake."*
3. **False consensus / echo chambers.** In multi-round chains, *"minor deviations regarding factuality or faithfulness are repeatedly cited and reused…eventually evolving into a false consensus at the system level."*
4. **Context accumulation.** Later stages drown in earlier output; the most recent stage's prompt may exceed the context window or dilute its instructions.
5. **No alternatives explored.** Sequential commits to one path early; parallel can compare K candidates and pick.
6. **Single point of failure per stage.** A stage that hallucinates pollutes everything downstream — there's no sibling to outvote it (unlike self-consistency).
7. **Token overhead too.** Beam.ai notes sequential pipelines often have *"3× token overhead for equivalent single-agent work"* because state gets re-shipped.

**Flip-the-decision triggers.** If latency budget is tight, or you need to explore alternatives, or you can verify/vote rather than refine — go parallel.

**On state-dependent reasoning.** Research cited in *Towards Data Science* shows that on *"strictly sequential, state-dependent planning, every multi-agent variant degrades performance ~−39% to −70%"* — parallel coordination overhead consumes budget without providing real parallel advantage. Multi-agent does not rescue inherently sequential reasoning.

## Coordination cost by topology

| Topology | Where the cost lives | Concrete failure mode |
|---|---|---|
| Hierarchical | Centralized on the orchestrator's context window | Orchestrator becomes a context-bloat blind spot. **~15× more tokens than chat**; **token usage explains 80% of variance** in Anthropic's browsing benchmark. |
| Flat / group-chat | O(N²) message complexity as everyone reads everyone | Chat devolves; AutoGen termination is famously fragile (~90% reliability with prompt-based termination); needs `MaxMessageTermination`, `TextMentionTermination`, `TokenUsageTermination`, or function-call kill-switches. |
| Pipeline | Cumulative context loss along the chain | Late agents lose nuance from early agents; errors compound. Each stage either inherits full history (ballooning context) or a summary (lossy). OpenAI Agents SDK exposes `input_filter` to manage this. |
| Mesh | Unbounded; potentially infinite | Loops; uncontrolled fan-out; debugging hell. LangGraph swarm requires explicit checkpointer + bounded state to avoid runaway. |
| Star | Same as hierarchical, but workers can't help each other compress | Most expensive per insight; orchestrator repeats context to each worker. |
| Blackboard | Read/write conflict resolution | Race conditions; conflicting writes; hard to construct a single trace. |

**Hard tradeoff to internalize.** Anthropic's explicit guidance: prefer multi-agent for tasks *"whose value is high enough to pay for the increased performance."* Don't reach for multi-agent reflexively when the value-per-token is low.

## Failure modes by topology

### Hierarchical / orchestrator-worker
- **Bottleneck/blind spot** — orchestrator can't see what workers don't surface; can't catch worker errors it didn't predict.
- **Vague task descriptions** — Anthropic notes subagents *"duplicate efforts or leave gaps in coverage"* without precise instructions including objective, output format, tools, sources, and boundaries.
- **Over-spawning** — lead agent spawns 50+ subagents for trivial queries (Anthropic listed this as a top failure mode).
- **Sub-agent quality drift** — workers can't fix orchestrator misunderstandings.

### Flat / group-chat
- **Non-termination** — hard-coded "TERMINATE" string detection is buggy; LLMs forget to emit it.
- **Talking past each other / collusion** — identity-driven biases; agents either defer to peers or cling to their own answers (arXiv:2510.07517 on identity bias in MAD).
- **Premature convergence** in debate.
- **No global goal-anchor** — drift over rounds.

### Pipeline / sequential
- **Compounding errors** — stage 3 inherits stage 1's bad assumption.
- **Late-stage powerlessness** — edit-stage can't restructure draft-stage's framing.
- **Context inflation** when each stage appends raw output, or **context loss** when each stage summarizes.
- **Capability mismatch** in plan-and-execute when planner is stronger than executor.

### Mesh / swarm
- **Infinite loops** (A calls B calls A).
- **Unbounded fan-out** (each agent calls 3 others; explosion).
- **Debugging hell** — no canonical trace; timing-dependent.
- **Goal drift without supervisor.**
- **Cost explosion** when handoffs pass full message history each time.

### Blackboard
- **Race conditions** on writes.
- **Conflicting contributions** with no resolver.
- **Hard to reason about** — state mutations from N agents in unpredictable order.
- **Control problem** — when does it stop? who fires? Classical blackboard systems needed an explicit control shell; the 2025 LLM revival leans on the main agent's reasoning instead.

### Anti-patterns (decomposition)
- **Premature parallelization.** Forcing fan-out on a task that wanted one coherent pass — pays full synthesis cost and produces a stitched-together result. Symptom: the synthesizer prompt grows huge and you're still post-editing.
- **Forced sequencing.** Inventing artificial "first do A, then B" when A and B are actually independent — pays full latency penalty for nothing. Symptom: A's output gets pasted into B's prompt but B never references it.
- **Parallel-then-merge-conflict.** N agents each modify the same artifact; the synthesizer becomes a merge-conflict resolver. Avoid by partitioning the artifact (sectioning) or doing it sequentially.
- **Sequential pipeline with no mid-pipeline validation.** Errors propagate to the end before being caught. Always insert gates between stages.
- **The "bag of agents."** Unstructured network with no orchestrator → up to **17.2× error amplification**.
- **Infinite refinement / debate loops.** No iteration cap → agents reinforce each other's errors or stall.
- **Hallucinated consensus.** Synthesizer claims agreement that doesn't exist. Mitigation: ask synthesizer to surface disagreements explicitly.
- **Context-less subagents.** Spawning workers without enough brief — they re-derive context badly. Mitigation: a planner stage produces shared context; orchestrator gives each worker *"an objective, an output format, guidance on the tools and sources to use, and clear task boundaries"* (Anthropic).
- **Parallel for tasks under the 45% baseline-quality saturation.** Adding agents only helps when single-agent baseline is already weak; above ~80% it adds noise.
- **MoA-style stacking for interactive use.** TTFT is unacceptable.

## Decision triggers

A decision tree to run top-to-bottom. Take the first match.

1. **If this is a single, coherent write to one artifact (one codebase, one document, one config), prefer single agent** — add a verifier-critic only if the artifact is high-stakes (Cognition's rule).
2. **If steps are fixed and known with one-way information flow, prefer pipeline** (CrewAI sequential, OpenAI Agents SDK handoffs, prompt chaining) — insert gates between stages.
3. **If the task decomposes cleanly into independent sub-tasks whose results can be combined at the end, and the value is high enough to justify ~15× tokens, prefer hierarchical / orchestrator-worker** — pre-write strict sub-task contracts (objective, output format, tools, boundaries) and bound the worker count.
4. **If the task requires multiple perspectives meeting in the middle (debate, code review, multi-rubric evaluation), prefer flat / debate** with small N (2–4) and a synthesizing judge — hard-cap rounds, anonymize speakers if worried about identity bias.
5. **If interaction patterns are unknowable until mid-task, use mesh / swarm only if** you can bound state, set a hop budget, and tolerate debugging difficulty — otherwise lift to hierarchical by inserting a router/supervisor.
6. **If many agents independently contribute to a shared artifact whose final form emerges from contributions, and capabilities are heterogeneous or evolving, consider blackboard** — with explicit conflict resolution and termination conditions.
7. **If sub-tasks themselves require multiple perspectives, OR the system has more than one phase, prefer hybrid** — hierarchical with peer subteams, or pipeline-of-orchestrators.

### Decomposition triggers

**Trigger → parallel:**
- Sub-task prompts can be written without referring to another sub-task's output → fan out.
- Same task with different perspectives / samples → parallel + voter (self-consistency / MoA).
- ≥4 independent subtasks and wall-clock matters → fan-out/fan-in (Beam threshold).
- Gathering from N independent sources → parallel research, then synthesize.
- Latency budget < sum of sequential stages → parallelize the antichains.

**Trigger → sequential:**
- Step N's prompt requires step N-1's output → chain.
- Refining the same artifact through stages (draft/critique/revise) → iterative refinement, capped at 3–5 rounds.
- Each stage is a different *kind* of work (research/plan/implement/test) → pipeline with gates.
- Reasoning is state-dependent (planning, multi-hop logic) → sequential; multi-agent here can degrade −39% to −70%.
- Need an audit trail or human-in-the-loop gate between stages → sequential.

**Trigger → hybrid:**
- Planning step followed by independent execution items → sequential plan → parallel execute.
- Need to gather broadly then write coherently → parallel gather → single synthesize.

**Trigger → don't decompose at all:**
- Single coherent task, modest size, single model can hold it all in context → one call (64% of tasks per Beam.ai).
- Baseline single-agent quality already > 80% on this kind of task → multi-agent adds noise, not signal (45% saturation rule, TDS).

## Hard "do not use" rules

- **Don't use group-chat in production without guaranteed termination conditions** (`MaxMessageTermination` + a function-call kill-switch).
- **Don't use multi-agent at all if a single agent with retrieval and good tool docs reaches your quality bar** — Anthropic's own opening guidance is "start simple."
- **Don't parallelize *writes* across agents** (Cognition).
- **Don't use mesh in production without a bounded hop budget and per-edge metrics.**
- **Don't use MoA-style stacking for interactive UX** — TTFT is unacceptable.
- **State the termination condition before recommending a topology.** Every multi-agent topology except pipeline needs an explicit termination strategy.

Three escalation rules from the 2026 taxonomy guide, worth quoting verbatim:
- *"Start single-agent. Escalate to multi-agent only when single-agent caps out on a measured quality dimension."*
- *"Hierarchical wins over swarm in production almost every time. The supervisor anchors goal alignment."*
- *"Avoid swarm in production; use in research mode only."*

## Production examples

| System | Topology | Notes |
|---|---|---|
| Anthropic Research / Claude Research | Hierarchical (often star-shaped) | Opus 4 lead + 3-5 Sonnet 4 workers, parallel tools. **90.2%** better than single-agent Opus 4. Workers don't talk to each other. CitationAgent runs as a separate post-process. |
| OpenAI Deep Research | Hierarchical with explicit triage stage | Triage → clarification → instruction → research over o3-class reasoning. Pipeline-of-orchestrators flavor. |
| Google Gemini Deep Research | Hierarchical with up-front planning + user approval gate | Plan → user approves → parallel execution → synthesis. |
| Cognition Devin | Single-threaded write + separate review (hybrid) | "Don't Build Multi-Agents" (June 2025): writes stay single-threaded; only "intelligence" parallelizes. Devin Review runs in **clean context** to avoid context rot. |
| Cursor 2.0 / 3.2 | Hierarchical with parallel implementation in git worktrees | Architect → Planner → up to 8 Implementation agents. /multitask spawns async sub-agents. |
| CrewAI | Pipeline (default) or hierarchical (`manager_llm`) | User picks via `process=` parameter. |
| LangGraph supervisor | Hierarchical with tool-call handoffs | Default for production. Supports nesting. |
| LangGraph swarm | Mesh with `active_agent` continuity | Used for chat-resumable assistants. |
| AutoGen GroupChat | Flat | Microsoft explicitly cautions the canonical example is *"not meant for real applications."* |
| OpenAI Agents SDK | Pipeline via handoffs (default) | Handoffs are tool-calls; receiving agent inherits conversation. |
| Stripe business verification | Pipeline (DAG) | Audit-grade traceability. |
| IBM watsonx Orchestrate | Hierarchical | Routes across 80+ domain agents. |
| HEARSAY-II | Blackboard | Canonical reference architecture. |
| arXiv:2510.01285 data discovery | Blackboard | Main agent posts, helpers self-select. **13–57% gain** over master-slave. |

**The architecture debate.** Anthropic and Cognition publicly disagree, but their stances are reconcilable:
- Anthropic: read-heavy, parallelizable, synthesize-at-end → multi-agent wins.
- Cognition: write-heavy, coherent decisions, single artifact → single-agent wins.

Cognition's two principles, paraphrased: (1) *"share context, and share full agent traces, not just individual messages"*; (2) *"actions carry implicit decisions, and conflicting decisions carry bad results."*

The single best decision axis is **read vs write.** Anthropic-style multi-agent shines when many agents read the world in parallel; Cognition's rule says don't parallelize writes. This one axis explains most of the public disagreement.

## Sources

**Primary frameworks & vendor docs**
- Anthropic, "Building Effective Agents" (Dec 2024) — anthropic.com/research/building-effective-agents
- Anthropic, "How we built our multi-agent research system" (June 2025) — anthropic.com/engineering/built-multi-agent-research-system
- LangGraph multi-agent concepts — langchain-ai.github.io/langgraph/concepts/multi_agent/
- LangGraph supervisor — github.com/langchain-ai/langgraph-supervisor-py
- LangGraph swarm — github.com/langchain-ai/langgraph-swarm-py
- LangGraph hierarchical agent teams — langchain-ai.github.io/langgraph/tutorials/multi_agent/hierarchical_agent_teams/
- AutoGen GroupChat — microsoft.github.io/autogen/stable/user-guide/core-user-guide/design-patterns/group-chat.html
- CrewAI processes — docs.crewai.com/concepts/processes
- OpenAI Agents SDK handoffs — openai.github.io/openai-agents-python/handoffs/
- OpenAI Deep Research announcement (Feb 2025) — openai.com/index/introducing-deep-research/
- AWS Prescriptive Guidance — Workflow for Prompt Chaining — docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-patterns/workflow-for-prompt-chaining.html

**Production-architecture commentary**
- Cognition, "Don't Build Multi-Agents" (June 2025) — cognition.ai/blog/dont-build-multi-agents
- ZenML LLMOps DB, "Cognition: Multi-Agent Systems in Production"
- "How OpenAI, Gemini, and Claude Use Agents to Power Deep Research" — blog.bytebytego.com
- "Agent Architecture Patterns: 2026 Taxonomy Guide" — digitalapplied.com/blog/agent-architecture-patterns-taxonomy-2026
- Cursor 2.0 changelog — cursor.com/changelog/2-0
- Beam.ai, "6 Multi-Agent Orchestration Patterns for Production (2026)" — beam.ai/agentic-insights/multi-agent-orchestration-patterns-production
- Towards Data Science, "Why Your Multi-Agent System is Failing: Escaping the 17x Error Trap of the 'Bag of Agents'"
- Skywork, "Multi-Agent Parallel Execution"
- AI Practitioner, "Scaling LangGraph Agents: Parallelization, Subgraphs, and Map-Reduce Trade-Offs"
- Simon Willison, "Embracing the parallel coding agent lifestyle" (Oct 2025)

**Academic / survey**
- Wu et al., "Multi-Agent Collaboration Mechanisms: A Survey of LLMs," arXiv:2501.06322 (Jan 2025)
- Wang et al., "Self-Consistency Improves Chain-of-Thought Reasoning in Language Models," arXiv:2203.11171 (2022)
- Wang et al., "Mixture-of-Agents Enhances Large Language Model Capabilities," arXiv:2406.04692 (2024)
- Shinn et al., "Reflexion: Language Agents with Verbal Reinforcement Learning," arXiv:2303.11366 (2023)
- Madaan et al., "Self-Refine: Iterative Refinement with Self-Feedback," arXiv:2303.17651 (2023)
- "Literature Review of Multi-Agent Debate for Problem-Solving," arXiv:2506.00066 (June 2025)
- "Measuring and Mitigating Identity Bias in Multi-Agent Debate via Anonymization," arXiv:2510.07517 (Oct 2025)
- "Encouraging Divergent Thinking in LLMs through Multi-Agent Debate," ACL EMNLP 2024

**Blackboard architecture (classical and revival)**
- Erman, Hayes-Roth, Lesser, Reddy, "The Hearsay-II Speech-Understanding System" (1980)
- Lesser & Erman, "A Retrospective View of the Hearsay-II Architecture," IJCAI-77
- "LLM-based Multi-Agent Blackboard System for Information Discovery in Data Science," arXiv:2510.01285 (Oct 2025)
- "Terrarium: Revisiting the Blackboard for Multi-Agent Safety, Privacy, and Security Studies," arXiv:2510.14312 (Oct 2025)
- Silva et al., "The Reflective Blackboard Architectural Pattern" (2003), Springer
