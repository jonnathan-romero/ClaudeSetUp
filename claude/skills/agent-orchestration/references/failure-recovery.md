# Failure Recovery and Durable Execution

How long-running multi-agent systems survive crashes, deploys, and bad runs. Distilled to drive defaults when designing any production multi-agent setup.

## Contents

- [When to consult this](#when-to-consult-this)
- [Why durability matters more for multi-agent](#why-durability-matters-more-for-multi-agent)
- [Checkpointing patterns](#checkpointing-patterns)
- [Replay vs resume](#replay-vs-resume)
- [Rainbow deployments](#rainbow-deployments)
- [Sub-agent failure modes](#sub-agent-failure-modes)
- [Idempotency for retries](#idempotency-for-retries)
- [Compensating actions and sagas](#compensating-actions-and-sagas)
- [Retry policies](#retry-policies)
- [Circuit breakers](#circuit-breakers)
- [Determinism collapse and reproducibility](#determinism-collapse-and-reproducibility)
- [Hung sub-agent detection](#hung-sub-agent-detection)
- [Resumable sub-agents](#resumable-sub-agents)
- [Dead-letter handling](#dead-letter-handling)
- [Decision triggers](#decision-triggers)
- [Anti-patterns](#anti-patterns)
- [What to default to in this skill](#what-to-default-to-in-this-skill)
- [Sources](#sources)

## When to consult this

Read this before shipping any multi-agent system to production, when designing recovery for a sub-agent topology, when picking between replay (Temporal-style) and resume (LangGraph-style) durability, when deploying prompt or graph changes while runs are in-flight, or when a multi-agent run wastes hours on a crash near completion. Skip for single-agent one-shot runs under five minutes that touch no external state.

## Why durability matters more for multi-agent

Single-agent runs are short-lived: a few tool calls, one or two minutes. If they crash, retry is cheap. Multi-agent runs invert this. Anthropic's research system runs orchestrator plus many sub-agents over many minutes to hours, accumulating state at each step.

> "Without effective mitigations, minor system failures can be catastrophic for agents. When errors occur, we can't just restart from the beginning: restarts are expensive and frustrating for users."

> "Agents are stateful and errors compound … minor system failures can be catastrophic for agents."
>
> — [Anthropic, "How we built our multi-agent research system" (Jun 2025)](https://www.anthropic.com/engineering/multi-agent-research-system)

Two compounding properties make this worse than classical microservices.

- **State is conversational and large.** Each sub-agent built up tool outputs, plans, partial syntheses. None of it is reconstructable from inputs alone.
- **Cost is monotonic.** Each token spent is gone. A 90-minute run that crashes at minute 80 wastes the entire spend. Restart-from-scratch is the most expensive default.

Inngest's "Building Durable Agents" identifies the canonical failure modes for long agents: memory overflow, nondeterministic outputs, infinite loops, goal drift, and "unrecoverable crashes" where "all-or-nothing execution prevents partial recovery." ([Inngest, Building Durable Agents](https://www.inngest.com/blog/building-durable-agents))

If the expected wall-clock of a multi-agent run exceeds ~5 minutes, prefer treating durability as mandatory because restart-from-scratch is too expensive. If the run touches external state (writes, payments, deploys), prefer the same default because retries without durability silently double-act.

## Checkpointing patterns

A checkpoint is a serialized snapshot of "everything I'd need to keep going from here." For multi-agent, the checkpoint must include:

- **Orchestrator plan.** The lead agent's current decomposition and which sub-tasks have shipped.
- **Sub-agent results so far.** Their final answers plus any intermediate citations or artifacts.
- **Conversation window** for any in-flight sub-agent so it can resume mid-thought.
- **Tool-call state.** Last tool input, last tool output, retry counter.
- **External-side-effect log.** Idempotency keys for actions already taken so resumption doesn't re-fire them (see [Idempotency for retries](#idempotency-for-retries)).

Anthropic describes the recovery shape:

> "the platform persists a lightweight snapshot of the agent's plan, conversation window, and tool outputs after major actions, and when a worker dies, the orchestrator reloads the last snapshot and asks Claude to 'continue from here,' so progress is lost only back to the previous checkpoint, not to the beginning."
>
> — [ByteByteGo summary of Anthropic, Jun 2025](https://blog.bytebytego.com/p/how-anthropic-built-a-multi-agent)

### When to checkpoint

- After each sub-agent returns to the orchestrator. Clearest semantic boundary.
- After each pipeline stage in a plan (plan → search → synthesize → cite).
- On a size threshold (every N tool calls or M tokens of new state).
- Before any external write so the write itself is the only non-idempotent thing on resume.

### LangGraph durability modes

LangGraph's three modes make the trade-off concrete ([LangChain Docs, Durable Execution](https://docs.langchain.com/oss/python/langgraph/durable-execution)).

| Mode | Behavior | Use when |
|---|---|---|
| `exit` | Persist only at completion / error / interrupt | Short, throwaway runs |
| `async` | Persist asynchronously during the next step | Default for most agents |
| `sync` | Persist before the next step starts | Critical writes; HITL workflows |

LangGraph saves at "super-step" boundaries (between node executions). Resumption restarts at the beginning of the node where execution halted, not the exact line. That puts an idempotency requirement on each node.

If the boundary you'd resume from is a sub-agent return, prefer checkpointing there by default because it's already a clean re-entry point. If a sub-agent is itself expected to run > 5 minutes, prefer adding intra-agent checkpoints because a crash inside it would otherwise lose the full run.

## Replay vs resume

Two distinct recovery models exist and they're often conflated.

- **Replay.** Re-execute the workflow deterministically from a logged event history. The framework re-runs your code; whenever it reaches a step it has logged, it skips actually running it and re-injects the logged result. Temporal's model: *"if the Workflow has to recover from a crash, it 'replays' your agent's progress to date."* ([Temporal, Multi-agent architectures](https://temporal.io/blog/using-multi-agent-architectures-with-temporal))
- **Resume.** Reload the last good state snapshot and continue from there. No re-execution. LangGraph plus checkpointer is closer to this model.

### When replay is right

- Workflow code is deterministic and the *workflow* layer doesn't make LLM calls itself; LLM calls live in non-deterministic activities whose outputs are recorded. Temporal's split: *"Workflows handle interaction, orchestration, dynamic decision making, unlimited duration. Activities execute external calls with automatic retries."*
- You want full auditability: the event log is a complete, deterministic trace.

### When resume is right

- Your orchestrator is itself an LLM, so it's not deterministic. You can't replay an LLM decision and expect the same result.
- Sub-agent state is large and you'd rather not re-execute even tool calls.

### Why replay is hard with LLMs

Even with `temperature=0`, LLM outputs vary across runs due to GPU non-determinism, tokenizer drift, model updates, and tool ordering.

> "Agents make dynamic decisions and are non-deterministic between runs, even with identical prompts. This makes debugging harder."
>
> — [Anthropic, Jun 2025](https://www.anthropic.com/engineering/multi-agent-research-system)

For replay to work in agentic systems, the LLM call must be wrapped as an activity so the *output* is logged and replayed, not the *call*.

If the orchestrator is itself an LLM (Claude-Code style), prefer resume from snapshot because LLM decisions don't replay deterministically. If orchestration logic is plain code wrapping LLM activities (Temporal/Inngest style), prefer replay because it gives a full audit log and free recovery. Don't try to replay LLM decisions verbatim.

## Rainbow deployments

You're deploying v2 of the agent, but 47 sub-agents are mid-task on v1. Cutover kills them; rolling restart kills the long-tail. Anthropic's exact pattern:

> "we use rainbow deployments to avoid disrupting running agents, by gradually shifting traffic from old to new versions while keeping both running simultaneously."
>
> — [Anthropic, Jun 2025](https://www.anthropic.com/engineering/multi-agent-research-system)

Operationally:

> "Every commit gets its own color, new requests flow to the new color, and old pods stay alive until their agents finish, giving zero-downtime releases even for stateful agents."
>
> — [ByteByteGo summary](https://blog.bytebytego.com/p/how-anthropic-built-a-multi-agent)

### Designing for rainbow from day one

- **Version the prompt as well as the code.** A prompt change is a deploy. The prompt graph (orchestrator prompt → sub-agent prompts → tool descriptions) is part of the artifact. Pin a prompt-graph version per session/run; do not let an in-flight run pick up new prompts mid-run.
- **Stateless orchestration tier; durable state tier.** Pods are disposable; checkpoints live in a separate store (Postgres, DynamoDB, S3) with a stable schema. New-color pods can read old-color checkpoints if needed, but the safer default is: a session always finishes on the color it started on.
- **Drain gracefully, not immediately.** LangGraph 1.2+ adds `RunControl.request_drain("sigterm")` which raises `GraphDrained` with a saved checkpoint; the run can be re-invoked with `invoke(None, config)` on the same thread. ([LangChain Docs, Durable Execution](https://docs.langchain.com/oss/python/langgraph/durable-execution))
- **Schema-evolve checkpoints carefully.** If v2 changes the checkpoint schema, either keep a reader for v1 or commit to "v1 sessions finish on v1 pods."

If sub-agent runs can outlive a deploy (more than a few minutes), prefer rainbow because cutover kills hour-long runs. The version of an in-flight run is fixed at the moment the run starts.

## Sub-agent failure modes

| Failure mode | Detection | Recovery |
|---|---|---|
| **Hang / no progress** | Wall-clock cap (5–15 min per sub-agent); also "no-progress" detection (tool calls without new useful output) | Kill, retry with revised prompt, or fall back to inline single-agent. Anthropic: *"letting the agent know when a tool is failing and letting it adapt works surprisingly well."* |
| **Malformed output** | JSON / Pydantic schema validation at orchestrator boundary | Retry once with the validation error appended to the prompt (Reflexion-style). After 2 failures, escalate. |
| **Empty / "I couldn't find anything"** | Heuristic on output content/length | Pivot strategy: broaden search query, switch tool, or kick to a different sub-agent role. |
| **Hallucination** | Citation check / verifier sub-agent / cross-source agreement | Re-ask with "show your sources." SagaLLM uses *"specialized small-context agents with rigorous validation criteria"* as independent validators ([SagaLLM, arXiv:2503.11951](https://arxiv.org/html/2503.11951v2)). |
| **Tool failure** | Non-2xx, exception, or schema fail | Retry with backoff (transient); fallback tool (persistent); return partial. |
| **Network / API failure** | Timeout, 5xx | Exponential backoff + retry budget + circuit breaker. |

### Reflexion as a retry strategy

Naive retry repeats the same failing prompt. Reflexion has the agent verbally reflect on the failure first, store that reflection in episodic memory, and try again with the reflection as added context — "verbal reinforcement to help agents learn from prior failings by converting binary or scalar feedback from the environment into verbal feedback." ([Shinn et al., "Reflexion," arXiv:2303.11366, 2023](https://arxiv.org/abs/2303.11366)). Reported 91% on HumanEval vs GPT-4 baseline 80%.

If a tool returns malformed JSON, prefer retry once with validation feedback because Reflexion-style self-correction works on format and method errors. If a sub-agent returns empty results, prefer pivoting strategy (broaden, switch tool, escalate) because blind retry returns the same nothing. If the failure is hallucinated facts, prefer a verifier loop or citation check because reflection alone doesn't fix factual errors.

## Idempotency for retries

When a sub-agent crashes mid-action and is retried, any side effect it took before crashing will be repeated unless the action is idempotent. Stripe-style idempotency keys are the standard answer:

> "a unique key that the server uses to recognize subsequent retries of the same request … the server skips the operation entirely and retrieves the previously stored result."
>
> — [Stripe API Reference, Idempotent requests](https://docs.stripe.com/api/idempotent_requests)

### For agent tool calls

- **Generate a deterministic key per logical action** at the orchestrator. Stable input → same key. The same retry produces the same key; the side-effecting service deduplicates.
- **For file edits.** Pre-check the current file content / hash before applying ("have I done this already?"). Idempotency by detection.
- **For destructive actions** (deletes, payments). Dry-run first, log intent, then commit. Resume sees the intent log and skips the commit if already done.
- **TTL on idempotency keys.** 24h is a common default, longer for high-stakes ops.

LangGraph makes the requirement explicit:

> "Wrap side effects in tasks … Use idempotent operations … If an operation is retried after a failure in the workflow, it will have the same effect as the first time it was executed."

Inngest's framing: *"Idempotent steps combined with progress tracking enable resumption."* ([Inngest, Building Durable Agents](https://www.inngest.com/blog/building-durable-agents))

If a sub-agent makes any external state change, prefer requiring an idempotency key on every write tool call because retries on non-idempotent writes silently double-act (double charges, duplicate file edits, duplicate emails).

## Compensating actions and sagas

Database transactions don't apply across agent actions on the world (you can't `ROLLBACK` a sent email or a deployed service). The saga pattern from microservices fills the gap: pair each step with a compensating action that logically reverses it.

**SagaLLM** ([Liu et al., arXiv:2503.11951, 2025](https://arxiv.org/html/2503.11951v2)) adapts this for multi-agent LLM planning.

- *"Failure in any transaction Tj triggers the execution of compensating transactions Cj−1, Cj−2, …, C1 in reverse sequence."*
- Compensations are domain-specific: cancel the flight, refund the charge, rollback the deploy, send a "disregard" email.
- Maintains three state dimensions: application state, operation state (logs of inputs/outputs/reasoning), dependency state.

### When to use sagas

- Multi-step workflow touches multiple external systems.
- Each step is individually committable but the whole sequence needs all-or-nothing semantics.
- Compensations exist and are cheaper than human cleanup.

### Anti-patterns

- Saga where compensations don't actually reverse the effect (refunding a credit card doesn't unsend the receipt email).
- Saga where compensations themselves can fail without their own retry / escalation path.
- Using sagas where idempotent retry would suffice (cheaper, simpler).

If the multi-agent sequence has more than 2 external writes that must succeed or fail atomically, prefer designing compensating actions before shipping because the world state can't be rolled back. If only one write or only reads, prefer idempotent retry because it's simpler and cheaper. See also [Microsoft Learn, "Compensating Transaction Pattern"](https://learn.microsoft.com/en-us/azure/architecture/patterns/compensating-transaction) and [AWS Prescriptive Guidance, "Prompt chaining saga patterns"](https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-patterns/prompt-chaining-saga-patterns.html).

## Retry policies

The wrong retry policy turns a failing service into a retry storm. ([Portkey, Retries, fallbacks, and circuit breakers in LLM apps](https://portkey.ai/blog/retries-fallbacks-and-circuit-breakers-in-llm-apps/))

### Per-error-class rules

- **Transient (retry).** Network instability, TLS handshake failures, cold starts, brief rate limits, token quota refresh. 429s with `Retry-After`.
- **Permanent (don't retry).** 4xx auth, 4xx schema, 4xx not-found.
- **Degraded (fallback, don't retry primary).** Provider outage, sustained 5xx — switch to a fallback model/provider rather than re-hammering.

### Mechanics

- **Exponential backoff with jitter.** 1s, 2s, 4s, 8s, capped (e.g. 30s).
- **Honor `Retry-After`** when the provider gives it.
- **Budget per session.** A hard cap on total retries across the whole run (e.g. 20). Anti-pattern: per-call budget without a session cap → infinite cost when many calls each retry to their cap.
- **Different policies per layer.**
  - Tool call: aggressive retry, low cost.
  - Sub-agent: conservative retry (1–2), since each retry costs a full sub-agent run.
  - Whole task: usually 0 automatic retries; surface to a human or DLQ.

If retries could be unbounded, prefer adding a per-session retry budget plus a circuit breaker because per-call caps multiplied across many calls produce infinite cost. If a provider returns 429 with `Retry-After`, prefer honoring the header because exponential backoff alone causes a retry storm.

## Circuit breakers

When a downstream service or sub-agent role keeps failing, stop trying. Circuit breakers move from microservices into agent stacks with three states ([tutorialQ, Circuit Breakers in LLM Services](https://tutorialq.com/ai/dl-infrastructure/circuit-breakers)).

- **Closed.** Normal, requests pass.
- **Open.** Trip threshold exceeded, all requests fail fast for a cooldown.
- **Half-open.** After cooldown, allow N test requests; if they pass, close; if they fail, reopen.

### Trip thresholds

- **Failure count or rate.** 5 consecutive failures or 50% error rate over the last 20 calls.
- **Specific status codes.** 429, 502, 503.
- **AI-specific** ([Waxell, AI Agent Circuit Breakers](https://dev.to/waxell/ai-agent-circuit-breakers-the-reliability-pattern-production-teams-are-missing-5bpg)):
  - **Runaway loops.** 2–3 consecutive identical tool calls with no new state.
  - **Cost velocity.** > $50/hour or > $200/session.
  - **Consecutive failures.** ≥ 3 on the same step → terminate.
  - **Scope violations.** Agent tries to call out-of-bounds tool or data source.

Why this matters specifically for agents: classic breakers assume binary failures and restart-fixes-it. Agents have *soft* failures — running but no progress, hallucinating, looping — where "your biggest failures look like successes." ([Waxell](https://dev.to/waxell/ai-agent-circuit-breakers-the-reliability-pattern-production-teams-are-missing-5bpg))

Kill switch vs circuit breaker: kill switch = human action; circuit breaker = automatic. *"At 3 AM on a Tuesday, when an agent enters a loop because a downstream API returned a transient 503, nobody is watching."*

If a sub-agent role or tool fails ≥ 3 times in a row, prefer circuit-break and escalate because retry won't fix soft failures. If cost velocity exceeds a session budget, prefer tripping the breaker because runaway loops won't self-terminate. If an agent makes 2–3 identical tool calls with no new state, prefer tripping the breaker because the agent has no way to detect the loop itself.

## Determinism collapse and reproducibility

Multi-agent runs are non-deterministic at three layers: LLM sampling, tool result ordering (parallel sub-agents), and orchestrator routing decisions. Two runs of "the same query" produce different traces. This breaks classical debugging and regression testing.

### What to log (Anthropic's approach, with privacy)

> "Adding full production tracing let us diagnose why agents failed and fix issues systematically. Beyond standard observability, we monitor agent decision patterns and interaction structures—all without monitoring the contents of individual conversations, to maintain user privacy."
>
> — [Anthropic, Jun 2025](https://www.anthropic.com/engineering/multi-agent-research-system)

Concretely log:

- **Agent boundaries.** Sub-agent spawn/return, role, parent.
- **Decision points.** Which branch of the plan was taken, what triggered the choice (token-level reasoning is optional and expensive).
- **Tool calls.** Name, input hash, output hash, latency, success/failure, retry count.
- **Checkpoint events.** Which step, size, duration to write.
- **NOT message contents in production traces.** Privacy + leak risk.

### Mitigations for non-determinism

- Snapshot inputs (the seed query + tool versions + prompt-graph version + model version).
- Seed where possible (but expect drift even at `seed=0`).
- Use traces for *patterns*, not exact reproductions: "this class of failure happens X% of the time on this kind of input."
- Hash tool inputs and outputs at log time. Hash collisions are the trace-level analogue of cache hits — they identify when two runs at least exercised the same tool surface even when the LLM commentary diverged.
- Replay regression tests at the *behavior* level (did the agent reach a terminal state with the right answer shape?), not at the *trace* level (did it produce the same tokens?).

If a multi-agent run is non-deterministic, prefer logging decision points + tool calls + agent boundaries because patterns matter more than verbatim traces. Prefer NOT logging raw message contents in production traces because of privacy and secret-leakage risk. If you need to debug a specific failed run, prefer pulling that run's transcript on demand from a separate, access-controlled store rather than streaming all message contents into general observability.

## Hung sub-agent detection

Two flavors of hang.

- **Hard hang.** Tool call never returns. Catch with wall-clock timeout per tool call (60s) and per sub-agent (5–15 min depending on role).
- **Soft hang / livelock.** Sub-agent keeps making tool calls but no useful state change. Detect by hashing successive tool inputs/outputs; trip if N consecutive calls produce no novel output. This is exactly the AI-specific circuit-breaker condition.

Temporal exposes timeouts at workflow, activity, and start-to-close levels, e.g. `timeout=timedelta(hours=20)`. ([Temporal, Multi-agent](https://temporal.io/blog/using-multi-agent-architectures-with-temporal))

If a sub-agent could hang on a slow tool, prefer wall-clock caps at both the tool and the sub-agent layer because one hung sub-agent stalls the whole tree. If a sub-agent's tool may itself be slow (long search), prefer setting the cap longer than the slowest expected tool but never unbounded.

## Resumable sub-agents

Claude Code persists each sub-agent transcript independently as JSONL at `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`. Subagent transcripts persist independently of the main conversation; when the main conversation compacts, subagent transcripts are unaffected. ([Claude Code subagent docs](https://code.claude.com/docs/en/sub-agents))

### Saves work when

- The sub-agent had completed a long search and the orchestrator just needs to keep using its outputs.
- Recovering from a crash where the sub-agent's last completed turn is still useful.

### Leads to inheriting bad state when

- The sub-agent had drifted from its task; resuming continues the drift.
- Known bug: resumed agents may "fork from checkpoint instead of accumulating context" — each resume loads only the original checkpoint, not prior resume interactions ([anthropics/claude-code #10856](https://github.com/anthropics/claude-code/issues/10856)).
- Known bug: agent transcript files do not store the user prompts that initiated/resumed the agent ([anthropics/claude-code #11712](https://github.com/anthropics/claude-code/issues/11712)).
- Known bug: large transcripts can crash on resume ([anthropics/claude-code #30302](https://github.com/anthropics/claude-code/issues/30302)).

If the sub-agent's last state was *known good* (it had returned a clean output and the crash was on the orchestrator side), prefer resume because the work is recoverable. If the crash was inside the sub-agent itself, prefer fresh-spawn with the original task description because resume inherits the drifted state.

## Dead-letter handling

Every multi-agent system needs a place for "this task failed all retries" to go. ([SRE School, DLQ](https://sreschool.com/blog/dead-letter-queue-dlq/); [softwarepatternslexicon, Dead-Letter Queues](https://softwarepatternslexicon.com/event-driven-architecture-patterns/reliability-and-delivery/dead-letter-queues/))

### Pattern

- After retry budget + circuit breaker exhaust, push the failed task with full context (input, last checkpoint, error, trace ID) to a DLQ.
- Auto-classify (LLM-assisted is a fit): transient infra → auto-retry later; permanent → human review.
- Surface human-review queue in a UI with a dashboard owner and SLA.
- Replay tool: deduplicate, validate, replay only after root cause fix.

> "add automated classification, retry logic, archival, and alerting … turn DLQ handling into a self-healing system that handles transient failures automatically and surfaces permanent failures for human review."
>
> — [Scalytics, DLQ AI Agent](https://www.scalytics.io/en-us/blog/intelligent-routing-for-event-driven-systems-the-scalytics-connect-dlq-agent)

Also: *"Dead Letter Queues Are Not Your Safety Net"* — DLQs need owners and processes, not just a bucket to drop things into. ([newsletter.systemdesignclassroom.com](https://newsletter.systemdesignclassroom.com/p/dead-letter-queues-are-not-your-safety-net))

If a production multi-agent system can have terminal failures, prefer shipping (a) a DLQ, (b) a named owner, (c) an SLA, and (d) a safe replay tool with dedup because tasks otherwise accumulate indefinitely with no one noticing.

## Decision triggers

Consolidated. Use these as the fast lookup.

| If… | Prefer… | Because… |
|---|---|---|
| Multi-agent run will take > 5 minutes | Checkpoint after each sub-agent return | Restart-from-scratch is too expensive |
| Sub-agents make external state changes | Idempotency keys on every write | Retries will otherwise double-act |
| Sub-agent could hang on a slow tool | Wall-clock timeout (per tool, per sub-agent) | Hung sub-agents block the orchestrator |
| Prompt graph being deployed and runs are in-flight | Rainbow deployment | Cutover kills hour-long runs |
| Retries could be unbounded | Per-session retry budget + circuit breaker | Otherwise infinite cost |
| Run is non-deterministic | Log decision points + tool calls + agent boundaries (NOT message contents) | Privacy + leak risk; patterns matter more than verbatim traces |
| Side-effect action could fail midway | Compensating action designed before shipping | World state can't be `ROLLBACK`'d |
| Sub-agent fails repeatedly (≥ 3×) | Circuit-break and escalate | Retry won't fix soft failures |
| Orchestrator is itself an LLM | Resume from snapshot, not deterministic replay | LLM decisions don't replay |
| Workflow is plain code wrapping LLM activities | Replay (Temporal-style) | Full audit log + free recovery |
| Agent tool returns malformed JSON | Retry once with validation feedback | Reflexion-style self-correction works |
| Sub-agent returns "I couldn't find anything" | Pivot strategy (broaden, switch tool, escalate) | Blind retry will return the same nothing |
| Live tool call latency > p99 expected | Honor `Retry-After`, exponential backoff with jitter | Prevent retry storm |
| Runaway loop: ≥ 3 identical tool calls | Trip circuit breaker | Soft failure, agents won't self-detect |
| Crash was on orchestrator side, sub-agent state clean | Resume sub-agent | Work is recoverable |
| Crash was inside the sub-agent | Fresh-spawn with original task | Resume inherits drifted state |
| Terminal failure after retries exhausted | Push to DLQ with named owner + SLA | Tasks otherwise accumulate silently |

## Anti-patterns

Do not do these.

- **Restart-from-scratch on any failure.** Loses hours of work; users churn.
- **No checkpointing on long runs.** A crash at hour 2 is unrecoverable.
- **Unbounded retries.** Infinite cost; retry storm; mask real failures.
- **Non-idempotent writes with retry-on-failure.** Silent double-write bugs (double charges, duplicate file edits, duplicate emails).
- **Cutover deploys that kill running agents.** Use rainbow.
- **No timeout on sub-agent calls.** One hung sub-agent stalls the whole tree.
- **Logging full message contents in production traces.** Privacy risk + secret leakage; log structure, not content.
- **Saga where compensations don't actually reverse the effect.** False sense of safety.
- **Per-call retry budget without a session-level cap.** Each call retries to its cap × N calls = unbounded total.
- **Treating Reflexion-style retry as a fix for hallucination of facts.** Reflection helps with format/method errors; for facts you need a verifier or citation check, not self-reflection.
- **Resuming a sub-agent that crashed mid-task.** Resumes the bad state. Fresh-spawn instead.
- **DLQ with no owner.** Tasks accumulate indefinitely; no one notices.

## What to default to in this skill

- **Checkpoint at sub-agent return boundaries.** That's the natural Claude-Code-style boundary. Add intra-agent checkpoints only when a sub-agent is expected to run > 5 min.
- **Resume, not replay, for LLM-orchestrated systems.** Snapshot plan + sub-agent results + in-flight conversation + tool-call state + side-effect log. Reserve replay for plain-code orchestrators wrapping LLM activities.
- **Pin a prompt-graph version per session.** A session always finishes on the color it started on. Rainbow-deploy by default once runs can outlive a deploy.
- **Idempotency key on every external write.** No exceptions. Stripe-style deterministic keys generated by the orchestrator.
- **Per-error-class retry rules with a session-level cap.** Transient → backoff; permanent → don't retry; degraded → fallback. Hard cap total retries at 20 per session by default.
- **Three-state circuit breaker per sub-agent role and per tool.** Trip on ≥ 3 consecutive failures, runaway-loop detection (≥ 3 identical tool calls), cost-velocity overrun, or scope violation.
- **Wall-clock cap on every sub-agent.** 5–15 min by default, longer only if the slowest expected tool justifies it. Never unbounded.
- **Log structure, not content.** Agent boundaries, decision points, tool input/output hashes, checkpoint events. Never raw message contents in production traces.
- **DLQ with named owner, SLA, and dedup-safe replay tool.** Required for any production setup.
- **Compensating actions before shipping** any sequence with > 2 external writes that need atomic semantics.

## Sources

Primary:

- [Anthropic, "How we built our multi-agent research system" (Jun 2025)](https://www.anthropic.com/engineering/multi-agent-research-system) — rainbow deployments, checkpointed durable execution, non-determinism, full production tracing.
- [LangChain Docs, "Durable Execution" (LangGraph)](https://docs.langchain.com/oss/python/langgraph/durable-execution) — checkpointers, durability modes (exit / async / sync), idempotency requirement, super-step boundaries, `RunControl`.
- [Temporal, "Durable multi-agentic AI architecture with Temporal"](https://temporal.io/blog/using-multi-agent-architectures-with-temporal) — replay model, deterministic workflows + non-deterministic activities, timeouts, signals.
- [Inngest, "Building Durable AI Agents"](https://www.inngest.com/blog/building-durable-agents) — five failure modes, step-based observability, idempotent steps, in-flight resumption.
- [Shinn et al., "Reflexion: Language Agents with Verbal Reinforcement Learning," arXiv:2303.11366 (2023)](https://arxiv.org/abs/2303.11366) — Actor / Evaluator / Self-Reflection retry loop with episodic memory.
- [Liu et al., "SagaLLM: Context Management, Validation, and Transaction Guarantees for Multi-Agent LLM Planning," arXiv:2503.11951 (2025)](https://arxiv.org/html/2503.11951v2) — saga pattern adapted for multi-agent LLM, compensating transactions, validation agents.

Supporting:

- [ByteByteGo, "How Anthropic Built a Multi-Agent Research System"](https://blog.bytebytego.com/p/how-anthropic-built-a-multi-agent) — paraphrased rainbow + checkpoint mechanics.
- [Portkey, "Retries, fallbacks, and circuit breakers in LLM apps"](https://portkey.ai/blog/retries-fallbacks-and-circuit-breakers-in-llm-apps/) — error classification, exponential backoff, fallback caveats.
- [Waxell, "AI Agent Circuit Breakers" (dev.to)](https://dev.to/waxell/ai-agent-circuit-breakers-the-reliability-pattern-production-teams-are-missing-5bpg) — agent-specific trip thresholds (cost velocity, runaway loops, scope violations), kill-switch vs breaker.
- [tutorialQ, "Circuit Breakers — Preventing Cascade Failures in LLM Services"](https://tutorialq.com/ai/dl-infrastructure/circuit-breakers) — three-state model.
- [Stripe API Reference, "Idempotent requests"](https://docs.stripe.com/api/idempotent_requests) — canonical idempotency-key implementation.
- [Scalytics, "DLQ AI Agent"](https://www.scalytics.io/en-us/blog/intelligent-routing-for-event-driven-systems-the-scalytics-connect-dlq-agent) — DLQ classification + human-review routing for agent failures.
- [SRE School, "Dead Letter Queue (DLQ)"](https://sreschool.com/blog/dead-letter-queue-dlq/) — DLQ operational practices.
- [Microsoft Learn, "Compensating Transaction Pattern"](https://learn.microsoft.com/en-us/azure/architecture/patterns/compensating-transaction) — classical saga compensation.
- [AWS Prescriptive Guidance, "Prompt chaining saga patterns"](https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-patterns/prompt-chaining-saga-patterns.html) — sagas applied to prompt chains.
- [Claude Code subagent docs](https://code.claude.com/docs/en/sub-agents); [issue #10856 (resume forks instead of accumulates)](https://github.com/anthropics/claude-code/issues/10856); [issue #11712 (resume missing user prompts)](https://github.com/anthropics/claude-code/issues/11712); [issue #30302 (large transcript crash)](https://github.com/anthropics/claude-code/issues/30302) — known limits of Claude Code's resumable-sub-agent model.
