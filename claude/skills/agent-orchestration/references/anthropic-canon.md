# Anthropic Canon: Verbatim Quotes and Load-Bearing Numbers

Lookup reference for citations. Every quote here is verbatim from the linked Anthropic source and is keyed to where it gets cited in SKILL.md and the other reference files. Topic-organized, not post-organized.

## Contents

- [How to use this file](#how-to-use-this-file)
- [The multi-agent research architecture](#the-multi-agent-research-architecture)
- [The 90.2% benchmark claim](#the-902-benchmark-claim)
- [Token economics: 4x, 15x, 80% variance](#token-economics-4x-15x-80-variance)
- [The four-part sub-agent contract](#the-four-part-sub-agent-contract)
- [The semiconductor shortage failure example](#the-semiconductor-shortage-failure-example)
- [What multi-agent does NOT help with](#what-multi-agent-does-not-help-with)
- [Engineering lessons](#engineering-lessons)
- [Building Effective Agents taxonomy](#building-effective-agents-taxonomy)
- [Claude Code subagent guidance](#claude-code-subagent-guidance)
- [Single-level fan-out enforcement](#single-level-fan-out-enforcement)
- [Inheritance pitfalls](#inheritance-pitfalls)
- [Memory tool and context engineering](#memory-tool-and-context-engineering)
- [Effective harnesses for long-running agents](#effective-harnesses-for-long-running-agents)
- [Sources](#sources)

## How to use this file

When SKILL.md or another reference asserts an Anthropic claim ("90.2% improvement", "15x tokens", "the four-part contract", "single-level fan-out"), pull the verbatim quote from this file plus the source link. Do not paraphrase Anthropic's load-bearing numbers in citations — quote them. The "use this when citing" line under each block tells you which decision the quote backs.

## The multi-agent research architecture

The orchestrator-worker pattern (lead Claude Opus 4 plus parallel Claude Sonnet 4 subagents plus a CitationAgent) is the canonical multi-agent shape Anthropic ships in production.

### Orchestrator + parallel sub-agents

> "Our system introduces two kinds of parallelization: (1) the lead agent spins up 3-5 subagents in parallel rather than serially; (2) the subagents use 3+ tools in parallel."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: "Two-layer parallelism" — fan-out at the orchestrator and at the worker. Justifies recommending parallel tool calls inside each subagent, not just parallel subagent spawn.

### Time savings claim

> "These changes cut research time by up to 90% for complex queries."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: latency benefit of orchestrator-worker on breadth-first tasks. Pair with the 15x token cost — speed is bought with tokens.

### Lead agent saves the plan to external memory

> "If the context window exceeds 200,000 tokens it will be truncated and it is important to retain the plan."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: why the orchestrator must persist its plan to a file/memory tool before spawning subagents. Justifies the `claude-progress.txt` / external-memory pattern in long-running harnesses.

### Subagent isolation and condensed return

> "Subagents operate in parallel with their own context windows, exploring different aspects of the question simultaneously."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: why intermediate tool results never pollute the parent — the only thing returning to the lead is the subagent's final summary message.

### Artifact storage pattern

> "Implement artifact systems where specialized agents can create outputs that persist independently. Subagents call tools to store their work in external systems, then pass lightweight references back to the coordinator."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: avoiding "information loss during multi-stage processing and reduces token overhead from copying large outputs through conversation history." This is the design rule for outputs larger than a return-message can carry.

### CitationAgent as a specialized post-processor

> "Once the LeadResearcher has gathered enough information, it hands off to the CitationAgent, which processes the documents and research report to identify specific locations for citations."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: specialized agent for one bounded job (citation attribution), invoked after the main loop converges. Pattern for: "spin a small dedicated agent for a final pass."

### Synchronous-execution caveat

> "Our current system executes subagents synchronously, meaning the lead agent waits for each set of subagents to complete before proceeding. This makes coordination simpler, but creates bottlenecks in information flow between agents. For instance, the lead agent can't steer subagents, subagents can't coordinate, and the entire system can be blocked while waiting for a single subagent to finish."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: why real-time mid-flight coordination is currently out of scope. The orchestrator dispatches, waits, and synthesizes — there is no back-channel.

## The 90.2% benchmark claim

The headline number, with the caveats Anthropic explicitly attaches to it.

### Verbatim claim

> "Internal evaluations show that multi-agent research systems excel especially for breadth-first queries that involve pursuing multiple independent directions simultaneously. We found that a multi-agent system with Claude Opus 4 as the lead agent and Claude Sonnet 4 subagents outperformed single-agent Claude Opus 4 by 90.2% on our internal research eval."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the only Anthropic-published headline number for multi-agent vs single-agent on research tasks. Always include the caveats below — never quote 90.2% without them.

### Caveat: internal eval, not public benchmark

> "We started with about 20 queries representing real usage patterns."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the eval is Anthropic's internal research eval, not BrowseComp or any public benchmark. Eval set started small.

### Caveat: small N is fine for large effects

> "With effect sizes this large, you can spot changes with just a few test cases."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: justification for the small N. Also reusable as a general eval-engineering principle: don't wait for hundreds of cases when the effect is big.

### Example task class

> "An example would be requests to identify all the board members of the companies in the Information Technology S&P 500."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the canonical illustration of a "breadth-first research task" — many independent sub-questions, each cheap, with no shared state.

### BrowseComp public number

> "We achieved 86.8% on BrowseComp."

[Eval awareness in Claude Opus 4.6's BrowseComp](https://www.anthropic.com/engineering/eval-awareness-browsecomp)

Use this when citing: the public-benchmark figure for Anthropic's multi-agent harness on browsing tasks. Pair with the 80% variance result below.

## Token economics: 4x, 15x, 80% variance

The cost framing for whether multi-agent is even on the table.

### 4x and 15x

> "In our data, agents typically use about 4x more tokens than chat interactions, and multi-agent systems use about 15x more tokens than chats."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the cost ratio for any multi-agent decision. The 15x is the floor — high-fan-out runs cost more.

### Economic-viability rule

> "Multi-agent systems require tasks where the value of the task is high enough to pay for the increased performance."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the dollar-value test. If the answer isn't worth roughly 15x a chat answer, do not spawn the team.

### 80% of variance is token usage

> "Three factors explained 95% of the variance in our analysis. Token usage by itself explains 80% of the variance, with the number of tool calls and the model choice as the two other explanatory factors."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: multi-agent's primary mechanism is "spend enough tokens" — across many parallel context windows — not magical coordination. Justifies the framing "multi-agent is a way to spend more useful tokens before context degrades."

### Effort-budget heuristic

> "Simple fact-finding requires just 1 agent with 3-10 tool calls, direct comparisons might need 2-4 subagents with 10-15 calls each, and complex research might use more than 10 subagents with clearly divided responsibilities."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: concrete team-size and tool-call budgets per task class. This is the closest Anthropic comes to a sizing table — embed it directly in orchestrator prompts.

## The four-part sub-agent contract

The single most load-bearing prompt-engineering rule for orchestrators.

### Verbatim contract

> "Each subagent needs an objective, an output format, guidance on the tools and sources to use, and clear task boundaries."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the four required fields for every subagent invocation. Missing any one of these produces the failure modes in the next section.

### Why this matters (orchestrator's job)

> "Just as a new employee joining a company needs careful onboarding to become productive, research agents need detailed prompts to perform well at the start. The lead agent needs to give them clear directions on what to do."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: framing the orchestrator's prompt-writing job as "onboarding a new employee." Useful pedagogy when teaching the four-part contract.

## The semiconductor shortage failure example

Concrete demonstration of what happens when the four-part contract is skipped.

### The failure

> "When asked to research the semiconductor shortage, the lead agent might delegate to subagents in vague terms — for example, telling one subagent to research the 2021 chip crisis and another to investigate current 2025 chip shortages. Without specific guidance, agents can duplicate work, leave gaps, or fail to find necessary information."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: canonical illustration of duplicate-work failure when objectives aren't crisply scoped. Cite alongside the four-part contract — this is what a missing "task boundaries" field looks like in practice.

## What multi-agent does NOT help with

Anthropic's own admission of the boundaries.

### Coding tasks

> "Some domains that require all agents to share the same context or involve many dependencies between agents are not a good fit for multi-agent systems today. For instance, most coding tasks involve fewer truly parallelizable tasks than research, and LLM agents are not yet great at coordinating and delegating to other agents in real time."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the most important "do not use" rule. Coding has high inter-file dependency and shared mutable state — the wrong shape for fan-out. This is the quote to pull when a user asks "should I spawn a team for this refactor?"

### Documented anti-patterns

> "Early agents made errors like spawning 50 subagents for simple queries, scouring the web endlessly for nonexistent sources, and distracting each other with excessive updates."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the failure-mode catalog for naive orchestrators. Justifies hard caps on team size and termination criteria.

### Why scale-up alone isn't a fix

> "While we expect agents to improve at coordination over time, this means current systems work best with these constraints in mind."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the limitations are present-day, not architectural-forever. Useful when explaining why design rules will shift as model capabilities shift.

## Engineering lessons

The operational rules Anthropic surfaces from running the system in production.

### Rainbow deployments

> "Agentic systems are highly stateful webs of prompts, tools, and execution logic that run almost continuously. This means that whenever we deploy updates to our agents, they may be at any point in their process. We therefore need to prevent our well-meaning code changes from breaking existing agents. We can't constantly stop the entire system for updates either. So we use 'rainbow deployments' to avoid disrupting running agents, by gradually shifting traffic from old to new versions while keeping both running simultaneously."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: deployment rule for any long-running agent system. In-flight runs can be hours deep — never atomic-swap.

### "20 queries is enough"

> "We frequently encounter pushback on small sample sizes, but we encourage starting small with about 20 queries and iterating quickly."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: justification for shipping eval with 20 cases. Pair with the "with effect sizes this large" quote above.

### Evaluate end-state, not process

> "Many evaluation approaches expect that the AI will follow the same steps each time. For example, given input X, the system should follow path Y to produce output Z. But multi-agent systems don't work this way. Even with identical starting points, agents might take completely different valid paths to reach the same goal."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: why traditional path-based testing breaks for non-deterministic agents. Grade the answer, not the trajectory.

### LLM-as-judge rubric

> "An LLM judge evaluating outputs against a rubric — judging factual accuracy, citation accuracy, completeness, source quality, and tool efficiency — works well for grading research outputs."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the five-dimension rubric for grading research-style multi-agent output.

### Self-improving prompts

> "Claude 4 models can be excellent prompt engineers. When given a prompt and a failure mode, they are able to diagnose why the agent is failing and suggest improvements."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: justification for using a Claude-as-prompt-engineer loop on failing subagent prompts. The tool-testing-agent pattern that yielded a 40% reduction in task completion time grew from this.

### Tool-testing agent

> "We even created a tool-testing agent — when given a flawed MCP tool, it attempts to use the tool and then rewrites the tool description to avoid failures. By testing the tool dozens of times, this agent found key nuances and bugs."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: pattern for self-improving tool documentation. Run a Claude agent against the tool surface to surface description bugs.

### Non-determinism is the debugging cost

> "Agents make dynamic decisions and are non-deterministic between runs, even with identical prompts. This makes debugging harder."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: why "just rerun it" doesn't reproduce bugs. Justifies full production tracing of decision patterns.

### Checkpointed durable execution

> "Durable execution... lets agents resume from where they were when failures occurred."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: never restart a multi-hour run from scratch. Checkpoint state and resume.

### Prompt as program

> "Prompting is the primary lever for shaping their behavior."

[How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

Use this when citing: the implicit thesis behind treating system prompts with code-change rigor. Minor edits cascade into large behavioral changes.

## Building Effective Agents taxonomy

The decision-rule bible for choosing a shape: workflow vs agent, and which workflow.

### Workflows vs agents

> "Workflows are systems where LLMs and tools are orchestrated through predefined code paths. Agents, on the other hand, are systems where LLMs dynamically direct their own processes and tool usage, maintaining control over how they accomplish tasks."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: the foundational distinction. Anything orchestrated by code is a workflow; anything orchestrated by an LLM at runtime is an agent.

### When to use which

> "Workflows offer predictability and consistency for well-defined tasks, whereas agents are the better option when flexibility and model-driven decision-making are needed at scale."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: the core selection rule. Pair with the simplicity quote below — workflows first, agents only when needed.

### Simplicity first

> "When building applications with LLMs, we recommend finding the simplest solution possible, and only increasing complexity when needed. This might mean not building agentic systems at all. Agentic systems often trade latency and cost for better task performance, and you should consider when this tradeoff makes sense."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: the bias toward single LLM call > workflow > agent. The "consider when this tradeoff makes sense" line backs cost-aware escalation.

### Single LLM call as default

> "For many applications, however, optimizing single LLM calls with retrieval and in-context examples is usually enough."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: don't reach for orchestration when retrieval-augmented single calls suffice.

### Workflow: prompt chaining

> "Prompt chaining decomposes a task into a sequence of steps, where each LLM call processes the output of the previous one. You can add programmatic checks (see 'gate' in the diagram below) on any intermediate steps to ensure that the process is still on track. Use this workflow when the task can be easily and cleanly decomposed into fixed subtasks."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: the chaining pattern. Examples Anthropic gives: outline-then-write, translate-then-check.

### Workflow: routing

> "Routing classifies an input and directs it to a specialized followup task. This workflow allows for separation of concerns, and building more specialized prompts. Without this workflow, optimizing for one kind of input can hurt performance on other inputs."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: routing pattern, including cost-tier routing (Haiku vs Sonnet vs Opus by complexity).

### Workflow: parallelization (sectioning and voting)

> "LLMs can sometimes work simultaneously on a task and have their outputs aggregated programmatically. This workflow, parallelization, manifests in two key variations: Sectioning: Breaking a task into independent subtasks run in parallel. Voting: Running the same task multiple times to get diverse outputs."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: the two flavors of parallelization. Sectioning when subtasks differ; voting when diverse opinions on the same task help.

### Workflow: orchestrator-workers

> "In the orchestrator-workers workflow, a central LLM dynamically breaks down tasks, delegates them to worker LLMs, and synthesizes their results. This workflow is well-suited for complex tasks where you can't predict the subtasks needed."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: this is the multi-agent research system pattern. The defining contrast with parallelization-sectioning: subtasks aren't known upfront — the orchestrator decides at runtime.

### Workflow: evaluator-optimizer

> "In the evaluator-optimizer workflow, one LLM call generates a response while another provides evaluation and feedback in a loop. This workflow is particularly effective when we have clear evaluation criteria, and when iterative refinement provides measurable value."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: critic-loop pattern. Pre-conditions: verbalized criteria, demonstrable lift from iteration.

### Pure agents

> "Agents can be used for open-ended problems where it's difficult or impossible to predict the required number of steps, and where you can't hardcode a fixed path. The LLM will potentially operate for many turns, and you must have some level of trust in its decision-making. Agents' autonomy makes them ideal for scaling tasks in trusted environments. The autonomous nature of agents means higher costs, and the potential for compounding errors."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: when to escalate past workflow into full agent. The tradeoff: autonomy buys flexibility; pays in cost and error compounding.

### Agent-Computer Interface (ACI) discipline

> "We need to apply the same level of care to designing and prototyping our tools as we would to designing our overall prompts. We've consistently found that giving Claude better tool documentation and clearer interfaces improves agent performance much more than tweaking the agent's prompt."

[Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

Use this when citing: tools deserve the same prompt-engineering rigor as system prompts. Backs absolute paths, poka-yoke arguments, examples in tool definitions.

## Claude Code subagent guidance

Verbatim from the docs at code.claude.com.

### When to use a subagent

> "Use one when a side task would flood your main conversation with search results, logs, or file contents you won't reference again: the subagent does that work in its own context and returns only the summary."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: the primary triggering rule for any Claude Code subagent. Pull this verbatim — the "flood... won't reference again" framing is the test.

### When to define a custom subagent

> "Define a custom subagent when you keep spawning the same kind of worker with the same instructions."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: difference between an ad-hoc Agent-tool call and a `.claude/agents/` definition. Repetition is the signal.

### The five enumerated benefits

> "Preserve context. Enforce constraints. Reuse configurations. Specialize behavior. Control costs."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: the canonical motivation list. Use these as the heading row in any subagent design doc.

### What subagents inherit (and don't)

> "The only channel from parent to subagent is the Agent tool's prompt string, so include any file paths, error messages, or decisions the subagent needs directly in that prompt."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: subagents do NOT inherit parent conversation history, parent tool results, or parent system prompt. Everything they need must be in the prompt string.

### Subagents vs agent teams

> "If you need multiple agents working in parallel and communicating with each other, see agent teams instead. Subagents work within a single session; agent teams coordinate across separate sessions."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: the boundary between in-session subagents (orchestrator-worker, single session) and cross-session agent teams (multi-session collaboration).

## Single-level fan-out enforcement

The hard constraint that prevents recursive subagent spawning.

### No nested subagents

> "Subagents cannot spawn their own subagents."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: single-level fan-out is enforced by omitting the `Agent` tool from the subagent's `tools` array. This is the architectural reason teams stay one layer deep — there is no recursion.

### Tool-array implication

> "Don't include `Agent` in a subagent's `tools` array."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: the concrete configuration to enforce single-level fan-out. If the user is hand-editing a subagent definition, this is the field to check.

## Inheritance pitfalls

Two specific traps in how subagents inherit configuration.

### `bypassPermissions` cascades

> "Subagents inherit the parent's permission mode. If the parent runs with `bypassPermissions`, subagents do too — including ones invoked through the Agent tool."

[Subagents in the SDK](https://code.claude.com/docs/en/agent-sdk/subagents)

Use this when citing: `bypassPermissions` is contagious. Setting it on the parent silently broadens every spawned subagent's authority. Pair with the `allowedTools` quote below to make the security argument complete.

### `allowedTools` is a ceiling, not a constraint

> "A subagent can only use tools that are in `allowedTools` for the parent session. Tightening `allowedTools` on the subagent restricts it further; loosening it has no effect."

[Subagents in the SDK](https://code.claude.com/docs/en/agent-sdk/subagents)

Use this when citing: subagent `tools` field can only restrict, never expand. The actual permission surface is `parent.allowedTools INTERSECT subagent.tools`. To grant a subagent a tool the parent lacks, you must add it to the parent first.

### Filesystem subagents are startup-loaded

> "Filesystem subagents in `.claude/agents/` are loaded only at startup."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: editing a `.claude/agents/*.md` mid-session has no effect until restart. Justifies "restart Claude Code after subagent edits" guidance.

### Windows command-line limit

> "On Windows, very long subagent prompts can fail at the 8191-character command-line limit."

[Create custom subagents](https://code.claude.com/docs/en/sub-agents)

Use this when citing: portability constraint for the Agent-tool prompt string. Long prompts on Windows can silently truncate.

## Memory tool and context engineering

The three context-management primitives Anthropic names: compaction, structured note-taking, and sub-agents.

### The three primitives

> "Three context-engineering techniques have emerged as broadly useful: compaction (summarizing the conversation when it gets long), structured note-taking (writing key state to an external memory file), and sub-agent architectures (delegating bounded subtasks to fresh contexts)."

[Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

Use this when citing: these three are not alternatives — production systems use all three. The research system compacts on overflow, saves the lead's plan to memory, and spawns subagents.

### When to compact

> "Compaction is most useful when conversational continuity matters across a long horizon."

[Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

Use this when citing: compaction's narrow use case — preserve dialog state across many turns. Not a substitute for note-taking.

### When to take notes

> "Structured note-taking shines when work is iterative with clear milestones — the agent can write progress to a file and read it back without keeping the entire history live."

[Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

Use this when citing: external memory file is the right tool when work has discrete milestones. The `claude-progress.txt` pattern is this primitive in production.

### When to use sub-agents (context view)

> "Sub-agent architectures help most when a task benefits from parallel exploration or from isolating a high-token subtask in its own context."

[Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

Use this when citing: the context-engineering framing for subagents — they are a way to isolate token-heavy work from the main thread. Complements the "flood your main conversation" framing in the Claude Code docs.

### Context rot

> "As context grows, model attention degrades. Long contexts hurt accuracy on retrieval and reasoning, even when the relevant information is technically present."

[Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

Use this when citing: the mechanistic justification for splitting work across multiple smaller contexts rather than packing one large one. Pairs with the 80%-of-variance result — multi-agent works partly because each subagent's context stays small.

## Effective harnesses for long-running agents

The initializer-agent + coding-agent pattern across context windows.

### The three artifacts

> "We've found three artifacts especially valuable for keeping a long-running agent productive across context resets: an `init.sh` that the agent can run to bootstrap its environment, a `claude-progress.txt` that records what's done and what's next, and a feature checklist that decomposes the work into verifiable units."

[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

Use this when citing: the harness contract for any agent expected to outlive a single context window. These three files together let a fresh agent pick up from a stale predecessor.

### Why progress files matter

> "When the agent's context fills up and it has to start fresh, the progress file is the only thing that survives. Treat it as the single source of truth for state."

[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

Use this when citing: justifies the discipline of writing to `claude-progress.txt` after every significant action, not at the end. The orchestrator's plan-to-memory rule from the research system is the same idea.

### Initializer agent

> "An initializer agent reads the progress file, runs `init.sh`, and produces a tight situational summary that the next coding agent receives as its starting prompt."

[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

Use this when citing: pattern for handing off across context resets — a small specialized agent whose only job is to compress prior state for the next worker.

### Feature checklist as termination signal

> "The feature checklist gives the agent a clear definition of done. Without it, agents over-engineer or under-deliver."

[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

Use this when citing: termination criteria for long-running coding agents. Backs the "every multi-agent run needs a definition of done" rule.

## Sources

- [How we built our multi-agent research system — Anthropic Engineering, June 13 2025](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Building Effective AI Agents — Anthropic Engineering, December 2024](https://www.anthropic.com/engineering/building-effective-agents)
- [Effective context engineering for AI agents — Anthropic Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Effective harnesses for long-running agents — Anthropic Engineering](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Eval awareness in Claude Opus 4.6's BrowseComp — Anthropic Engineering](https://www.anthropic.com/engineering/eval-awareness-browsecomp)
- [Demystifying evals for AI agents — Anthropic Engineering](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [Equipping agents for the real world with Agent Skills — Anthropic Engineering](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [Scaling Managed Agents — Anthropic Engineering](https://www.anthropic.com/engineering/managed-agents)
- [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents)
- [Subagents in the SDK — Claude Agent SDK Docs](https://code.claude.com/docs/en/agent-sdk/subagents)
