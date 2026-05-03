# Decision Tree: Spawn Sub-Agents or Stay Single?

The full diagnostic for "should this become a multi-agent task at all?" Use when the abbreviated checklist in SKILL.md doesn't resolve the call, when token cost is non-trivial, or when the proposed decomposition has any whiff of false parallelism.

## Contents

- [Default posture](#default-posture)
- [STOP checklist (any one means stay single-agent)](#stop-checklist-any-one-means-stay-single-agent)
- [Green-light criteria (need at least one PRO + zero STOPs)](#green-light-criteria-need-at-least-one-pro--zero-stops)
- [Canonical examples that justify multi-agent](#canonical-examples-that-justify-multi-agent)
- [The decision tree](#the-decision-tree)
- [Cost/benefit denominator](#costbenefit-denominator)
- [The false-parallelism trap](#the-false-parallelism-trap)
- [MAST failure modes as red flags](#mast-failure-modes-as-red-flags)
- [Escalation ladder (single → chain → multi)](#escalation-ladder-single--chain--multi)
- [Quick triggers by request shape](#quick-triggers-by-request-shape)
- [Worked walkthroughs](#worked-walkthroughs)
- [Read-vs-write phase separation](#read-vs-write-phase-separation)
- [Edge cases](#edge-cases)

## Default posture

Start single. Add specialists only when one of the green-light criteria fires *and* none of the STOP rules fires.

> "Find the simplest solution possible, and only increase complexity when needed." — Anthropic, [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) (Dec 2024)

> "Start with one agent whenever you can. Add specialists only when they materially improve capability isolation, policy isolation, prompt clarity, or trace legibility." — [OpenAI Agents SDK orchestration & handoffs](https://developers.openai.com/api/docs/guides/agents/orchestration)

> "Not every complex task requires this approach — a single agent with the right (sometimes dynamic) tools and prompt can often achieve similar results." — [LangChain multi-agent docs](https://docs.langchain.com/oss/python/langchain/multi-agent)

The bias is asymmetric: a multi-agent system that should have been single-agent burns ~15× tokens and inherits coordination failure modes. A single agent that should have been multi-agent loses some latency on breadth-first work. Pay the cheaper mistake.

## STOP checklist (any one means stay single-agent)

Walk top to bottom. First match wins — do not continue evaluating.

| # | If… | Stay single because… |
|---|---|---|
| S1 | The output is a single coherent artifact (one essay, one module, one design doc) where stylistic or architectural choices made in one part constrain choices in another | Cognition's Flappy Bird failure: parallel agents make incompatible implicit decisions the integrator cannot reconcile. *"Actions carry implicit decisions, and conflicting decisions carry bad results."* — [Cognition, *Don't Build Multi-Agents*](https://cognition.ai/blog/dont-build-multi-agents) (June 12, 2025) |
| S2 | Subtasks share state or would edit the same files | *"Two teammates editing the same file leads to overwrites. Break the work so each teammate owns a different set of files."* — [Anthropic Claude Code agent-teams docs](https://code.claude.com/docs/en/agent-teams) |
| S3 | Each step's output feeds the next and you cannot pre-decompose | *"Coding involves fewer truly parallelizable tasks than research."* — [Anthropic, *How we built our multi-agent research system*](https://www.anthropic.com/engineering/multi-agent-research-system) (June 2025). Use prompt chaining, not multi-agent. |
| S4 | A synthesizer would have to re-read most of the source material to merge sub-results | False parallelism. The reconciliation re-does the work; net cost > single-agent cost. |
| S5 | The answer requires reasoning over the whole input simultaneously (proof check, bug in a 200-line function, architectural smell) | Sharding by lines or sections destroys the very signal needed. |
| S6 | All proposed subagents would be the same model with the same prompt | Without heterogeneity you get duplication, not diversity. *"Model heterogeneity acts as a universal antidote."* — [Zhang et al., *Stop Overvaluing MAD*](https://arxiv.org/abs/2502.08788) (arXiv:2502.08788, Feb 2025) |
| S7 | You have not yet tried Chain-of-Thought or self-consistency on a single agent | MAD frequently loses to CoT + Self-Consistency despite higher cost (Zhang et al. 2025). Try the cheaper baseline first. |
| S8 | The work is bottlenecked by I/O on a single resource (one API, one DB, one filesystem path) | Parallelizing agents does not parallelize the bottleneck. |
| S9 | You would need to share full traces (not just summaries) between agents to keep them coherent | Cognition's Principle 1: *"Share context, and share full agent traces, not just individual messages."* If you cannot, single-thread with context compression. |
| S10 | The task is short, well-bounded, or one-shot | *"Splitting too early creates more prompts, more traces, and more approval surfaces without necessarily making the workflow better."* — OpenAI Agents SDK |
| S11 | The value of the answer doesn't justify ~15× token spend | Multi-agent systems use ~15× more tokens than chats; agent interactions ~4× more (Anthropic). Do the math before committing. |
| S12 | You cannot write disjoint, non-overlapping briefs — two would naturally read the same file or run the same query | Anthropic failure mode: *"duplicated work without effective labor division."* Collapse them. |
| S13 | The user is in iterative dialogue and will steer turn-by-turn | Each subagent spawn destroys the live conversation thread. |
| S14 | You cannot bake verification into each subagent's brief | MAST shows 31% of multi-agent failures concentrate in verification & termination. Bake it in or skip multi-agent. |

If any STOP fires: single agent (or a prompt chain), and stop the evaluation. Do not "but we could mitigate" — the mitigations are themselves multi-agent failure modes.

## Green-light criteria (need at least one PRO + zero STOPs)

Any one PRO is sufficient *if and only if* no STOP fired above.

| # | If… | Multi-agent is justified because… |
|---|---|---|
| P1 | You can write down N≥3 sub-questions whose answers don't depend on each other and that you'd merely concatenate or aggregate | Independent breadth is what subagents are designed for. Multi-agent Opus 4 + Sonnet 4 subagents outperformed single-agent Opus 4 by **90.2%** on Anthropic's internal research eval. — [Anthropic, *Multi-Agent Research System*](https://www.anthropic.com/engineering/multi-agent-research-system) |
| P2 | The task requires reading >10 files, ingesting large logs, or running a chain of tool calls whose intermediate output is throwaway | *"When a task requires exploring ten or more files, or involves three or more independent pieces of work, that's a strong signal to direct Claude toward subagents."* — [Anthropic, subagents in Claude Code](https://claude.com/blog/subagents-in-claude-code). Verbose output stays in the subagent; only synthesis returns. |
| P3 | Your single-agent system prompt has grown into a kitchen sink of conflicting instructions, or its tool list is so long that tool-selection accuracy is dropping | *"A single agent has too many tools and makes poor decisions about which to use."* — LangChain. Splitting into role-specific agents with focused prompts and narrower tool sets recovers accuracy. |
| P4 | Wall-clock latency matters more than token cost AND the work is genuinely parallel | Anthropic measured **up to 90% latency reduction** for breadth-first parallel work. |
| P5 | The task benefits from adversarial verification — debugging with competing hypotheses, security review with multiple lenses | *"Spawn 5 agent teammates to investigate different hypotheses. Have them talk to each other to try to disprove each other's theories, like a scientific debate."* — Anthropic agent-teams docs. Parallel falsification beats sequential investigation's anchoring. |
| P6 | Each subagent's output can be independently verified (tests pass, citation matches, schema validates) without the parent re-doing the work | Anthropic's research system pairs subagents with a CitationAgent that verifies each claim independently. Verification baked in is the boundary between multi-agent that works and multi-agent that fails. |
| P7 | The problem is open-ended with unpredictable structure — you cannot write the DAG of subtasks ahead of time | *"Open-ended problems where it's difficult or impossible to predict the required number of steps and where you can't hardcode a fixed path."* — Anthropic, *Building Effective Agents*. Orchestrator decides subtasks based on intermediate results. |

## Canonical examples that justify multi-agent

Use these as templates when matching against the user's request.

**S&P 500 board members (Anthropic).** *"Identify all the board members of the companies in the Information Technology S&P 500."* A single agent searched sequentially and failed; a multi-agent decomposition (one subagent per company, or per cluster of companies) found the answer. Multi-agent Opus 4 + Sonnet 4 subagents outperformed single-agent Opus 4 by 90.2% on Anthropic's internal research eval and cut research latency up to 90%. The shape: one orchestrator, N independent lookups, trivial aggregation. P1 + P2 + P4.

**PR review through different lenses (Anthropic agent-teams).** Security agent reads for vulnerabilities, performance agent reads for hot paths, test-coverage agent checks for gaps. Each owns its lens, each produces an independently verifiable report. P3 + P5 + P6. Disjoint reads (not edits) keep S2 from firing.

**Adversarial debugging (Anthropic agent-teams).** *"Spawn 5 agent teammates to investigate different hypotheses. Have them talk to each other to try to disprove each other's theories, like a scientific debate."* Each subagent owns one hypothesis, tries to falsify the others. Beats sequential single-agent investigation, which anchors on the first plausible cause. P5 + P7.

**Comparative analysis at scale.** *"Compare 20 vendors on these axes."* One orchestrator, one subagent per vendor (or per axis), aggregate to a table. P1 + P2.

**Literature survey across many papers.** Each subagent reads one paper and returns a structured summary; orchestrator merges into a comparative review. P1 + P2 + P6 (citation as verification).

**Verbose-output isolation (Anthropic subagents docs).** *"One of the most effective uses for subagents is isolating operations that produce large amounts of output. Running tests, fetching documentation, or processing log files can consume significant context. By delegating these to a subagent, the verbose output stays in the subagent's context while only the relevant summary returns to your main conversation."* Even within a single-agent task, wrapping a noisy tool call in a subagent is justified. P2.

## The decision tree

```
Is the task one coherent artifact requiring a single voice/architecture?
├─ YES → single agent (or prompt chain). STOP.
└─ NO →
   Can you write N≥3 disjoint, independently verifiable subtasks
   whose results merely aggregate (no re-reading source to merge)?
   ├─ NO → single agent (false parallelism risk). STOP.
   └─ YES →
      Is the value > 15× the single-agent token cost,
      OR is latency-reduction critical?
      ├─ NO → single agent. STOP.
      └─ YES →
         Will subagents need to share traces / coordinate mid-task?
         ├─ YES → single thread w/ context compression (Cognition pattern). STOP.
         └─ NO →
            Is verification baked into each subagent's brief?
            ├─ NO → add verification, OR fall back to single agent.
            └─ YES → MULTI-AGENT (3-5 subagents, parallel, breadth-first).
```

The tree has five gates: artifact coherence → decomposability → value/latency → coordination need → verification. Failure at any gate routes to single agent. Only tasks that clear all five earn the multi-agent multiplier.

## Cost/benefit denominator

Numbers to plug into the value gate:

| Configuration | Token multiplier vs single chat | Source |
|---|---|---|
| Single chat | 1× | baseline |
| Single agent with tools | ~4× | Anthropic |
| Multi-agent system | ~15× | Anthropic — driven 80% by token usage variance per BrowseComp eval |
| 4-agent workflow | ~3.5× | DeepMind / [*The Multi-Agent Trap*](https://towardsdatascience.com/the-multi-agent-trap/) (2026) |

> "Multi-agent systems use ~15× more tokens than chats; agent interactions ~4× more. Tasks must have high enough value to justify it." — Anthropic, *Multi-Agent Research System*

Reliability decay across sequential steps:

- 95% per-step × 10 steps → 59.9% end-to-end success
- 95% per-step × 20 steps → 35.8% end-to-end success

Latency:

- Up to 90% reduction for breadth-first parallel work
- Increased for sequential coordination

The multiplier IS justified for:

- High-stakes, high-value answers (research deliverables, regulatory analysis, due diligence)
- Broad search where answer quality scales with breadth (S&P 500 board members, comparative vendor analysis)
- Tasks where verification is itself expensive and an extra agent doing it is cheaper than human review
- Latency-critical breadth-first work where wall-clock dominates token cost
- Tasks the user will pay 15× for because the answer would otherwise be unreachable

The multiplier is NOT justified for:

- One-shot factual queries answerable in-context
- Short codegen tasks (<5 files, <500 lines)
- Tasks where the parent's existing context is the asset (rewriting that context into N subagent prompts loses information)
- Iterative dialogue where the user steers turn-by-turn
- Anything where a CoT or self-consistency single-agent baseline hasn't been tried

## The false-parallelism trap

Tasks that look parallelizable but aren't. If the proposed decomposition matches any pattern below, it is single-agent work in disguise.

**Hidden shared state (Flappy Bird).** Parallel subagents make conflicting implicit decisions the integrator cannot reconcile without re-doing the work. *Tell:* the subtasks share an unstated style, architecture, or format that no brief fully specifies. The integrator faces a Frankenstein of mismatched parts.

**Reconciliation re-does the work.** "Summarize each chapter" → "produce one coherent summary" forces the synthesizer to re-read or re-reason over everything to deduplicate, order, and stitch. *Tell:* the synthesis prompt would itself need most of the source material, not just the subagent outputs. Net cost > single-agent cost.

**Cascading errors.** *"Unstructured multi-agent networks amplify errors up to 17.2× compared to single-agent baselines."* — Google DeepMind via [*The Multi-Agent Trap*](https://towardsdatascience.com/the-multi-agent-trap/). Compound reliability collapses fast (see denominator table). *Tell:* a long sequential chain of agents, each consuming the previous output without verification.

**Agreement-on-wrong (MAD failure).** *"MAD often fail to outperform simple single-agent baselines such as Chain-of-Thought and Self-Consistency, even when consuming significantly more inference-time computation."* — Zhang et al. 2025. When agents share priors, debate ratifies errors instead of correcting them. *Tell:* all subagents are the same model with the same prompt — duplication, not diversity.

**Tool-call bottleneck disguised as compute bottleneck.** Work is bottlenecked by I/O on one resource. *Tell:* spawning more agents just queues on the same lock.

**Context isolation that hides facts the parent needs.** Subagent finds the answer but returns only a summary; parent's follow-up needs a discarded fact; subagent gets re-run. *Tell:* you find yourself wishing the parent had the trace, not just the result. Cognition's Principle 1 applies — share full traces or stay single-threaded.

## What multi-agent that actually fails looks like

Three failure shapes worth memorizing — they show up across the literature and are the strongest argument for the conservative defaults above.

**The Flappy Bird (Cognition).** Two parallel subagents are told to build a Flappy Bird clone. One builds a Super Mario Bros. background; the other builds a mismatched bird sprite. The integrator can't reconcile them. This is the canonical case for STOP rule S1 (single coherent artifact). The brief omitted what every subagent would have needed: shared style, shared sprite dimensions, shared physics constants. *No brief can fully specify the implicit shared state of a coherent artifact.* If you find yourself writing "and please match the visual style of the other subagent's output" into a sub-brief, you've identified a Flappy Bird.

**Endless web search (Anthropic failure mode).** Subagents spawn for trivial queries, then spawn search loops looking for nonexistent sources. The orchestrator doesn't terminate because no subagent declares "no result found." This maps to MAST category 3 (verification & termination) and to STOP rule S14. Mitigations: hard step caps, explicit "return 'not found'" affordance in each subagent brief, a top-level budget check.

**Cascading degradation (DeepMind).** *"Unstructured multi-agent networks amplify errors up to 17.2× compared to single-agent baselines."* Each agent in a sequential chain consumes the previous output as ground truth without verification. Small errors at step 1 become large errors by step 10. Compound reliability: 95% per-step × 10 steps = 59.9%; × 20 steps = 35.8%. This is why STOP rules S3 and S14 are non-negotiable: long sequential chains without per-step verification are doomed by arithmetic, not by model quality.

## MAST failure modes as red flags

The MAST taxonomy (Cemri et al., [*Why Do Multi-Agent LLM Systems Fail?*](https://arxiv.org/abs/2503.13657), arXiv:2503.13657, Mar 2025) catalogs 14 failure modes across three categories. ~70% of MAS failures are coordination/verification problems, not capability problems. If the proposed decomposition can't design these out, don't decompose.

**Specification & System Design — 37% of failures.** Disobey task spec, disobey role spec, step repetition, loss of conversation history, unaware of termination conditions. *Red flag:* you can't write a tight per-agent role brief without overlap or ambiguity.

**Inter-Agent Misalignment — 31% of failures.** Conversation reset, fail to ask for clarification, task derailment, information withholding, ignored other agent's input, reasoning–action mismatch. *Red flag:* the agents need to negotiate or pass nuanced state between each other.

**Verification & Termination — 31% of failures.** Premature termination, no/incomplete verification, incorrect verification. *Red flag:* you have no mechanical check (test, schema, citation resolve) for each subagent's output.

> "Improvements in base model capabilities will be insufficient to address the full MAST." — Cemri et al. 2025

These are architectural problems. Better models do not fix them. The decomposition either prevents them by design or eats them.

## Escalation ladder (single → chain → multi)

Climb the ladder one rung at a time. Re-evaluate after each rung. Stop at the lowest rung that meets the goal.

**Rung 0 — Single chat.** Plain prompt, no tools. ~1× baseline cost. Try first for one-shot factual queries, single-question Q&A, anything answerable from training data without retrieval.

**Rung 1 — Single agent with tools.** One agent, focused tool set, narrow system prompt. ~4× baseline cost. Default for codegen, refactors, debugging, and most assistance work. Resist adding tools beyond what the immediate task needs — every extra tool degrades selection accuracy.

**Rung 2 — Single agent + Chain-of-Thought or Self-Consistency.** Same agent, structured reasoning or N samples + majority vote. Try this *before* multi-agent debate; Zhang et al. 2025 shows MAD often loses to it. Self-consistency at N=5 typically costs less than a 3-agent debate and often performs better.

**Rung 3 — Prompt chain.** Sequential single-agent calls where step N feeds step N+1, each call with a tightly scoped prompt. Use when the task is sequential but each step's prompt is materially different (extract → transform → validate → emit). Verification gate between every step. Cheaper and more reliable than a single mega-prompt for multi-stage work.

**Rung 4 — Routing.** Single classifier agent dispatches to one of M specialist agents. Use when the input space partitions cleanly (intent A → specialist A, intent B → specialist B) and the specialists need divergent prompts/tools, but only one runs per request. Routing pays for itself when the classifier is small/fast and the specialists are deep.

**Rung 5 — Single thread with context compression (Cognition pattern).** One agent, long task, periodic compression of trace into summaries to keep context under budget. Use when you wanted multi-agent for context isolation but coherence matters more than parallelism. The compression itself can be a sub-call (cheap), but the main reasoning stays linear.

**Rung 6 — Orchestrator + parallel subagents (3–5).** Multi-agent. ~15× baseline cost. Reserve for breadth-first independent work that cleared all five gates of the decision tree. Anthropic guidance: *"Start with 3-5 teammates. Three focused teammates often outperform five scattered ones."* Each subagent gets a self-contained brief, narrow tools, and a verification mechanism.

**Rung 7 — Orchestrator + parallel subagents + adversarial reviewers.** Multi-agent with explicit "try to disprove each other" framing. Use for hypothesis investigation, security review, or anywhere anchoring bias is the failure mode. The adversarial framing is the entire point — without it, you've spent rung-7 tokens for rung-6 outcomes.

**Rung 8 — Hierarchical (orchestrator → sub-orchestrators → workers).** Reserve for genuinely huge breadth-first problems where flat 3–5 fan-out doesn't fit. Each layer doubles the coordination surface and the MAST failure exposure; most tasks never need this rung. If you're considering it, first check whether the problem can be batched into independent rung-6 invocations instead.

Rule: do not skip rungs. If you're considering rung 6, you should be able to articulate why rungs 1–5 fail.

Heuristics for sizing rung 6:

- **Start with 3.** *"Three focused teammates often outperform five scattered ones."* — Anthropic agent-teams docs. Three forces tight role briefs; five tempts overlap.
- **Cap at 5 unless the breadth is genuinely indexable.** Anthropic's S&P 500 case scales to N=500 because each subagent owns one company — the indexing is mechanical. If your subagents need hand-written briefs, 5 is the soft ceiling.
- **Never spawn 50 for a trivial query.** Anthropic explicitly lists this as a failure mode. If you're tempted, the upstream task spec is wrong — re-decompose at a coarser grain.
- **Match model to subagent role.** Orchestrator on Opus, workers on Sonnet (or smaller). Anthropic's 90.2% gain came from Opus 4 + Sonnet 4 subagents, not Opus everywhere.
- **One verification mechanism per subagent.** No subagent ships without a check (test, schema, citation, structured-output validator). MAST: 31% of failures are verification holes.

## Quick triggers by request shape

Pattern-match the user's ask against these. Not exhaustive, but covers the common cases.

| Request shape | Default rung | Why |
|---|---|---|
| "Compare X across N things" with N≥4 | Rung 6 (multi-agent) | Independent branches, aggregate result. P1 fires. |
| "Is this PR good?" with multiple lenses (security/perf/tests) | Rung 6 (agent team, one lens each) | P5 (adversarial) + P3 (specialized prompts) fire. Disjoint files reduce S2 risk. |
| "Research X" with open scope | Rung 6 (orchestrator + breadth-first subagents) | P1 + P7 fire. Open-ended, breadth-first, aggregate. |
| "Identify all the [thing] across [large set]" | Rung 6 | The Anthropic S&P 500 canonical case. P1 + P2 + P4 fire. |
| "Fix this bug" | Rung 1 (single agent) | S3 + S5 fire — sequential, holistic, shared state. |
| "Refactor this module" | Rung 1 | S1 fires — single coherent artifact. |
| "Write [essay / doc / module]" | Rung 1 | S1 fires — single voice required. |
| "Find all references to X across these 50 files" | Rung 6 | P2 fires — file scan is the canonical fan-out. |
| "Read the whole codebase and tell me Y" | Rung 5 or 6 | P2 fires; choose rung 5 if Y requires holistic understanding, rung 6 if Y aggregates per-file findings. |
| "Help me think through Z" | Rung 0 or 1 | S13 fires — iterative dialogue, user is steering. |
| "Run the test suite and tell me what failed" | Rung 1 with subagent for the test run | P2 fires for the verbose-output isolation; the analysis itself is single-agent. |

Phil Schmid's compression: *"Read tasks (research, analysis) → multi-agent. Write tasks (code, content) → single agent. Mixed → separate read and write phases."* — [Single vs Multi-Agent System?](https://www.philschmid.de/single-vs-multi-agents) Useful as a sanity check after the gate walk, not a substitute for it.

## Read-vs-write phase separation

A useful framing when the task mixes both:

> "Read tasks (research, analysis) → multi-agent. Write tasks (code, content) → single agent. Mixed → separate read and write phases." — Phil Schmid, [Single vs Multi-Agent System?](https://www.philschmid.de/single-vs-multi-agents)

Read tasks tolerate parallelism because the input is fixed and the outputs aggregate. Write tasks resist parallelism because the output is a single coherent artifact that propagates implicit decisions (S1, the Flappy Bird).

When a request is mixed ("research X then write a memo about it"), don't try to multi-agent both phases. Multi-agent the research, hand the structured findings to a single-agent writer. The writer benefits from the research breadth without inheriting the coherence problem.

This framing also resolves the "I want adversarial review on my draft" case: write the draft single-agent, then adversarially review it with a second agent (sequential prompt chain, rung 3), not parallel co-writers.

## Edge cases

**"It feels parallelizable but the gates fail."** Trust the gates. The Flappy Bird, MAD, and cascading-error failures all started as "this feels parallelizable." If the gates fail, the parallelism is hallucinated.

**"The user explicitly asked for multiple agents."** Surface the trade-off — token cost, coordination failure modes, MAST 70% — and let them decide. Don't silently downgrade their request, don't silently honor a request that will burn 15× tokens for a worse answer.

**"It's borderline."** Default to the lower rung. The asymmetric cost (above) means borderline calls should fall to single-agent. The upgrade is cheaper to make later than the downgrade.

**"I want adversarial review on a single artifact (S1) — what now?"** Single agent produces draft. Second agent (or same agent in a fresh context) critiques. Sequential, not parallel. This is rung 3 (prompt chain) with a critic step, not rung 6.

**"The orchestrator itself is becoming complex."** That's a signal you've over-decomposed. Collapse subagents back into the orchestrator's context until the orchestrator is doing the simplest thing that could possibly work.

**"Latency is critical but the gates fail."** You can't buy parallelism out of a sequential problem. Look for caching, smaller models, narrower prompts, or pre-computation instead of more agents.

**"The user keeps asking follow-ups after each multi-agent run."** The multi-agent shape is wrong for this conversation. Drop to single-agent and let the user steer; spawn subagents only for individual verbose sub-tasks within their turns.

**"My multi-agent system worked yesterday and is failing today."** First check whether the underlying task shape changed (more files, different artifact type, new shared state). MAST failures are often latent — a system that handled 5 disjoint files breaks at 50 because a synthesizer overflow that was tolerable at small N becomes fatal at large N. Re-run the gates against today's task, not yesterday's.

**"I'm not sure whether to trust the gates."** The gates encode failure modes that have been measured in production at Anthropic, Cognition, DeepMind, and in academic evals. Trusting them costs you some latency on borderline calls. Distrusting them costs you ~15× tokens, MAST failures, and Flappy Birds. The asymmetry favors the gates.

**"The framework I'm using (CrewAI, LangGraph, AutoGen, etc.) makes multi-agent easy."** Tooling ease is not evidence of task fit. The frameworks make spawning agents cheap; they do not make the underlying coordination problems disappear. Walk the gates regardless of framework.

## Worked walkthroughs

Three concrete requests, walked through the gates.

**Request 1: "Find all the places this deprecated function is called across our 80-file backend, and tell me which call sites need migration to the new API."**

- S1 (single artifact)? No — the output is an enumeration, not a coherent draft.
- S2 (shared state / same files)? No — read-only scan, no edits.
- S3 (sequential dependence)? No — each file inspection is independent.
- S4 (synthesizer re-reads source)? No — the synthesizer only needs the per-file findings.
- S5 (holistic reasoning)? No — per-call-site analysis is local.
- S10 (short / one-shot)? No — 80 files exceeds the in-context easy case.
- S14 (verification baked in)? Yes, can be — each subagent returns "found N call sites at lines L1…LN, migration: trivial/manual/none" and the orchestrator can spot-check.
- P1 fires (N≥3 disjoint subtasks). P2 fires (>10 files). P6 fires (per-file verification cheap).
- Verdict: rung 6, multi-agent. 5–10 subagents partitioned by file group.

**Request 2: "Refactor this 600-line module to extract a clean public API."**

- S1 (single artifact)? Yes — one module, architectural choices propagate.
- Stop. Verdict: rung 1, single agent. Do not split by section, do not parallelize "refactor each function" — the API extraction *is* the holistic reasoning.

**Request 3: "Write a research report comparing how five major cloud providers handle ephemeral compute, with citations."**

- S1 (single artifact)? Borderline — the final report is one document, but the per-provider research is genuinely independent. Resolve by separating phases: research is multi-agent, writing is single-agent. (Phil Schmid: read tasks → multi-agent, write tasks → single agent, mixed → separate phases.)
- For the research phase: S2/S3/S4/S5 don't fire. S14: verification = citation resolves. P1 + P5 + P6 fire.
- Verdict for research phase: rung 6, one subagent per provider, each returns structured findings + citations.
- Verdict for write phase: rung 1, single agent ingests the structured findings and writes the report in one voice.
