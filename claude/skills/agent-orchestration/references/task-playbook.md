# Task-Type Playbook

Per-task orchestration recipes. Twenty task signatures, each with its recommended pattern, typical agent count, escalation triggers, anti-patterns, and a concrete unfold. Consult when the 10-row summary table in SKILL.md is too coarse.

Two cross-cutting truths from the primary literature anchor everything below:

1. "Token usage alone explains 80% of the variance in performance" — Anthropic on their multi-agent research system. Multi-agent fan-out spends ~15x more tokens than single-shot chat. You buy parallel exploration with tokens; if the task does not reward exploration, you are lighting tokens on fire ([Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)).
2. "Multi-agent works when writes stay single-threaded and additional agents contribute intelligence rather than actions" — Cognition's revised position after operating multi-agent systems in production. The biggest failure mode is multiple actors making conflicting writes; the safest multi-agent shape is many readers/critics and one writer ([Cognition — Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents)).

Both companies independently converged on: **context engineering, not agent count, is the lever.**

## Contents

- [1. Open-ended research](#1-open-ended-research)
- [2. Codebase exploration](#2-codebase-exploration)
- [3. Code generation — small feature, single file](#3-code-generation--small-feature-single-file)
- [4. Code generation — large feature spanning many files](#4-code-generation--large-feature-spanning-many-files)
- [5. Refactoring across many files](#5-refactoring-across-many-files)
- [6. Bug diagnosis / debugging](#6-bug-diagnosis--debugging)
- [7. Code review](#7-code-review)
- [8. Test generation](#8-test-generation)
- [9. Security review / threat modeling](#9-security-review--threat-modeling)
- [10. Planning / architecture design](#10-planning--architecture-design)
- [11. Documentation writing](#11-documentation-writing)
- [12. Data extraction / scraping at scale](#12-data-extraction--scraping-at-scale)
- [13. Evaluation / benchmarking / scoring](#13-evaluation--benchmarking--scoring)
- [14. Migration tasks](#14-migration-tasks)
- [15. Open-ended creative writing](#15-open-ended-creative-writing)
- [16. Translation / localization](#16-translation--localization)
- [17. Decision-making with tradeoffs](#17-decision-making-with-tradeoffs)
- [18. Synthesis of many documents](#18-synthesis-of-many-documents)
- [19. Long-horizon agent tasks](#19-long-horizon-agent-tasks)
- [20. One-shot lookup / question answering](#20-one-shot-lookup--question-answering)
- [Summary lookup table](#summary-lookup-table)
- [Cross-cutting heuristics](#cross-cutting-heuristics)
- [Escalation ladder](#escalation-ladder)
- [Decision procedure](#decision-procedure)

## 1. Open-ended research

**Pattern:** Orchestrator + parallel research workers + synthesizer. The canonical fan-out-then-merge use case.

**Typical N:** Lead spawns **3–5 subagents per round** (Anthropic's measured sweet spot). For very wide queries, two rounds (15–25 total worker invocations).

**Trigger to escalate:**
- Query has ≥3 clearly independent sub-questions.
- Expected answer requires synthesis from ≥10 sources.
- Single-agent context would overflow with raw evidence.
- Wall-clock matters and subqueries are independent.

**Stay single-agent when:** The user just wants one fact, the answer fits in a few searches, or sub-questions chain (each depends on the previous answer — that is a pipeline, not fan-out).

**Anti-patterns:**
- Spawning subagents for *sequentially dependent* lookups — they duplicate work and miss each other's findings.
- Letting subagents write to a shared scratchpad — write conflicts; instead each returns a structured summary to the lead.
- Using the orchestrator's context as a dumping ground for raw worker output — force workers to return tight structured summaries.

**Concrete unfold:** "Compare the security models of major LLM coding agents." Lead writes a 5-bullet plan, spawns 5 subagents (one per agent: Claude Code, Cursor, Devin, Copilot, Codex), each subagent does ~10 parallel tool calls (web search, doc fetch, GitHub), each returns a 200-token structured summary, lead synthesizes a comparison table, optional citation-checker subagent verifies claims.

Why it wins: read-only work (no write conflicts), wide unpredictable search space requires dynamic decomposition, independent subqueries parallelize cleanly, each worker gets its own context window so the lead is never polluted with raw search dumps. Anthropic measured this pattern beating single-agent Opus 4 by 90.2% on internal research evals, with up to 90% wall-clock reduction on complex queries ([Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system); [Anthropic — Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)).

## 2. Codebase exploration

**Pattern:** Single Explore-style sub-agent (delegated, not inline) for non-trivial questions. Inline for one-shot greps.

**Typical N:** 1 explorer for "how does Y work"; 2–4 parallel explorers for "compare implementation across N modules / repos."

**Trigger to escalate (inline → single subagent):** Expected to read ≥5 files OR run ≥3 grep iterations OR file paths are not obvious upfront. Below that bar, do it inline — spawning a subagent costs a turn and serializes you behind its return.

**Trigger to escalate (one → many):** The question explicitly compares N independent areas; OR the codebase has ≥3 services and the question crosses all of them.

**Stay single-agent when:** A single grep would answer it.

**Anti-patterns:**
- Spawning a sub-agent for a single `grep` — round-trip cost dwarfs the work.
- Parallel explorers on a single small repo — they re-read the same files.
- Asking the explorer to also fix the bug it finds — mixes read with write and loses the context-isolation benefit (the parent now needs full diff context anyway).

**Concrete unfold:** "How does authentication work?" Spawn one Explore agent with the codebase, it greps, reads ~15 files, builds a mental model, returns a 300-token summary with file paths and a flow diagram. Parent uses the summary to answer the user without ever loading those 15 files.

Why it wins: the primary value of delegating here is **context isolation** — you do not want 50 file reads polluting the parent context. One Explore sub-agent does the spelunking and returns a tight answer ([Subagents in VS Code](https://code.visualstudio.com/docs/copilot/agents/subagents); [Cognition — Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents)).

## 3. Code generation — small feature, single file

**Pattern:** Single agent. Optionally a critic pass if correctness is important.

**Typical N:** 1 (writer). Add 1 critic if the code is going to production.

**Trigger to escalate (single → single + critic):** Code touches a security boundary, payments, or anything where a bug is expensive; OR the user explicitly wants review.

**Trigger to escalate further:** Do not, until the task crosses into category #4.

**Stay single-agent when:** Default. Single file, single concern, no parallelism dividend.

**Anti-patterns:**
- "Planner + implementer" split for a 50-line change — the planner just rewrites the request.
- Spawning a test-writer subagent in parallel with the implementer — tests will be wrong because the implementation is still in flux.

**Concrete unfold:** "Add a debounce to this input handler." Single agent reads file, edits, optionally runs tests. Done.

Why it wins: coordination overhead would dwarf the work. Cognition's "Don't Build Multi-Agents" thesis was sharpest here — parallel subagents make conflicting micro-decisions about naming, style, and structure when the work is small and tightly coupled ([Cognition — Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents); [Anthropic — Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)).

## 4. Code generation — large feature spanning many files

**Pattern:** Planner (single) → single implementer with on-demand subagents for isolated sub-problems → tester/reviewer. Avoid parallel implementers writing to the same code surface.

**Typical N:** 1 planner, 1 implementer, 0–N read-only sub-explorers, 1 tester. Total active writers: **always 1**.

**Trigger to escalate to true multi-implementer:** Only when the feature decomposes into **provably disjoint files/modules with a stable interface contract written first** (e.g., "build the frontend page and the new API endpoint in parallel, contract is this OpenAPI spec"). Use Git worktree isolation per agent in this case ([Cursor 2.0 — multi-agent worktree isolation](https://cursor.com/changelog/2-0); [Composio Agent Orchestrator](https://github.com/ComposioHQ/agent-orchestrator)).

**Stay single-implementer when:** No interface contract has been agreed upfront. Default.

**Anti-patterns:**
- Parallel implementers on overlapping files — merge hell, conflicting abstractions.
- Planner that writes pseudocode the implementer must "fill in" — the implementer often disagrees with the plan halfway through and you waste the plan.
- Skipping the interface contract before parallel implementation.

**Concrete unfold:** "Add a billing module." Planner produces a 1-page design + interface contract + file list. Implementer works file-by-file, spawning explore-subagents as needed for "how does the existing Stripe integration work." Tester subagent writes tests against the interface contract. Critic reviews diff. If parallelizing: planner writes the contract, then frontend-implementer and backend-implementer work in separate worktrees against the contract, each with their own test agent.

Why it wins: writes must stay single-threaded to avoid conflicting design decisions (Cognition's hardest-won lesson). Planning benefits from one careful agent owning the architecture; *exploration* benefits from parallel read-only subagents. The implementer can spawn read-only subagents on demand without forking the write surface ([Cognition — Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents); [MetaGPT](https://arxiv.org/abs/2308.00352)).

## 5. Refactoring across many files

**Pattern:** Planner (defines the transformation) → parallel per-file or per-module workers → integration verifier. One of the cleanest fan-out fits in coding.

**Typical N:** 5–50 parallel workers (one per file or small group), gated by file count and rate limits. Google/LinkedIn report processing hundreds of files in hours with this shape.

**Trigger to escalate:** ≥10 files affected by the same mechanical change AND the change is local (does not require global reasoning per file).

**Stay single-agent when:** The refactor requires global reasoning (e.g., redesigning a class hierarchy where one decision propagates), or the file count is small (<10).

**Anti-patterns:**
- Parallel workers without a deterministic codemod for the mechanical parts — agents produce stylistically inconsistent results across files.
- No integration verification step — files compile individually but break at boundaries.
- Letting workers redesign on the fly — they should follow the planner's spec rigidly.

**Concrete unfold:** "Migrate all 80 React class components to hooks." Planner writes a per-file transformation spec and identifies the 5 patterns observed. 80 parallel workers each handle one file with the spec. Each runs the file's tests. Integration agent runs the full test suite and triages failures. Flagged files get a serial second pass.

Why it wins: refactors are usually mechanical and *locally scoped per file* once the transformation is specified. Per-file work is independent, so write conflicts are file-bounded, not codebase-wide ([LinkedIn — AI Agents for Framework Migration](https://www.zenml.io/llmops-database/ai-agents-for-accelerating-model-development-and-framework-migration); [Migrating Code At Scale With LLMs At Google](https://arxiv.org/html/2504.09691v1); [Codemod](https://codemod.com/)).

## 6. Bug diagnosis / debugging

**Pattern:** Single agent with reflexion loop, optionally with a separate read-only "explore" sub-agent for codebase context. For hard bugs, add an evaluator-optimizer pair (debugger writes hypothesis + minimal repro; critic challenges).

**Typical N:** 1 debugger; +1 explorer (on demand); +1 critic for hard bugs. Maximum 3.

**Trigger to add a critic:** First fix attempt failed; OR hypothesis has not narrowed after 3 iterations; OR bug is in unfamiliar code.

**Trigger to add an explorer:** Bug crosses ≥3 files the debugger does not already have loaded.

**Stay single-agent when:** Bug is in code already loaded and first hypothesis is concrete.

**Anti-patterns:**
- Parallel debuggers on the same bug — they pick different theories and the orchestrator cannot tell which is right.
- Letting the critic see the debugger's reasoning chain — sycophancy: the critic agrees because the chain looks plausible. Show only execution traces, expected vs. actual, and rubric.
- Skipping minimal repro before fixing.

**Concrete unfold:** "This test is flaky." Debugger reads the test, hypothesizes a race condition, adds logging, runs 50 times, reflects on results. Still failing. Critic reviews execution traces (not debugger's reasoning) and points out a missed code path. Debugger forms new hypothesis, fixes, critic verifies.

Why it wins: debugging is inherently sequential — each test/print result narrows the hypothesis space. Parallel debuggers diverge into different theories and waste tokens. AgentDevel found that an implementation-blind critic that sees only execution traces (not the agent's "blueprint") substantially improves outcomes — the critic must be ignorant of the agent's reasoning to avoid sycophancy. Self-Refine and Reflexion both demonstrated that iterative self-critique on the same trace beats one-shot, with Reflexion + LDB hitting 98.2 on HumanEval ([Self-Refine](https://arxiv.org/abs/2303.17651); [Reflexion](https://openreview.net/pdf?id=vAElhFcKW6); [AgentDevel — implementation-blind critic](https://arxiv.org/html/2601.04620); [Reflection Agents (LangChain)](https://blog.langchain.com/reflection-agents/)).

## 7. Code review

**Pattern:** Parallel checklist specialists (security, performance, style, correctness, docs) → consensus aggregator. Optionally with a verification pass to filter false positives.

**Typical N:** 3–7 specialists (security, performance, correctness, style, docs, dependencies, tests). Add 1 verification agent that re-checks each finding against the actual code to filter hallucinations.

**Trigger to escalate (single reviewer → panel):** PR touches ≥1 sensitive surface (auth, payments, data); OR diff size >200 lines; OR cross-cutting concerns (perf + security + correctness).

**Stay single-reviewer when:** Trivial diffs, internal scripts, throwaway code.

**Anti-patterns:**
- One mega-prompt asking one agent to check everything — produces shallow generic findings.
- No verification pass — half the findings are hallucinations citing code that does not exist.
- Letting reviewers see each other's findings before voting — anchoring bias.

**Concrete unfold:** PR opens. Orchestrator dispatches 5 reviewers in parallel against the diff. Each returns structured findings with line refs. Verification agent confirms each finding by re-reading the cited code. Aggregator clusters duplicates and weights by inter-reviewer agreement. Posts consolidated review.

Why it wins: different review concerns are largely independent (a security review and a style review do not conflict). Specialization beats generalization here — a security-focused prompt with vulnerability patterns produces deeper findings than "review this code." Cognition reports their Devin Review pattern catches an average of 2 bugs per PR. Confidence-weighted consensus reduces false positives (findings flagged by ≥2 agents are higher signal) ([Cloudflare — Orchestrating AI Code Review at scale](https://blog.cloudflare.com/ai-code-review/); [AI Code Reviewer (Calimero)](https://github.com/calimero-network/ai-code-reviewer); [Cognition — Devin Review](https://www.zenml.io/llmops-database/multi-agent-systems-in-production-code-generation-and-review-at-scale); [Claude Code — Code Review](https://code.claude.com/docs/en/code-review)).

## 8. Test generation

**Pattern:** Separate test-writer agent (not the same one that wrote the code), optionally with a property-based fan-out (Generator + Tester pair).

**Typical N:** 1 test writer (separate from implementer); for hard correctness, +1 property-test generator that produces invariants (Generator/Tester pair).

**Trigger to use property-based fan-out:** Function has clear invariants (commutativity, idempotence, round-trip), or you need adversarial coverage beyond examples.

**Stay in same agent when:** Tiny throwaway code, or a bug fix where the regression test is obvious from the bug description.

**Anti-patterns:**
- Same agent writes implementation and tests in one breath — tests pass trivially.
- Test writer with full access to the implementation — tests overfit to it. Give the writer the *spec/interface*, not the implementation, when feasible.
- Property-based fan-out for plain CRUD code — overhead with no payoff.

**Concrete unfold:** Implementer finishes feature. Test-writer agent receives the function signature, docstring, and acceptance criteria (NOT the implementation). Writes example tests. Property generator proposes 3 invariants. Tester runs 1000 random inputs against each invariant. Failures get fed back to implementer.

Why it wins: the implementer is biased toward "tests that the implementation passes" — they encode the same misunderstandings. A separate writer reads the spec and writes tests for *intended* behavior. The Property-Generated Solver paper showed a Generator/Tester separation produces 23–37% relative pass@1 gains over TDD baselines ([Property-Generated Solver](https://arxiv.org/html/2506.18315v1); [CANDOR / JUnit multi-agent](https://arxiv.org/abs/2506.02943); [Rethinking the Value of Agent-Generated Tests](https://arxiv.org/html/2602.07900)).

## 9. Security review / threat modeling

**Pattern:** Red team / blue team (adversarial pair). Optionally a "purple team" orchestrator that arbitrates and tracks findings. The cleanest adversarial fit in the entire taxonomy.

**Typical N:** 1 red + 1 blue + 1 arbiter (purple) = **3**. For deep audits, multiple specialized red agents (injection, auth bypass, data exfil, supply chain).

**Trigger to use red/blue:** Code is internet-facing, touches credentials/PII/payments, runs in shared infrastructure, or implements a security primitive.

**Stay single-agent when:** Quick check on a known-low-risk diff (still better to use an evaluator-optimizer than nothing).

**Anti-patterns:**
- Red and blue see each other's full reasoning — they collude.
- No executable artifact requirement on red — produces theoretical "could be vulnerable" instead of "here's the exploit."
- One agent playing both roles — the optimization gradient is incoherent.

**Concrete unfold:** New auth endpoint. Red agent enumerates threat model and tries to produce 5 concrete attack scripts. Blue agent reviews each, hardens code or proves infeasible. Purple agent tracks which threats are mitigated, which require runtime controls, which are accepted risks. Output is a STRIDE-style table with concrete repros.

Why it wins: security is fundamentally an asymmetric game — the defender must close every hole; the attacker needs one. Independent agents with opposing objectives surface the gaps a single "balanced" agent rationalizes away. Co-RedTeam decomposes into discovery + exploitation stages with execution-grounded iterative reasoning. BlueCodeAgent shows that *automated* red-teaming bootstraps a stronger blue-teamer ([Co-RedTeam](https://arxiv.org/pdf/2602.02164); [BlueCodeAgent (Microsoft Research)](https://www.microsoft.com/en-us/research/blog/bluecodeagent-a-blue-teaming-agent-enabled-by-automated-red-teaming-for-codegen-ai/); [DeepTeam](https://github.com/confident-ai/deepteam); [Rethinking Cybersecurity Red and Blue Teaming in the Age of LLMs](https://arxiv.org/pdf/2506.13434)).

## 10. Planning / architecture design

**Pattern:** Single planner + critic for most cases. Debate (3 agents) for genuinely contested decisions with no obvious winner.

**Typical N:** Planner + critic = 2. Debate = 3 (more participants → diminishing returns and longer rounds).

**Trigger to escalate to debate:** The decision has multiple defensible answers and the team genuinely disagrees; OR the cost of being wrong is high enough to justify 5–10x tokens.

**Stay single-planner when:** The constraints actually narrow the answer (most of the time); OR the decision is reversible cheaply.

**Anti-patterns:**
- Debate without a forced terminating step — rounds drag, tokens explode, no decision.
- Critic with no rubric — produces vague "have you considered…" rather than concrete pushback.
- Planner + critic where the planner sees the critic's identity and starts pre-empting — anchoring.

**Concrete unfold:** "Should we move from REST to gRPC for the internal API?" Single planner drafts a decision doc with options, tradeoffs, recommendation. Critic challenges with edge cases, deployment cost, observability gaps. Planner revises, final doc. For higher-stakes: 3 agents each independently propose; round 2 each critiques the others; round 3 each updates final answer; orchestrator picks the most-supported with rationale.

Why it wins: a coherent design needs a single point of view; debate with too many voices produces wishy-washy compromises. The critic catches blind spots without diluting authorship. For decisions with real tradeoffs (microservices vs monolith, SQL vs NoSQL), multi-agent debate (Du et al.) genuinely improves factuality and reasoning by forcing each agent to confront the others' arguments — but ICLR 2025 analysis shows MAD often *fails* to outperform single-agent + self-consistency at equivalent token budgets, so use it sparingly ([Du et al. — Multiagent Debate](https://arxiv.org/abs/2305.14325); [ICLR 2025 — MAD Performance Analysis](https://d2jud02ci9yv69.cloudfront.net/2025-04-28-mad-159/blog/mad/); [Anthropic — Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)).

## 11. Documentation writing

**Pattern:** Researcher (extracts from code) + writer (single voice) + editor (consistency pass). For very long docs, section-parallel writers + editor, but only if the editor is strong enough to enforce voice.

**Typical N:** Researcher + writer + editor = 3. For long docs: 1 researcher, N section writers (≤5), 1 editor.

**Trigger to escalate to section-parallel writers:** Doc is ≥10 sections AND each section has clear scope.

**Stay single-writer when:** Anything under 2000 words; or the doc is narrative (tutorial, explainer) where flow matters more than coverage.

**Anti-patterns:**
- Multiple parallel writers without a strong style guide passed as context — outputs read like Frankenstein.
- Researcher doing the writing — code-grounded prose tends to be dry and listy.
- No editor pass — duplication, contradictions, terminology drift.

**Concrete unfold:** API docs project. Researcher inventories all public APIs, generates per-endpoint structured facts. Writer turns the structured facts into prose using a style guide. Editor reads end-to-end, fixes voice and links. For a 50-page reference: researcher produces inventory, 5 writers each take 10 endpoints (with the style guide), editor stitches and rewrites intros.

Why it wins: voice consistency is the dominant quality signal in docs and it suffers when multiple writers contribute. Researcher/writer split helps because docs need both code-grounded extraction and prose craft — different optima ([Anthropic — Building Effective Agents](https://www.anthropic.com/research/building-effective-agents); [MetaGPT — role-based document generation](https://arxiv.org/abs/2308.00352)).

## 12. Data extraction / scraping at scale

**Pattern:** Embarrassingly parallel map-reduce. N workers process N pages independently; reducer aggregates and dedupes.

**Typical N:** Bounded by rate limits and budget. 10s–1000s of workers in parallel.

**Trigger to escalate:** Document count >5 AND extraction schema is consistent.

**Stay single-agent when:** A handful of docs and you want one coherent narrative summary, not a structured extraction.

**Anti-patterns:**
- Reducer that re-reads the raw documents — defeats the point. Workers should produce structured output the reducer can merge without re-reading.
- Workers with wide context windows reading multiple docs each — loses the parallelism dividend; lower per-call quality.
- No schema validation per worker — garbage merges into garbage.

**Concrete unfold:** "Extract company name, valuation, and lead investor from 500 funding announcements." Schema written once. 500 workers (small model, tight prompt) extract per article. Each output validated against schema. Reducer agent dedupes by company, normalizes investor names, produces final table.

Why it wins: per-document extraction is the textbook independent task. No coordination needed during the map phase. Map-reduce summarization research shows hierarchical merge can match full-context processing at substantially lower cost. Workers can use small/fast models for extraction; reducer can use a stronger model for normalization ([LLM×MapReduce (ACL 2025)](https://aclanthology.org/2025.acl-long.1341.pdf); [NexusSum — Hierarchical LLM Agents for Long-Form Summarization](https://arxiv.org/html/2505.24575v1); [Google Cloud — Map-reduce for document workflows](https://cloud.google.com/blog/products/ai-machine-learning/long-document-summarization-with-workflows-and-gemini-models)).

## 13. Evaluation / benchmarking / scoring

**Pattern:** Panel of judges (PoLL) — N diverse models score independently, aggregate. For tight budgets, single judge with rubric. For high-stakes, debate among judges.

**Typical N:** Panel of 3–5 judges from different model families. For statistical reliability, 3 is the floor.

**Trigger to escalate (single → panel):** Judge bias would skew results (using GPT-4 to judge GPT-4 outputs); decisions have downstream impact (ranking models, gating releases); inter-rater reliability matters.

**Stay single-judge when:** Quick spot-check, internal triage, judging is just a sanity gate.

**Anti-patterns:**
- Same model family for all judges — defeats bias-cancellation.
- Letting judges see each other's scores before deciding — anchoring.
- Pairwise comparison without randomized order — positional bias.

**Concrete unfold:** Eval new prompt against 200 examples. 3 judges (Claude, GPT, Gemini) each score independently with the same rubric. Aggregator computes per-example agreement, reports majority-vote score and disagreement rate. High-disagreement examples flagged for human review.

Why it wins: single LLM judges are biased (positional, length, self-preference). Verga et al. showed a panel of *diverse* models (different families) correlates better with human judgment than a single GPT-4 judge, at ~7x lower cost. CyclicJudge minimizes variance through round-robin assignment. Multi-judge variance reduction is one of the better-replicated multi-agent results ([Verga et al. — Replacing Judges with Juries (PoLL)](https://arxiv.org/html/2404.18796v1); [CyclicJudge](https://arxiv.org/html/2603.01865); [LLMs-as-Judges Survey](https://arxiv.org/html/2412.05579v2)).

## 14. Migration tasks

**Pattern:** Pipeline (planner → per-file parallel executors → environment validator) with deterministic codemod for mechanical parts. Essentially #5 (refactoring) plus an environment-in-the-loop.

**Typical N:** 1 planner, 1 codemod runner (deterministic, not an LLM), N=10–100 per-file LLM workers, 1 test/integration validator.

**Trigger to escalate:** ≥20 files affected, OR semantic changes per file are non-trivial, OR a test suite exists for validation.

**Stay single-agent when:** Small repo (<10 files), or migration is purely mechanical (just run the codemod).

**Anti-patterns:**
- All-LLM with no codemod — wastes tokens and produces inconsistent mechanical changes.
- No environment validator — agents claim success based on syntax alone.
- Per-file workers with no shared style guide — diff is stylistically inconsistent.

**Concrete unfold:** Upgrade Airflow 2 → 3. Planner reads release notes, classifies changes into "codemod-able" and "needs LLM." Codemod handles imports, deprecated kwargs. 50 parallel workers tackle the semantically-changed files using upgrade docs. Environment agent runs `airflow dags list-import-errors` after each file. Validator runs full test suite. Flagged files get a serial second pass.

Why it wins: upgrades have two distinct workloads — mechanical changes (deterministic, codemodable) and semantic changes (need an LLM). The win is splitting them: codemod handles imports/syntax shifts at zero cost; LLM agents handle semantic rewrites file-by-file in parallel. The Environment-in-the-Loop paper formalizes Migration / Environment / Testsuite agents; LinkedIn migrated 75% of files automatically in 4 hours using per-file parallel pipelines ([Environment-in-the-Loop](https://arxiv.org/html/2602.09944v1); [LinkedIn — Framework Migration agents](https://www.zenml.io/llmops-database/ai-agents-for-accelerating-model-development-and-framework-migration); [Migrating Code At Scale With LLMs At Google](https://arxiv.org/html/2504.09691v1); [Codemod](https://codemod.com/)).

## 15. Open-ended creative writing

**Pattern:** Single agent for short-to-medium pieces. For long-form (novellas, novels), outline-agent + writer + critic with strong shared context. Avoid wide role-splits unless you have a strong editor downstream.

**Typical N:** 1 for short. For long: 1 outliner + 1 writer (sequential per chapter) + 1 critic = 3. Avoid >3 for creative work.

**Trigger to escalate:** Piece >10k words AND structure/coherence is failing in single-agent attempts.

**Trigger to add critic:** Piece is for publication; OR specific quality dimension matters (humor, pacing, character consistency) and a specialist prompt can target it.

**Stay single-agent when:** Default for anything under novella length.

**Anti-patterns:**
- Multiple parallel writers on adjacent scenes — voice drift, character drift.
- Critic that demands "more conflict" or other generic notes — produces homogenized output.
- Role-split (CEO/CTO-style) for fiction — projects org-chart energy onto the prose.

**Concrete unfold:** Short story → single agent. Novella → outliner produces beat sheet, writer agent goes scene-by-scene with outline + last-scene summary in context, critic reads full draft for character/plot consistency, writer revises flagged scenes.

Why it wins: voice and authorial intent are hard to maintain across multiple writers — they read as committee work. Recent multi-agent systems (Agents' Room, Co-DIRECT, StoryWriter) show coherence wins for *long* narratives where a single agent's context cannot hold the whole story. For shorter creative work, multi-agent dilutes voice without helping. The cleanest win is **outline-then-write** ([Agents' Room](https://openreview.net/forum?id=HfWcFs7XLR); [Co-DIRECT](https://www.sciencedirect.com/science/article/abs/pii/S0957417425041867); [StoryWriter](https://arxiv.org/abs/2506.16445)).

## 16. Translation / localization

**Pattern:** Pipeline: translator → reviewer → editor. Per-language single agent for the translation step. TransAgents-style role split for high-quality literary work.

**Typical N:** 3 (translator, reviewer, editor) for standard work; 5 for literary. Per language, run in parallel — across languages is embarrassingly parallel.

**Trigger to use full pipeline:** Published content, technical docs with terminology consistency requirements, literary work.

**Stay single-agent when:** Chat/casual translation.

**Anti-patterns:**
- Same agent doing translate → review — pretends to critique its own work.
- No glossary passed through the pipeline — terminology drifts.
- Parallel chunk translation without an editor pass — sentence-boundary discontinuities.

**Concrete unfold:** EN → JA marketing copy. Translator produces draft. Reviewer (different prompt, "act as a senior editor") flags 8 issues. Editor (third agent) integrates fixes and adapts cultural references. Proofreader does final pass. For 10 languages: run this pipeline 10x in parallel, one per language.

Why it wins: translation has natural sequential stages (initial translation → accuracy review → cultural adaptation → proofread) that map cleanly onto a pipeline. TransAgents' literary translation pipeline (translator → junior editor → senior editor → localization specialist → proofreader) outperforms single-agent translation on human evaluation. Within a single language, parallelism does not help — translation is inherently coherent at the document level ([TransAgents](https://www.deeplearning.ai/the-batch/transagents-a-system-that-boosts-literary-translation-with-a-multi-agent-workflow/); [Andrew Ng — translation-agent](https://github.com/andrewyng/translation-agent)).

## 17. Decision-making with tradeoffs

**Pattern:** Multi-agent debate (3 agents). Each independently proposes a position with rationale, then critiques the others, then revises. Orchestrator extracts the decision and dissents.

**Typical N:** 3 (sweet spot — 2 produces an argument, 4+ produces noise). 2–3 rounds.

**Trigger to use debate:** Decision is non-reversible AND has multiple defensible answers AND stakes justify 5–10x token spend.

**Stay single-agent when:** Constraints actually narrow the answer; decision is cheap to reverse.

**Anti-patterns:**
- Open-ended debate with no terminating round — agents converge on consensus prematurely or never converge.
- All agents same model + same prompt → groupthink.
- Orchestrator picks a "winner" rather than surfacing the tradeoff structure — defeats the purpose.

**Concrete unfold:** "Postgres vs DynamoDB for the new service?" Three agents each get the requirements doc with different framing prompts (cost-optimizer, scale-first, ops-simplicity). Each proposes a recommendation with reasoning. Round 2 each critiques the others' weakest claim. Round 3 final positions. Orchestrator outputs a decision matrix with the dissents intact and a final recommendation tied to which constraints dominate.

Why it wins: tradeoff decisions have no objectively right answer — they depend on values and constraints. A single agent picks the most-defensible-looking option and rationalizes; debate forces explicit confrontation of opposing values. Du et al. demonstrated debate improves factuality and reasoning, particularly when answers are non-obvious. ICLR 2025 caveat: at equal token budgets, MAD often loses to single-agent + self-consistency, so reserve it for *genuinely contested* decisions ([Du et al. — Multiagent Debate](https://arxiv.org/abs/2305.14325); [ICLR 2025 — MAD analysis](https://d2jud02ci9yv69.cloudfront.net/2025-04-28-mad-159/blog/mad/)).

## 18. Synthesis of many documents

**Pattern:** Map-reduce / hierarchical merge. Workers summarize per-document; reducer merges hierarchically.

**Typical N:** N workers (one per doc, or one per chunk for long docs); log_k(N) reduce levels with branching factor k=5–10.

**Trigger to escalate to map-reduce:** Total content exceeds context window; OR independent summaries are useful intermediate outputs.

**Stay single-agent when:** Everything fits in context AND coherent narrative output matters more than coverage (single-pass produces better flow).

**Anti-patterns:**
- Reducer that produces a list of summaries instead of a synthesis — merge ≠ concatenate.
- Workers with too-loose prompts → summaries are inconsistent in granularity → reducer cannot merge.
- Single-level reduce on huge N → reducer's context blows up; use hierarchy.

**Concrete unfold:** "Synthesize findings from 200 customer interviews." 200 workers extract themes per interview. Level-1 reducers merge groups of 20 into theme clusters (10 reducers). Level-2 reducer merges 10 cluster summaries into final report. Optional citation pass linking themes back to original quotes.

Why it wins: same as #12 (extraction) but with prose synthesis at the merge stage. NexusSum and LLM×MapReduce show hierarchical merge matches full-context processing at substantially lower cost. The hierarchy depth scales with input size — 100 docs might need 2 levels; 10000 needs 4–5 ([LLM×MapReduce](https://aclanthology.org/2025.acl-long.1341.pdf); [NexusSum](https://arxiv.org/html/2505.24575v1); [Anthropic — multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system)).

## 19. Long-horizon agent tasks

**Pattern:** Orchestrator + on-demand subagents for clearly bounded sub-problems. Single-threaded writes. Subagents are for **context isolation, not parallelism.** This is the Claude Code shape.

**Typical N:** 1 main agent + on-demand subagents (typically 0–5 active at once). Total subagents over the lifetime of a long task: dozens.

**Trigger to spawn a subagent:** Subtask requires reading >5 files OR running >3 exploratory commands OR producing an output the main agent does not need to think about, just consume.

**Stay inline when:** Subtask is short and the result *is* the next step (do not pay round-trip cost for trivial work).

**Anti-patterns:**
- Spawning a subagent for every action — round-trip overhead.
- Multiple writer subagents in the same workspace → conflicts.
- Subagents that return raw context dumps to the orchestrator — defeats context isolation; distill before returning.
- Forking into independent agents that lose the project plan and start over.

**Concrete unfold:** "Build a CLI for managing my notes." Main agent designs the architecture, picks the structure. Spawns explorer subagent to find similar projects on disk. Main agent writes scaffolding. Spawns subagent to figure out how to use the database library (returns 200-token summary). Main agent implements features one-by-one. Spawns test-writer subagent for the tricky parts. Spawns reviewer subagent before committing. Throughout: only the main agent writes code; subagents do bounded reads and return summaries.

Why it wins: the primary motivation is **context window management**, not throughput. The orchestrator cannot hold the full codebase, the full conversation, the test outputs, and the design docs. Subagents do bounded work and return distilled outputs. This is exactly the Cognition-Anthropic synthesis: many readers/explorers, single writer ([Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system); [Cognition — Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents); [Subagents in VS Code](https://code.visualstudio.com/docs/copilot/agents/subagents); [Cursor 2.0 — agent-first architecture](https://www.digitalapplied.com/blog/cursor-2-0-agent-first-architecture-guide)).

## 20. One-shot lookup / question answering

**Pattern:** Single agent. Often no agent at all — a single prompt is enough.

**Typical N:** 1.

**Trigger to escalate:** Question requires synthesizing ≥3 sources OR involves multi-step reasoning across tools (then it is a category #1 or #19 task, not lookup).

**Stay single-agent when:** Default for any one-shot question.

**Anti-patterns:**
- Spawning a research subagent for "what's today's date?".
- Adding a critic to a factual lookup that is either right or wrong.

**Concrete unfold:** "What's the current Anthropic API rate limit for tier 2?" Single agent, one search, done.

Why it wins: round-trip overhead of any orchestration dwarfs the work. GAIA Level-1 tasks (the "easy" tier) require fewer than 5 steps and minimal tool use, and single agents handle them well. Multi-agent for one-shot lookups is the most common over-engineering in this space ([GAIA: A Benchmark for General AI Assistants](https://arxiv.org/abs/2311.12983)).

## Summary lookup table

| # | Task signature | Recommended pattern | Typical N | Key risk |
|---|---|---|---|---|
| 1 | Open-ended research | Orchestrator + parallel research workers + synthesizer | 3–5 workers/round | Token spend (~15x single-agent) |
| 2 | Codebase exploration | Single Explore subagent (delegated) | 1 (or 2–4 cross-module) | Subagent overhead vs trivial query |
| 3 | Small code feature | Single agent | 1 (+1 critic optional) | Over-engineering |
| 4 | Large multi-file feature | Planner → 1 implementer → tester (writes single-threaded) | 3 sequential | Parallel writers → merge conflicts |
| 5 | Refactor across many files | Planner → parallel per-file workers → integration verifier | 5–50 workers | Style/abstraction inconsistency |
| 6 | Bug debugging | Single agent + reflexion + (critic for hard bugs) | 1–3 | Parallel debuggers diverge |
| 7 | Code review | Parallel checklist specialists + verification | 3–7 specialists | False positives without verification |
| 8 | Test generation | Separate test-writer (decoupled from implementer) | 1–2 | Tests overfit to implementation |
| 9 | Security review | Red team / blue team / purple arbiter | 3 | Single agent rationalizes risks |
| 10 | Architecture planning | Single planner + critic (debate for hard tradeoffs) | 2–3 | Debate dilutes coherent design |
| 11 | Documentation | Researcher + writer + editor | 3 | Voice drift across writers |
| 12 | Data extraction at scale | Embarrassingly parallel map-reduce | 10s–1000s | Schema inconsistency |
| 13 | Eval / scoring | Panel of judges (PoLL), diverse models | 3–5 | Single-judge bias |
| 14 | Migration / upgrade | Codemod + per-file parallel + env validator | 10–100 workers | Skipping codemod, no validator |
| 15 | Creative writing | Single agent (long: outliner + writer + critic) | 1–3 | Multi-agent dilutes voice |
| 16 | Translation | Translator → reviewer → editor pipeline | 3–5 | Same agent self-reviewing |
| 17 | Tradeoff decisions | Multi-agent debate | 3 / 2–3 rounds | Token spend without payoff |
| 18 | Document synthesis | Hierarchical map-reduce | log_k(N) levels | Reducer concatenates instead of synthesizing |
| 19 | Long-horizon "build X" | Orchestrator + on-demand read subagents | 1 main + N transient | Multiple writers; subagent over-spawning |
| 20 | One-shot lookup | Single agent (or just a prompt) | 1 | Over-orchestration |

## Cross-cutting heuristics

These rules generalize across task types. Use them to break ties when multiple patterns seem plausible.

1. **Verifiability gates fan-out.** If sub-outputs cannot be independently verified (research findings, code changes), parallelism is dangerous. If they can (per-file refactors, per-doc extractions, per-judge scores), parallelism is cheap. `parallel ≈ safe ⇔ outputs are independently checkable`.

2. **Read parallel, write serial.** Cognition's hardest-won lesson. Multiple readers/critics/explorers compose cleanly; multiple writers conflict. When in doubt about whether to parallelize, ask: *do they produce text that gets read, or actions that change state?* Parallelize the readers; serialize the writers.

3. **Coherence gates against role-split.** Tasks where a single voice/style/design matters (creative writing, architecture design, short docs) suffer from role-splitting. Tasks where coverage matters (research, code review, eval) benefit. `role-split ≈ safe ⇔ output is structured/checklisty rather than narrative`.

4. **Token-spend ratio: always ~15x for fan-out.** Anthropic measured this on their research system. A 15x token premium is justified when (a) the task is high-value, (b) wall-clock matters, (c) parallel exploration genuinely covers more ground. Not justified for casual queries.

5. **Token usage explains 80% of performance variance** (Anthropic). Before adding agents, ask: would I get the same lift by giving the existing agent more turns / more thinking budget / more context? Often yes.

6. **Debate underperforms self-consistency at equal token budget** (ICLR 2025). Reserve debate for genuinely contested decisions; use self-consistency (sample N times, vote) for verifiable answers.

7. **Critics should be implementation-blind** (AgentDevel). A critic that sees the generator's reasoning chain becomes sycophantic. Show the critic only the artifact, the rubric, and the execution trace — never the producer's chain-of-thought.

8. **Diversify judge models, do not just count them** (Verga et al.). N judges from the same family ≈ 1 judge for variance reduction. The whole point of PoLL is decorrelating biases.

9. **Force tight structured returns from subagents.** The orchestrator's context is the scarce resource. Workers should return ≤500-token structured summaries, not raw evidence. This is what makes the orchestrator-workers pattern actually beat single-agent — context isolation, not parallelism per se.

10. **Verification is mandatory for fan-out outputs.** Parallel agents hallucinate independently; without a verification step that re-grounds findings against source-of-truth, you are aggregating noise. Claude Code's review and Calimero's reviewer both include this step explicitly.

11. **Codemod what you can, LLM what you must.** Migration and refactor tasks waste enormous tokens on mechanical transformations LLMs do poorly. Always extract the deterministic core into a codemod; reserve LLM agents for the semantic remainder.

12. **Worktree isolation > clever merging.** When you must run parallel writers (large multi-file features, parallel migrations), give each their own Git worktree. Cursor 2.0 and Composio Agent Orchestrator both adopted this pattern — it converts a coordination problem into an integration problem, which is much easier.

## Escalation ladder

Climb the ladder one rung at a time. **Default to the lowest rung.** Each rung up adds tokens, latency, and coordination risk; only climb when the lower rung demonstrably cannot deliver.

**Rung 0 — No agent.** Just a single LLM prompt, no tools, no loop. Use for one-shot text transformations and lookups.
- *Climb when:* The task requires tool use OR multi-step reasoning OR external information.

**Rung 1 — Single agent (linear).** One agent, one context, sequential tool calls. The Cognition baseline.
- *Climb when:* The agent fails at the task, AND failure is in a way a critic could catch (wrong answers, missed cases) — not just lack of capability.

**Rung 2 — Single agent + critic / evaluator-optimizer.** One generator, one critic, refinement loop.
- *Climb when:* Critic catches issues but the agent has too much to keep in context; OR exploration would benefit from parallelism (read-only); OR the task naturally splits into independent verifiable subtasks.

**Rung 3 — Small role split (2–3 specialized agents).** Pipeline (translate → review → edit), red/blue, planner+critic, generator+tester, researcher+writer+editor.
- *Climb when:* The task has ≥4 clearly independent specialist roles; OR you need dynamic decomposition (subtasks are not known upfront); OR throughput requires real parallelism across many independent items.

**Rung 4 — Orchestrator + workers (3–10 agents).** Lead agent dynamically decomposes, fans out to workers (each context-isolated), synthesizes. The Anthropic Research shape.
- *Climb when:* You are processing large batches (100s–1000s of items); OR you need a panel of diverse models (eval); OR you have a long-horizon project with many distinct phases requiring different expertise.

**Rung 5 — Full multi-agent system.** Persistent specialized agents, complex routing, often cross-model. MetaGPT/ChatDev-style SOPs.
- *Caveat:* Most teams should never reach this rung. Cognition operates production multi-agent systems but explicitly built up to them after extensive failure modes on simpler shapes. The 15x token cost is real, debugging is genuinely hard, and the wins disappear without strict context-engineering discipline.

## Decision procedure

Given a task, run through these gates in order:

1. **Classify the task** against the 20 types above (use the task signature in the lookup table).
2. **Apply the per-task recommended pattern** as your starting point.
3. **Sanity-check against the cross-cutting heuristics** — especially "read parallel, write serial" and "verifiability gates fan-out." If the recommendation violates these for your specific case, downshift.
4. **Pick your rung on the escalation ladder** — start at the lowest plausible rung, not the highest.
5. **State your N explicitly and the trigger that would justify climbing further** — this prevents unbounded fan-out and makes your reasoning auditable.

The goal of the playbook is not to maximize multi-agent usage. It is to **stop reaching for multi-agent when single-agent would do**, and to **reach for it confidently when the task genuinely needs it**.
