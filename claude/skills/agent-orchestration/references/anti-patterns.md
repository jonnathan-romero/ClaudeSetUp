# Multi-Agent Anti-Patterns

The full catalog of failure modes when orchestrating sub-agents. Negative-rule-first. Each entry names the failure, gives recognition triggers from the literature, and prescribes a mitigation. SKILL.md lists the top 10; this file is the complete reference.

## Contents

- [When to consult this](#when-to-consult-this)
- [1. Premature decomposition](#1-premature-decomposition)
- [2. Agent sprawl / role inflation](#2-agent-sprawl--role-inflation)
- [3. Hallucinated handoffs](#3-hallucinated-handoffs)
- [4. Same-model critic / correlated blind spots](#4-same-model-critic--correlated-blind-spots)
- [5. Context loss at handoff](#5-context-loss-at-handoff)
- [6. Synthesis bottleneck](#6-synthesis-bottleneck)
- [7. Infinite / runaway loops](#7-infinite--runaway-loops)
- [8. Sycophantic chains](#8-sycophantic-chains)
- [9. Tools-instead-of-agents](#9-tools-instead-of-agents)
- [10. Cost blindness ("the swarm tax")](#10-cost-blindness-the-swarm-tax)
- [11. Determinism collapse](#11-determinism-collapse)
- [12. Premature parallelization](#12-premature-parallelization)
- [13. The "more is more" fallacy](#13-the-more-is-more-fallacy)
- [14. Orchestrator overload](#14-orchestrator-overload)
- [15. Lost-in-the-middle on stitched outputs](#15-lost-in-the-middle-on-stitched-outputs)
- [16. The 10-question STOP checklist](#16-the-10-question-stop-checklist)
- [MAST taxonomy mapping](#mast-taxonomy-mapping)
- [Triggers in conversation](#triggers-in-conversation)
- [Green-light pattern](#green-light-pattern)
- [Framework-specific traps](#framework-specific-traps)
- [Common defenses that do not work](#common-defenses-that-do-not-work)
- [How these anti-patterns compound](#how-these-anti-patterns-compound)
- [Escape-hatch playbook](#escape-hatch-playbook)
- [How to test these rules in practice](#how-to-test-these-rules-in-practice)
- [Sources](#sources)

## When to consult this

Read this before spawning a sub-agent, before invoking the Task/Agent tool more than once for related work, before recommending CrewAI / LangGraph / AutoGen / OpenAI Agents SDK / MetaGPT / ChatDev, and any time the user proposes "have agents debate," "have an agent review your work," or a multi-step orchestrator-worker layout. Skip for a single one-shot Task call where only the prompt content is in question.

The MAST taxonomy ([Cemri et al., arXiv:2503.13657](https://arxiv.org/abs/2503.13657)) categorizes multi-agent failures into three families — specification failures (~42%), inter-agent misalignment (~37%), and verification failures (~21%). The 16 anti-patterns below map onto those families: 1, 2, 4, 13 are specification failures; 3, 5, 6, 12, 14, 15 are inter-agent misalignment; 7, 8, 9, 10, 11 are verification and economic failures.

Default action when triggered: run the 10-question STOP checklist in §16. If any STOP fires, propose the single-agent alternative *with reasoning*, never silently. If the user explicitly overrides, proceed but require structured outputs with citations (mitigates #3) and a hard iteration cap (mitigates #7). The negative rules are sharper than the positive ones — when in doubt, stay single-agent.

## 1. Premature decomposition

**The failure:** Splitting a task into sub-agents *before* the task can be cleanly framed. Each sub-agent works on a misframed slice; the synthesis layer cannot detect the misframing because each report looks internally coherent. Result: a confidently-wrong answer with five sub-reports backing it.

**What it looks like:** Anthropic's semiconductor-shortage example is the canonical case — a one-line task ("research the semiconductor shortage") gets fanned out to subagents who independently choose a year, a region, and a sub-industry to focus on. Three of them pick differently. The synthesizer receives three internally-coherent reports about three different topics and produces a fourth that averages them.

**Recognition triggers:**
- You cannot write a single, unambiguous prompt that captures the whole task in one paragraph.
- The decomposition is "obvious" but you have not named the *interface* between sub-agents (inputs, outputs, what counts as done).
- You are choosing role names ("Researcher," "Critic," "Synthesizer") before you have a problem statement.
- Anthropic's own example: when lead agents gave "simple, short instructions like 'research the semiconductor shortage,'" subagents would *"misinterpret the task or perform the exact same searches as other agents"* — *"one subagent explored the 2021 automotive chip crisis while 2 others duplicated work investigating current 2025 supply chains."* ([Anthropic, How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system))

**Mitigation:**
- Write the single-agent prompt first. If you cannot yet write a clean single-agent prompt for the whole task, you cannot write clean sub-agent prompts either. Decomposing earlier just multiplies the ambiguity.
- Only decompose when the single-agent prompt itself reveals natural seams: distinct deliverables, distinct evidence sources, distinct success criteria.
- Name the *interface* — for each sub-agent, write down its inputs, its outputs, and one sentence of "what counts as done" — before you write its system prompt.
- If you cannot tell two proposed sub-agents apart by their done-criteria, collapse them into one.

## 2. Agent sprawl / role inflation

**The failure:** Tutorials in CrewAI/AutoGen routinely show 5-7 agents (Researcher, Writer, Editor, Critic, Manager, QA, Publisher) when 1-2 would do. Each handoff costs round-trip latency, context loss, and creates **ceremonial reviewers** that rubber-stamp because they have no fresh information to act on.

**What it looks like:** A "blog post pipeline" with Researcher → Writer → Editor → Critic → Publisher. The Editor reformats. The Critic says "looks good, here are minor suggestions." The Publisher renames the file. Four of five agents add no information; they just relay the Writer's output. Total cost: 5× the single-Writer baseline, with one extra source of error per stage.

**Recognition triggers:**
- An agent's contribution is just *"reformat,"* *"say it back,"* or *"approve."*
- A "Critic" agent's output is consistently *"Looks good, here are minor suggestions."*
- Two agents have overlapping system prompts (the difference is one adjective).
- You can describe a role only by listing what it forwards to the next role.
- Industry observation: *"Most applications don't need multi-agent systems — a single agent with good tools and a clear system prompt handles 80% of real-world use cases."*
- CrewAI specifically: *"abstracts away too much for complex use cases, and when agents need to share nuanced state or precise control over conversation flow, developers hit walls."*

**Mitigation:**
- If a role's output is mostly a rephrase of its input, delete the role.
- Collapse overlapping prompts into one richer agent.
- Reserve named roles for agents whose outputs are *different in kind*, not in framing.
- Sanity check: read each role's system prompt with the others' names redacted. If you cannot tell which role is which, the roles are inflated.
- Default to 1-3 agents. Reach for 5+ only with explicit cost/latency/quality justification.

## 3. Hallucinated handoffs

**The failure:** A sub-agent returns a confident summary that omits or **fabricates** load-bearing detail. The orchestrator treats the summary as ground truth and acts on it. Downstream work is silently corrupted because the original text is no longer in context to verify against.

**What it looks like:** A research subagent returns "Source X confirms Y." The orchestrator cites this in the final report. The actual source said "Y is debated; some authors argue Z." Nobody in the chain re-reads the source. The final report ships a misattributed claim.

**Recognition triggers:**
- Anthropic explicitly calls the multi-hop architecture a **"game of telephone,"** where information degrades through agent-to-agent communications.
- CriticGPT ([McAleese et al., OpenAI, arXiv:2407.00215](https://arxiv.org/abs/2407.00215)): *"Critics can have limitations of their own, including hallucinated bugs that could mislead humans into making mistakes,"* and the paper finds *"the rate of nitpicks and hallucinated bugs is much higher for models than for humans."*
- A sub-agent's summary contains specific numbers, names, or dates with no inline citation back to a source.

**Mitigation:**
- Force **verbatim quotes** with `file:line` (or URL+anchor) for any factual claim a sub-agent makes.
- Require structured outputs (JSON with explicit `evidence` fields) so missing citations are visible to the orchestrator.
- Spot-check a random subset of sub-agent claims by re-reading the source.
- Treat any sub-agent claim without a citation as **provisional**.
- Never let a sub-agent's summary become the new ground truth. Every load-bearing claim needs a re-checkable artifact.

## 4. Same-model critic / correlated blind spots

**The failure:** Generator and critic share training distribution and miss the same things. The critic confidently approves the same mistakes the generator made. "Have a sub-agent review your work" therefore produces sycophantic agreement, not adversarial signal.

**What it looks like:** The user says "have an agent double-check your work." Claude spawns a Task call with the same model and a "you are a careful reviewer" prompt. The reviewer reads the same code, reasons in the same way, arrives at the same blind spots, and writes "looks correct to me." A real bug ships, with two confident sign-offs. CriticGPT had to be specifically trained against this failure mode; off-the-shelf same-model critics are insufficient.

**Recognition triggers:**
- Generator and critic are the same model with the same temperature.
- Critic prompt says "find issues" without specifying *what kinds*.
- Critic approval rate is >90% (you are buying rubber stamps).
- CriticGPT (arXiv:2407.00215) had to be **specially trained** to find errors; an off-the-shelf same-model critic was inadequate. Even then: *"human-machine teams of critics and contractors catch similar numbers of bugs to LLM critics while hallucinating less than LLMs alone."* The takeaway: critic alone < human alone + critic.
- [Identity-bias paper, arXiv:2510.07517](https://arxiv.org/abs/2510.07517): *"sycophancy [is] far more common than self-bias"* — same-model agents do not even self-favor; they cave to whatever was said last.
- [Multi-LLM Debate, NeurIPS 2024](https://proceedings.neurips.cc/paper_files/paper/2024/hash/32e07a110c6c6acf1afbf2bf82b614ad-Abstract-Conference.html): *"similar model capabilities or responses can result in static debate dynamics where debate converges to majority opinion. When this majority opinion reflects a common misconception, debate is likely to converge to answers associated with that misconception."*

**Mitigation:**
- Use a structurally different model for the critic when possible (different family, different size, different post-training).
- Constrain the critic to a checklist of known failure types it must explicitly verify (e.g., "for each claim, cite the source line; flag any claim without a citation").
- Anonymize the critic's view of who said what — Identity-Bias paper (arXiv:2510.07517) finds anonymization measurably reduces sycophancy.
- Pair model critics with human spot-checks; OpenAI's CriticGPT result is that critic+human < critic alone in *hallucinated* bugs.
- Same-model self-critique is theater unless one of the above is in place.

## 5. Context loss at handoff

**The failure:** Sequential agents lose information that earlier agents had. Each handoff is **lossy compression**. Late-stage agents cannot fix decisions baked into earlier stages because they do not know the reasoning behind them.

**What it looks like:** Stage 1 (planner) reads the codebase and decides "we'll refactor by extracting a helper module." It passes a one-paragraph summary to stage 2 (implementer). Stage 2 implements, but the summary did not include the constraint that an existing public API must stay intact — that constraint was in the codebase context the planner had but the implementer does not. Stage 3 (reviewer) sees the broken API but cannot tell whether breaking it was intentional, because the original constraint never reached this far in the chain.

**Recognition triggers:**
- The orchestrator only sees sub-agent *summaries*, not their full traces.
- Late-stage agents ask "why did we do X?" and there is no answer in their context.
- Bug fixes require regenerating the entire upstream chain because the bug was baked into a decision two handoffs ago.
- Cognition ([Yan, Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents)) puts this as Principle 1: *"Share context, and share full agent traces, not just individual messages."*
- Anthropic's "game of telephone" framing is the same observation.
- ["Single-Agent LLMs Outperform Multi-Agent Systems on Multi-Hop Reasoning Under Equal Thinking Token Budgets" (arXiv:2604.02460)](https://arxiv.org/abs/2604.02460) grounds this in the **Data Processing Inequality**: *"every time information is summarized and handed off between different agents, there is a risk of data loss."*

**Mitigation:**
- Pass full agent traces, not just summaries, when downstream agents need to revisit decisions (Cognition Principle 1).
- If full traces will not fit downstream, the chain is too long — shorten it, not the trace.
- For unavoidable compression, preserve explicit citations so downstream agents can re-fetch the original on demand.
- Default to a single long-context agent when the task is short enough to fit.
- The Data Processing Inequality is hard math: information cannot be added by handoff, only lost or held constant.

## 6. Synthesis bottleneck

**The failure:** N parallel sub-agents return N reports, but the orchestrator cannot fit or reconcile them. Symptoms: orchestrator (a) picks one report and ignores the rest, (b) produces shallow stitching ("Agent 1 said X. Agent 2 said Y. Agent 3 said Z."), or (c) runs out of context before synthesizing.

**What it looks like:** Ten parallel research agents each return 4-page briefs. The orchestrator's context fills with 40 pages of sub-reports plus its own plan. Synthesis prose ends up 1.5 pages, quotes only agents 1, 2, and 10, and silently drops 3 through 9 — a textbook lost-in-the-middle interaction (#15) compounding the bottleneck.

**Recognition triggers:**
- Final synthesis is shorter than any one sub-report (signal you dropped most of them).
- Synthesis quotes only the first or last sub-agent (lost-in-the-middle).
- Orchestrator context usage >70% before synthesis even starts.
- Anthropic notes lead-agent context fills with sub-agent reports + plans + state, **degrading synthesis quality**.
- ["Lost in the Middle" (Liu et al., TACL 2024, arXiv:2307.03172)](https://arxiv.org/abs/2307.03172): performance is *"highest when relevant information occurs at the beginning or end of the input context, and significantly degrades when models must access relevant information in the middle."*

**Mitigation:**
- If the synthesis step cannot fit all sub-agent outputs comfortably (say, <50% of context), there are too many sub-agents or they are too verbose.
- Reduce sub-agent count first; force shorter structured outputs second.
- Use hierarchical reduction (pairwise merges) instead of flat stitching when N > 4.
- Give the synthesizer a checklist that names every sub-agent output, forcing acknowledgment of each.
- Consider a separate synthesis agent with a fresh context window receiving only the structured outputs.

## 7. Infinite / runaway loops

**The failure:** Critic loops with no termination. Debate that does not converge. Mesh topologies where agents call each other in cycles. Anthropic literally observed agents *"scouring the web endlessly for nonexistent sources"* and *"distracting each other with excessive updates."*

**What it looks like:** A "writer + critic" loop where the critic is the same model as the writer. Round 1 the critic finds three "issues." Round 2, after the writer addresses them, the critic finds three more (often new issues, not residual ones). Round 3, three more. The loop never terminates because the critic's job is "find issues" and there is always another nit available; quality plateaus or regresses after round 2.

**Recognition triggers:**
- Loop body has no explicit termination predicate beyond a counter.
- "Quality" is judged by the same model that is iterating — it can always find one more thing.
- Debate rounds keep producing new "concerns" without ever changing the verdict.

**Mitigation:**
- Hard iteration cap (e.g., max 3 critic rounds).
- Convergence detection: stop when the diff between rounds falls below threshold.
- Token budget per agent and per session.
- Default to "ship the current best" on timeout, not "keep iterating."
- Every loop needs a budget *and* a stopping rule that is not "the model says it's done."
- For debate loops, require new evidence (not just new framing) for any continued round; if no new evidence, stop.

## 8. Sycophantic chains

**The failure:** Each agent agrees with the prior agent. Disagreement decays over rounds. Role-played "debates" with the same model produce consensus that looks like deliberation but is just recency bias compounded.

**What it looks like:** "Set up two agents to debate whether to use approach A or B." Round 1: Agent A argues for A, Agent B argues for B. Round 2: Agent B concedes "you make a good point about X." Round 3: Agent A concedes "fair, B has merit too." Round 4: consensus on B because B spoke last. The debate looked rigorous; the verdict is recency, not deliberation. The Identity-Bias and Peacemaker papers both replicate this pattern across model families.

**Recognition triggers:**
- Round-N agent uses round-(N-1) agent's framing verbatim.
- Disagreements vanish after round 2 with no new evidence introduced.
- "Devil's advocate" agent volunteers concessions before being challenged.
- ["Talk Isn't Always Cheap" (arXiv:2509.05396)](https://arxiv.org/abs/2509.05396): *"agent disagreement rate decreases as debate progresses, and… this observation is correlated with performance degradation."*
- ["Peacemaker or Troublemaker" (arXiv:2509.23055)](https://arxiv.org/abs/2509.23055): sycophancy is the dominant force shaping multi-agent-debate outcomes.
- Identity-bias paper (arXiv:2510.07517): sycophancy >> self-bias in same-model debates.

**Mitigation:**
- "Have agents debate" is not a free win.
- Use **different models** for opposing sides — different family or different training run, not just different temperatures.
- **Anonymize** which agent said what so identity bias does not collapse the disagreement (Identity-Bias paper, arXiv:2510.07517).
- Apply **hard adversarial constraints**: the critic *must* identify three concrete defects with citations or fail the round; the defender *must* concede or counter each one with evidence.
- Track disagreement rate per round; if it falls below threshold without new evidence, stop the debate and ship the current best.

## 9. Tools-instead-of-agents

**The failure:** Spawning an LLM agent for work that should be a deterministic function call: parse JSON, run a script, query a DB, call an API, format a date, sort a list. Each LLM agent adds latency, tokens, and a chance to hallucinate the answer.

**What it looks like:** A "data formatter agent" whose entire job is "convert this CSV to JSON." A "calculator agent" that adds three numbers. A "sort agent." Each is an LLM call that introduces nondeterminism, latency, and token cost over a 3-line function. The work is closed-form; the agent is theatre.

**Recognition triggers:**
- The "agent's" job has a closed-form correct answer.
- A 5-line Python function would do it.
- The "agent" is wrapping a single tool call.
- The agent's prompt is "given X, return Y" with no judgment required.

**Mitigation:**
- If the work is deterministic, use a tool, not an agent.
- Agents are for tasks that require *judgment over open-ended input*.
- Anthropic's framing in the research-system post is consistent: agents add value when **search and judgment** are needed, not when execution is mechanical.
- Heuristic: if a 5-line Python function would do it, write the function.
- A single agent calling one tool is one agent and one tool — not "an agent for the tool."

## 10. Cost blindness ("the swarm tax")

**The failure:** Multi-agent uses ~15× tokens and N× wall-clock latency. Spawning multi-agent for low-stakes or short tasks burns money and patience for marginal or negative quality gain.

**What it looks like:** A user asks "what color should this button be?" An agent crew is spawned: Researcher (web-search recent UI trends), Critic (review the recommendation), Synthesizer (write up the final pick). Total cost: 15× a single-agent answer. Quality gain: zero — the answer was "use your accent color" either way.

**Recognition triggers:**
- Anthropic, verbatim: *"Multi-agent systems use about 15× more tokens than chats"* and *"agents typically use about 4× more tokens than chat interactions."* Their own conclusion: *"For economic viability, multi-agent systems require tasks where the value of the task is high enough to pay for the increased performance."*
- [VentureBeat](https://venturebeat.com/orchestration/are-you-paying-an-ai-swarm-tax-why-single-agents-often-beat-complex-systems) dubs this the **"swarm tax."**
- The task could be done in <30 seconds by one agent.
- The orchestration ceremony (planning, dispatch, synthesis) is longer than the actual work.

**Mitigation:** Run the "is this worth 15×?" check before spawning:
- Single-agent cost ≈ X tokens.
- Multi-agent cost ≈ 15X tokens, N× latency, M× failure modes.
- Does the marginal quality gain justify 15× tokens? For most coding/research turns: **no**.
- If the task could be done in <30s by one agent, do not multi-agent it. The orchestration overhead alone exceeds the work.
- Set a **per-session token budget** and a **per-agent token budget**; halt and surface a partial result on breach rather than silently overrunning.
- Multi-agent fits when *"the value of the task is high enough to pay for the increased performance"* (Anthropic). Stake that value before spawning, not after.

## 11. Determinism collapse

**The failure:** Multi-agent compounds nondeterminism. Small variations in sub-agent outputs cascade into wildly different final outputs. Hard to debug, hard to evaluate, hard to reproduce.

**What it looks like:** Two runs of the same multi-agent pipeline on the same input produce different final answers. A regression suite shows 30% diff between runs. Bisecting which agent introduced the divergence is impossible without persisted full traces, and even with traces the cause is often a small upstream rephrasing that branched the entire downstream chain. Anthropic invented rainbow deployments specifically because this class of system cannot be cut over safely.

**Recognition triggers (all verbatim from Anthropic):**
- *"Agents make dynamic decisions and are non-deterministic between runs, even with identical prompts. This makes debugging harder."*
- *"Agents are stateful and errors compound… When errors occur, we can't just restart from the beginning: restarts are expensive and frustrating for users."*
- *"Even with identical starting points, agents might take completely different valid paths to reach their goal."*
- *"Multi-agent systems have emergent behaviors, which arise without specific programming. For instance, small changes to the lead agent can unpredictably change how subagents behave."*

This forced Anthropic to invent **rainbow deployments** — running old and new versions simultaneously and shifting traffic gradually — because they could not safely cut over a stateful multi-agent system.

**Mitigation:**
- If you need reproducibility (regression tests, audit trail, A/B comparison), multi-agent is the wrong tool.
- Variance compounds at every junction. Use a single agent with temperature 0 and a deterministic toolchain instead.
- Persist full traces of each run if you must keep multi-agent — without traces you cannot diff runs, cannot bisect failures, and cannot safely roll out changes.
- Plan for rainbow-style deployment if you ship multi-agent to users: do not cut over a stateful agent system in place.

## 12. Premature parallelization

**The failure:** Forcing parallelism onto a task with hidden serial dependencies. Sub-agents end up duplicating or conflicting; synthesis must reconcile the conflicts painfully.

**What it looks like (Cognition's Flappy Bird parable):** A user asks for a Flappy Bird clone. Subagent 1 is told to build the background; subagent 2 is told to build the bird. Subagent 1 picks Mario-style green pipes and a blue sky. Subagent 2 picks a realistic-looking eagle. The synthesizer is handed two incompatible art styles and cannot repair the mismatch — the implicit "decide on an art direction" step was never assigned to anyone.

**Recognition triggers:**
- Sub-task A's output shape depends on sub-task B's choices.
- "We'll just merge later" with no defined merge protocol.
- Sub-agents need to make naming/style/structural decisions independently.
- Cognition's **Flappy Bird** parable: *"Subagent 1 and subagent 2 cannot see what the other was doing and so their work ends up being inconsistent with each other"* — one builds a Mario-style background, another makes incompatible bird sprites, the synthesizer cannot repair the mismatch. ([Yan, Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents))
- Anthropic explicitly warns: *"most coding tasks involve fewer truly parallelizable tasks than research."*

**Mitigation:**
- Parallelize only when sub-tasks share *no* implicit decisions. Coding is rarely such a task.
- If parallelization is mandatory, pre-decide all shared conventions (names, schemas, styles) in the orchestrator and pass them as constraints to every sub-agent.
- Define the merge protocol *before* spawning. "We'll figure out merge later" is a guarantee that synthesis will fail.
- When in doubt, sequence: agent 1 produces the design, agent 2 implements against it, agent 3 reviews against the same design.

## 13. The "more is more" fallacy

**The failure:** When a single agent's output is poor, the reflex is to add more agents (a critic, a planner, a verifier). Often the real fix is a **better single prompt**: clearer success criteria, better examples, the right tools, more context.

**What it looks like:** "The agent's plan was bad, let's add a planner agent." "The plan was still bad, let's add a critic for the planner." "The critic over-rejects, let's add a meta-critic." Three agents later, the output is still wrong, the cost is 3× the original, and the underlying issue — that the original prompt had no success criteria — remains unaddressed.

**Recognition triggers:**
- You are adding agents because the output is wrong, not because the task is genuinely composite.
- Each new agent's job is to compensate for the prior agent's flaw.
- You have not tried: better examples, better tools, better context, better success criteria — first.
- Industry observation: *"a single agent with good tools and a clear system prompt handles 80% of real-world use cases."*
- Anthropic's own escalation order — they fixed the *"spawning 50 subagents for simple queries"* problem with **better prompts**, not more agents.

**Mitigation:**
- Try improving the single-agent prompt twice before adding an agent.
- The escalation order is: better success criteria → better examples → better tools → better context → only then more agents.
- If the single agent still fails, the problem is usually the prompt or the context, not the architecture.
- Anthropic's own escalation order — they fixed the *"spawning 50 subagents for simple queries"* problem with **better prompts**, not more agents.

## 14. Orchestrator overload

**The failure:** Lead agent's context fills with: sub-agent reports + its own plan + intermediate state + tool outputs. By synthesis time, it is at 90% context utilization and synthesis quality collapses.

**What it looks like:** A research orchestrator dispatches 8 subagents, then ingests all 8 reports plus tool-call logs plus its own running scratchpad. By the time it goes to synthesize, the orchestrator is past 85% context. It produces a generic summary that cites only what is fresh in attention (the last 1-2 reports and its own most recent thought), drops the topics it acknowledged 20k tokens earlier, and tool calls near the end fail with truncated arguments.

**Recognition triggers:**
- Orchestrator's final output drops topics it acknowledged earlier in the run.
- Synthesis prose feels generic — the orchestrator stopped citing specifics.
- Tool errors near the end of the run that would not have happened earlier.
- The orchestrator hits context limits before the last sub-agent returns.

**Mitigation:**
- **Hierarchical compression**: sub-agent → summary → super-summary, with explicit citations preserved.
- **Structured intermediate state** in a scratchpad file/tool, not in context.
- A separate "synthesis-only" agent with a fresh context window that receives only the structured sub-agent outputs.
- Track orchestrator context usage. If it exceeds ~60% before synthesis, redesign — either fewer sub-agents, smaller reports, or a separate synthesizer.

## 15. Lost-in-the-middle on stitched outputs

**The failure:** Long stitched outputs from many agents suffer attention degradation. Reader (or downstream agent) misses middle sections. Compounds with synthesis bottleneck (#6) and orchestrator overload (#14).

**What it looks like:** Five sub-agent reports concatenated into one synthesis prompt. The synthesizer's final answer reflects reports 1 and 5 strongly, makes a passing reference to 2, and ignores 3 and 4 entirely. None of the dropped content was less important — it was just structurally positioned where attention degrades. Liu et al.'s U-shaped curve predicts exactly this.

**Recognition triggers:**
- ["Lost in the Middle" (Liu et al., TACL 2024, arXiv:2307.03172)](https://arxiv.org/abs/2307.03172): U-shaped performance curve — *"performance is often highest when relevant information occurs at the beginning or end of the input context, and significantly degrades when models must access relevant information in the middle."*
- Linked to the psychological serial-position effect.
- A synthesis prompt that concatenates >4 sub-agent reports without structural scaffolding.
- Final output reflects sub-agents 1 and N strongly but loses 2 through N-1.

**Mitigation:**
- Put the most critical sub-agent output **first or last** in the synthesis prompt.
- Force the synthesizer to produce a **per-source checklist** so middle sources cannot be silently dropped.
- Prefer hierarchical reduction (pairwise merges) over flat stitching.
- Do not concatenate >3-4 sub-agent outputs into a single synthesis prompt without structural scaffolding that forces attention to each one.

## MAST taxonomy mapping

The MAST taxonomy (Cemri et al., [arXiv:2503.13657](https://arxiv.org/abs/2503.13657)) gives the academic frame for the failure modes catalogued above. Three families, with the rough share of observed failures:

- **Specification failures (~42%):** the multi-agent system is asked to do something the agents cannot reliably scope. Anti-patterns: #1 premature decomposition, #2 agent sprawl, #4 same-model critic, #13 more-is-more.
- **Inter-agent misalignment (~37%):** agents do their jobs but cannot reconcile their work. Anti-patterns: #3 hallucinated handoffs, #5 context loss, #6 synthesis bottleneck, #12 premature parallelization, #14 orchestrator overload, #15 lost-in-the-middle.
- **Verification failures (~21%):** the system has no reliable way to know whether it is done or correct. Anti-patterns: #7 runaway loops, #8 sycophantic chains, #9 tools-instead-of-agents, #10 swarm tax, #11 determinism collapse.

Two implications:
- Specification failures are the largest single class. The cheapest place to prevent multi-agent failure is *before spawning* — by forcing yourself to write a single-agent prompt first (the test for #1).
- Verification is the smallest class but the most expensive when it goes wrong, because it produces silent corruption (#3, #4, #8). Mitigations here — citations, structurally different critics, anonymization — pay for themselves quickly.

## Triggers in conversation

Map verbal cues from the user (or your own draft) to the anti-pattern they predict:

| Verbal cue | Predicts |
|---|---|
| "Have an agent review your work" | #4 same-model critic, #8 sycophantic chains |
| "Spawn N agents in parallel to…" | #1 premature decomposition, #12 premature parallelization |
| "Have agents debate" | #4, #8, #7 infinite loops |
| "Use a CrewAI/AutoGen pipeline" | #2 agent sprawl, #5 context loss |
| "Have an agent format/parse/sort/fetch X" | #9 tools-instead-of-agents |
| "Add a planner agent to fix the plan" | #13 more-is-more |
| "We'll just merge the outputs later" | #12 premature parallelization, #6 synthesis bottleneck |
| "The result needs to be reproducible" | #11 determinism collapse (single-agent only) |
| "Loop the critic until it approves" | #7 runaway loops, #4 same-model critic |
| "Stitch the sub-agent reports together" | #6 synthesis bottleneck, #15 lost-in-the-middle |
| "Spawn 50 subagents for…" (Anthropic's own canary phrase) | #10 swarm tax, #1 premature decomposition |
| "Have a red team and a blue team…" | #4, #8 — sycophantic if same model; viable only with structurally different models |
| "Set up an evaluator-optimizer loop" | #7 runaway loops, #4 same-model evaluator |
| "Build it with CrewAI / AutoGen / MetaGPT / ChatDev" | #2 sprawl by default; the frameworks encourage it |
| "Have agents A, B, C each handle one subtask in parallel" | #12 parallelization, #6 synthesis bottleneck — verify there are no shared decisions first |
| "Recursively decompose the problem" | #1 premature decomposition, #5 context loss across hops |

When you hear these in the request — or catch yourself drafting them — run the STOP checklist before proceeding. Do not silently spawn; surface the relevant anti-patterns and propose the single-agent alternative with reasoning.

## 16. The 10-question STOP checklist

This is the operational core. Run through these **before** spawning a sub-agent or proposing a multi-agent layout. Block-by-default: any "yes" to a STOP trigger blocks multi-agent.

| # | Question | If answer suggests… | Then… |
|---|---|---|---|
| 1 | Could I do this in a single prompt that fits comfortably (<60%) in my context? | yes | **STOP. Single agent.** |
| 2 | Is the task small / low-stakes / under ~30s for a single agent? | yes | **STOP. Single agent.** |
| 3 | Are the sub-agents' outputs actually different *in kind*, or just rephrasings of each other? | rephrasings | **STOP. Consolidate roles (#2).** |
| 4 | Have I defined what "done" looks like for each sub-agent *and* for the synthesis step, in checkable terms? | no | **STOP. Define first; spawning before this is premature decomposition (#1).** |
| 5 | Can I afford ~15× tokens and N× latency for this task? | no | **STOP. Single agent (#10).** |
| 6 | Is the work deterministic (parse, run, format, fetch)? | yes | **STOP. Use a tool, not an agent (#9).** |
| 7 | Do the sub-tasks have hidden serial dependencies (one's output shape depends on another's choices)? | yes | **STOP. Don't parallelize (#12).** |
| 8 | Is this task primarily coding, or any task requiring shared context across decisions? | yes | **STOP. Single agent (Anthropic's own guidance).** |
| 9 | Would the sub-agents be the *same model* as me, asked to "review my work"? | yes | **STOP. Sycophantic / correlated blind spots (#4, #8).** |
| 10 | Do I need the run to be reproducible/auditable? | yes | **STOP. Determinism collapse (#11).** |

If any STOP fires, propose the single-agent alternative *with reasoning*, not silently. If the user explicitly overrides, proceed but apply the [Escape-hatch playbook](#escape-hatch-playbook) below — at minimum: structured outputs with citations (mitigates #3) and a hard iteration cap (mitigates #7).

The checklist is intentionally biased toward STOP. The asymmetry of harm is the reason: a wrongly-blocked multi-agent run costs you a few minutes of conversation; a wrongly-spawned multi-agent run can burn 15× tokens, ship silently corrupted output, and (in the worst case) cause a determinism collapse that takes hours to debug. When in doubt, stay single-agent and revisit if the single-agent attempt actually fails.

## Green-light pattern

Multi-agent is justified only when **all** of the following hold:

- Task is **research-shaped**: many independent leads, judgment over open-ended sources.
- Each sub-agent has a **clearly bounded, verifiable deliverable** with citation requirements.
- Total expected value justifies ~15× tokens.
- Synthesis step has a **real protocol** (checklist, structured merge), not "stitch and summarize."
- Sub-agents do **not** make implicit decisions that need to be consistent with each other (Cognition Principle 2).
- You can afford nondeterminism in the output.

**Examples that pass all six:**
- Surveying a literature for one specific question across 30+ papers — each paper is independent, deliverables are direct quotes with citations, no shared decisions.
- Pulling competitor pricing from N independent sources — each source is independent, output is structured (price + URL), no coordination needed.
- Generating M independent variants of a design and ranking them — variants are by construction independent; the ranker is the synthesis protocol.

**Examples that fail (and where they fail):**
- Building any non-trivial codebase (#5 context loss, #12 parallelization, Cognition's Flappy Bird).
- "Have an agent debate the design choice" (#4, #8 — at best produces sycophantic consensus).
- "Have an agent review the code" (#4 — same-model critic; pair with structurally different reviewer or human instead).
- Anything that needs to be reproducible (#11 determinism collapse).

The single sharpest heuristic, paraphrasing Anthropic's own scope guidance: multi-agent fits when *"the value of the task is high enough to pay for the increased performance"* and the work is naturally **parallel research-like**, not when sub-tasks must **share context or coordinate decisions**. Most coding tasks fail both tests.

## Framework-specific traps

The anti-patterns above show up reliably in the popular multi-agent frameworks. A short checklist when the user proposes one:

- **CrewAI.** Default templates ship 4-7 agent crews (Researcher / Writer / Editor / Critic / Manager). Recognition trigger #2 (agent sprawl) fires almost immediately. Industry observation about CrewAI specifically: *"abstracts away too much for complex use cases, and when agents need to share nuanced state or precise control over conversation flow, developers hit walls."* Push back on crew-size before adopting a template; ask which agents have outputs that are *different in kind*.
- **AutoGen.** Conversation-driven multi-agent. Risk profile leans toward #7 runaway loops (chats can spiral) and #5 context loss (each conversation turn is a handoff). Cap turns hard; persist full conversation logs.
- **LangGraph.** Graph topology can encourage mesh patterns and cycles. Risk profile: #7 runaway loops if cycles are unbounded; #11 determinism collapse if state nodes mutate non-deterministically.
- **OpenAI Agents SDK.** Tool-call-centric, lower risk of sprawl, but tool-instead-of-agents (#9) is easy to get wrong if a tool is wrapped as an agent for "consistency."
- **MetaGPT / ChatDev.** Role-driven simulated organizations. Almost every MAST-class failure shows up at scale: specification (#1, #2), inter-agent (#5, #6, #12), verification (#7, #8). Use only for research / demos, not production work that needs reproducibility.

The frameworks are not the problem — the templates and the implicit defaults are. Whatever the framework, run the STOP checklist before instantiating it.

## Common defenses that do not work

Patterns that look like they should fix the anti-patterns but do not, in practice:

- **"We'll prompt the critic to be harsher."** A same-model critic with a harsher prompt is still the same model with the same blind spots. Harshness produces more nitpicks, not better catches (CriticGPT specifically: hallucinated bug rate is *much higher* for models than for humans, regardless of prompt).
- **"We'll have three agents vote."** Voting helps only when the votes are independent. Same model + similar prompts = correlated errors = the majority is often confidently wrong (Multi-LLM Debate, NeurIPS 2024: debate "converges to majority opinion. When this majority opinion reflects a common misconception, debate is likely to converge to answers associated with that misconception.").
- **"We'll add another summarization pass."** Summarization compounds the Data Processing Inequality. Each pass loses information. The fix is shorter chains, not more compression.
- **"We'll let the orchestrator decide when to stop."** The orchestrator is the same model that's running the loop. It will always find one more thing. Termination must be external (counter, budget, convergence threshold).
- **"We'll have agents debate longer."** "Talk Isn't Always Cheap" finds disagreement decreases as debate progresses, *correlated with performance degradation*. More rounds make it worse, not better.
- **"We'll use different temperatures."** Temperature variation does not produce structurally different reasoning. Same model + different temperature ≠ different perspective.
- **"We'll add a verifier agent at the end."** A verifier with no fresh information cannot verify. Either the verifier re-does the work (expensive) or it rubber-stamps (useless).

## How these anti-patterns compound

The 16 are not independent. They cluster and amplify each other; recognizing one is usually a signal that two or three more are present.

- **Premature decomposition (#1) → agent sprawl (#2) → orchestrator overload (#14).** A misframed task generates more roles to compensate for the missing frame; more roles produce more output that floods the orchestrator's context.
- **Hallucinated handoffs (#3) → context loss (#5) → lost-in-the-middle (#15).** Each handoff is a fresh chance to lose detail, and stitched outputs hide the loss in the middle of the synthesis prompt.
- **Same-model critic (#4) → sycophantic chains (#8) → infinite loops (#7).** A same-model critic produces approving rounds that never converge to a real verdict; the loop runs until a counter trips.
- **Tools-instead-of-agents (#9) → cost blindness (#10) → determinism collapse (#11).** Wrapping deterministic work in an agent multiplies cost *and* introduces variance the deterministic version did not have.
- **Premature parallelization (#12) → synthesis bottleneck (#6) → "more is more" (#13).** Parallel sub-agents make conflicting choices; the synthesizer cannot reconcile them; the response is to add a reconciliation agent rather than fix the parallelization.

When you find yourself reaching for one anti-pattern's mitigation, scan the cluster it sits in. Fixing only the visible symptom usually leaves the rest of the cluster intact.

## Escape-hatch playbook

When the user has already overridden a STOP and insists on multi-agent, harden the run with these mitigations rather than refusing:

1. **Force structured outputs with citations.** Every sub-agent must return JSON with explicit `claim`, `evidence`, and `source` fields. Reject (or re-prompt) any sub-agent return with missing citations. (Mitigates #3 hallucinated handoffs.)
2. **Cap iteration counts hard.** `max_rounds = 3` for any critic/debate loop. On hitting the cap, ship the current best — do not keep iterating. (Mitigates #7 runaway loops.)
3. **Cap token budgets per agent and per session.** On breach, halt and surface the partial result. (Mitigates #10 swarm tax.)
4. **Persist full traces.** Store every sub-agent's full input and output to disk so the run is reproducible-ish and bisectable. (Mitigates #11 determinism collapse.)
5. **Use structurally different critics.** A critic must be a different model family from the generator, or constrained to a verifiable checklist (not "find issues"). (Mitigates #4 same-model critic.)
6. **Pre-commit shared conventions.** Before any parallel sub-agent spawns, the orchestrator writes down naming, schema, and style decisions. Sub-agents receive these as constraints, not as choices. (Mitigates #12 premature parallelization.)
7. **Force per-source acknowledgment in synthesis.** The synthesis prompt requires the synthesizer to produce a checklist with one row per sub-agent output, naming what was used and what was discarded. (Mitigates #6 synthesis bottleneck and #15 lost-in-the-middle.)
8. **Track orchestrator context utilization.** If it crosses 60% before synthesis, abort and re-run with fewer sub-agents or a separate synthesizer. (Mitigates #14 orchestrator overload.)
9. **Anonymize debate participants.** When pairing critic/defender, hide identity tags so identity bias cannot collapse disagreement. (Mitigates #8 sycophantic chains.)
10. **Stake the value of the task.** Before spawning, write down what quality gain justifies the 15× token cost. If you cannot, do not spawn. (Mitigates #10 swarm tax.)

These do not turn a bad multi-agent layout into a good one. They turn a bad layout into a *recoverable* one — failures will at least be visible, citable, and re-runnable.

## How to test these rules in practice

Run a single experiment whenever you are unsure:

1. Solve the task with a single agent. Note time, tokens, and a quality score (rubric or self-assessment).
2. Solve the same task with the proposed multi-agent layout. Note the same.
3. Compute the ratio: `(quality_multi - quality_single) / (cost_multi / cost_single)`.
4. Multi-agent only justifies itself when this ratio is positive *and* the absolute quality gain is large enough to matter for the use case.

In the brief's terms: multi-agent is paying for ~15× tokens. If the quality gain is not visible in side-by-side comparison, the gain is not real and the cost is. Most experiments end here, with the single agent winning.

A second test: re-run the proposed multi-agent layout three times on the same input. If the three outputs disagree materially, you have determinism collapse (#11) — even if quality is acceptable on any single run, the system is not safe to ship for any use case that needs reproducibility, regression testing, or audit trail.

A third test: hand the multi-agent run's full traces to a human reader. If the human can immediately point to a sub-agent claim that has no source, you have hallucinated handoffs (#3) and the run's "quality" was overstated by exactly that much.

These three tests — quality-vs-cost ratio, determinism check, and source-traceability check — between them catch most of the 16 anti-patterns. Run them before adopting any multi-agent layout into ongoing work.

## Sources

- [How we built our multi-agent research system — Anthropic (Jun 2025)](https://www.anthropic.com/engineering/built-multi-agent-research-system)
- [Don't Build Multi-Agents — Walden Yan, Cognition (Jun 12, 2025)](https://cognition.ai/blog/dont-build-multi-agents)
- [LLM Critics Help Catch LLM Bugs (CriticGPT) — McAleese et al., OpenAI, arXiv:2407.00215](https://arxiv.org/abs/2407.00215)
- [LLM Critics paper PDF — OpenAI](https://cdn.openai.com/llm-critics-help-catch-llm-bugs-paper.pdf)
- [Why Do Multi-Agent LLM Systems Fail? (MAST taxonomy) — Cemri et al., arXiv:2503.13657](https://arxiv.org/abs/2503.13657)
- [Improving Factuality and Reasoning in Language Models with Multiagent Debate — Du, Li, Torralba, Tenenbaum, Mordatch](https://composable-models.github.io/llm_debate/)
- [Talk Isn't Always Cheap: Understanding Failure Modes in Multi-Agent Debate, arXiv:2509.05396](https://arxiv.org/abs/2509.05396)
- [Peacemaker or Troublemaker: How Sycophancy Shapes Multi-Agent Debate, arXiv:2509.23055](https://arxiv.org/abs/2509.23055)
- [Multi-LLM Debate: Framework, Principals, and Interventions — NeurIPS 2024](https://proceedings.neurips.cc/paper_files/paper/2024/hash/32e07a110c6c6acf1afbf2bf82b614ad-Abstract-Conference.html)
- [Measuring and Mitigating Identity Bias in Multi-Agent Debate via Anonymization, arXiv:2510.07517](https://arxiv.org/abs/2510.07517)
- [Single-Agent LLMs Outperform Multi-Agent Systems on Multi-Hop Reasoning Under Equal Thinking Token Budgets, arXiv:2604.02460](https://arxiv.org/abs/2604.02460)
- [Lost in the Middle: How Language Models Use Long Contexts — Liu et al., TACL 2024, arXiv:2307.03172](https://arxiv.org/abs/2307.03172)
- [Are you paying an AI 'swarm tax'? — VentureBeat](https://venturebeat.com/orchestration/are-you-paying-an-ai-swarm-tax-why-single-agents-often-beat-complex-systems)
- [Single vs Multi-Agent System? — Phil Schmid](https://www.philschmid.de/single-vs-multi-agents)
