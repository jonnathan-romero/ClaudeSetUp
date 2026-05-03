# Memory and Shared State Across Agents

How state lives, moves, and rots across multi-agent systems. Distilled to drive defaults when designing handoffs, persistence, and shared context.

## Contents

- [When to consult this](#when-to-consult-this)
- [The two anchor frames](#the-two-anchor-frames)
- [Cognition: share full traces](#cognition-share-full-traces)
- [Anthropic: distill on return](#anthropic-distill-on-return)
- [Reconciling the two](#reconciling-the-two)
- [External memory patterns](#external-memory-patterns)
- [Plan-to-file before truncation](#plan-to-file-before-truncation)
- [Anthropic memory tool](#anthropic-memory-tool)
- [Artifact storage by reference](#artifact-storage-by-reference)
- [Long-running harness pattern](#long-running-harness-pattern)
- [External memory backend comparison](#external-memory-backend-comparison)
- [Blackboard architecture](#blackboard-architecture)
- [MAST taxonomy: 14 failure modes](#mast-taxonomy-14-failure-modes)
- [The five state-handoff modes](#the-five-state-handoff-modes)
- [In-context vs out-of-context state](#in-context-vs-out-of-context-state)
- [Cross-session memory](#cross-session-memory)
- [Decision triggers](#decision-triggers)
- [Anti-patterns](#anti-patterns)
- [Bottom line](#bottom-line)
- [Sources](#sources)

## When to consult this

Read this when designing how state moves between agents — when spawning subagents, choosing between in-context and external memory, picking a handoff schema, deciding whether to distill or pass full traces, planning for context-window truncation, or designing cross-session persistence. Skip for single-shot tasks well under context budget where state never leaves one conversation.

## The two anchor frames

Two production-tested writeups from the same week of June 2025 give apparently opposite advice. They aren't contradicting each other. They describe different points on the same axis: **read-vs-write workload** and **commensurability of subagent outputs.**

- **Cognition (pessimistic frame):** default to single-threaded; only branch when parallelism is genuinely independent; when you must branch, pass the full trace.
- **Anthropic (optimistic frame):** fan out to parallel subagents with isolated context windows; distill heavily on return; externalize aggressively; verify with citations.

Pick the frame that matches the task shape. The rest of this document is the classifier.

## Cognition: share full traces

Walden Yan, ["Don't Build Multi-Agents," Cognition AI, 12 Jun 2025](https://cognition.ai/blog/dont-build-multi-agents).

Cognition states two principles as load-bearing for any agent architecture:

> **Principle 1:** *"Share context, and share full agent traces, not just individual messages."*
>
> **Principle 2:** *"Actions carry implicit decisions, and conflicting decisions carry bad results."*

A "message" is the visible output a subagent returns. A "trace" is the full reasoning chain — every tool call, every intermediate decision, every dead-end the subagent explored. When subagents pass only summaries upward, the orchestrator sees the conclusions but loses the *reasoning that produced them.* Those hidden reasoning steps are full of implicit decisions ("I interpreted 'header' as the navbar, not the page H1"; "I assumed Postgres, not MySQL"). Downstream agents that don't see those choices will silently make conflicting ones.

The Flappy Bird example in the post: Subagent 1 builds a Super Mario-style background; Subagent 2 builds a misaligned bird sprite. Each is internally consistent. The final assembler can't reconcile them because *"Subagent 1 and subagent 2 cannot see what the other was doing and so their work ends up being inconsistent with each other."* The bug isn't capability — it's missing shared state.

Cognition's resulting architectural recommendation is the strong form: *"The simplest way to follow the principles is to just use a single-threaded linear agent."* They go further: *"Running multiple agents in collaboration only results in fragile systems. The decision-making ends up being too dispersed."*

**When full-trace sharing is necessary:**

- Sequential pipelines where downstream work depends on upstream interpretation choices (e.g., subagent A picks an API contract, subagent B implements against it).
- Any task where multiple agents touch the same artifact (code, doc, schema).
- When the parent will need to defend a decision later ("why did we choose X?").

**When full-trace sharing is wasteful:**

- Independent fan-out exploration where outputs are commensurable and don't need to be reconciled (e.g., search 5 different sources for X, return citations).
- Disposable scouting where only the answer matters, not the path.

Read Cognition as: *default to single-threaded; only branch when the parallelism is genuinely independent.*

## Anthropic: distill on return

Anthropic, ["How we built our multi-agent research system," 13 Jun 2025](https://www.anthropic.com/engineering/built-multi-agent-research-system).
Anthropic, ["Effective context engineering for AI agents," 29 Sep 2025](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents).

Anthropic's research system uses a lead agent that spawns parallel subagents, each with its own context window, that each return a distilled ~1,000–2,000 token summary despite having burned tens of thousands of tokens internally on web searches and tool calls. From the context-engineering post:

> Subagents *"perform deep work and return condensed summaries (typically 1,000-2,000 tokens). This pattern achieved a substantial improvement over single-agent systems on complex research tasks."*

From the multi-agent research system post:

> *"Subagents facilitate compression by operating in parallel with their own context windows, exploring different aspects"* before condensing findings.

**Why this works for research and not for code.** Research outputs *are* their summaries — the value is "here are 5 facts and citations." Code outputs are not — losing the reasoning trail loses the design. Anthropic acknowledges this directly:

> *"Most coding tasks involve fewer truly parallelizable tasks than research, and LLM agents are not yet great at coordinating and delegating to other agents in real time"* and *"domains that require all agents to share the same context or involve many dependencies between agents are not a good fit."*

## Reconciling the two

Cognition and Anthropic describe different points on the same axis. Map your task to the table:

| Axis | Distill summaries (Anthropic) | Share full traces (Cognition) |
|---|---|---|
| Subagent outputs commensurable? | Yes (facts + citations) | No (design choices) |
| Will outputs be merged into one artifact? | Loosely (synthesis) | Tightly (one codebase) |
| Token budget pressure | High (200K cap looms) | Lower priority than coherence |
| Verifiability needed later? | Citations carry it | Trace carries it |
| Read-vs-write workload | Read-heavy (gather, synthesize) | Write-heavy (build shared artifact) |

**Decision rule:** *Distill when you can verify the distillation against external evidence (citations, files on disk). Pass the trace when the distillation would lose decisions the next agent must respect.*

The two frames bound the design space. Real systems sit on the spectrum — distill citations *and* keep a trace pointer to disk; distill summary *and* require verbatim quotes for load-bearing claims.

**Worked contrast.**

- *Research task — "summarize the last quarter's earnings calls for these 5 companies."* Each subagent reads one transcript, extracts 8–12 facts with quotes and timestamps. Outputs are commensurable (same schema), independently verifiable (each quote points at source), and combine by concatenation. Anthropic frame fits: fan out, distill, return summaries.
- *Code task — "refactor the auth module to support OAuth alongside basic auth."* Subagent A picks the token storage shape; subagent B writes the OAuth flow against it; subagent C migrates existing tests. B's choices are downstream of A's; C's are downstream of both. Outputs are not commensurable (one codebase, one merged tree). Cognition frame fits: serialize the work, pass full traces, or pin a shared spec doc that all three subagents anchor against.

The classifier question: *if I deleted the trace and kept only the output, could the next agent still do its job correctly?* If yes, distill. If no, share the trace.

## External memory patterns

Anthropic's context-engineering post names three techniques for long-horizon tasks:

1. **Compaction** — *"the practice of taking a conversation nearing the context window limit, summarizing its contents, and reinitiating a new context window with the summary."*
2. **Structured note-taking** — *"The agent regularly writes notes persisted to memory outside of the context window. These notes get pulled back into the context window at later times."*
3. **Multi-agent architectures** — covered in [the two anchor frames](#the-two-anchor-frames).

The next four subsections cover the concrete techniques that fall under (1) and (2).

## Plan-to-file before truncation

From the multi-agent research system post:

> *"The LeadResearcher begins by thinking through the approach and saving its plan to Memory to persist the context, since if the context window exceeds 200,000 tokens it will be truncated."*

This is the canonical save-plan-before-truncation pattern. The lead agent writes its plan to a file *first*, before doing any work. Even if the conversation is later compacted into a 5,000-token summary, the plan survives verbatim and can be reloaded.

**If state must survive context-window truncation or session restart, write to file before the work, not after.** If compaction fires mid-task, anything not externalized is gone. Plan-to-file is cheap insurance.

## Anthropic memory tool

[Anthropic memory tool docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool).

A client-side file directory (`/memories`) Claude can `view` / `create` / `str_replace` / `insert` / `delete` / `rename`. The system prompt automatically tells the agent:

> *"IMPORTANT: ALWAYS VIEW YOUR MEMORY DIRECTORY BEFORE DOING ANYTHING ELSE… ASSUME INTERRUPTION: Your context window might be reset at any moment, so you risk losing any progress that is not recorded in your memory directory."*

**Use cases listed:**

- Maintain project context across multiple agent executions.
- Learn from past interactions, decisions, and feedback.
- Build knowledge bases over time.
- Cross-conversation learning.

Pair memory with compaction:

> *"compaction keeps the active context manageable without client-side bookkeeping, and memory persists important information across compaction boundaries so that nothing critical is lost in the summary."*

Compaction handles the active window; memory handles what must outlive it. Compaction alone is unsafe for load-bearing detail.

## Artifact storage by reference

From Anthropic's multi-agent research system appendix:

> *"Direct subagent outputs can bypass the main coordinator for certain types of results, improving both fidelity and performance"* and *"This prevents information loss during multi-stage processing and reduces token overhead from copying large outputs through conversation history."*

The pattern: subagent writes a 50KB report to `/artifacts/research_2025_05_02.md` and returns the path. The orchestrator never holds the bytes — it holds a pointer. When a downstream agent needs the content, it reads the file. This solves both the token budget and the lossy-summary problem at once.

**If subagent output is large (>10KB), write to `/artifacts/<name>` and return the path.** Keeps token budget free; downstream reads only what it actually needs.

**If subagent output will likely not be consumed by parent, bypass parent entirely and write straight to artifact store.** Anthropic's words: *"Direct subagent outputs can bypass the main coordinator… improving both fidelity and performance."*

## Long-running harness pattern

Anthropic, ["Effective harnesses for long-running agents"](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

The recommended structure for multi-session work:

- A **`claude-progress.txt`** that logs what's been done and what's next.
- A **structured JSON feature checklist** with each feature marked `failing` until end-to-end verified.
- An **`init.sh`** that brings the dev environment up.
- A startup ritual: read progress, check git log, run init.sh, run a basic smoke test.

The principle: *"Work on one feature at a time. Only mark a feature complete after end-to-end verification confirms it works, not just after the code is written."*

**If the project spans multiple sessions, bootstrap with `claude-progress.txt` + feature checklist + `init.sh`, read at every session start.** Cheap recovery, no "what was I doing?" tax.

## External memory backend comparison

| Pattern | Latency | Recoverability | Debuggability | Best for |
|---|---|---|---|---|
| Plan-to-file (single markdown) | Low | High (read once at start) | High (human-readable) | Single long task spanning truncation |
| Memory tool (`/memories` dir) | Low (file ops) | High | High | Cross-session knowledge, multi-turn projects |
| Artifact storage (subagent → disk → path) | Low | High (file persists) | High (inspectable) | Large outputs that downstream agents may or may not consume |
| Vector store / RAG memory | Medium (embedding query) | High but lossy (semantic match, not exact recall) | Low (hard to inspect why a chunk surfaced) | Large unstructured corpora the agent didn't author |
| Structured DB (SQLite/Postgres) | Low | High and queryable | Medium | Episodic event log, entity tracking, audit |
| In-conversation scratchpad | Zero | Dies on truncation | High while alive | Short-lived working memory within one context |

**When external memory adds complexity for no payoff:**

- Single-shot tasks well under context budget. Just keep state inline.
- When the "memory" is actually just the prompt the next agent should see — pass it as input, don't write/read a file.
- When latency matters more than recoverability (e.g., interactive UI tools).

## Blackboard architecture

Salemi et al., ["An LLM-Based Multi-Agent Blackboard System for Data Discovery in Data Lakes," arXiv:2510.01285](https://arxiv.org/abs/2510.01285), submitted 30 Sep 2025 (revised 31 Jan 2026).

The blackboard is a 1980s symbolic-AI architecture: agents read and write to a shared workspace ("blackboard") rather than messaging each other directly. The 2025 LLM revival uses it for data-lake discovery where the orchestrator can't possibly know every subagent's expertise.

From the abstract:

> *"a central agent posts requests to a shared blackboard, and autonomous subordinate agents — either responsible for a partition of the data lake or retrieval from the web — volunteer to respond based on their capabilities. This design improves scalability and flexibility by removing the need for a central coordinator to know each agent's expertise or internal knowledge."*

**Reported gains:** *"13%-57% relative improvements in end-to-end success and up to a 9% relative gain in data discovery F1 over the best baseline"* across three benchmarks.

**When blackboard beats message-passing:**

- Orchestrator doesn't know which subagent is best for a given subtask (capabilities can't be enumerated).
- Multiple subagents may contribute partial answers to one request.
- The set of subagents changes at runtime.
- You want subagents to react to each other's writes, not just to the orchestrator's dispatches.

**When message-passing or hierarchical orchestration is fine:**

- Fixed cast of agents with known specialties.
- Deterministic delegation (router knows where to send).
- No need for cross-subagent observability.

LangGraph's shared `State` with reducers is essentially a typed, in-process blackboard. Nodes *"read from state, write updates to it, and LangGraph merges those updates using reducer logic."* The `Annotated[list[str], add]` pattern lets multiple parallel agents append to a shared list without clobbering — the canonical blackboard write. Private channels (`PrivateState`) let subgraphs scratchpad without polluting the global board.

## MAST taxonomy: 14 failure modes

Every handoff is lossy compression. The MAST taxonomy quantifies how often this kills systems.

Cemri et al., ["Why Do Multi-Agent LLM Systems Fail?" arXiv:2503.13657](https://arxiv.org/abs/2503.13657), NeurIPS 2025 Datasets & Benchmarks Spotlight ([project page](https://sky.cs.berkeley.edu/project/mast/)).

1,642 annotated execution traces across 7 MAS frameworks, 14 failure modes, 3 categories. Inter-annotator agreement κ = 0.88.

**Category 1 — Specification Issues (~41.8%)**

- FM-1.1 Disobey task specification
- FM-1.2 Disobey role specification
- FM-1.3 Step repetition
- **FM-1.4 Loss of conversation history** — *"Unexpected context truncation, disregarding recent interaction history"*
- FM-1.5 Unaware of termination conditions

**Category 2 — Inter-Agent Misalignment (~36.9%)**

- **FM-2.1 Conversation reset** — *"Unexpected or unwarranted restarting of a dialogue, potentially losing context"*
- FM-2.2 Fail to ask for clarification
- **FM-2.3 Task derailment** — *"Deviation from the intended objective or focus of a given task"*
- **FM-2.4 Information withholding** — agents fail to share data that would influence peers
- **FM-2.5 Ignored other agent's input** — *"Disregarding or failing to adequately consider input or recommendations provided by other agents"*
- FM-2.6 Reasoning-action mismatch

**Category 3 — Task Verification (~21.3%)**

- FM-3.1 Premature termination
- FM-3.2 No or incomplete verification
- FM-3.3 Incorrect verification

## The five state-handoff modes

Five of the fourteen modes are direct consequences of state/context handoff failures — roughly a third of all failures originate in how state moves (or doesn't) between agents. These are the failure surface this skill exists to prevent.

| Mode | Description | Mitigation |
|---|---|---|
| **FM-1.4 Loss of conversation history** | Unexpected context truncation, disregarding recent interaction history | Persist plan/decisions to file before any compaction; reload on resume |
| **FM-2.1 Conversation reset** | Unexpected or unwarranted restarting of a dialogue, potentially losing context | Checkpointing; durable thread IDs (LangGraph checkpointer, Claude Code session resume) |
| **FM-2.3 Task derailment** | Deviation from the intended objective or focus of a given task | Pin the goal in a top-of-context spec file the agent re-reads each step |
| **FM-2.4 Information withholding** | Agents fail to share data that would influence peers | Structured handoff schemas with mandatory fields; verbatim quotes for load-bearing claims |
| **FM-2.5 Ignored other agent's input** | Disregarding or failing to adequately consider input or recommendations provided by other agents | Blackboard pattern; require explicit acknowledgement/citation of upstream agent outputs |

**The "game of telephone" framing:** every distillation drops information. After three handoffs you may have lost the original load-bearing detail. The defenses are:

- **Verbatim citations** ("according to file X line Y…") instead of paraphrase.
- **Artifact paths** ("see /artifacts/spec.md") instead of artifact content.
- **Explicit structured handoff schemas** (typed fields the next agent must read).
- **Single-writer pattern** for any artifact that multiple agents could touch.

**Handoff schema shape.** When subagent A passes work to subagent B, require a typed envelope, not free-form prose. The envelope forces A to surface what B will need and gives B a checkable contract. A reasonable minimum:

- `goal` — the objective B is being asked to advance, restated.
- `decisions_made` — list of choices A locked in, each with a one-line rationale.
- `evidence` — verbatim quotes or file:line citations backing each decision.
- `open_questions` — anything A could not resolve, that B may need to revisit.
- `artifacts` — paths to files A wrote that B should read.
- `out_of_scope` — what A deliberately did not do, so B doesn't redo or contradict it.

The schema turns the handoff into a boundary contract. Missing fields are visible; "I forgot to tell you" becomes a schema violation, not a silent failure.

## In-context vs out-of-context state

| Property | In-context (conversation) | Out-of-context (file/DB/tool) |
|---|---|---|
| Latency to read | Free (already loaded) | Tool call (~100ms + tokens) |
| Survives truncation | No | Yes |
| Survives session end | No (unless captured) | Yes |
| Debuggable post-hoc | Only via transcript | Inspectable directly |
| Token budget cost | Linear in size | Constant (just the path/handle) |
| Concurrent multi-agent access | Hard (each has own copy) | Natural (shared file) |

From Anthropic's context-engineering post:

> *"Every new token introduced depletes this budget by some amount, increasing the need to carefully curate the tokens available to the LLM."* And: *"Good context engineering means finding the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome."*

**Decision rule:** *Keep state in-context only if (a) it fits, (b) it's needed every turn, and (c) it doesn't need to survive truncation. Otherwise externalize.*

**Compaction's role.** Compaction is the bridge — server-side summarization when you approach the context limit. The Anthropic memory-tool doc recommends pairing them: *"compaction keeps the active context manageable without client-side bookkeeping, and memory persists important information across compaction boundaries so that nothing critical is lost in the summary."* Compaction alone is unsafe for load-bearing detail — anything you can't afford to lose belongs in memory before compaction triggers.

A lightweight compaction option is **tool result clearing**: drop raw tool outputs deep in history (the agent already extracted what it needed) without summarizing the rest. Anthropic calls this out as a low-risk first move.

## Cross-session memory

[Claude Code subagents docs](https://code.claude.com/docs/en/sub-agents):

- Each subagent runs in *its own context window* with its own system prompt, tools, and permissions. *"Subagents help you preserve context by keeping exploration and implementation out of your main conversation."*
- Subagents return only a summary to the parent (not their full trace by default).
- Subagents can have a **persistent memory directory** that survives across conversations (build up codebase patterns, debugging insights, architectural decisions over time).
- Sessions are resumable by ID; **forking a subagent inherits the full conversation context** instead of starting fresh.
- Note: *"Subagents work within a single session; agent teams coordinate across separate sessions."* For cross-session multi-agent work, use **agent teams** instead.

**Anthropic memory tool** (`/memories` directory): persistent across all sessions on the same store. Not subagent-specific — per-agent or per-project depending on how the directory is mounted.

**LangGraph checkpointers**: thread-based persistence keyed by `thread_id`. Resume from any prior checkpoint, inspect intermediate state, time-travel debugging.

[**CrewAI memory**](https://docs.crewai.com/en/concepts/memory):

- Unified `Memory` class replacing previously-separate short-term, long-term, entity memories.
- Default backend LanceDB at `./.crewai/memory`.
- *"All agents in the crew share the crew's memory unless an agent has its own."* Per-agent scoping via `memory.scope("/agent/researcher")`.

**What survives across runs by default:**

| System | Survives session end? | Cross-agent visible? |
|---|---|---|
| Claude Code main conversation | Yes (if resumed by ID) | N/A |
| Claude Code subagent context | No, unless persistent memory dir configured | No (each subagent isolated) |
| Anthropic memory tool files | Yes (file-backed) | Yes if same dir mounted |
| LangGraph state without checkpointer | No | Within graph only |
| LangGraph state with checkpointer | Yes (by `thread_id`) | Within graph only |
| CrewAI crew memory | Yes (LanceDB on disk) | Yes (crew-shared by default) |

## Decision triggers

Apply these as `if X, prefer Y because Z`:

1. **If subagents make shared design decisions, prefer a shared planning/spec doc that every subagent reads, because** otherwise Cognition's "implicit conflicting decisions" failure surfaces (Flappy Bird).

2. **If a subagent's full trace exceeds N tokens but the answer is small, prefer distill-on-return (~1,000–2,000 token summaries), because** token budget; the parent doesn't need the exploration path if the answer is verifiable (Anthropic pattern).

3. **If a claim is load-bearing and may need verification later, prefer verbatim citation (file:line, URL, quote) over summary, because** MAST FM-2.4 (information withholding) and the telephone problem; lossy compression of evidence kills auditability.

4. **If state must survive context-window truncation or session restart, prefer write-to-file before work starts, not after, because** the Anthropic 200K plan-to-Memory pattern; if compaction fires mid-task, unwritten state is gone.

5. **If multiple agents will revise the same artifact, prefer blackboard pattern (shared workspace + reducer) or strict single-writer pattern (one owner, others read-only and PR back), because** naive concurrent writes race; LangGraph reducers exist exactly for this.

6. **If the pipeline is sequential and downstream agents need upstream reasoning, prefer passing the full trace over the summary, because** Cognition Principle 1 — downstream needs to know *why* upstream chose what it did.

7. **If the task is research/exploration with commensurable outputs, prefer fan-out to parallel subagents and distill-on-return, because** Anthropic research-system pattern; outputs combine cleanly via citation.

8. **If the task is code/design with one shared artifact, prefer single-threaded linear agent (Cognition's "simplest"), branching only for genuinely independent subtasks, because** otherwise inconsistent implicit decisions accrue.

9. **If the orchestrator can't enumerate which subagent handles what, prefer blackboard architecture (volunteers respond to posted requests), because** Salemi et al. 2025; hierarchical fails when capabilities aren't known up front.

10. **If the project is long-running and multi-session, prefer bootstrapping with `claude-progress.txt` + feature checklist + `init.sh` read at every session start, because** Anthropic harness pattern; cheap recovery, no "what was I doing?" tax.

11. **If subagent output is large (>10KB), prefer writing to `/artifacts/<name>` and returning the path, because** keeps token budget free; downstream reads only what it actually needs.

12. **If subagent output will likely not be consumed by parent, prefer bypassing parent entirely and writing straight to artifact store, because** *"Direct subagent outputs can bypass the main coordinator… improving both fidelity and performance"* (Anthropic).

13. **If knowledge should compound across sessions, prefer the memory tool with `/memories` directory, because** survives compaction *and* session boundaries (Anthropic memory tool use case).

14. **If state is working memory inside one short task, prefer keeping it in conversation, because** file I/O latency and cognitive overhead for no recoverability gain.

## Anti-patterns

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| Dumping raw subagent traces straight into the orchestrator | Blows token budget; orchestrator can't separate signal from noise | Distill on return OR write trace to artifact and pass the path |
| Aggressive summarization that strips citations | Load-bearing claims become unverifiable; "telephone" failure | Require verbatim quotes for any claim downstream agents will act on |
| Multiple parallel agents writing to the same artifact with no reducer | Last-write-wins; data loss; race conditions | Blackboard with explicit reducer (LangGraph `Annotated[..., add]`) or single-writer pattern |
| Keeping plan/spec in conversation only | Vaporizes at compaction or 200K cap (MAST FM-1.4) | Plan-to-file *first*, before the work starts |
| No citation requirements for load-bearing claims | MAST FM-2.4 information withholding; downstream propagates errors silently | Structured handoff schema with required `evidence` / `source` fields |
| Spawning subagents whose outputs depend on each other | Cognition's exact failure mode — implicit conflicting decisions | Either serialize them with full-trace handoff, or give them a shared spec doc to anchor decisions |
| Using vector-store memory for exact recall | Embedding similarity ≠ exact match; load-bearing facts may not surface | File-based memory with deterministic paths for anything that *must* be retrievable |
| Resetting subagent context between calls when continuity matters | MAST FM-2.1 conversation reset | Resumable subagent sessions or persistent memory dir |
| Treating compaction as free | Compaction loses detail silently; you discover the loss only when something downstream breaks | Externalize critical state *before* approaching the limit; treat compaction as last resort, not a feature |
| In-context state when external would survive better | Single truncation event wipes hours of work | Default to externalizing anything that took non-trivial work to produce |

## Bottom line

The two anchor frames are Cognition's pessimism ("default single-threaded; full traces if you must branch") and Anthropic's optimism ("distill heavily, externalize aggressively, verify with citations"). They don't contradict — they describe different task shapes.

The core job when designing state flow is two steps:

1. **Classify the task** — commensurable parallel exploration vs. shared-artifact design.
2. **Pick the state architecture that matches** — distill-and-return vs. shared-spec-with-full-trace, in-context vs. file-backed, message-passing vs. blackboard.

Five of the 14 MAST failure modes (FM-1.4, FM-2.1, FM-2.3, FM-2.4, FM-2.5) are state-handoff bugs. That is the failure surface this reference exists to prevent.

## Sources

- Walden Yan, ["Don't Build Multi-Agents," Cognition AI, 12 Jun 2025](https://cognition.ai/blog/dont-build-multi-agents)
- Anthropic, ["How we built our multi-agent research system," 13 Jun 2025](https://www.anthropic.com/engineering/built-multi-agent-research-system)
- Anthropic, ["Effective context engineering for AI agents," 29 Sep 2025](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- Anthropic, ["Effective harnesses for long-running agents"](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- Anthropic, [Memory tool docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)
- [Claude Code subagents docs](https://code.claude.com/docs/en/sub-agents)
- Cemri et al., ["Why Do Multi-Agent LLM Systems Fail?" arXiv:2503.13657](https://arxiv.org/abs/2503.13657), NeurIPS 2025; [project page](https://sky.cs.berkeley.edu/project/mast/)
- Salemi et al., ["LLM-Based Multi-Agent Blackboard System," arXiv:2510.01285](https://arxiv.org/abs/2510.01285), Sep 2025 (rev Jan 2026)
- [LangGraph Graph API docs](https://docs.langchain.com/oss/python/langgraph/graph-api)
- [CrewAI Memory docs](https://docs.crewai.com/en/concepts/memory)
- Tim Williams summary of MAST modes — https://timajwilliams.com/2025-08-05/agent-failure
- Anna Grigoryan summary of MAST — https://thegrigorian.medium.com/why-do-multi-agent-llm-systems-fail-14dc34e0f3cb
