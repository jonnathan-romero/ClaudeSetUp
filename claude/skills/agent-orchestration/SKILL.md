---
name: agent-orchestration
description: Decides when and how to use multi-agent orchestration in Claude Code — single agent vs sub-agents, team size (1/2/3/5/10), topology (orchestrator-worker, role triad, debate, hierarchical), per-agent tool scoping, termination and cost bounds. ALWAYS trigger when the user mentions sub-agent, subagent, agent team, multi-agent, fan out, parallel agents, orchestrator, debate agents, red team, blue team, evaluator-optimizer, critic loop, role split, builder/tester/reviewer, agent crew, agent swarm, MoA, self-consistency, or asks "should I spawn agents", "how many agents", "split this task", "have agents review each other", "agents in parallel". ALWAYS trigger when about to invoke the Agent/Task tool more than once for related work, when designing a `.claude/agents/` subagent, when choosing fan-out vs sequential decomposition, or when recommending CrewAI, LangGraph, AutoGen, OpenAI Agents SDK, MetaGPT, or ChatDev. Do NOT trigger for a single one-shot Agent/Task call where only the prompt content is in question.
---

# Agent Orchestration

Decides how to use multi-agent patterns in Claude Code. The skill's central claim is unfashionable: **single-agent is the default, multi-agent is exceptional**. Anthropic's own multi-agent research system uses ~15× more tokens than chat, and Anthropic itself admits "most coding tasks involve fewer truly parallelizable tasks than research." Reach for multi-agent only when the task shape genuinely calls for it.

## When this fires

This skill is the right thing to consult whenever the conversation involves an orchestration *decision*: how many agents, what topology, what hand-off shape, what tool scopes, when to stop. It is **not** for executing a single sub-agent call where the design is already settled — go ahead and call the Agent tool in that case.

## The single decision: spawn or stay single?

Default: **single agent**. The burden of proof is on multi-agent. Read the green-light criteria; if any apply, proceed to pattern selection. If none apply, stay single.

**Green-light triggers (any one is sufficient to consider multi-agent):**

1. Task decomposes into ≥3 *independent* sub-questions whose answers aggregate, not merge into a single coherent artifact.
2. Exploration would produce ≥10× more tokens than the answer needs (context isolation, even serial — see Mode B).
3. Sub-tasks need genuinely different tool surfaces, model tiers, or trust scopes.
4. Wall-clock matters AND the work is genuinely parallel (synthesizer cost won't dominate).
5. Task is security-shaped or has multiple plausible answers and benefits from adversarial pressure (Mode E).

**Hard STOP signals (any one defaults you back to single agent):**

1. **One coherent artifact** requiring a single voice or architecture (essay, single-file fix, one design doc, refactor of one module). Cognition's "Flappy Bird" failure: parallel agents make incompatible implicit decisions.
2. **Tight inter-step dependencies** — one sub-agent's output shape depends on another's choices.
3. **Same-model "adversarial"** review (correlated blind spots produce sycophancy, not signal).
4. **Deterministic work** (parse JSON, run a script, sort, validate schema) — that's a tool, not an agent.
5. **Cost/latency envelope can't absorb ~15× tokens** or N× wall-clock for the task's actual value.
6. **Coding/refactor with shared mutable state** — Anthropic's own multi-agent admission: research-shaped wins, coding-shaped doesn't.
7. **You can't define what "done" looks like** for each sub-agent and the synthesis step in checkable terms.

If any STOP fires, stay single (consider a critic pass per Mode A.2). If only green-lights fire, pick the pattern below.

Full checklist with every diagnostic: [references/decision-tree.md](references/decision-tree.md).

## Pick the pattern

| Task signature | Mode | Typical N | Key risk |
|---|---|---|---|
| Open-ended research, breadth-first across many sources | **C** orchestrator + parallel workers | 3–5 | over-spawning; source-quality bias |
| Verbose exploration where the parent only needs the answer | **B** sub-agent for context isolation | 1 (serial OK) | summary loses load-bearing citations |
| Build a feature with distinct deliverables (code + tests + review) | **D** role split / triad | 2–3 | role inflation; reviewer rubber-stamping |
| Single-file fix, single-module refactor, isolated bug | **A** single agent (+critic if hard) | 1–2 | parallel debuggers diverge |
| Architecture decision with real tradeoffs | **E.1** debate, heterogeneous models | 3 (×2–4 rounds) | same-model = sycophantic convergence |
| Security review / threat-model / red-team | **E.2** red-blue + judge | 2–3 | red lacks executable proof |
| Generator + evaluator with external rubric (test runner, schema) | **E.3** critic loop | 2 (≤3 iter) | infinite polishing; fix-induced regressions |
| Map-reduce / sectioning over many independent items | **C** orchestrator + parallel workers | N=items, cap concurrency 4–6 | synthesizer concatenates instead of synthesizing |
| Long-horizon "build me X", multi-session, persistent state | **F** agent team OR single + on-demand readers | 1 main + N transient | parallel writers cause Flappy Bird |
| One-shot lookup, trivial task, lone fact | **A** single agent (no spawn) | 1 | over-orchestration |

Per-task-family playbook with 20 task signatures: [references/task-playbook.md](references/task-playbook.md).

---

## Mode A — Single agent (the default)

**When:** one coherent task, fits comfortably in context, no genuine parallelism gain. Most coding work, most chat, most one-shot questions.

**Steps:**
1. Just do the task in the current session. No `Agent`/`Task` tool calls.
2. **A.2 — Critic upgrade:** if the artifact needs an outside view (security-adjacent code, plan validation, draft refinement against a rubric):
   - Add a critic pass at the end against a written checklist or external verifier.
   - The critic must use **a different model family OR an external tool the generator lacks** (test runner, type checker, schema validator). Same-model "review my work" produces sycophancy, not signal — see [references/adversarial.md](references/adversarial.md).
   - Iteration cap: ≤3 rounds. Stop on PASS, no-diff, or regression.

**Upgrade trigger A → B:** you find yourself wanting to read >5 files OR run >3 exploratory tool chains OR ingest a large log/spec to extract one fact. That's context-isolation territory.

**Upgrade trigger A → D:** the task naturally produces ≥2 distinct artifacts (code + tests + review) where each benefits from a different perspective.

---

## Mode B — Sub-agent for context isolation (the under-used reason)

**When:** exploration that would pollute parent context for an answer the parent doesn't need raw evidence of.

This is the most-missed reason to spawn. Even *one serial* sub-agent is the right call when the work-to-answer ratio is high. The trigger is not "can I parallelize?" but **"will this work pollute my context?"** — a separate axis from parallelism.

**Quantitative triggers (any one):**
- Will read ≥5 files I won't reference again
- Tool output will dump ≥5K tokens (full test runs, log scrapes, doc fetches, large file reads)
- ≥3 exploratory tool chains for one sub-question
- Parent context already ≥50% full (lost-in-middle and context-rot accelerate non-linearly)
- Investigation depth is unknown ahead of time

**Steps:**
1. Spawn one sub-agent. For codebase exploration, use the built-in `Explore` (read-only, Haiku).
2. Apply the sub-agent design contract (below).
3. Force structured summary output with citations; verify no load-bearing claim is uncited.

Full quantitative triggers and recipes: [references/context-isolation.md](references/context-isolation.md).

---

## Mode C — Orchestrator + parallel workers

**When:** task naturally decomposes into N≥3 independent sub-questions whose results merely aggregate (not merge into a coherent artifact).

Canonical examples: research across many sources, comparison across many entities, map-reduce over data shards, parallel checklist code review (security/perf/style/correctness), data extraction at scale.

**Architecture:**
- **Lead** plans, decomposes, dispatches, synthesizes; uses the strong model.
- **Workers** do bounded execution; cheaper model is fine if outputs are verifiable.
- **Synthesis** is its own step — never just "stitch outputs."
- Optional **CitationAgent** runs after research to verify claims trace to sources (Anthropic's pattern).

**Sweet-spot N (per Anthropic's published guidance):**
- Simple fact-finding: 1 agent, 3–10 tool calls
- Direct comparison: 2–4 sub-agents, 10–15 tool calls each
- Complex research: 5–10 sub-agents
- More than 10 from one orchestrator: split into hierarchical sub-supervisors (Mode F)

**Cost reality:** this pattern uses ~15× more tokens than a single chat (Anthropic measured; "token usage explains 80% of variance" on their browsing benchmark). They also measured 90.2% accuracy improvement on their internal research eval — but only on tasks that match this shape. Don't apply to coding or shared-context work.

**Common failure modes:** over-spawning ("50 sub-agents for trivial queries"), duplicate work from vague briefs, source-quality bias toward SEO content, synthesis bottleneck when N×summary exceeds orchestrator context. See [references/anti-patterns.md](references/anti-patterns.md).

Deeper: [references/topologies.md](references/topologies.md), [references/team-size.md](references/team-size.md).

---

## Mode D — Role split / triad

**When:** task naturally produces ≥2 distinct artifacts (code + tests, plan + execution, draft + review) that benefit from different perspectives, with each role's deliverable being unambiguous.

**Canonical triads:**
- **Builder + tester + reviewer** — three outputs, no overlap. Reviewer in clean context (no writer reasoning visible) — Cognition's Devin Review pattern catches ~2 bugs/PR by working from the diff alone.
- **Researcher + writer + editor** — sequential, three stages.
- **Planner + executor + verifier** — planner produces plan, executor walks it, verifier checks against the plan.
- **Red + blue + judge** — 2 if no verdict, 3 with judge (see Mode E.2).

**Where role wins are real vs theater:**
- Real wins come from (a) context isolation per role, (b) distinct artifact handoff that gets scrutinized, (c) ideally different model family for adversarial roles.
- "Persona-only" splits (same model, same context, just different system prompts) are theater on objective tasks. Persona prompts do not reliably improve LLM performance — see [references/role-specialization.md](references/role-specialization.md).

**Sweet spot:** 3 roles. Past 5 roles you're paying coordination tax for diminishing returns (MetaGPT's 5 roles and ChatDev's 7 roles produce $10+/HumanEval-task overhead with marginal quality gain over 3-role designs).

---

## Mode E — Adversarial (debate / red-blue / critic loop)

**When:** task has multiple plausible answers, security-adjacent, or needs reasoning verification with an external check.

### E.1 — Debate

Use for genuinely contested decisions (architecture choice, ethical judgment, multi-hop reasoning with branches).

- **N:** 3 agents × 2–4 rounds.
- Requires **heterogeneous models** OR **forced-asymmetric positions** to avoid sycophantic convergence. Same-model debate often *degrades* accuracy by 1.2–12.0 pp on CommonSenseQA per "Talk Isn't Always Cheap" (2025).
- **Always compare against a single-agent + self-consistency baseline.** "Stop Overvaluing Multi-Agent Debate" (2025) shows MAD frequently loses to CoT + Self-Consistency at lower cost. Only ship debate if it wins.
- **Never stop on agreement alone** — agreement is the failure mode, not the success criterion.

### E.2 — Red team / blue team

Use for security review, jailbreak testing, prompt-injection probing, threat modeling.

- **N:** 2 (no judge) or 3 (with judge).
- The asymmetric incentive (red needs ONE failure, blue defends all paths) is what makes it work; symmetric "balanced reviewer" loses this property.
- Require red to produce **executable proofs** (concrete attack scripts), not theoretical "could be vulnerable" lists.
- Red and blue should not see each other's full reasoning — only the artifact and the rubric. Otherwise they collude.

### E.3 — Critic loop / evaluator-optimizer

Use generator + critic against an **external rubric** (test runner, type checker, schema validator, factuality DB).

- **N:** 2 agents, ≤3 iterations.
- Without an external signal, self-correction *degrades* reasoning (Huang et al. 2023; Stechly et al. 2024). Same-model self-critique is theater on pure-reasoning tasks.
- Stop on PASS, no-diff, regression (roll back), or iteration cap.
- Track correct→incorrect flips. Roll back on regression.

**Hard rules across all adversarial modes:**
- Never same-model adversarial without an external verifier.
- Always cap iterations explicitly.
- LLM judges have position bias and self-preference — randomize position OR use a different-family judge OR use a Panel of LLM Judges (≥3 from different families).

Deeper: [references/adversarial.md](references/adversarial.md).

---

## Mode F — Hierarchical / agent teams

**When:** task spans multiple sessions, needs supervisor-of-supervisors, or runs will outlive a code/prompt deploy.

- Top-level supervisor routes to sub-team supervisors, each managing 3–5 workers.
- In Claude Code, **sub-agents within a session cannot spawn sub-agents** (single-level fan-out is enforced). Multi-level coordination uses the separate `agent teams` primitive across sessions.
- Reach for this when (a) a single orchestrator's context fills with sub-agent results before synthesis, (b) sub-tasks need genuinely different sub-team specializations, (c) long-horizon project with persistent state across runs, (d) you need rainbow deployments (sessions outlive code deploys).

**Anti-pattern:** jumping to hierarchical when single-level fan-out (Mode C) suffices. The 3–5 teammate sweet spot from production cases dominates; >10 sub-agents from one orchestrator is almost always wrong.

Production examples and architectures: [references/case-studies.md](references/case-studies.md).

---

## Sub-agent design contract (apply to every spawn)

Anthropic's verbatim rule: *"Each subagent needs an objective, an output format, guidance on the tools and sources to use, and clear task boundaries. Without detailed task descriptions, agents duplicate work, leave gaps, or fail to find necessary information."* Every sub-agent invocation is incomplete unless it ships all four.

1. **Objective** — terminal state, not a verb. "Produce a list of X with Y attributes from Z sources" beats "research X." Vague briefs caused Anthropic's documented chip-shortage failure: three sub-agents investigated three different time periods in parallel.

2. **Output format** — structured JSON with required fields:
   - `summary` (≤500 words)
   - `evidence` (each claim with `file:line` or `URL#anchor`, plus verbatim quote ≤200 chars)
   - `confidence` (high/medium/low)
   - `open_questions` (explicit tickets for follow-up)
   - `unable_to_determine` (distinguish "looked and found nothing" from "didn't look")

   Free-form prose loses citations and admits hallucination. Schema-constrained output is mechanically mergeable.

3. **Tool/source guidance** — specify which tools and which corpora. Restrict via the subagent's `tools:` allowlist.

4. **Boundaries** — explicit don'ts ("don't make code changes"), stop conditions ("stop after 5 confirmed citations"), tool restrictions enforced by the harness.

**Model tier:** orchestrator gets the strongest model; workers can use Sonnet or Haiku if outputs are bounded and verifiable. **Underprovisioning the orchestrator** (cheap brain, expensive limbs) is the #1 mixed-tier failure.

**Claude Code permissions pitfall:** if the parent runs in `bypassPermissions`, `acceptEdits`, or `auto`, sub-agents inherit and **cannot override**. `allowedTools` does NOT constrain `bypassPermissions` — only `disallowedTools` (deny rules) hold across all modes. See [references/security.md](references/security.md).

Full schema and worked examples: [references/handoff-design.md](references/handoff-design.md).

---

## Operational guardrails (apply to every multi-agent run)

These run regardless of mode. The MAST taxonomy (NeurIPS 2025) found ~36% of multi-agent failures are termination/verification bugs — these are not optional.

1. **Hard iteration cap on every loop.** Defaults: ≤3 critic rounds, ≤4 debate rounds, ≤25 LangGraph-style recursion. **Always OR a token/time budget with the semantic stop** — prompt-only termination is ~90% reliable in AutoGen production, not 100%.

2. **Wall-clock timeout per sub-agent** (5–15 min depending on role). Hung tool calls don't trigger semantic terminators; only wall-clock catches them.

3. **Trust-boundary split** for any task touching untrusted input (web fetch, email, file from outside the repo, user upload, search results, MCP responses from external servers). Untrusted-input handler gets read-only tools, no outbound network, no persistent memory. Privileged orchestrator gets the action tools but never sees raw untrusted text — only the structured fields of the handler's output. This is the single highest-leverage security rule (the "lethal trifecta": private data + untrusted content + external comms = exfiltration; cut a leg per agent role).

4. **Cost ceiling per session.** Multi-agent uses ~15× tokens of single chat. Set a per-session token budget; on exhaust, return best-so-far + `incomplete=true`, never silently truncate. Stack prompt caching + Batch API to recover up to 95% of input cost when the workload is async-tolerant and the prefix is stable.

5. **Idempotency keys on every external write tool call.** Retries will otherwise double-fire — silent double-write (charges, file edits, emails) is the worst recoverable failure.

6. **Audit trace for runs >5 min:** log decision points, agent boundaries, tool-call inputs/outputs (NOT raw message contents — privacy + leak risk). Use these to diagnose patterns post-hoc; multi-agent is non-deterministic so per-run reproduction is impossible.

7. **Resume, don't replay.** LLM orchestrators can't replay (decisions are non-deterministic). Use checkpoint snapshots and "continue from here." Restart-from-scratch on hour-long runs is the worst default.

Operational details: [references/termination.md](references/termination.md), [references/failure-recovery.md](references/failure-recovery.md), [references/cost-latency.md](references/cost-latency.md), [references/security.md](references/security.md).

---

## Top anti-patterns (red flags — stop and reconsider)

If you spot any of these in a proposed design, default back to a smaller pattern:

1. **"Spawn 50 sub-agents"** — Anthropic's own documented over-spawning failure. Right-size: 3–5 typical, 10 ceiling per orchestrator.
2. **Vague sub-agent prompt** ("research X") — produces duplication and gaps. Apply the four-part contract.
3. **Same-model critic on pure reasoning** without external verifier — sycophancy, not signal.
4. **Parallel writers on shared state** — Cognition's Flappy Bird: subagents make incompatible implicit decisions; assembler can't reconcile.
5. **Sub-agent wrapping a single deterministic tool call** — that's a Bash invocation, not an agent.
6. **Free-form prose summary from a sub-agent that read untrusted content** — laundered prompt injection; require schema-constrained output.
7. **Skipping the verification step when fanning out** — N agents hallucinate independently; without re-grounding you aggregate noise.
8. **No iteration cap on critic loops** — runaway cost, fix-induced regressions.
9. **Multi-agent for low-value queries** — 15× cost is indefensible if the task could be a single chat.
10. **Adding agents to fix a quality problem** — try improving the single-agent prompt twice before adding agents. 64% of real-world tasks are handled fine by a single agent at equivalent resources.

Full 16-anti-pattern catalog with recognition triggers: [references/anti-patterns.md](references/anti-patterns.md).

---

## When deeper theory matters

Reach for the references when the task crosses into one of these zones:

- **Right-sizing N specifically** → [references/team-size.md](references/team-size.md) — debate, self-consistency, MoA, fan-out cost curves
- **Picking topology beyond the modes here** → [references/topologies.md](references/topologies.md) — hierarchical / flat / pipeline / mesh / blackboard
- **Adversarial design (debate, red/blue, critic)** → [references/adversarial.md](references/adversarial.md)
- **Why role-splits help vs theater** → [references/role-specialization.md](references/role-specialization.md)
- **Context isolation as a separate axis from parallelism** → [references/context-isolation.md](references/context-isolation.md)
- **Sub-agent prompt + handoff schema details** → [references/handoff-design.md](references/handoff-design.md)
- **State across agents** (full traces vs summaries, blackboards) → [references/memory-state.md](references/memory-state.md)
- **Model tiering, cross-family panels, bias decorrelation** → [references/model-routing.md](references/model-routing.md)
- **Termination, convergence, runaway-loop prevention** → [references/termination.md](references/termination.md)
- **Evaluating multi-agent quality** (end-state vs path, judge variance) → [references/evaluation.md](references/evaluation.md)
- **Cost / cache / latency engineering** → [references/cost-latency.md](references/cost-latency.md)
- **Tool count thresholds, allowedTools recipes, MCP scoping** → [references/tool-design.md](references/tool-design.md)
- **Cross-agent prompt injection, allowedTools/bypassPermissions edges** → [references/security.md](references/security.md)
- **Checkpointing, retries, rainbow deploys, circuit breakers** → [references/failure-recovery.md](references/failure-recovery.md)
- **Production case studies** (Anthropic Research, Devin, Cursor, Stripe, Deep Research) → [references/case-studies.md](references/case-studies.md)
- **Verbatim Anthropic quotes & numbers for citation** → [references/anthropic-canon.md](references/anthropic-canon.md)
- **Task-type → pattern lookup** (20 task families, full per-task playbook) → [references/task-playbook.md](references/task-playbook.md)
- **Full STOP checklist + decision tree** → [references/decision-tree.md](references/decision-tree.md)

## References

- [references/decision-tree.md](references/decision-tree.md) — Full STOP checklist, decision tree, escalation ladder
- [references/task-playbook.md](references/task-playbook.md) — 20 task signatures → pattern → N → key risk
- [references/team-size.md](references/team-size.md) — Diminishing returns, self-consistency, debate, MoA, fan-out cost curves
- [references/topologies.md](references/topologies.md) — Hierarchical / flat / pipeline / mesh / blackboard
- [references/adversarial.md](references/adversarial.md) — Debate, red/blue, critic loops, evaluator-optimizer
- [references/role-specialization.md](references/role-specialization.md) — Builder/tester/reviewer; planner/executor; persona theater
- [references/context-isolation.md](references/context-isolation.md) — Sub-agents as context firewalls (separate from parallelism)
- [references/handoff-design.md](references/handoff-design.md) — Four-part contract, structured output schema, citations
- [references/memory-state.md](references/memory-state.md) — Full traces vs distilled summaries, external memory, blackboards
- [references/model-routing.md](references/model-routing.md) — Opus/Sonnet/Haiku tiering, cross-family heterogeneity
- [references/termination.md](references/termination.md) — Convergence, iteration caps, runaway-loop prevention
- [references/evaluation.md](references/evaluation.md) — End-state vs path eval, LLM-judge variance, equal-budget comparison
- [references/cost-latency.md](references/cost-latency.md) — 15× tokens, prompt caching, Batch API, TTFT, slowest-of-N
- [references/tool-design.md](references/tool-design.md) — 30–50 tool threshold, allowedTools recipes, MCP scoping
- [references/security.md](references/security.md) — Untrusted→privileged split, lethal trifecta, capability scoping
- [references/failure-recovery.md](references/failure-recovery.md) — Checkpointing, rainbow deploys, idempotency, circuit breakers
- [references/anti-patterns.md](references/anti-patterns.md) — 16 named anti-patterns with recognition triggers
- [references/case-studies.md](references/case-studies.md) — Anthropic Research, Devin, Cursor, Deep Research, Stripe, Replit, Bedrock
- [references/anthropic-canon.md](references/anthropic-canon.md) — Verbatim Anthropic quotes and load-bearing numbers
