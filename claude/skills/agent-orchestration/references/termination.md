# Termination, Convergence, and Runaway Prevention

How to decide when a multi-agent run is done — and how to prevent it from running forever, billing forever, or stopping too early. Termination/verification is the largest single failure cluster in production multi-agent systems (~36% of failures per MAST), so default conservatively.

## Contents

- [When to consult this](#when-to-consult-this)
- [Why termination is the dominant failure mode](#why-termination-is-the-dominant-failure-mode)
- [Termination strategies](#termination-strategies)
  - [Hard iteration cap](#hard-iteration-cap)
  - [Convergence detection](#convergence-detection)
  - [Explicit termination tokens](#explicit-termination-tokens)
  - [External signal termination](#external-signal-termination)
  - [Resource-budget termination](#resource-budget-termination)
  - [Human-in-the-loop gate](#human-in-the-loop-gate)
  - [Function-call termination](#function-call-termination)
  - [Confidence-threshold termination](#confidence-threshold-termination)
- [AutoGen termination conditions](#autogen-termination-conditions)
- [Convergence in debate](#convergence-in-debate)
- [Convergence in critic loops](#convergence-in-critic-loops)
- [Runaway loops in mesh and hierarchical topologies](#runaway-loops-in-mesh-and-hierarchical-topologies)
- [Premature termination as the inverse failure](#premature-termination-as-the-inverse-failure)
- [Budget backstops and what to do when they fire](#budget-backstops-and-what-to-do-when-they-fire)
- [Cross-session and long-running agent termination](#cross-session-and-long-running-agent-termination)
- [Composition recipes by framework](#composition-recipes-by-framework)
- [Monitoring signals for runaway detection](#monitoring-signals-for-runaway-detection)
- [Debugging termination failures](#debugging-termination-failures)
- [Decision triggers](#decision-triggers)
- [Anti-patterns](#anti-patterns)
- [Defaults to apply when unsure](#defaults-to-apply-when-unsure)
- [Sources](#sources)

## When to consult this

Read this when setting termination strategy for a multi-agent run, configuring a critic/evaluator-optimizer loop, sizing debate rounds, sanity-checking a recursion or hop budget, choosing between AutoGen termination conditions, or diagnosing a system that loops forever, exits early, or returns silently truncated state. Skip for single-shot one-agent calls.

## Why termination is the dominant failure mode

Single-agent loops have a natural step boundary — each LLM call is discrete and the orchestrator either calls again or returns. Multi-agent systems have no such boundary. Agents call agents, hand off control, vote, debate, and re-prompt each other across turns whose count is determined by the agents themselves. The "are we done?" decision is now distributed across multiple LLM judgments, not one line of orchestrator code.

The MAST taxonomy (Cemri et al., arXiv:2503.13657, v3 26 Oct 2025) annotated 1,600+ traces across 7 multi-agent frameworks (AutoGen, ChatDev, MetaGPT, etc.) with κ=0.88 inter-annotator agreement and quantifies the cluster:

- Category FC3 "Task Verification" = **23.5%** of all observed multi-agent failures.
  - FM-3.1 Premature termination: **6.2%**
  - FM-3.2 No or incomplete verification: **8.2%**
  - FM-3.3 Incorrect verification: **9.1%**
- FM-1.5 "Unaware of termination conditions" (in FC1 System Design): **12.4%**.

Combined: **~35.9%** of multi-agent failures are rooted in not knowing when to stop, stopping too early, or failing to verify completion. This is the largest cluster after step repetition (15.7%) and reasoning-action mismatch (13.2%) — both arguably termination-adjacent.

The asymmetry: a single agent's worst case is one bad answer. A multi-agent system's worst case is unbounded billing, runaway tool calls, and no signal returned to the caller. Treat termination as a first-class design problem, not a footnote.

## Termination strategies

Each strategy has a niche. Production setups OR multiple together; never rely on any single one alone.

### Hard iteration cap

Orchestrator counts steps; raises or returns when the counter exceeds N. AutoGen `MaxMessageTermination(max_messages=N)`; LangGraph `recursion_limit` (default **25**, raises `GraphRecursionError`).

- **Shines.** Deterministic upper bound on cost. Works regardless of model behavior. The only termination strategy *guaranteed* to fire.
- **Fails.** Fires mid-task and silently truncates if there are no completion semantics. Users hit the cap, raise it to 100, and never investigate the underlying cycle. The LangGraph troubleshooting doc explicitly warns: "If you are not expecting your graph to go through many iterations, you likely have a cycle. Check your logic for infinite loops." Issue `langchain-ai/deepagents#1698` shows even framework code silently re-defaults sub-agent recursion limits to 25 — easy to miss.
- **Use as.** Always-on backstop, never as the primary stop signal.

### Convergence detection

Compare round N's output to round N-1; terminate when equal or below an edit-distance threshold. For debates, stop when all agents emit identical answers.

- **Shines.** Avoids paying for redundant rounds when the system has actually settled. Useful in critic loops where iterations N and N+1 produce substantively similar feedback.
- **Fails.** In debate, "convergence" is itself a failure signal. Wynn, Satija & Hadfield ("Talk Isn't Always Cheap", arXiv:2509.05396, ICML MAS Workshop 2025) show agents "shift from correct to incorrect answers in response to peer reasoning, favoring agreement over challenging flawed reasoning"; CommonSenseQA dropped **1.2–12.0 percentage points** after debate across heterogeneous group configurations (3 models: GPT-4o-mini, LLaMA-3.1-8B, Mistral-7B; T=2 rounds; 100 samples × 5 seeds). Stopping on convergence in this regime locks in the wrong answer.
- **Use as.** Secondary signal in critic loops with regression rollback. **Never the sole stop in debate.**

### Explicit termination tokens

Agent emits an in-band sentinel string; orchestrator regexes for it. AutoGen `TextMentionTermination("APPROVE" | "TERMINATE")`.

- **Shines.** Zero infra. Trivial to implement. Works for simple two-agent loops where the model reliably emits the token.
- **Fails.** Catastrophically unreliable in production. Documented modes:
  1. Model forgets the token entirely. AutoGen 0.2 FAQ acknowledges TERMINATE-keyword workarounds work "around 90% of the time" — the LLM "still forgets to terminate" the rest.
  2. Model emits the token mid-explanation ("I will now TERMINATE the analysis with a summary…") causing premature stop.
  3. Prior-message contamination — if "TERMINATE" appears anywhere in conversation history, predicate fires on next turn. AutoGen team docs warn to filter history before resuming a session.
- **Use as.** Avoid in production. AutoGen issue [#133](https://github.com/microsoft/autogen/issues/133) was filed specifically to deprecate this pattern in favor of function calls. If unavoidable, always backstop with a hard cap.

### External signal termination

A deterministic verifier outside the LLM loop returns a binary signal. Loop exits the moment the verifier returns OK.

- **Shines.** The gold standard. Termination grounded in an external truth (compiler succeeds, JSON schema validates, test suite green, regex matches, lint passes). Reflexion (Shinn et al., arXiv:2303.11366, NeurIPS 2023) reaches **91% pass@1 on HumanEval** by terminating exactly when unit tests pass.
- **Fails.** Only works when an external verifier exists. For "write a good essay," no oracle. Poorly-spec'd tests can pass with garbage output (FM-3.3 "Incorrect verification," **9.1%** in MAST).
- **Use as.** Primary terminator whenever available. Everything else is a backstop.

### Resource-budget termination

Hard cap on tokens, dollars, or wall-clock seconds, enforced by orchestrator outside the model loop. AutoGen `TokenUsageTermination`, `TimeoutTermination`.

- **Shines.** Protects against billing runaways. The only true backstop against tool-call hangs — a sub-agent stuck in an HTTP retry won't be saved by `MaxMessageTermination` because no new messages are produced.
- **Fails.** Fires mid-task with no completion semantics. Must be paired with a "return best-so-far + incomplete flag" handler, otherwise the caller gets silent truncation.
- **Use as.** Always-on backstop alongside iteration cap. Wall-clock specifically required when sub-agents make outbound network calls.

### Human-in-the-loop gate

Orchestrator pauses after N turns or before high-impact actions; human decides continue/stop. AutoGen `HandoffTermination(target="user")`, `ExternalTermination`.

- **Shines.** High-stakes domains (medical, legal, deploy). Irreversible actions. Ambiguous termination criteria where only a human can adjudicate.
- **Fails.** Doesn't scale. Introduces wall-clock latency. Operator fatigue degrades gating quality over time.
- **Use as.** Gate before destructive or expensive actions, not as a default termination signal.

### Function-call termination

Agent emits a structured tool call (`finish(reason="…")`); orchestrator catches the call and terminates. AutoGen `FunctionCallTermination(function_name="approve")` and `StopMessageTermination`.

- **Shines.** More reliable than text sentinels because tool-call schemas are enforced by the model's tool-use machinery, not free-text generation. The principled fix recommended in AutoGen issue [#133](https://github.com/microsoft/autogen/issues/133).
- **Fails.** Model still has to *decide* to call the tool — same root issue as text tokens, just with better signal isolation. Must be backstopped by a hard cap.
- **Use as.** Preferred semantic stop for AutoGen and any tool-using framework. Always OR'd with `MaxMessageTermination` and `TimeoutTermination`.

### Confidence-threshold termination

Stop when self-reported confidence (or an external uncertainty estimator) crosses a threshold.

- **Shines.** Research settings with calibrated uncertainty estimators.
- **Fails.** LLM self-reported confidence is poorly calibrated; sycophantic agents in debate report rising confidence as they converge on wrong answers (per "Talk Isn't Always Cheap").
- **Use as.** Avoid in production unless paired with an external calibration check.

## AutoGen termination conditions

From the [AutoGen AgentChat termination tutorial](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/termination.html):

| Condition | Trigger | Failure mode |
|---|---|---|
| `MaxMessageTermination(max_messages=N)` | Message count reached | Always fires; reliable. Pure backstop. |
| `TextMentionTermination("APPROVE")` | Sentinel substring in any new message | Model may not emit token; prior-history contamination |
| `TokenUsageTermination(max_*_tokens=N)` | Cumulative tokens exceed cap | Requires agents to report token usage; only fires post-message |
| `HandoffTermination(target="user")` | Agent hands off to specified target | Used in Swarm patterns to pause for user |
| `StopMessageTermination` | Agent emits a `StopMessage` typed message | More structured than text sentinel |
| `FunctionCallTermination(function_name="approve")` | Specific tool call executed | Best in-band signal; still depends on model behavior |
| `SourceMatchTermination(sources=[...])` | Specific agent finishes a turn | Useful for "stop after summarizer speaks" |
| `ExternalTermination` | `.set()` called from outside the run | UI stop buttons; programmatic kill switch |
| `TimeoutTermination(timeout_seconds=N)` | Wall-clock elapsed | Critical backstop for hangs |
| `TextMessageTermination` | Any TextMessage produced | Pause-on-text patterns |
| `FunctionalTermination(func=…)` | Custom predicate over delta messages returns True | Escape hatch for arbitrary logic |

**Composition.** Combine with `cond_a | cond_b` (OR — stop if either fires) and `cond_a & cond_b` (AND — stop only when both fired). After a run, conditions are *stateful* and must be `.reset()` before reuse — a footgun that has caused observed false-early-terminations in the wild.

**Reliability problems.** Issues [#133](https://github.com/microsoft/autogen/issues/133), [#581](https://github.com/microsoft/autogen/issues/581), [#1659](https://github.com/microsoft/autogen/issues/1659), [#3462](https://github.com/microsoft/autogen/issues/3462), [#5335](https://github.com/microsoft/autogen/issues/5335), [#6123](https://github.com/microsoft/autogen/issues/6123) all describe variations of the same problem: the combinatorial of (a) prompt-based TERMINATE, (b) GroupChatManager's speaker-selection LLM, and (c) message-history contamination produces flaky termination behavior that cannot be debugged from logs alone. Issue [#581](https://github.com/microsoft/autogen/issues/581) reports termination-condition lambdas (`x.get("content","").rstrip().endswith("TERMINATE")`) firing spuriously or failing to fire and remained unresolved.

**Idiomatic production setup.** Combine multiple termination conditions:

```
termination = (
    MaxMessageTermination(20)
    | TimeoutTermination(300)
    | FunctionCallTermination("finish")
)
```

That is: a cost backstop, a hang backstop, and a semantic stop — OR'd together. **Never rely on the semantic stop alone.**

## Convergence in debate

Du, Li, Torralba, Mordatch & Tenenbaum, ["Improving Factuality and Reasoning in Language Models through Multiagent Debate"](https://arxiv.org/abs/2305.14325) (ICML 2024) is the canonical multi-agent debate paper. Setup: **3 agents × 2 rounds**, chosen "due to computational cost." Results show monotone improvement with more agents (fixing rounds=2) on arithmetic; rounds beyond **4** produce "similar final performance" — the marginal-return curve flattens by round 4.

Wynn, Satija & Hadfield, ["Talk Isn't Always Cheap"](https://arxiv.org/abs/2509.05396) (5 Sep 2025), is the more pointed result. Across CommonSenseQA, MMLU, GSM8K with 3 models (GPT-4o-mini, LLaMA-3.1-8B, Mistral-7B):

- "Agent disagreement rate decreases as debate progresses" — and this **correlates with performance decline**, not improvement.
- More correct→incorrect transitions than incorrect→correct in later rounds: "a larger shift in agent responses from correct → incorrect answers (red) than incorrect → correct (green), indicating that debate can actively mislead agents."
- Agents that resisted a wrong answer in round 1 show "lower resistance to the social pressure from disagreement after round 2."
- Aggregate effect: **−1.2 to −12.0 percentage points** after debate on CommonSenseQA across heterogeneous configurations.

**When forced convergence is bad.**
- Models have asymmetric capability — the weaker model's errors propagate.
- Topic is value-laden (commonsense, ethics) — sycophantic dynamics dominate.
- Debate runs >2 rounds without an external grounding signal.

**Adaptive-break vs fixed-rounds.** Adaptive-break beats fixed-rounds when an external verifier exists, or when distributional stability detection (Beta-Binomial mixture / KS-test on judge consensus dynamics, per ["Multi-Agent Debate for LLM Judges with Adaptive Stability Detection"](https://openreview.net/forum?id=Vusd1Hw2D9)) preserves >99% accuracy with 30–60% compute reduction. Fixed-rounds beats adaptive when the only "convergence signal" is "agents agree" — because agreement *is* the failure mode there.

**Default for debate.** `max_rounds ≤ 4`. Allow adaptive break only on no-new-information signals (new arguments, new evidence cited) — never on agreement alone.

## Convergence in critic loops

Madaan et al., ["Self-Refine: Iterative Refinement with Self-Feedback"](https://arxiv.org/abs/2303.17651) (NeurIPS 2023): max **4 FEEDBACK-REFINE iterations**, terminated by a task-dependent `is_refinement_sufficient` function. Across 7 tasks, ~20% absolute improvement on average vs single-step generation. Code Optimization: 22.0 → 28.8 across 3 iterations. Sentiment Reversal: 33.9 → 36.8 across 3 iterations. **Largest gains in iterations 1–2; iteration 3+ yields diminishing or non-trivial-but-shrinking returns.**

Reflexion (Shinn et al., arXiv:2303.11366, NeurIPS 2023): improves HumanEval pass@1 to **91%** vs GPT-4's 80%. AlfWorld +22% absolute over 12 iterative steps; HotPotQA +20%; HumanEval +11%. The cycle "repeats until success or a trial limit is reached" — external verifier (test pass) is the primary terminator, with trial limit as backstop.

**Practical heuristics.**
- "Looks great" plateau is itself a stopping signal: when iteration N+1 produces feedback substantively similar to iteration N, halt.
- **Regression detection.** If iteration N+1 scores worse than N on the same rubric, *roll back to N* and terminate. Self-Refine's pattern of preferring the best output seen rather than always the latest is the right default.
- Default cap: **≤3 critic iterations.** Anthropic's [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) places evaluator-optimizer in their workflow taxonomy with the explicit caveat that it requires "clear evaluation criteria" and "demonstrated improvement through feedback" — and emphasizes "stopping conditions (such as a maximum number of iterations) to maintain control."
- Independent critic, not the producer. Same-agent producer-critic loops collapse into FM-3.3 incorrect verification (9.1%).

## Runaway loops in mesh and hierarchical topologies

Pathologies that emerge once agents talk to agents:

- **A→B→A cycles.** Agent A asks B a question; B responds with another question to A; A responds with a clarifying question to B. No external verifier ever fires.
- **Unbounded fan-out.** Each agent calls 3 sub-agents, each of which calls 3 more. Tree depth N produces 3^N agent invocations. Anthropic's [agent-teams docs](https://code.claude.com/docs/en/agent-teams) explicitly disallow nested teams ("teammates cannot spawn their own teams or teammates") to bound this.
- **Mesh chatter.** In a fully-connected N-agent mesh, each turn produces N(N−1) potential message edges. State explodes.

**LangGraph defenses.**
- Default `recursion_limit` = **25**, raises `GraphRecursionError` on overrun. Per the [troubleshooting doc](https://docs.langchain.com/oss/python/langgraph/errors/GRAPH_RECURSION_LIMIT): "circular edges (a→b→a) commonly trigger this." Override per-invocation: `graph.invoke({...}, {"recursion_limit": 100})`.
- Required checkpointer for swarm patterns — `create_swarm()` returns a `StateGraph` that must be `.compile()`'d with a checkpointer. Without it the swarm "would forget which agent was last active," producing state-divergent loops.
- Best practice from the LangGraph community: simple edges where possible; conditional edges only at real decision points; bounded cycles.

**Detection signals.**
- Same `(agent, tool, args)` triple repeats — emit a step-repetition warning (MAST FM-1.3 step repetition is **15.7%** of failures).
- Hop budget exceeded — count distinct agent transitions, not just messages.
- Cumulative tool calls exceed expected upper bound for the task type.

**Prevention.**
- Enforce hop budget in the orchestrator, not in agents.
- Idempotency check: dedupe identical tool calls at the orchestrator layer.
- Topology constraint: prefer DAG-shaped task graphs to mesh; if mesh required, cap edges per agent per round.

## Premature termination as the inverse failure

MAST FM-3.1 Premature termination = **6.2%** of all observed multi-agent failures: agents declare "done" before the work meets spec. Symptoms:

- Coding agent commits a stub then claims completion.
- Debate concludes after one agent agrees with another, without addressing the original question.
- Critic loop terminates because the critic lazily approves to avoid a token-expensive re-iteration.

Anthropic's agent-teams [troubleshooting note](https://code.claude.com/docs/en/agent-teams#lead-shuts-down-before-work-is-done) calls this out explicitly: "The lead may decide the team is finished before all tasks are actually complete. If this happens, tell it to keep going." The fix is verification gates:

- `TaskCompleted` hook in agent-teams: "Exit with code 2 to prevent completion and send feedback."
- Independent verifier agent: don't let the producer also be the judge.
- External grounding (tests, schema, lint) before allowing the terminate signal to fire.

**The tension.** Hard-cap termination protects against runaway; verification gates protect against premature stop. Both are needed; they pull in opposite directions, which is why they are typically AND'd together: terminate if `verifier_passes() AND iteration < N_max`, otherwise continue and possibly hit the budget cap with `incomplete=True`.

## Budget backstops and what to do when they fire

The unconditional last line of defense — fires regardless of model state.

- **Token budget.** Per-session, per-agent, per-round caps. AutoGen `TokenUsageTermination`. Anthropic `max_tokens` per call.
- **Wall-clock cap.** Especially for sub-agents whose tool calls might hang. AutoGen `TimeoutTermination`. Critical because *no semantic termination condition fires while a tool call is pending* — only wall-clock can recover from a stuck HTTP request or a livelocked subprocess.
- **Cost cap (dollar).** Aggregate across all sub-agents in a session.

**When the budget hits, do:**

1. **Return best-so-far** with explicit `incomplete=True` flag in the result envelope.
2. **Escalate to human** (or parent agent) with the partial state.
3. **Mark the task** in shared state so downstream consumers don't treat partial as final.
4. **Never silently truncate.** Silent truncation is the worst possible outcome — the caller believes they have a complete answer that is actually a midstream snapshot.

Anthropic's [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) addresses adjacent concerns (progress files, git checkpoints, feature-list state) but does not specify hard token/wall-clock budgets — that is left to the harness implementer.

## Cross-session and long-running agent termination

Anthropic's [agent-teams docs](https://code.claude.com/docs/en/agent-teams) describe a multi-session model with explicit graceful-shutdown semantics:

- **Lead-initiated shutdown.** "The lead sends a shutdown request. The teammate can approve, exiting gracefully, or reject with an explanation." Termination is *negotiated*, not unilateral.
- **Cleanup gating.** `Clean up the team` "checks for active teammates and fails if any are still running, so shut them down first." Prevents cleanup-during-execution races.
- **Slow-shutdown caveat.** "Teammates finish their current request or tool call before shutting down, which can take time." There is no hard kill at the team layer; you fall back to OS-level (`tmux kill-session`).
- **Hooks as termination guards.** `TaskCompleted` hook can `exit 2` to *block* a completion mark and force the teammate back to work — critical against FM-3.1 premature termination.
- **Known limitation.** "Lead shuts down before work is done" is documented as a recurring failure mode requiring user intervention.

**Rainbow deployments.** Per [Anthropic's Managed Agents engineering write-up](https://www.anthropic.com/engineering/managed-agents) and surrounding coverage: traditional stateless deployment (kill old, start new) is unsafe for long-running agents because forced interruption causes task failure. The solution is a progressive deployment strategy where new agent versions take new traffic while old versions complete in-flight tasks — analogous to blue-green/canary but with agent-session-aware drain semantics. The implication for skill design: **agent-team termination must be drainable, not just killable.**

## Composition recipes by framework

Concrete patterns. Apply directly; tune limits to your task profile.

### AutoGen GroupChat (production)

```python
from autogen_agentchat.conditions import (
    MaxMessageTermination,
    TimeoutTermination,
    FunctionCallTermination,
    SourceMatchTermination,
)

# Cost backstop + hang backstop + semantic stop, OR'd.
termination = (
    MaxMessageTermination(max_messages=20)
    | TimeoutTermination(timeout_seconds=300)
    | FunctionCallTermination(function_name="finish")
)

# After each run:
await termination.reset()
```

Why three: prompt-based termination is ~90% reliable in AutoGen production (FAQ-acknowledged); the message cap protects against billing runaway; the timeout protects against tool-call hangs that produce no messages.

### AutoGen Swarm with handoff

```python
termination = (
    MaxMessageTermination(max_messages=30)
    | TimeoutTermination(timeout_seconds=600)
    | HandoffTermination(target="user")
)
```

Handoff to user is a pause-and-wait signal, not a final stop — pairs with cost and hang backstops so the swarm cannot escape into infinite handoffs between agents that never reach the user gate.

### LangGraph swarm

```python
from langgraph.checkpoint.memory import MemorySaver
from langgraph_swarm import create_swarm

swarm = create_swarm(agents=[a, b, c], default_active_agent="a")
graph = swarm.compile(checkpointer=MemorySaver())  # required

result = graph.invoke(
    {"messages": [...]},
    config={
        "recursion_limit": 50,           # explicit override of default 25
        "configurable": {"thread_id": "session-1"},
    },
)
```

Wrap in a `try/except GraphRecursionError` that returns `{result: state.best_so_far, incomplete: true}` rather than letting the exception propagate as a 500.

### LangGraph with deepagents subagent middleware

```python
# Verify recursion_limit propagates to subagents — issue #1698 documents
# silent re-default to 25. Set it explicitly on every invocation.
state = main_agent.invoke(
    inputs,
    config={"recursion_limit": 100, "configurable": {"subagent_recursion_limit": 100}},
)
```

If the subagent middleware version pre-dates the fix, wrap subagent invocations in your own orchestrator and pass the limit through.

### Critic loop (framework-agnostic)

```python
best = None
best_score = -inf
for i in range(MAX_ITERS := 3):
    candidate = producer(task, prior=best)
    score = critic(candidate)               # independent agent
    if score >= PASS_THRESHOLD:
        return candidate                    # external-verifier stop
    if best is None or score > best_score:
        best, best_score = candidate, score
    elif score < best_score - REGRESSION_EPS:
        break                               # regression rollback
return best                                  # cap reached; best-so-far
```

Three guarantees: bounded iterations, regression rollback, best-so-far returned. Producer and critic must be different agents (FM-3.3 antidote).

### Debate (3-agent, 3-round, no convergence-stop)

```python
positions = [agent.initial(task) for agent in [a, b, c]]
for round in range(MAX_ROUNDS := 3):
    new_positions = [
        agent.respond(task, peers=positions, round=round)
        for agent in [a, b, c]
    ]
    if no_new_information(new_positions, positions):
        break                               # adaptive break on no-new-info ONLY
    positions = new_positions
return aggregator.synthesize(positions)     # majority vote, weighted, or judge
```

Note what is *absent*: no `if all(p == positions[0] for p in positions): terminate`. Agreement is not a stop signal in debate. The aggregator runs once at the end.

## Monitoring signals for runaway detection

Instrument these; alert on threshold breach. Fixing termination after a billing spike is more expensive than catching it live.

| Signal | What it means | Threshold heuristic |
|---|---|---|
| Same `(agent, tool, args)` triple in last K calls | Step repetition (MAST FM-1.3, 15.7% of failures) | K=3 identical → warn; K=5 → terminate |
| Hop count exceeds expected for task type | Unbounded mesh traversal | 2× expected → warn; 3× → terminate |
| Wall-clock per turn rising | Tool calls hanging or context bloat | p95 turn time > 60s → investigate |
| Token usage non-monotonic per turn | Context not pruned; history accumulating | Per-turn tokens > 2× prior → warn |
| `TimeoutTermination` firing in production | Tool hangs are the dominant exit | >5% of runs → fix the tool, not the cap |
| `MaxMessageTermination` firing in production | Semantic stop never fires | >10% of runs → semantic stop is broken; investigate |
| `FunctionCallTermination` never firing | Model isn't calling `finish()` | Add to system prompt; backstop with `MaxMessage` |
| Same conversation has multiple "TERMINATE" tokens | Predicate fired but loop continued, or contamination | Filter history before resuming |
| Sub-agent depth >2 | Nested-team violation | Hard error; agent-teams disallows nesting |
| Agreement rate rising in debate | Sycophancy converging on potentially wrong answer | Log; do not auto-terminate |

These are operational signals — log them per-run with the run ID so post-hoc analysis can correlate failure modes with topology, model, and prompt changes.

## Debugging termination failures

When a multi-agent run terminates wrong, work the diagnostic ladder in order. Stop at the first hit.

1. **Did it terminate too early or too late?**
   - Too early → premature termination (FM-3.1, 6.2%) or incorrect verification (FM-3.3, 9.1%).
   - Too late → unaware of termination conditions (FM-1.5, 12.4%) or no/incomplete verification (FM-3.2, 8.2%).

2. **Which condition fired?** Log the matched termination condition by name. AutoGen's composed conditions can fire with ambiguous attribution if you don't log per-condition state. Add structured logging:

   ```python
   for cond in [c1, c2, c3]:
       logger.info("term_check", extra={"name": type(cond).__name__, "matched": cond.terminated})
   ```

3. **For text-sentinel stops, scan history for token contamination.**
   - Did "TERMINATE" appear in any prior message before this run started?
   - Was history filtered when resuming from a checkpoint?
   - Does the system prompt itself mention the termination token? (Common — and it counts as history.)

4. **For function-call stops, did the model call the function?**
   - Inspect the last N tool-call records.
   - If the function was never called, fix the system prompt or switch to `MaxMessage` as primary.

5. **For external-verifier stops, did the verifier return correctly?**
   - Did the verifier itself error out (treated as "not passed yet")?
   - Did the verifier accept a stub or empty result? (FM-3.3.)

6. **For LangGraph `GraphRecursionError`, find the cycle.**
   - Use `graph.get_graph().draw_ascii()` to visualize.
   - Look for circular edges; a→b→a is the canonical pattern.
   - Per the troubleshooting doc: "circular edges (a→b→a) commonly trigger this."

7. **For wall-clock timeouts, find the hang.**
   - Per-tool-call latency histogram.
   - Outbound network calls without their own timeout will pin a sub-agent indefinitely.

8. **For "stopped on agreement" debate failures, audit the convergence trajectory.**
   - If correct→incorrect transitions outnumber incorrect→correct in later rounds, sycophancy is the cause (per "Talk Isn't Always Cheap"). Reduce rounds or remove agreement-stop.

9. **For AutoGen flaky stops, check `.reset()` was called.**
   - Stateful conditions carry state across runs. Inspect `cond.terminated` before each new run.

10. **If diagnostic ladder yields nothing**, dump the full message log + tool-call log + termination-condition state per turn and diff against a known-good run. Multi-agent termination bugs frequently emerge from interactions between three correct components, none of which is wrong in isolation.

## Decision triggers

Apply these as "If X, prefer Y because Z." Each row is actionable.

| If… | Then… | Because… |
|---|---|---|
| You have a critic loop / evaluator-optimizer | `max_iterations ≤ 3` by default; require evidence of measured rubric improvement to raise | Self-Refine and Reflexion show diminishing returns past iteration 2–3; regression risk past 4 |
| You have a debate | `max_rounds ≤ 4`; allow adaptive break on no-new-info; **never stop on agreement alone** | Du et al. plateau at round 4; "Talk Isn't Always Cheap" shows agreement-driven convergence is anti-correlated with accuracy |
| You have an AutoGen GroupChat or any group chat | Require **BOTH** `MaxMessageTermination` AND an explicit termination predicate, OR'd | Prompt-based termination is ~90% reliable; hard cap is the unconditional backstop (issues #133, #581) |
| You have a mesh / dynamic routing | Set a **hop budget** counted by the orchestrator, not by agents | Mesh edges grow N(N−1); agents cannot self-bound traversal |
| A stage produces no diff vs the previous stage | Terminate that stage and roll forward to the best output seen | Iteration without diff is a strong "settled" signal; preserves cost |
| The evaluator rubric is met | Terminate **immediately**, even if budget remains | External grounding beats internal heuristics; don't burn budget for marginal polish |
| Budget exhausted before completion | Return **best-so-far + `incomplete=True`**, never silently truncate | Silent truncation is unrecoverable; caller needs the signal to escalate |
| Termination is purely "agent emits TERMINATE" | Backstop with hard cap, or replace with function-call termination | Text-sentinel termination is unreliable (forgotten tokens, history contamination) |
| You're using LangGraph with cycles | Set explicit `recursion_limit`; require checkpointer for swarm | Default 25 is intentionally low; subagent middleware can silently revert to default (issue #1698) |
| Sub-agents may hang on tool calls | Add wall-clock `TimeoutTermination` at the sub-agent level | Semantic termination conditions don't fire during pending tool calls |
| The task has an external verifier (tests, schema, lint) | Use it as the primary terminator; everything else is a backstop | Reflexion's 91% pass@1 on HumanEval is the existence proof |
| The task has no external verifier and is value-laden | Avoid debate beyond 2 rounds; prefer single-pass + critic with regression rollback | Sycophancy compounds with rounds when there's no ground truth |
| Long-running agent across sessions | Use negotiated shutdown (lead requests; teammate approves/rejects); make it drainable, not killable | Forced interruption mid-task = wasted work; rainbow-deployment pattern |
| Producer also acts as verifier | Insert an independent judge agent | FM-3.3 incorrect verification (9.1%) — producers rationalize their own output |
| Sub-agent middleware in deepagents/LangGraph | Verify `recursion_limit` is propagated, not silently re-defaulted to 25 | Issue `langchain-ai/deepagents#1698` |

## Anti-patterns

Each of these has been observed in production systems and traced back to MAST failure modes.

1. **"Trust the model when it says it's done."** Worst single anti-pattern. ~10% of TERMINATE-style stops fail; in critic loops, sycophantic critics approve to avoid extra work. Always pair with a verifier or a hard cap.
2. **No termination predicate at all** ("the model knows when to stop"). Loops forever or until the API errors out.
3. **Hard cap so high it never fires** (`max_iterations=1000`). Effectively no cap; surfaces as billing surprises and unbounded latency.
4. **Termination at first agreement** in debate. Locks in convergence-driven failure; especially bad with heterogeneous-capability agents (per "Talk Isn't Always Cheap").
5. **Silent truncation when budget hits.** Returning a partial result without the `incomplete` flag means callers treat midstream state as final.
6. **Single termination condition for production group chats.** AutoGen issue tracker exists largely because users tried this. Always OR a hard cap.
7. **Termination predicate that reads message history without filtering** (`TextMentionTermination("TERMINATE")` on a resumed session containing prior "TERMINATE" tokens). Fires immediately on next turn.
8. **Same agent generates and verifies.** FM-3.3 incorrect verification (9.1% of MAST failures); the producer rationalizes its own output. Use an independent judge.
9. **Nested teams without a hop budget.** Each level multiplies cost; Anthropic's agent-teams doc disallows nesting precisely to prevent this.
10. **Using `recursion_limit` as the only mechanism** in LangGraph. The exception is raised — but if your graph wasn't designed to handle the exception, you've just converted an infinite loop into a crash with no partial result.
11. **Ignoring `TimeoutTermination` for tool-using agents.** Hung HTTP calls do not produce messages and therefore do not trigger message-count or token-count terminators. Wall-clock is the only saver.
12. **Promoting "convergence" to "correctness."** Stop predicates of the form `if all_agents_agree(): terminate` confuse social dynamics with epistemic ground truth.
13. **Forgetting to `.reset()` AutoGen termination conditions between runs.** Stateful predicates carry state across runs; produces false early terminations on the next invocation.

## Defaults to apply when unsure

When the task profile is ambiguous, use these defaults — they reflect the published research minima and the most common production setups.

- **Critic loop:** `max_iterations = 3`, regression rollback, independent critic, terminate immediately on rubric pass.
- **Debate:** `max_rounds = 3`, never stop on agreement, prefer odd-numbered agent counts to avoid ties.
- **AutoGen GroupChat:** `MaxMessageTermination(20) | TimeoutTermination(300) | FunctionCallTermination("finish")` — three conditions OR'd.
- **LangGraph cycles:** explicit `recursion_limit` set per-invocation; checkpointer required for any swarm; verify subagent middleware propagates the limit.
- **External verifier available:** use it as primary; cap and timeout as backstops only.
- **No external verifier, value-laden task:** single-pass + one critic round + regression rollback; do not debate.
- **Long-running cross-session:** negotiated shutdown only; drain in-flight tasks; rainbow-style deployment for version updates.
- **Budget hit:** return `{result: best_so_far, incomplete: true, reason: "budget_exhausted"}`; never silently truncate.
- **High-stakes irreversible action:** human-in-the-loop gate before the action, regardless of other termination signals.

## Sources

- Cemri et al. — "Why Do Multi-Agent LLM Systems Fail?" — MAST taxonomy, arXiv:2503.13657 (v3, 26 Oct 2025): https://arxiv.org/abs/2503.13657
- Wynn, Satija, Hadfield — "Talk Isn't Always Cheap: Understanding Failure Modes in Multi-Agent Debate" — arXiv:2509.05396 (5 Sep 2025; ICML MAS Workshop 2025): https://arxiv.org/abs/2509.05396
- Du et al. — "Improving Factuality and Reasoning in Language Models through Multiagent Debate" — arXiv:2305.14325 (ICML 2024): https://arxiv.org/abs/2305.14325
- Madaan et al. — "Self-Refine: Iterative Refinement with Self-Feedback" — arXiv:2303.17651 (NeurIPS 2023): https://arxiv.org/abs/2303.17651
- Shinn et al. — "Reflexion: Language Agents with Verbal Reinforcement Learning" — arXiv:2303.11366 (NeurIPS 2023): https://arxiv.org/abs/2303.11366
- Anthropic — "Building Effective Agents": https://www.anthropic.com/research/building-effective-agents
- Anthropic — "Effective harnesses for long-running agents": https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Anthropic — "Orchestrate teams of Claude Code sessions": https://code.claude.com/docs/en/agent-teams
- Anthropic — "Managed Agents" (rainbow deployments context): https://www.anthropic.com/engineering/managed-agents
- AutoGen AgentChat — Termination tutorial: https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/termination.html
- AutoGen issue #133 — "Use function call to detect termination signal in conversation": https://github.com/microsoft/autogen/issues/133
- AutoGen issue #581 — "Groupchat auto-terminate": https://github.com/microsoft/autogen/issues/581
- AutoGen issue #1659 — "Group Chat Manager Is Not Working Properly": https://github.com/microsoft/autogen/issues/1659
- AutoGen issue #3462: https://github.com/microsoft/autogen/issues/3462
- AutoGen issue #5335 — "Termination on Agent Selection": https://github.com/microsoft/autogen/issues/5335
- AutoGen issue #6123: https://github.com/microsoft/autogen/issues/6123
- LangGraph — GRAPH_RECURSION_LIMIT troubleshooting: https://docs.langchain.com/oss/python/langgraph/errors/GRAPH_RECURSION_LIMIT
- LangGraph — recursion-limit source troubleshooting doc: https://github.com/langchain-ai/langgraph/blob/main/docs/docs/troubleshooting/errors/GRAPH_RECURSION_LIMIT.md
- deepagents issue #1698 — `SubAgentMiddleware` does not propagate `recursion_limit`: https://github.com/langchain-ai/deepagents/issues/1698
- "Multi-Agent Debate for LLM Judges with Adaptive Stability Detection" — OpenReview: https://openreview.net/forum?id=Vusd1Hw2D9
- langgraph-swarm-py — checkpointer & state management: https://github.com/langchain-ai/langgraph-swarm-py
