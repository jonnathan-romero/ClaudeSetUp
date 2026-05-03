# Role Specialization

When to split work across role-specialized agents (planner/executor, builder/tester, researcher/writer, architect/implementer/critic) and when those splits are theater. Read before adding a role to a multi-agent design — the default should be a single agent unless a real mechanism justifies the split.

## Contents

- [When to consult this](#when-to-consult-this)
- [The three real mechanisms (and the one fake one)](#the-three-real-mechanisms-and-the-one-fake-one)
- [Planner + Executor](#planner--executor)
- [Researcher + Writer](#researcher--writer)
- [Builder + Tester](#builder--tester)
- [Builder + Tester + Reviewer](#builder--tester--reviewer)
- [Architect + Implementer + Critic](#architect--implementer--critic)
- [Coder + Compiler-loop agent](#coder--compiler-loop-agent)
- [Gather + Synthesize + Format](#gather--synthesize--format)
- [Specialist crews (frontend / backend / devops)](#specialist-crews-frontend--backend--devops)
- [The MAST 14-mode failure taxonomy](#the-mast-14-mode-failure-taxonomy)
- [Cognition's three principles](#cognitions-three-principles)
- [Empirical evidence (with honest effect sizes)](#empirical-evidence-with-honest-effect-sizes)
- [Anti-patterns catalog](#anti-patterns-catalog)
- [Decision triggers](#decision-triggers)
- [When you must split: handoff hygiene](#when-you-must-split-handoff-hygiene)
- [Decision tree](#decision-tree)
- [Sources](#sources)

## When to consult this

Read this before proposing or accepting a role split — builder/tester triads, planner/executor pipelines, architect/implementer/critic, researcher/writer/editor, or any "let's add a reviewer agent." Skip for single-agent design choices, prompt-only questions, or pure tooling/topology decisions (those live in other references).

The decision rule is not "is the task complex?" but **"does the task have natural context boundaries that justify isolating a context window, AND can the handoff be done without lossy translation?"**

## The three real mechanisms (and the one fake one)

A role split only beats a single agent if it activates one of three mechanisms. Without at least one, the split is ceremony.

**1. Context isolation (strong, well-evidenced).** Each role gets a fresh context window with only the inputs it needs. Context pollution measurably degrades reasoning; tool-selection quality degrades when an agent juggles 15–20+ tools; long contexts have well-documented attention-degradation issues (lost-in-the-middle). This is the dominant mechanism in successful production multi-agent systems. Anthropic's explicit guidance: **"Divide work by context boundaries, not problem types."**

**2. Forced explicit handoffs / artifact scrutiny (moderate).** Splitting forces an intermediate artifact (plan, spec, draft, test list) that gets scrutinized rather than buried in scratchpad reasoning. [MetaGPT's](https://arxiv.org/abs/2308.00352) key innovation was not the roles per se but **structured document handoffs** (PRD, architecture diagrams) replacing free-form chat — preventing "conversational drift."

**3. Reduced "writer's bias" via outside view (moderate, identity-laundered).** LLMs favor their own generations. ["LLM Amplifies Self-Bias in Self-Refinement"](https://aclanthology.org/2024.acl-long.826.pdf) (Xu et al., ACL 2024) found self-bias is prevalent across models and languages, and self-refine pipelines amplify it. Critically: when the same answer was attributed to "another LLM," choice-supportive bias **disappeared** — the bias is identity-driven, not capability-driven. So framing a separate call as "review this code from another developer" can recover an outside-view effect. But it does not vanish entirely with same-model reviewers — Anthropic and OpenAI evaluators still show +4.27% and +9.4% positive self-evaluation bias respectively.

**The fake mechanism: prompt-conditioning persona effects.** A "you are a critical code reviewer" system prompt elicits different attention patterns — but the empirical literature on persona prompting is mixed at best. ["When 'A Helpful Assistant' Is Not Really Helpful"](https://arxiv.org/html/2311.10054v3) (Zheng et al., arXiv:2311.10054) found **personas in system prompts do not reliably improve LLM performance on objective tasks** and may hurt factual accuracy on knowledge-heavy tasks. **Persona prompts on the same model with the same context are theater on objective tasks.** Gains attributed to "the reviewer persona" almost always trace back to one of the three real mechanisms above (different inputs, different tools, fresh context, different model) — not to the costume.

**Test for theater:** strip the role names and replace each agent with "Agent A / Agent B / Agent C." If the design still produces different outputs, a real mechanism is at work. If it collapses to "one agent talking to itself," it was theater.

**Four canonical failure modes when the mechanism is missing:**

- **The "Flappy Bird" failure (Cognition, 2025).** Parallelize "build the background" and "build the bird" → subagent 1 builds Mario-style pipes, subagent 2 builds an off-style bird, neither knows the other's choices, the assembling agent gets two miscommunications. Mechanism: **implicit decisions made by each subagent conflict because they cannot see the others' contexts.**
- **Reviewer rubber-stamping.** SWE-PRBench: frontier models catch only **15–31% of human-flagged issues**. A reviewer that cannot find the bugs the builder missed is ceremony. Same-model reviewer + perplexity-familiarity bias → systematic over-approval.
- **Roles-too-similar collapse.** A "Senior Engineer reviewer" prompt and a "Coder" prompt on the same model converge to similar outputs on objective tasks. The reviewer paraphrases rather than challenges. Cognition: **"agents today are not quite able to engage in this style of long-context proactive discourse with much more reliability."**
- **Communication tax.** ["Stop Wasting Your Tokens"](https://arxiv.org/html/2510.26585v2) (arXiv:2510.26585) quantifies that a substantial fraction of inter-agent verification tokens is **redundant revalidation rather than novel insights**. Multi-agent systems consume **4–220x more tokens** for often marginal quality gains.

## Planner + Executor

**How it works.** Planner LLM call decomposes the goal into a multi-step plan; Executor (single agent or parallel workers) carries out each step, often with a smaller/cheaper model. A "replanner" node optionally revises the plan as steps return. Variants: Planner–Verifier–Executor; Planner–Critic–Executor.

**When it wins.**
- Plan would otherwise be implicit and the executor would drift. Forcing explicit upfront structure enables midcourse correction.
- Cost split: big planner model + small executor model = significant savings on long workflows ([LangChain's stated motivation](https://www.langchain.com/blog/planning-agents)).
- Plan needs human approval before execution. Then the planner output is the human-in-the-loop artifact.
- Multi-step DAG with parallelizable branches (LLMCompiler reports ~3.6x latency speedup over sequential ReAct).

**When it's theater.**
- Planner rationalizes executor convenience. When the same model plans and executes (or related models), the planner often implicitly biases toward "what an LLM can do easily" rather than what the task needs.
- Plan-execution mismatch. The planner doesn't know what the executor will discover at step 3 that invalidates step 5. Without aggressive replanning, plans become straitjackets.
- Tasks with dense early-stage uncertainty. ReAct's reactivity is an asset; pre-committed plans are a liability.
- Single-step or near-single-step tasks. Don't plan two-step problems.

**Source.** [LangChain: Planning Agents](https://www.langchain.com/blog/planning-agents); ReWOO (Xu et al. 2023, "Reasoning WithOut Observation"); LLMCompiler (Kim et al. 2023).

## Researcher + Writer

**How it works.** A "researcher" agent (or several in parallel) gathers raw material; a "writer" composes the final artifact from that material. Anthropic's research system is the canonical production example: Lead Researcher → parallel Subagents → CitationAgent.

**When it wins.**
- Large research synthesis where source material exceeds a single context window (Anthropic's 90% gain is here).
- Citation work that needs to be checked against sources (CitationAgent pattern).
- Multi-source consolidation where each source needs its own first-pass extraction.
- Distinct artifact boundary: research notes → blog post is a natural seam.

**When it's theater.**
- Short pieces where research and composition share vocabulary and emphasis. Splitting produces a "stilted seam" — the writer drops nuances the researcher implicitly weighed.
- Voice-driven writing (essays, opinion, narrative) where the writer's framing needs to influence what gets gathered. A pre-gathered research dump biases the writer toward what's there, away from what's needed.
- Single-source summarization. Just read it and write. The research role is empty.

**Heuristic.** Split at a natural artifact boundary. If you can name the intermediate artifact in one noun phrase ("annotated bibliography," "outline with claims and evidence"), split. If the intermediate is "research blob," don't split.

**Source.** [Anthropic: How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system).

## Builder + Tester

**How it works.** One agent writes implementation code; another writes (or runs) tests. Sometimes test-writer goes first (TDD-style red/green/refactor).

**When it wins.**
- Test-independence matters. Safety-critical, correctness-critical, or contract-driven code where "passing tests the builder wrote" is meaningless.
- Spec is fuzzy and tests force re-derivation. The tester re-reads the spec, surfacing ambiguities.
- Test-writing requires different domain knowledge (property-based tests, fuzzing, security tests).
- TDAD-style workflows where you have explicit dependency context between source and tests (1.82% regression vs 6.08% baseline).

**When it's theater.**
- Tiny refactors / single-file fixes. Spec and impact are obvious; no spec to re-derive.
- Changes whose tests already exist. Just run them. No tester role needed.
- Tasks where the builder has natural test affordances. Modern coding agents writing pytest alongside implementation in the same context produce coherent test suites.
- Coupling risk: builder writes idiosyncratic code only the original tester knows how to test for. Splitting then makes the system more fragile, not less.

**Caveat from the data.** TDAD's ablation found that **adding TDD procedural instructions without telling the agent which specific tests to check actually increased regressions to 9.94% — worse than vanilla**. The mechanism that helps is **targeted test context, not the role split per se**.

**Source.** [Simon Willison: Red/Green TDD agentic pattern](https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/); TDAD (Test-Driven Agentic Development).

## Builder + Tester + Reviewer

**How it works.** Adds an independent code reviewer to the builder/tester pair. Reviewer evaluates the patch before submission against a checklist (bug classes, style, regressions).

**When it wins.**
- Reported **7.2% absolute improvement** on SWE-bench Verified from adding a reviewer role (72.2% multi-agent vs ~65% single-agent on same model) — "same model, same capabilities producing different results just from having a second pair of eyes."
- Reviewer has different inputs (security scanner output, compiler diagnostics, runtime traces) the builder didn't see.
- Reviewer is a different model than the builder (genuine outside view).
- Reviewer has authority to reject — not advisory.

**When it's theater.**
- SWE-PRBench (350 PRs with human ground truth) found 8 frontier models detect only **15–31% of human-flagged issues** in diff-only configuration; a top ACR (automated code review) technique reaches only **F1 19.38%**. Reviewer agents in the wild are weak.
- Same-model reviewer with the same context as the builder. Perplexity-familiarity bias means LLMs evaluate fluent text more favorably, so a reviewer reading its own model's output is **systematically biased toward approval**.
- Reviewer with no checklist, no different inputs, no power to reject. Ceremony.
- "Senior Engineer reviewer" prompt + "Coder" prompt on the same model converge to similar outputs on objective tasks. The reviewer paraphrases rather than challenges.

**Sources.** [Multi-Agent vs Single-Agent Coding](https://vibecoding.app/blog/multi-agent-vs-single-agent-coding); [Benchmarking LLM-based Code Review](https://arxiv.org/html/2509.01494v1); [SWE-PRBench](https://arxiv.org/html/2603.26130v1).

## Architect + Implementer + Critic

**How it works.** Architect drafts the design; implementer builds; critic reviews against design AND output. Often used with a quality-gate handoff (implementer cannot start until critic approves the architect's plan).

**When it wins.**
- Greenfield system design where the architecture artifact (PRD, sequence diagram, schema) is independently valuable and humans review it.
- Implementation requires committing to interface choices that are expensive to revisit. Forcing a design artifact upfront prevents implementation-driven design rot.
- Critic has access to test suites, contracts, or spec documents the implementer doesn't.
- The architect / critic / implementer are differently capable (different models or different tools).

**When it's theater.**
- Same model, same context, three "hats." Roles converge; critic rubber-stamps; architect over-specifies things the implementer would handle better with full context.
- Small features. The "PRD" is a one-line bullet; the architect role is empty.
- ChatDev / MetaGPT-style 5–7 role waterfalls applied to tasks a single agent handles in one context window. Diminishing returns past ~3 roles per task. MetaGPT achieves 85.9% / 87.7% Pass@1 on HumanEval/MBPP — but at **~$10 per HumanEval task**.

**Sources.** [MetaGPT (Hong et al., ICLR 2024)](https://arxiv.org/abs/2308.00352); [ChatDev (Qian et al., ACL 2024)](https://arxiv.org/abs/2307.07924).

## Coder + Compiler-loop agent

**How it works.** Coder writes; a separate "compiler loop" agent runs the build/tests, parses errors, and feeds back a structured failure report (rather than raw stderr).

**When it wins.**
- Build / test output is large and noisy. The loop agent acts as an error-decoder that turns 500 lines of tracebacks into "test_foo failed because X."
- The coder's context would otherwise fill with stderr and degrade.
- Iteration count is high (10+ build cycles), so context isolation compounds.

**When it's theater.**
- Single build cycle. Just paste the error.
- Failures are short and obvious. The decoder loses information that the coder needs verbatim (line numbers, exact strings).
- The "loop agent" is the same model with the same context — it just summarizes what the coder would have read anyway.

This is mostly a **context isolation** pattern, not a true outside-view pattern. Justify it that way or drop it.

**Source.** Internal pattern; close cousin of Anthropic's CitationAgent (specialized post-processor on a noisy intermediate artifact). No standalone published study.

## Gather + Synthesize + Format

**How it works.** Three-stage pipeline. Gather (search, read, extract); Synthesize (write the body); Format (citations, structure, polish).

**When it wins.**
- The CitationAgent is the canonical example of when a role split helps: it has one job (attach citations to claims), needs only the document index + draft, and would pollute the writer's context if interleaved.
- Each stage has a distinct artifact and distinct tools.
- Format stage runs deterministic transforms (linters, citation matchers) better kept out of the writer's context.

**When it's theater.**
- Format stage is "make it markdown." Just ask the writer to emit markdown.
- Synthesis and gathering share vocabulary. The format stage is the only honest seam.

**Empirical anchor.** Anthropic's orchestrator-subagent system **outperformed single-agent Claude Opus 4 by 90.2% on internal research evals** — but at **~15x more tokens** than chat baseline, ~4x more than a single-agent. The gain is large; the cost is real.

**Source.** [Anthropic: How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system).

## Specialist crews (frontend / backend / devops)

**How it works.** One agent per domain; each owns its files, has domain-specific tools, and writes its slice in parallel. CrewAI's role-playing framework is the canonical implementation (Role + Goal + Backstory + Tools per agent).

**When it wins.**
- File ownership is genuinely disjoint. Frontend touches `/web`, backend touches `/api`, no shared edits.
- Domain-specific tools differ (e.g., frontend uses a browser MCP, backend uses a SQL client).
- Parallelism is real — slices can be built without seeing each other.

**When it's theater.**
- Slices share interfaces (API contracts, data models). Cross-cutting changes get split between agents who can't see each other's decisions — the [Flappy Bird failure](https://cognition.ai/blog/dont-build-multi-agents).
- "Persona" specialization without different files or tools. Same context, different costume.
- Role inflation past ~3–5 agents. Reported sweet spot: **"Three to five teammates is the sweet spot. Token costs scale linearly, and three focused teammates consistently outperform five scattered ones."**

**Source.** [CrewAI documentation](https://docs.crewai.com/en/introduction); [Coding Agent Teams (DevOps.com)](https://devops.com/coding-agent-teams-the-next-frontier-in-ai-assisted-software-development/); MetaGPT's SOP roles; many Claude Code sub-agent collections (VoltAgent's awesome-claude-code-subagents lists 100+).

### Applied to Claude Code `.claude/agents/`

The `.claude/agents/` directory makes role specialization cheap to declare — a SKILL.md or agent file per role. That cheapness is the trap. Each declared subagent should answer:

- **What context does it isolate?** If it shares the parent's context, it's a prompt, not an agent.
- **What tools does it have that the parent doesn't?** If the toolset is identical, the split is theater.
- **What artifact does it return?** If the return value is "the same code, reviewed," and the parent could self-review, drop it.
- **Does it survive the Agent A/B/C test?** Strip the role label. Does the design still make sense?

Default for a Claude Code session: one main agent. Add subagents only for parallel breadth-first search, isolatable tool-heavy work (browser automation, large repo grep, third-party API exploration), or genuine outside-view review with different inputs.

## The MAST 14-mode failure taxonomy

["Why Do Multi-Agent LLM Systems Fail?"](https://arxiv.org/abs/2503.13657) (Cemri, Pan, Yang et al., arXiv:2503.13657, ICLR 2025) annotated 1600+ traces across 7 frameworks (kappa = 0.88) and produced 14 failure modes in three categories. **~77% of failures originate from design and inter-agent communication problems — i.e., introduced by the multi-agent architecture itself.** Use this list as a pre-mortem before approving a role split.

**FC1 — Specification & System Design (~41.8% of failures):**
1. Disobey task specification
2. Disobey role specification
3. Step repetition
4. Loss of conversation history
5. Unaware of termination conditions

**FC2 — Inter-Agent Misalignment (~36.9%):**
6. Conversation reset
7. Fail to ask for clarification
8. Task derailment
9. Information withholding
10. Ignored other agent's input
11. Reasoning-action mismatch

**FC3 — Task Verification & Termination:**
12. Premature termination
13. No or incomplete verification
14. Incorrect verification

**Implications for role design.**
- **FM-1.2 (Disobey role specification)** is the persona-theater failure mode: agents wander out of role when their training pulls them elsewhere.
- **FM-1.3 (Step repetition) + FM-2.1 (Conversation reset)** are the "agents redo each other's work" failure: no shared state tracker.
- **FM-2.4 (Information withholding) + FM-2.6 (Ignored other agent's input)** are the lossy-handoff failure modes — the dominant case for "share full traces, not summaries."
- **FM-3.1 (Premature termination) + FM-3.3 (Incorrect verification)** are the rubber-stamp reviewer failure: a "QA agent" that approves wrong things is worse than no QA — it provides false assurance.

If a proposed role split would obviously trigger 2+ of these modes and you have no mitigation, drop the split.

**Mitigations by mode.**

- **FM-1.2 (disobey role spec):** make the role spec executable — a checklist the agent must complete and submit, not a free-form persona.
- **FM-1.3 / FM-2.1 (step repetition / conversation reset):** maintain an external state artifact (file, scratchpad, plan document) that every agent reads and updates. Don't rely on conversation memory.
- **FM-2.4 / FM-2.6 (information withholding / ignored input):** pass full traces, not summaries. If summarization is required, log the full trace and require the next agent to acknowledge specific decisions.
- **FM-3.1 / FM-3.3 (premature / incorrect verification):** the verifier must produce structured evidence (test outputs, diff hunks, citations) — not "looks good." If the verifier cannot produce evidence, it cannot reject — and a rubber-stamp verifier is worse than none.

## Cognition's three principles

From [Cognition's "Don't Build Multi-Agents"](https://cognition.ai/blog/dont-build-multi-agents) (Walden Yan, 2025) — the most credible production-experience source on coding-specific multi-agent design. Embed these in any role-split decision.

**1. "Share context, and share full agent traces, not just individual messages."** When you must split, pass the full trace of relevant prior decisions, not summaries. Lossy summaries are where the [Flappy Bird failure](https://cognition.ai/blog/dont-build-multi-agents) lives.

**2. "Actions carry implicit decisions; conflicting decisions carry bad results."** Walden Yan's canonical example: parallelize "build the background" and "build the bird" → subagent 1 builds Mario-style pipes, subagent 2 builds an off-style bird, neither knows the other's choices, the assembling agent gets two miscommunications. **If two subagents make contradictory implicit choices, no clever assembling agent can fix it.**

**3. "Divide work by context boundaries, not problem types."** A feature + its tests share context (don't split). Five independent companies to research don't (split). Cognition's coding-specific verdict: **"agents today are not quite able to engage in this style of long-context proactive discourse with much more reliability"** — recommend single-threaded linear agents with continuous context as the default for coding. Warp's **71% on SWE-bench Verified** with a single-agent architecture is the existence proof.

**Practical translation.**

- When you split, dump the prior agent's full conversation trace into the next agent's context — not a summary. If it doesn't fit, the split was wrong: shrink scope or merge agents.
- Before parallelizing, list the implicit decisions each branch will make. If any branch's decisions affect a sibling's, do not parallelize.
- Default for coding tasks: single-threaded linear agent. Justify any deviation with a concrete artifact boundary or an isolatable parallel branch.
- Default for research tasks: orchestrator + parallel subagents on independent sources, plus a CitationAgent at the end. Anthropic's blueprint.

## Empirical evidence (with honest effect sizes)

Use this table to calibrate expectations before pitching a role split. Most published "wins" come from one of two regimes: parallel breadth-first research (large gains, large cost) or coding benchmarks (small gains, comparable to single-agent under matched compute).

| Source | System | Setup | Result |
|---|---|---|---|
| Anthropic (June 2025) | Multi-agent research system | Opus lead + Sonnet subagents vs single-agent Opus | **+90.2%** on internal research eval; **15x token cost** |
| AgentVerse (Chen et al. 2023) | Multi-role group on HumanEval | Multi vs single GPT-4 | 87.2% vs 86.0% Pass@1 (~1.2 pts); GPT-3.5: 75.6% vs 73.8% (~1.8 pts) |
| MetaGPT (Hong et al., ICLR 2024) | 5-role assembly line | vs single-agent on HumanEval/MBPP | 85.9% / 87.7% Pass@1 — SOTA at the time, but **~$10 per HumanEval task** |
| ChatDev (Qian et al., ACL 2024) | 7-role waterfall | vs GPT-Engineer & MetaGPT | Outperformed GPT-Engineer; better than MetaGPT on quality metric |
| Reflexion (Shinn et al., NeurIPS 2023) | Self-reflection loop (single agent w/ memory) | vs vanilla | +20% HotpotQA, +11% HumanEval — **note: single-agent baseline, not multi-agent** |
| Du et al. 2023 ("Improving Factuality...") | Multiagent debate | Same-model debate vs single | Significant accuracy gains on factual + reasoning tasks |
| UIUC study (cited in multiple secondary sources) | Multi-agent overhead measurement | Multi vs single | **4–220x token overhead** |
| Multi-Hop Reasoning under Equal Thinking Budget (arXiv:2604.02460) | Equal thinking-token budgets | Single vs multi | **Single-agent matches or outperforms multi-agent** when thinking-tokens held constant |
| Warp (2025) | Single-agent SWE-bench Verified | Pure single-agent | **71%** — competitive with multi-agent, simpler, cheaper |
| Reviewer-added SWE-bench (2025) | Builder + tester + reviewer | Same model + reviewer role | **+7.2%** absolute improvement (72.2% vs ~65%) |
| SWE-PRBench (350 PRs) | Diff-only review | 8 frontier models | **15–31%** of human-flagged issues detected |
| Benchmarking LLM-based Code Review (2025) | Top ACR technique | Best frontier model | **F1 19.38%** |

**Honest read.** Multi-agent gains are large for parallel breadth-first research (Anthropic 90%), modest for benchmark coding (1–8 percentage points on HumanEval/SWE-bench), and often vanish or reverse when controlling for compute/thinking budget. The "multi-agent is better" framing routinely conflates "more compute is better" with "more *roles* are better." When you see a multi-agent benchmark win, ask: was thinking-token budget controlled? If not, the same gain is likely available from a single agent with longer reasoning.

## Anti-patterns catalog

1. **Pure relay roles (no transformation).** Role A passes A's output to Role B unchanged, which passes to C. The roles add only latency.
2. **Reviewer rubber-stamping.** Reviewer with no teeth (no power to reject), no checklist, and no different system prompt. SWE-PRBench data: F1 19.38% across frontier models.
3. **Role inflation.** ChatDev's 7 roles, MetaGPT's 5 roles — diminishing returns past ~3 roles per task. The DevOps "3–5 teammate" sweet spot lines up with Anthropic's "1 agent = simple, 2–4 = comparison, 10+ = complex research" effort scaling.
4. **Lost-in-handoff context drops.** Summarized handoffs lose 70–90% of tokens but introduce information loss; after 8–10 handoffs degradation is measurable in 15–20% of workflows.
5. **Builder/tester coupling.** The tester only knows the builder's idiom; replacing the builder breaks the tester. Defeats the independence-of-perspective rationale.
6. **Same-model "outside view" delusion.** Self-bias persists across instances of the same model unless attribution is laundered. Anthropic and OpenAI evaluators show +4.27% and +9.4% positive self-evaluation bias respectively.
7. **Persona theater.** "You are a 10x senior engineer" prompts on the same model don't reliably improve objective-task performance and can hurt factual accuracy ([Zheng et al. 2023](https://arxiv.org/html/2311.10054v3)).
8. **Disobey role specification (MAST FM-1.2).** Roles are defined but agents wander out of them when their training pulls them elsewhere.
9. **Step repetition (MAST FM-1.3) and conversation reset (MAST FM-2.1).** Multiple agents redo each other's work because no one tracks state.
10. **Premature/incorrect verification (MAST FM-3.1, FM-3.3).** A "QA agent" that approves wrong things is worse than no QA — it provides false assurance.
11. **Decomposing by problem-type instead of context-boundary** (Anthropic's explicit warning). Splitting a single feature into "planner / implementer / reviewer" all sharing the same context just adds coordination tax.

## Decision triggers

### Stop and question the split if any of these are true

- The task fits in one context window with room to spare. **Single agent.**
- The subtasks are tightly interdependent (all need to share the same context). **Single agent.**
- The intermediate artifact has no natural noun-phrase name. No clean handoff exists. **Single agent.**
- The task is short (<5–10 steps). **Single agent.** Latency overhead dominates.
- You're splitting "coder / reviewer" on a same-model setup with no different inputs or tools for the reviewer. **Theater.** Use a single agent with a self-review prompt at the end, or use a different model for review.
- The "roles" are just stylistic personas with the same context. **Theater.** Use one agent.
- The task is interactive coding with a single coherent objective. Cognition's stance: **single-threaded linear agent**. Warp's 71% SWE-bench result.
- Stripping the role names collapses the design to "one agent talking to itself." **Theater.**

### Strongly consider splitting if any of these are true

- Genuine parallelism with isolatable contexts (e.g., search 5 companies in parallel). Anthropic's 90% gain regime.
- Context window strain is routine and degrading performance. Subagents can keep their exploration cost internal and return summaries.
- The agent juggles 15–20+ tools and tool-selection quality is degrading. Specialize.
- The task has a natural artifact boundary (research notes → article; spec → tests → impl; plan → execution). Split at the artifact.
- You need a true outside view with different inputs (reviewer with fresh context, different tools, or different model). The independence is what helps, not the role label.
- Cost/quality split via model heterogeneity. Big planner, cheap executors.
- The verification step needs different tools than generation (formal verifier, compiler, fuzzer).
- Long-horizon (>20–30 steps) work where context compaction would lose key state. Subagent contexts can be checkpointed independently.

### Three principles to embed in every decision

From Cognition + Anthropic, the two most credible production-experience sources:

1. **Share context, and share full agent traces, not just individual messages.** When you must split, pass the full trace of relevant prior decisions, not summaries.
2. **Actions carry implicit decisions; conflicting decisions carry bad results.** If two subagents make contradictory implicit choices, no clever assembling agent can fix it.
3. **Divide work by context boundaries, not problem types.** A feature + its tests share context (don't split). Five independent companies to research don't (split).

### Honest read on effect sizes

Multi-agent gains are **large for parallel breadth-first research** (Anthropic 90%), **modest for benchmark coding** (1–8 percentage points on HumanEval/SWE-bench), and **often vanish or reverse when controlling for compute/thinking budget** (single-agent matches multi-agent on multi-hop reasoning under equal thinking-token budgets). The "multi-agent is better" framing routinely conflates "more compute is better" with "more *roles* are better."

Token cost reality: multi-agent systems consume **4–220x more tokens** for often marginal quality gains (["Stop Wasting Your Tokens"](https://arxiv.org/html/2510.26585v2), arXiv:2510.26585). Each handoff adds 500ms–1.5s for context summarization; after 8–10 handoffs, measurable degradation appears in 15–20% of long workflows.

## When you must split: handoff hygiene

Once a split is justified, the handoff itself is where most multi-agent value leaks. Apply these rules:

- **Name the artifact in one noun phrase before splitting.** "Annotated bibliography." "Outline with claims and evidence." "Failing test list." If you cannot name it, you do not have a clean handoff — merge the agents.
- **Pass the full trace, not a summary.** Cognition: "Share context, and share full agent traces, not just individual messages." Summarization is where implicit decisions get lost.
- **Make the receiving agent acknowledge specific decisions.** Force the next agent to reference choices made upstream (file paths, library picks, naming conventions). Prevents MAST FM-2.6 (ignored other agent's input).
- **Externalize state.** A shared file (plan, scratchpad, decision log) every agent reads/writes beats relying on conversation memory. Prevents MAST FM-1.3 / FM-2.1 (step repetition / conversation reset).
- **Bound the role's authority.** A reviewer either has the power to reject (with required structured evidence) or it's advisory ceremony. Pick one explicitly.
- **Cap iteration depth.** Set a hard limit on review/refine cycles (e.g., 2 rounds). Self-refine pipelines amplify bias on each iteration ([Xu et al., ACL 2024](https://aclanthology.org/2024.acl-long.826.pdf)) and unbounded loops trigger MAST FM-3.1 (premature termination) or runaway token cost.

## Decision tree

```
Is the task <5 steps and fits in one context?
  → Single agent.

Is the task tightly interdependent (one piece informs the next)?
  → Single agent.

Does the task have parallelizable independent branches AND value > 15x token cost?
  → Multi-agent (orchestrator-subagent).

Does the task need a true outside view (fresh context, different tools, or different model)?
  → Critic/reviewer — but with teeth (different inputs, not just a different prompt).

Does the task have a natural artifact boundary (named intermediate)?
  → Split at the artifact.

Does the task have 20+ tools?
  → Specialize agents by toolset.

Otherwise
  → Single agent with structured self-review at the end.
```

After designing a split, run the MAST pre-mortem: which of the 14 failure modes does this design make likely? If 2+ light up with no mitigation, simplify.

## Sources

- [Cognition AI: Don't Build Multi-Agents (Walden Yan, 2025)](https://cognition.ai/blog/dont-build-multi-agents)
- [Anthropic: How we built our multi-agent research system (June 2025)](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Anthropic / Claude: When to use multi-agent systems (and when not to)](https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them)
- [Why Do Multi-Agent LLM Systems Fail? — Cemri, Pan, Yang et al. (arXiv:2503.13657, ICLR 2025)](https://arxiv.org/abs/2503.13657) — the MAST taxonomy
- [MetaGPT: Meta Programming for a Multi-Agent Collaborative Framework — Hong et al. (ICLR 2024 Oral)](https://arxiv.org/abs/2308.00352)
- [ChatDev: Communicative Agents for Software Development — Qian et al. (ACL 2024)](https://arxiv.org/abs/2307.07924)
- [AgentVerse: Facilitating Multi-Agent Collaboration and Exploring Emergent Behaviors — Chen et al. (2023)](https://arxiv.org/abs/2308.10848)
- [Reflexion: Language Agents with Verbal Reinforcement Learning — Shinn et al. (NeurIPS 2023)](https://arxiv.org/abs/2303.11366)
- [Improving Factuality and Reasoning in Language Models with Multiagent Debate — Du et al.](https://composable-models.github.io/llm_debate/)
- [Pride and Prejudice: LLM Amplifies Self-Bias in Self-Refinement — Xu et al. (ACL 2024)](https://aclanthology.org/2024.acl-long.826.pdf)
- [Self-Preference Bias in LLM-as-a-Judge](https://arxiv.org/html/2410.21819v1)
- [When "A Helpful Assistant" Is Not Really Helpful: Personas in System Prompts Do Not Improve Performances — Zheng et al. (arXiv:2311.10054)](https://arxiv.org/html/2311.10054v3)
- [LangChain: Plan-and-Execute Agents](https://www.langchain.com/blog/planning-agents)
- [CrewAI documentation](https://docs.crewai.com/en/introduction)
- [Warp scores 71% on SWE-bench Verified (single-agent architecture)](https://www.warp.dev/blog/swe-bench-verified)
- [Multi-Agent vs Single-Agent Coding: Data-Driven Comparison](https://vibecoding.app/blog/multi-agent-vs-single-agent-coding)
- [Single-Agent LLMs Outperform Multi-Agent Systems on Multi-Hop Reasoning Under Equal Thinking Token Budgets](https://arxiv.org/html/2604.02460v1)
- [Stop Wasting Your Tokens: Towards Efficient Runtime Multi-Agent Systems (arXiv:2510.26585)](https://arxiv.org/html/2510.26585v2)
- [SWE-PRBench: Benchmarking AI Code Review Quality Against Pull Request Feedback](https://arxiv.org/html/2603.26130v1)
- [Benchmarking and Studying the LLM-based Code Review (ACR F1 19.38%)](https://arxiv.org/html/2509.01494v1)
- [TDAD: Test-Driven Agentic Development (regression reduction)](https://arxiv.org/html/2603.17973)
- [Simon Willison: Red/Green TDD agentic pattern](https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/)
- [Galileo: Why Multi-Agent Systems Fail (handoff failure analysis)](https://galileo.ai/blog/why-multi-agent-systems-fail)
- [Coding Agent Teams: The Next Frontier (DevOps.com — 3–5 teammate sweet spot)](https://devops.com/coding-agent-teams-the-next-frontier-in-ai-assisted-software-development/)
- [Papers-to-Posts: LLM-supported planning, drafting, revising research blog posts](https://arxiv.org/html/2406.10370v1)
