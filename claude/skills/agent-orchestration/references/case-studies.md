# Production Case Studies

What real multi-agent systems shipped in 2025–2026, what shape they chose, what broke, and the rule each teaches. Use this to anchor pattern selection in actual deployed precedent rather than framework folklore.

## Contents

- [When to consult this](#when-to-consult-this)
- [Claude Code sub-agents / Task tool](#claude-code-sub-agents--task-tool)
- [Anthropic Claude Research](#anthropic-claude-research)
- [OpenAI Deep Research](#openai-deep-research)
- [Google Gemini Deep Research](#google-gemini-deep-research)
- [Cognition Devin](#cognition-devin)
- [Cursor 2.0 / 3.x Composer](#cursor-20--3x-composer)
- [GitHub Copilot coding agent](#github-copilot-coding-agent)
- [Replit Agent](#replit-agent)
- [Perplexity Pro Search and Computer](#perplexity-pro-search-and-computer)
- [MetaGPT, ChatDev, AgentVerse](#metagpt-chatdev-agentverse)
- [CrewAI in production](#crewai-in-production)
- [LangGraph in production](#langgraph-in-production)
- [AutoGen in production](#autogen-in-production)
- [OpenAI Agents SDK / Swarm](#openai-agents-sdk--swarm)
- [Stripe compliance investigation agents](#stripe-compliance-investigation-agents)
- [Amazon Bedrock multi-agent collaboration](#amazon-bedrock-multi-agent-collaboration)
- [IBM watsonx Orchestrate](#ibm-watsonx-orchestrate)
- [Salesforce Agentforce / Atlas](#salesforce-agentforce--atlas)
- [Box AI agents](#box-ai-agents)
- [Amazon Q Business](#amazon-q-business)
- [Cross-cutting decision rules](#cross-cutting-decision-rules)
- [Recurring failure modes](#recurring-failure-modes)
- [Adoption signals worth discounting](#adoption-signals-worth-discounting)
- [The convergent winning pattern](#the-convergent-winning-pattern)
- [Pick a pattern in 30 seconds](#pick-a-pattern-in-30-seconds)
- [Sources](#sources)

## When to consult this

Read this when deciding whether a task wants single-thread or fan-out, picking a topology, choosing how many sub-agents, scoping per-agent tools, deciding whether to gate on a human, or arguing against a framework default that doesn't fit. Skip for one-shot prompts where only the wording is in question.

## Claude Code sub-agents / Task tool

**Pattern:** Single-level orchestrator-worker fan-out. The main session is the orchestrator; sub-agents are short-lived one-shot workers invoked through the `Task` tool with a `subagent_type`.

**Architecture:** Sub-agent definitions live in `.claude/agents/` (project) and `~/.claude/agents/` (user). Frontmatter declares `name`, `description`, `tools`; the body is the system prompt. Each sub-agent runs in its own context window with a custom system prompt, restricted tool list, and independent permissions. Sub-agents return only a summary, not their working trace. Description-driven dispatch: "Claude uses each subagent's description to decide when to delegate tasks." Built-ins: `Explore` (read-only file/codebase search), `Plan` (used in plan-mode), and `general-purpose`. The Explore agent is explicitly read-only. Single-level fan-out is enforced — sub-agents cannot spawn sub-agents ("prevents infinite nesting"). Multi-level coordination is a separate primitive (agent teams across separate sessions).

Why these choices (Anthropic, corroborated by Cognition's own commentary, June 2025): the sub-agent's main job is to keep "search results, logs, or file contents you won't reference again" out of the main context. The constraints on tools and the no-write default for `Explore` exist because, per Cognition: "the subtask agent lacks context from the main agent that would otherwise be needed to do anything beyond answering a well-defined question. And if they were to run multiple parallel subagents, they might give conflicting responses."

**Lessons taught / what broke:**
- Fan out only on read/explore work — the sub-agent returns a digest, not a write.
- Restrict tools per role to enforce read-only invariants and protect the parent's context budget.
- Never let sub-agents spawn sub-agents in coding settings; depth explodes coordination cost faster than it adds value.
- Keep the main agent's job to *orchestration and synthesis* — push token-heavy reading into workers whose output you can summarize.
- Write descriptions that the orchestrator can dispatch on — the description *is* the routing logic.

**Source(s):** https://code.claude.com/docs/en/sub-agents, https://cognition.ai/blog/dont-build-multi-agents

## Anthropic Claude Research

**Pattern:** Pure orchestrator-worker fan-out with a downstream citation pass.

**Architecture:** Three roles, all in separate context windows.

- **LeadResearcher** (Claude Opus 4) plans, persists the plan to memory (since runs exceed 200K tokens), spawns subagents, decides whether more research is needed, and synthesizes the final report.
- **Subagents** (Claude Sonnet 4) "independently perform web searches, evaluate tool results using interleaved thinking, and return findings to the LeadResearcher."
- **CitationAgent** runs after research completes; it "processes the documents and research report to identify specific locations for citations."

The lead spins up 3–5 subagents in parallel rather than serially; each subagent uses 3+ tools in parallel. These changes "cut research time by up to 90% for complex queries."

Reported numbers — verbatim where possible:

- **Quality lift:** "A multi-agent system with Claude Opus 4 as the lead agent and Claude Sonnet 4 subagents outperformed single-agent Claude Opus 4 by **90.2%**" on internal research evals.
- **Token-explains-quality:** "Token usage by itself explains **80% of the variance**" in BrowseComp performance.
- **Cost multiplier:** "Agents typically use about **4× more tokens than chat interactions, and multi-agent systems use about 15× more tokens than chats**."

**Lessons taught / what broke:**
- Documented failure mode — over-spawning: "agents spawning 50 subagents for simple queries." Fix by encoding complexity tiers in the orchestrator prompt.
- Documented failure mode — endless searching for nonexistent sources.
- Documented failure mode — agent interference via excessive updates.
- Documented failure mode — vague task decomposition (the chip-shortage example: "one subagent explored the 2021 automotive chip crisis while 2 others duplicated work investigating current 2025 supply chains, without an effective division of labor").
- Documented failure mode — source-quality bias: "early agents consistently chose SEO-optimized content farms over authoritative but less highly-ranked sources like academic PDFs or personal blogs."
- Documented failure mode — inefficient queries: continuing past sufficiency, overly verbose queries, wrong tools.
- Use rainbow deployments — "we use rainbow deployments to avoid disrupting running agents, by gradually shifting traffic from old to new versions while keeping both running simultaneously."
- Build resumable agents — "We built systems that can resume from where the agent was when the errors occurred." Tell the model when a tool fails and ask it to adapt — "works surprisingly well."
- Evaluate end-states, not steps; use LLM-as-judge with a 5-criterion rubric (factual accuracy, citation accuracy, completeness, source quality, tool efficiency); run a ~20-query starter set; recruit human testers for edge cases like the SEO bias.
- Compress to external memory — "agents summarize completed work phases and store essential information in external memory before proceeding... agents can spawn fresh subagents with clean contexts while maintaining continuity through careful handoffs."
- Accept the synchronous bottleneck (admitted limitation) — "lead agents execute subagents synchronously, waiting for each set of subagents to complete... the entire system can be blocked while waiting for a single subagent."
- Apply only where economically viable — multi-agent works for "valuable tasks that involve heavy parallelization, information that exceeds single context windows, and interfacing with numerous complex tools." It is a poor fit for "domains that require all agents to share the same context or involve many dependencies between agents... most coding tasks involve fewer truly parallelizable tasks than research." "For economic viability, multi-agent systems require tasks where the value of the task is high enough to pay for the increased performance."

**Source(s):** https://www.anthropic.com/engineering/built-multi-agent-research-system

## OpenAI Deep Research

**Pattern:** Sequential routing pipeline of specialist agents culminating in a single deep reasoner that fans out web/internal searches.

**Architecture:** Four-stage pipeline.

1. **Triage Agent** routes to Clarifier or Instruction Builder based on whether key context is missing.
2. **Clarifier Agent** (`gpt-4o-mini`) asks follow-up questions and awaits the user.
3. **Instruction Builder Agent** (`gpt-4o-mini`) turns enriched input into a precise research brief.
4. **Research Agent** (`o3-deep-research-2025-06-26` or `o4-mini-deep-research-2025-06-26`) uses `WebSearchTool` and `HostedMCPTool` to execute the brief; it is itself an RL-trained reasoning model that internally plans multi-step search.

The tier-routing principle is the heart of the design: cheap models clean and shape the query; the expensive reasoner runs once on a clean, complete brief. Each stage hands off the conversation cleanly so traces are readable per step.

**Lessons taught / what broke:**
- Pre-process and clarify with cheap models before invoking the expensive long-running reasoner.
- Treat handoffs as latency cost paid for modularity, transparency, and per-step debuggability.
- Reserve Deep Research for "planning, synthesis, tool use, or multi-step reasoning" — not trivial Q&A.
- Spend the smart model's budget on one well-scoped invocation, not on iterative back-and-forth.

**Source(s):** https://developers.openai.com/cookbook/examples/deep_research_api/introduction_to_deep_research_api_agents, https://cobusgreyling.medium.com/openai-deep-research-ai-agent-architecture-7ac52b5f6a01

## Google Gemini Deep Research

**Pattern:** Plan → human-approval gate → execution → synthesis. A pipeline with an explicit HITL approval step between planning and autonomous work.

**Architecture:** User question → Gemini "creates a multi-step research plan for you to either revise or approve." After approval the system "begins deeply analyzing relevant information from across the web on your behalf" through iterative search. "It generates a comprehensive report of the key findings, which you can export into a Google Doc." Originally launched on Gemini 1.5 Pro with 1M context; later upgraded to Gemini 2.x.

**Lessons taught / what broke:**
- Gate the autonomous phase behind explicit plan approval when runs are long, expensive, and end in a deliverable the user must trust.
- Treat the plan as the contract — it scopes the agent and gives the user something to revise before tokens burn.

**Source(s):** https://blog.google/products/gemini/google-gemini-deep-research/

## Cognition Devin

**Pattern:** Single-threaded write agent. Multi-agent only where it cannot conflict — review in a clean context, parallel sessions on independent tasks.

**Architecture:** A constellation of single-purpose agents, each in its own session, never fanning out writers inside a session.

- **Devin** — main agent, single-threaded write agent per session; users spin up multiple parallel Devins, each as an independent single-thread session with its own cloud IDE (Devin 2.0).
- **Devin Search** — agentic codebase explorer, with optional Deep Mode (a separate read-only agent — analogous to Anthropic's Explore).
- **Devin Wiki** — periodic indexer producing repo wikis and architecture diagrams.
- **Devin Review** — separate agent in a clean context that reviews PRs, groups logically related hunks, and walks the human through the diff. Review is a *second* agent in a fresh context, not a sub-agent of the writer.
- **DANA** — data-analyst variant.
- **Ask Devin** — codebase Q&A.

Walden Yan's "Don't Build Multi-Agents" (June 12, 2025) load-bearing quotes:
- "Principle 1: **Share context, and share full agent traces, not just individual messages**."
- "Principle 2: **Actions carry implicit decisions, and conflicting decisions carry bad results**."
- "I would argue that Principles 1 & 2 are so critical, and so rarely worth violating, that you should by default rule out any agent architectures that don't abide by them."
- "The simplest way to follow the principles is to just use a **single-threaded linear agent**."
- For very long traces: introduce "a new LLM model whose key purpose is to compress a history of actions & conversation into key details, events, and decisions" — Cognition has fine-tuned a small model for this.
- On Claude Code (June 2025 read): "it never does work in parallel with the subtask agent, and the subtask agent is usually only tasked with answering a question, not writing any code... The designers of Claude Code took a purposefully simple approach."
- "In 2025, running multiple agents in collaboration only results in fragile systems. The decision-making ends up being too dispersed and context isn't able to be shared thoroughly enough."

2025 performance numbers: 67% PR merge rate (vs. 34% prior year), 4× faster on problem solving, 20× efficiency on security fixes, 10–14× on code migrations. Cognition's own usage: 659 Devin PRs merged in one week (Feb 2026).

**Lessons taught / what broke:**
- Default to single-thread for write workloads (code, edits, refactors); use sub-agents only for read/explore that returns a summary.
- Keep code review as a separate fresh-context agent, not a sub-tool of the writer — a clean context spots more bugs.
- Get parallelism by running multiple independent sessions on independent tasks, not by fanning out writers inside one session.
- "Share full traces" or collapse to single-thread — anything in between produces conflicting implicit decisions.

**Source(s):** https://cognition.ai/blog/dont-build-multi-agents, https://cognition.ai/blog/devin-2, https://cognition.ai/blog/devin-annual-performance-review-2025, https://cognition.ai/blog/devin-review, https://cognition.ai/blog/how-cognition-uses-devin-to-build-devin

## Cursor 2.0 / 3.x Composer

**Pattern:** Worktree-isolated parallel agents — competing workers with output diff and a human picking the winner.

**Architecture:** Up to 8 agents in parallel on a single prompt, each in an isolated git worktree or remote machine — "to prevent file conflicts. Each agent operates in its own isolated copy of your codebase." The IDE diffs the resulting branches against the user's working tree so the human can pick the winning attempt. Composer is Cursor's own MoE+RL coding model, "4× faster than similarly intelligent models," most turns under 30s. Plan mode allows planning with one model and building with another, including running plans in parallel agents to compare them. Background Agents were renamed Cloud Agents with claimed "99.9% reliability, instant startup." Walked back / deprecated: Notepads removed; explicit context menu items (`@Definitions`, `@Web`, `@Link`, `@Recent Changes`) removed in favor of agent self-gathering — the team's read on this was that as the agent gets better at gathering its own context, manual scaffolding becomes friction rather than support.

Emergent strategy reported by Cursor: assign the same task to Composer + Sonnet + GPT-5 in parallel and pick the winner — "having multiple models attempt the same problem and picking the best result significantly improves the final output, especially for harder tasks."

**Lessons taught / what broke:**
- Use worktrees as the cheap, correct way to make parallel write agents non-interfering.
- Run N-version programming with model diversity for hard tasks — but only when a human selects the winner.
- Strip manual context primitives as the agent improves at self-gathering — scaffolding becomes friction.
- Keep the human as the picker; multi-attempt without a selector is just expense.
- Cap parallel attempts (Cursor's max is 8) — the marginal benefit of attempt N+1 falls fast and the diff fatigue rises.

**Source(s):** https://cursor.com/blog/2-0, https://cursor.com/changelog/2-0

## GitHub Copilot coding agent

**Pattern:** Async per-issue single agent (cloud agent) running a plan → implement → test loop. Multi-agent appears as orchestrated personas, not concurrent writers.

**Architecture:** "Copilot agent mode acts as an autonomous peer programmer that performs multi-step coding tasks... analyzing your codebase, reading relevant files, proposing file edits, and running terminal commands and tests." The per-task loop is determine context → propose edits → run terminal/tests → iterate, and the agent owns the issue from assignment through PR. The slash-command UX layers structure on top: `/plan` then `/autopilot` then the Copilot Code Review agent. Custom agents (Oct 2025) are YAML-defined personas with prompts, tool selections, and MCP servers; they can be delegated to from Copilot CLI. The community Orchestra pattern uses a Conductor agent coordinating Planning, Implementation, and Code Review subagents. AgentHQ (Nov 2025) extends the model to deploy ecosystem agents directly in GitHub. The platform-level multi-agency comes from running many issue-scoped agents in parallel across the org, not from fanning out inside one issue.

**Lessons taught / what broke:**
- Treat the natural unit as "issue-scoped async agent" — one agent per work item; the platform manages many.
- Specialize personas (planner, implementer, reviewer) and route them via a conductor; do not fan out writes inside one issue.
- Make personas YAML-declarable so reviewers can audit prompt, tool list, and MCP servers as code.
- Get parallelism from the issue queue (many tasks × one agent each), not from concurrency inside a task.

**Source(s):** https://github.blog/changelog/2025-10-28-github-copilot-cli-use-custom-agents-and-delegate-to-copilot-coding-agent/, https://github.com/newsroom/press-releases/coding-agent-for-github-copilot

## Replit Agent

**Pattern:** Pipelined multi-agent (manager + editors + verifier) with HITL by design. Agent 4 added explicit ideate → design → build → review phases with parallel editor sub-agents.

**Architecture:** Manager Agent orchestrates the workflow. Editor Agents take narrow, specific coding tasks. Verifier Agent checks outputs but "often falls back to talking to the user in order to enforce continuous user feedback." The team's stated philosophy (Catasta): "We don't strive for full autonomy." Stack: 30+ tools, custom Python DSL instead of vanilla function calling, LangGraph for orchestration, LangSmith for traces. Agent 3 introduced a self-test loop: generate → execute → identify errors → fix → rerun, plus Browser App Testing that simulates user clicks against the running app. Agent 4 added a four-phase pipeline — ideation phase asks clarifying questions and produces a plan; design phase generates UI mockups; build phase runs parallel sub-agents on app sub-parts; review phase exposes a web preview the user can poke at.

**Lessons taught / what broke:**
- Limit each agent to "the smallest possible task" — reduces compounding errors.
- Skip fine-tuning as the unlock — switching to Claude 3.5 Sonnet was what shifted quality.
- Use dynamic prompt construction with compressed memory trajectories to handle token limits.
- Structure prompts with XML/Markdown — improves comprehension.
- Treat HITL as a feature, not friction, for end-user-facing code generation; the verifier-talks-to-user pattern is what keeps the agent honest.
- Pair every autonomous loop with an outward-facing checkpoint (browser test, web preview) so the user has something concrete to validate against, not just text.

**Source(s):** https://www.langchain.com/breakoutagents/replit, https://blog.replit.com/introducing-agent-3-our-most-autonomous-agent-yet, https://docs.replit.com/replitai/agent

## Perplexity Pro Search and Computer

**Pattern:** Two distinct systems. Pro Search: single agent with explicit plan/execute split and per-step parallel search fan-out. Computer: parent agent with `run_subagent` calls into typed specialist agents.

**Architecture (Pro Search):** "AI creates a step-by-step plan. For each step, search queries are generated and executed sequentially, with results from previous steps passed when executing subsequent steps." Per-step parallel search fan-out (multiple queries inside one step), but no separate sub-agents — one agent owns the entire trace. Multi-model orchestration with prompts customized per model so the same plan can target different model strengths. Evals via LLM-as-judge plus A/B testing in production.

**Architecture (Computer, Mar 2026):** Parent agent with `run_subagent` calls. Sub-agents are typed by capability: asset creation, web research/synthesis, website building, general-purpose, coding. The orchestration layer does task classification (which sub-agent), model selection per task (which backend), and result synthesis. Sub-agents can themselves spawn sub-agents — a deliberate departure from Claude Code's single-level rule, with the trade-off of deeper coordination cost in exchange for more capable composite workflows.

**Lessons taught / what broke:**
- Use orchestrator-worker for search-and-synthesize — it's the sweet spot.
- Type sub-agents narrowly for coding/creative tasks rather than running one general worker.
- Add explicit LLM planning steps for complex research; pair with dynamic UI feedback to raise user latency tolerance.
- Pass results from previous steps forward — sequential search where each step is informed by the last beats parallel-fan-out for research depth.
- If you allow nested sub-agents (Computer's choice), invest in tracing and per-call cost caps; the depth budget is the new context budget.

**Source(s):** https://www.langchain.com/breakoutagents/perplexity, https://www.perplexity.ai/hub/blog/introducing-perplexity-computer

## MetaGPT, ChatDev, AgentVerse

**Pattern:** Role-play multi-agent frameworks with hardcoded SOPs (Standard Operating Procedures) and many specialist roles (Product Manager, Architect, Engineer, QA, etc.).

**Architecture:** Each system encodes a software-team metaphor.

- **MetaGPT** — 5 agents, claims 85.9% Pass@1 HumanEval, 87.7% MBPP.
- **ChatDev** — 7 agents in a sequential design-code-test pipeline.
- **AgentVerse** — configurable cast with negotiation rounds.
- **AgentCoder (3-agent baseline)** — programmer, test designer, test executor; outperforms the larger casts at a fraction of cost.

Token overhead per HumanEval/MBPP task: AgentCoder 56.9K/66.3K; **MetaGPT 138.2K/206.5K; ChatDev 183.7K/259.3K; AgentVerse 149.2K/193.6K**. "Large agent groups such as MetaGPT and ChatDev introduce high communication costs, often exceeding **$10 per HumanEval task**."

**Lessons taught / what broke:**
- Distrust role inflation — more roles do not improve quality but linearly raise tokens.
- Discount benchmark wins on HumanEval/MBPP — these are short, well-specified problems where role choreography masks model capability rather than adding value.
- Credit SOP encoding, not agent count, for the robustness gain MetaGPT reports.
- Collapse to fewer agents if you cannot point to a customer-relevant capability that *requires* multiple roles. AgentCoder's 3-agent design (programmer, test designer, test executor) outperforms larger casts at a fraction of cost.

**Source(s):** https://arxiv.org/pdf/2308.00352, https://arxiv.org/pdf/2312.13010

## CrewAI in production

**Pattern:** Two first-class processes — Sequential (assembly line) and Hierarchical (manager agent dynamically delegates). 3–5 teammate sweet spot is folklore-grade guidance from production write-ups.

**Architecture:** CrewAI claims agents for "60% of Fortune 500 companies" (vendor claim, treat with caution). Sequential mode runs tasks in fixed order; hierarchical mode adds a manager agent that decides delegation. CrewAI Flows wraps Crews with state persistence, conditional routing, and gradual autonomy.

**Lessons taught / what broke:**
- "Sequential process offers reliability at the cost of flexibility, while a hierarchical process offers dynamic power at the cost of predictability."
- Cap cost in hierarchical mode — agents enter "extended deliberations" that "burn through an API budget with alarming speed." Mitigations: tier different models per agent, cache identical tool calls, decompose large tasks.
- Wrap vanilla Crews in a stateful runtime — vanilla Crews lack durable state; production write-ups consistently cite this as the production gap.
- Stay at 3–5 agents. Beyond that, communication overhead dominates.
- Default to sequential. Promote to hierarchical only when subtask shape is genuinely unknown ahead of time.

**Source(s):** https://docs.crewai.com/en/learn/sequential-process, https://medium.com/@takafumi.endo/crewai-scaling-human-centric-ai-agents-in-production-a023e0be7af9, https://crewai.com/case-studies

## LangGraph in production

**Pattern:** Graph-based state machine. Three reference topologies: Supervisor, Hierarchical Teams (supervisor of supervisors), Swarm (decentralized, shared workspace, agents pick up work matching their expertise).

**Architecture:** LangChain claims LinkedIn, Uber, "and 400+ other companies" run LangGraph in production. Supervisor pattern is the most common; HITL via interruption nodes is the standard production extension. Supervisor scales by composition — divisions get their own supervisors, with a top-level "supervisor of supervisors." Databricks publicly pushes Supervisor as the enterprise default; AWS publishes patterns combining LangGraph with Bedrock as the recommended supervisor stack.

**Lessons taught / what broke:**
- Reach for a state-machine framework before reaching for a multi-agent framework when you genuinely need durable state, conditional routing, and HITL interrupts.
- Default to Supervisor; treat Swarm as research mode — it shines for emergent problem-solving but is harder to debug.
- Budget for production hurdles — state machine design, memory leaks, monitoring. "Familiarity with graph theory, distributed systems, and state persistence strategies" is required.

**Source(s):** https://langchain-ai.github.io/langgraph/tutorials/multi_agent/hierarchical_agent_teams/, https://www.databricks.com/blog/multi-agent-supervisor-architecture-orchestrating-enterprise-ai-scale, https://aws.amazon.com/blogs/machine-learning/build-multi-agent-systems-with-langgraph-and-amazon-bedrock/

## AutoGen in production

**Pattern:** GroupChat (turn-taking moderated chat among agents) and Magentic-One (orchestrator + WebSurfer + FileSurfer + Coder + ComputerTerminal).

**Architecture:** AutoGen Studio is a prototyping UI; Magentic-One is a research agent stack for browser/file/computer-use tasks. AutoGen is now in maintenance mode; Microsoft recommends Microsoft Agent Framework for new production work (built on AutoGen lessons with enterprise support).

Microsoft caveats — verbatim where possible:

- **AutoGen Studio:** "AutoGen Studio is meant to help you rapidly prototype multi-agent workflows... It is **not meant to be a production-ready app**. Developers are encouraged to use the AutoGen framework to build their own applications, implementing authentication, security and other features required for deployed applications."
- **Magentic-One:** documentation includes a Caution section noting it "involves interacting with a digital world designed for humans, which carries inherent risks" and that "agents may occasionally attempt risky actions, such as recruiting humans for help or accepting cookie agreements without human involvement."
- **Recommended mitigations** for Magentic-One: containers, virtual environments, log monitoring, human oversight, limited access, safeguarded data.

Where it's actually used: research prototyping, internal hackathons, RPA-adjacent automations behind heavy guardrails. Enterprise-grade AutoGen deployments tend to wrap GroupChat in their own orchestration and add deterministic guards.

**Lessons taught / what broke:**
- Replace generic GroupChat ("everyone talks until consensus") with a deterministic supervisor + typed handoffs whenever you ship — no agent owns context in GroupChat, which is fragile in production.
- Wrap GroupChat in your own orchestration and add deterministic guards if you must use it at all.
- Treat Magentic-One as prototype-tier and sandbox aggressively if running it.

**Source(s):** https://microsoft.github.io/autogen/stable//user-guide/agentchat-user-guide/magentic-one.html, https://github.com/microsoft/autogen

## OpenAI Agents SDK / Swarm

**Pattern:** Handoffs as the primary primitive — an agent's "tool" can be another agent or a function returning another agent; the conversation transfers fully on a handoff. Agents-as-tools is the alternative primitive when the calling agent needs to keep ownership and only borrow a sub-agent's output.

**Architecture:** Swarm is explicitly an *educational* framework — "not a managed service, not a production runtime, and not actively maintained." OpenAI redirects production use to the OpenAI Agents SDK, which generalizes Swarm's primitives (Agents, Agents-as-tools, Handoffs) into a maintained package with tracing, guardrails, and structured outputs. Deep Research's reference implementation (Section 3) is built on this SDK. The mental model: Handoffs route — the receiving agent now *is* the conversation. Agents-as-tools delegate — the calling agent stays in control and incorporates the tool agent's output into its own response.

**Lessons taught / what broke:**
- Use Handoffs for routing pipelines and triage flows where each step truly owns the conversation.
- Use Agents-as-tools, not Handoffs, when you need parallelism — Handoffs serialize by design.
- Do not ship Swarm; the SDK is the production successor.
- Pick the primitive by who should own context next — if the answer is "the same agent, just augmented," use Agents-as-tools; if the answer is "a different specialist owns this thread now," use Handoffs.

**Source(s):** https://github.com/openai/swarm, https://openai.github.io/openai-agents-python/handoffs/, https://openai.github.io/openai-agents-python/multi_agent/

## Stripe compliance investigation agents

**Pattern:** Pipeline DAG with audit-grade traceability. Explicitly *not* an open orchestrator — the workflow is a pre-defined directed acyclic graph that the agent navigates within "rails."

**Architecture:** Compliance (Enhanced Due Diligence) workflow decomposed into a DAG: "This DAG provides 'rails' for the agents, ensuring they spend appropriate time on regulatory-required investigation areas rather than rabbit-holing on irrelevant topics." Built on Amazon Bedrock (chosen for standardized security vetting across model vendors) with prompt caching to address quadratic-cost iterative loops. Specialized agent service separate from ML inference: network-bound, non-deterministic flows, 5–10 minute timeouts for deep investigations. "Every agent interaction produces complete audit trails showing what the agent found, how it found it, what tool calls it made, and what results those tools returned." Stripe operates "over 100 agents across the company," though their tech lead (Christopher) is publicly skeptical of this proliferation, suggesting most use cases reduce to "shallow React agents, deep React agents, and perhaps to-do list agents."

Reported numbers:

- **26% reduction** in average compliance review handling time.
- **96% helpfulness rating** from reviewers.
- Initial wins came from pre-fetching research before reviewers open cases, not from full automation.

**Lessons taught / what broke:**
- Constrain the topology to a DAG, not an open agent, for regulated audit-heavy domains. Auditability comes from structure, not prompts.
- Adopt incremental automation: "The natural instinct to have agents replace entire workflows is unrealistic. **Incremental approaches using agents as tools for human experts are more tractable and provable**."
- Recognize tool-calling primacy — dynamic tool selection is what makes agents useful vs. static LLM Q&A.
- Treat human-in-the-loop as non-negotiable for regulated decisions.
- Decompose work into bite-sized tasks: "essential for fitting work within the agent's working memory and making quality evaluation tractable."
- Encode mandatory steps and parallelism opportunities at the DAG; leave search and judgment inside each node to the LLM.

**Source(s):** https://www.zenml.io/llmops-database/ai-powered-compliance-investigation-agents-for-enhanced-due-diligence

## Amazon Bedrock multi-agent collaboration

**Pattern:** Supervisor + collaborators, GA March 10, 2025. Two modes — Supervisor (full orchestration, decomposes and synthesizes) and Supervisor-with-routing (simple requests bypass orchestration and go straight to a specialist; complex queries fall back to full supervisor).

**Architecture:** A supervisor agent is wired to a fixed set of collaborator agents at design time. The supervisor decides which collaborator(s) to invoke for a given turn, marshals their outputs, and synthesizes the final response. There is a soft limit of 3 hierarchical layers — AWS treats deeper nesting as a code smell. Conversation-history sharing with subagents is optional per collaborator, so the supervisor can decide which workers see the prior turns and which get a clean brief. Payload referencing (passing pointers to large blobs rather than re-embedding them in every prompt) is a first-class primitive. Trace/debug console exposes per-turn agent decisions; CloudFormation/CDK support makes the topology infrastructure-as-code. Reference use cases: investment advisory (research + portfolio + execution agents), retail ops (inventory + pricing + promotion agents), social-media campaign management (content + scheduling + analytics agents).

**Lessons taught / what broke:**
- Cap hierarchy at 3 layers — even AWS, with deep production tooling, treats deeper as a code smell.
- Provide a routing mode so simple queries don't pay the full supervisor cost.
- Use payload referencing rather than re-embedding to keep multi-agent token bills sane.
- Decide per-collaborator whether it sees conversation history; the default of "everyone sees everything" wastes tokens and pollutes specialist context.
- Express the topology as IaC so that supervisor/collaborator wiring is reviewable and reproducible — multi-agent systems are infrastructure, not prompts.

**Source(s):** https://aws.amazon.com/blogs/aws/introducing-multi-agent-collaboration-capability-for-amazon-bedrock/

## IBM watsonx Orchestrate

**Pattern:** Multi-agent supervisor/router/planner that coordinates IBM-native agents and imported agents from Bedrock AgentCore, LangGraph, CrewAI, and Strands.

**Architecture:** A central Orchestrate runtime exposes a supervisor that can route or plan across a registered set of agents regardless of authoring framework. Agent Catalog ships 150+ pre-built agents (Box, MasterCard, Oracle, Salesforce, ServiceNow, etc.) so customers compose rather than build. Supports MCP for tool calls and A2A for cross-vendor agent-to-agent coordination, on the bet that enterprise multi-agent will be heterogeneous (multiple frameworks, multiple vendors). The product surface is explicitly catalog + composition, not "build your agents from scratch."

**Lessons taught / what broke:**
- Bet on protocol interop (MCP for tools, A2A for cross-vendor coordination) when the strategy is enterprise integration.
- Ship a curated catalog; supervised composition of vetted agents is more predictable than open agent discovery.
- Treat framework heterogeneity as the steady state — production stacks will mix LangGraph, CrewAI, Bedrock-native, and home-grown agents, and the supervisor must speak to all of them.

**Source(s):** https://aws.amazon.com/blogs/ibm-redhat/building-agentic-workflows-with-ibm-watsonx-orchestrate-on-aws/

## Salesforce Agentforce / Atlas

**Pattern:** Modular, pluggable reasoning orchestrator with "System 2" inference-time reasoning. Asynchronous publish-subscribe event-driven architecture decouples component nodes; functions operate "coherently but somewhat independently."

**Architecture:** Atlas is the reasoning engine inside Agentforce. It composes specialist agents at inference time rather than chaining them through a fixed pipeline. Each agent is described by five attributes — Role, Data, Actions, Guardrails, Channel — which governance and runtime both consume. Multi-agent orchestration is used to surface multiple points of view in response to one query (e.g., a sales-perspective agent and a service-perspective agent on the same customer record), which the orchestrator then merges. The pub/sub backbone means component nodes can be deployed, scaled, and replaced independently — closer to a service mesh than a chat loop.

**Lessons taught / what broke:**
- Decouple agent components via event-driven pub/sub when you need them to scale independently.
- Force agent definitions through a fixed schema (Role/Data/Actions/Guardrails/Channel) to make governance tractable.
- Use multi-agent orchestration to deliver multiple POVs on one question rather than to subdivide a single answer — the value is perspective diversity, not parallelism.

**Source(s):** https://engineering.salesforce.com/inside-the-brain-of-agentforce-revealing-the-atlas-reasoning-engine/

## Box AI agents

**Pattern:** Single-purpose enterprise agents (Box Extract for data extraction, Box Automate for cross-team workflow orchestration) published on Google Agentspace.

**Architecture:** Box Extract pulls structured fields out of unstructured documents stored in Box; Box Automate orchestrates workflow steps that span teams and applications. Both are published on Google Agentspace and support the A2A protocol and Google ADK so other agents (inside or outside Google's ecosystem) can call Box capabilities as building blocks. The architectural bet is that enterprise context — the corpus Box already owns — is the differentiator, not the orchestration layer on top of it.

**Lessons taught / what broke:**
- Expose your domain agent as a callable building block via A2A/ADK rather than building a sprawling orchestrator yourself.
- Lean on the data moat — agents win when they sit on top of context the buyer already has.
- Ship narrow agents (Extract, Automate) rather than a single "Box AI agent" that tries to do both — the surface is more legible to other agents calling in.

**Source(s):** https://www.boxinvestorrelations.com/news-and-media/news/press-release-details/2025/Box-Announces-Next-Generation-AI-Agents-to-Drive-Intelligent-Workflows/

## Amazon Q Business

**Pattern:** Single-orchestrator + plugin pattern, not a multi-agent mesh. Chat orchestration "automatically manages chat requests across configured plugins and data sources."

**Architecture:** A single Q Business orchestrator routes each user turn across 50+ connectors (read paths into enterprise systems) and 10+ plugins (write/act paths). Custom plugins can themselves call Bedrock agents via Lambda or EKS, so the multi-agent capability sits *behind* a plugin boundary rather than in front of the user. The orchestrator's job is connector/plugin selection and answer assembly, not delegating to peer agents.

**Lessons taught / what broke:**
- Choose orchestrator + plugins over multi-agent mesh when the surface is "answer questions across a known set of systems."
- Push action breadth into plugins, not into more agents — plugin contracts are easier to govern and test than peer-agent coordination.
- Hide multi-agent complexity behind a plugin so only one system has to reason about user intent.

**Source(s):** https://aws.amazon.com/about-aws/whats-new/2025/02/amazon-q-business-orchestration-user-query-management/

## Cross-cutting decision rules

These are the patterns that recur across the case studies, written as decision rules with concrete triggers.

| Trigger | Pattern | Why | Evidence |
|---|---|---|---|
| Task is read-heavy (research, search, exploration), parallelizable, value/token is high | Orchestrator-worker fan-out with strong lead + cheaper workers | 90.2% lift over single-agent; subagents scale across context windows | Anthropic Multi-Agent Research |
| Task is write-heavy (code edits, content creation) within one artifact | Single-thread agent; sub-agents only for read/explore returning a summary | Conflicting writes from parallel agents produce inconsistent assumptions | Cognition "Don't Build Multi-Agents" |
| You need multiple parallel writers | Give each its own worktree/sandbox; pick a winner via human or judge | Worktrees + N-version programming with model diversity | Cursor 2.0 |
| Task is regulated / auditable | DAG with rails, agent inside each node, end-to-end audit trace persisted | Regulators demand specific evidence be examined; open orchestration risks skipped steps | Stripe EDD |
| Task is long-running (>5 min, expensive) and ends in a deliverable users must trust | Plan → human approval gate → execute → synthesize | Approval is the contract | Gemini Deep Research |
| Long-horizon agent that may be redeployed mid-run | Rainbow deployments + resumable checkpoints + tell the model when tools fail | Stateful agents survive deploys "anywhere in their process" | Anthropic Multi-Agent Research |
| Cost-sensitive | Tier routing — cheap models for clarify/route/triage, expensive reasoner once on a clean brief | `gpt-4o-mini` for triage/clarify/instruct, `o3-deep-research` only for the actual research step | OpenAI Cookbook |
| Code review of an agent's output | Separate agent in clean context (not a sub-tool of the writer) | Clean context spots more bugs | Devin Review; Anthropic CitationAgent |
| You're considering >5 specialist roles | Probably wrong. Compress to ≤3 (programmer / test-designer / test-executor) or to 1 single-thread agent | Token overhead dominates; AgentCoder beats MetaGPT (5 roles) and ChatDev (7) at a fraction of the cost | AgentCoder + MetaGPT papers |
| You want sub-agents to spawn sub-agents | Don't. Single-level fan-out. | Coordination cost explodes; Claude Code, Bedrock (3-layer soft limit), and Cognition all converge here | Claude Code docs; Bedrock docs |
| You need conditional routing + durable state + HITL interrupts | State-machine framework (LangGraph, CrewAI Flows) before multi-agent | Production write-ups consistently cite state mgmt as the production gap | LangGraph & CrewAI production posts |
| Build prototype → ship to production | Don't ship the prototype topology; replace GroupChat with deterministic supervisor + typed handoffs | Microsoft's own AutoGen Studio caveat; Magentic-One safety warnings | AutoGen docs |

## Recurring failure modes

Six failure modes appear across the case studies often enough to deserve names. Each entry names the symptom, the canonical case, and the fix that the shipping team adopted.

1. **Over-spawning** (Anthropic): 50 sub-agents for a trivial query. The orchestrator over-decomposes because the prompt does not encode "how much agent is enough." Fix — encode complexity tiers in the orchestrator's prompt ("simple = 1 agent, 3–10 calls; standard = 2–4 agents, 10–15 calls; complex = ≥10 agents with clear divisions"). The orchestrator should pick the tier explicitly before spawning.
2. **Duplicate work** (Anthropic chip-shortage example): vague subtask descriptions cause overlap — "one subagent explored the 2021 automotive chip crisis while 2 others duplicated work investigating current 2025 supply chains, without an effective division of labor." Fix — the orchestrator must give each subagent an objective, output format, sources, and explicit boundaries; "you" and "not you" both get named.
3. **Conflicting decisions** (Cognition Flappy Bird): subagents make incompatible implicit choices because each carries only partial context. The composite output has internally inconsistent assumptions. Fix — share full traces, or collapse to single-thread. There is no middle ground that holds.
4. **Source-quality bias** (Anthropic): agents prefer SEO content over authoritative-but-lower-ranked sources. Caught by human testers, not by the model itself. Fix — human-tester edge-case eval + explicit source-quality rubric in the LLM-judge. Treat the eval set as a living artifact.
5. **Cost explosion** (CrewAI hierarchical, ChatDev): deliberation loops burn budget. Hierarchical CrewAI agents enter "extended deliberations"; ChatDev's 7-role choreography exceeds $10 per HumanEval task. Fix — tier models, cache tool calls, decompose tasks, set hard caps (max iterations, max tokens, max wall-clock).
6. **State loss between runs** (LangGraph adoption posts): in-memory only. Long-running agents die mid-step or get redeployed mid-run; restarting loses everything. Fix — persistent state machine + checkpointing; tell the model when a tool fails so it can adapt rather than crash.

## Adoption signals worth discounting

Several case studies report headline numbers that read like marketing. Treat these with a calibrated skepticism — and notice the same skepticism inside the engineering posts themselves.

- **CrewAI's "60% of Fortune 500"** is a vendor claim with no published methodology. Discount unless you see a named customer + use case.
- **LangChain's "400+ companies on LangGraph"** is similarly vendor-self-reported. The technically substantive evidence is the AWS/Databricks reference architectures, not the headcount.
- **MetaGPT/ChatDev HumanEval scores** look impressive in isolation but cost $10+ per task and beat single-agent baselines mostly on benchmark-shaped problems. AgentCoder's 3-agent design outperforms them at a fraction of the cost.
- **Stripe's "100+ agents across the company"** comes with the company's own tech lead publicly suggesting most cases reduce to "shallow React agents, deep React agents, and perhaps to-do list agents" — i.e., the agent count is inflated by counting trivial wrappers.
- **Vendor "multi-agent" products** (Bedrock, watsonx, Agentforce) frequently mean "supervisor + plugins" or "supervisor + collaborator pool" — closer to plugin architectures than to peer-agent meshes. Read the architecture, not the marketing word.

The signal worth heeding: who shipped what, in production, with public failure modes. The engineering posts from Anthropic, Cognition, Cursor, Replit, and Stripe meet that bar. The vendor "look at our agents" posts often do not.

## The convergent winning pattern

The dominant 2025–2026 production pattern is *not* "many agents talking" — it is **one well-specified orchestrator with narrow, single-purpose workers and persistent state**. Multi-agent collaboration in the AutoGen-style "everyone chats until consensus" sense is essentially absent from shipped enterprise systems; where it exists (Magentic-One, GroupChat) the vendors themselves caveat it as prototype-tier.

The convergent winner across Anthropic, OpenAI, Cognition (read-side and review), Cursor, Replit, AWS Bedrock, Salesforce Atlas, and Stripe is **orchestrator-worker with strict context isolation, restricted worker tool sets, and a separate clean-context reviewer**. The four invariants worth memorizing:

1. **Strict context isolation.** Each worker gets a clean window with only the brief it needs; the orchestrator owns the global view. Workers return summaries, not raw traces, so the orchestrator's context budget survives the run.
2. **Restricted worker tool sets.** Read-only by default for explorers; write tools only for workers whose role demands them; sandboxed (worktree, container, separate session) wherever multiple writers are concurrent.
3. **Separate clean-context reviewer.** The reviewer is a *new* agent in a fresh context, not a sub-call of the writer. Devin Review, Anthropic's CitationAgent, and Cursor's plan-mode comparison all converge here — clean context catches bugs the writer is blind to.
4. **Single-level fan-out.** Sub-agents do not spawn sub-agents in coding settings. Claude Code enforces this; AWS Bedrock soft-caps at 3 layers; Cognition argues for one level on first principles.

When in doubt: start single-thread, add a read-only sub-agent for exploration, add a clean-context reviewer for verification, and only fan out writers under sandboxed isolation when a human will pick the winner.

## Pick a pattern in 30 seconds

A compressed lookup that mirrors the cross-cutting decision rules. Walk top-to-bottom; first matching row wins.

- Read-heavy research, parallelizable, value/token high → orchestrator-worker fan-out (Anthropic Research shape).
- Write-heavy code task, single artifact → single-thread agent + read-only Explore sub-agent + clean-context reviewer (Devin shape).
- Multiple independent write attempts on the same task → worktree-isolated parallel agents, human picks winner (Cursor shape).
- Regulated / auditable workflow → DAG with rails, agent inside each node, full audit trace (Stripe shape).
- Long-running, expensive, ends in a deliverable → plan → human approval → execute → synthesize (Gemini Deep Research shape).
- Routing / triage flow with handoffs → tier-routed pipeline (OpenAI Deep Research shape).
- Many independent issues / tasks in parallel → one async issue-scoped agent per task, platform manages many (Copilot shape).
- End-user-facing code generation with non-developer users → manager + editor + verifier-talks-to-user (Replit shape).
- "I want agents to talk until they agree" → no. Replace with deterministic supervisor + typed handoffs.

## Sources

- [How we built our multi-agent research system — Anthropic Engineering, Jun 13 2025](https://www.anthropic.com/engineering/built-multi-agent-research-system)
- [Building Effective Agents — Anthropic Research](https://www.anthropic.com/research/building-effective-agents)
- [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents)
- [Don't Build Multi-Agents — Cognition / Walden Yan, Jun 12 2025](https://cognition.ai/blog/dont-build-multi-agents)
- [Devin's 2025 Performance Review — Cognition](https://cognition.ai/blog/devin-annual-performance-review-2025)
- [Devin 2.0 — Cognition](https://cognition.ai/blog/devin-2)
- [Devin Review — Cognition](https://cognition.ai/blog/devin-review)
- [How Cognition Uses Devin to Build Devin — Cognition](https://cognition.ai/blog/how-cognition-uses-devin-to-build-devin)
- [Introducing Cursor 2.0 and Composer](https://cursor.com/blog/2-0)
- [Cursor 2.0 Changelog](https://cursor.com/changelog/2-0)
- [Try Deep Research and our new experimental model in Gemini — Google Blog](https://blog.google/products/gemini/google-gemini-deep-research/)
- [Introduction to Deep Research API with the Agents SDK — OpenAI Cookbook](https://developers.openai.com/cookbook/examples/deep_research_api/introduction_to_deep_research_api_agents)
- [OpenAI Deep Research AI Agent Architecture — Cobus Greyling](https://cobusgreyling.medium.com/openai-deep-research-ai-agent-architecture-7ac52b5f6a01)
- [OpenAI Swarm GitHub](https://github.com/openai/swarm)
- [OpenAI Agents SDK — Handoffs](https://openai.github.io/openai-agents-python/handoffs/)
- [OpenAI Agents SDK — Multi-agent](https://openai.github.io/openai-agents-python/multi_agent/)
- [Replit Agent — LangChain Breakout Agents Case Study](https://www.langchain.com/breakoutagents/replit)
- [Introducing Replit Agent 3 — Replit Blog](https://blog.replit.com/introducing-agent-3-our-most-autonomous-agent-yet)
- [Replit Agent docs](https://docs.replit.com/replitai/agent)
- [Perplexity Pro Search — LangChain Breakout Agents Case Study](https://www.langchain.com/breakoutagents/perplexity)
- [Introducing Perplexity Computer](https://www.perplexity.ai/hub/blog/introducing-perplexity-computer)
- [GitHub Copilot CLI custom agents — GitHub Changelog](https://github.blog/changelog/2025-10-28-github-copilot-cli-use-custom-agents-and-delegate-to-copilot-coding-agent/)
- [Introducing GitHub Copilot agent mode — VS Code Blog](https://code.visualstudio.com/blogs/2025/02/24/introducing-copilot-agent-mode)
- [Coding agent for GitHub Copilot — GitHub Newsroom](https://github.com/newsroom/press-releases/coding-agent-for-github-copilot)
- [MetaGPT (ICLR 2024)](https://arxiv.org/pdf/2308.00352)
- [AgentCoder paper](https://arxiv.org/pdf/2312.13010)
- [CrewAI Sequential Process docs](https://docs.crewai.com/en/learn/sequential-process)
- [CrewAI in Production — Takafumi Endo / Medium](https://medium.com/@takafumi.endo/crewai-scaling-human-centric-ai-agents-in-production-a023e0be7af9)
- [CrewAI case studies](https://crewai.com/case-studies)
- [LangGraph Hierarchical Agent Teams](https://langchain-ai.github.io/langgraph/tutorials/multi_agent/hierarchical_agent_teams/)
- [Multi-Agent Supervisor Architecture — Databricks](https://www.databricks.com/blog/multi-agent-supervisor-architecture-orchestrating-enterprise-ai-scale)
- [Build multi-agent systems with LangGraph and Amazon Bedrock — AWS](https://aws.amazon.com/blogs/machine-learning/build-multi-agent-systems-with-langgraph-and-amazon-bedrock/)
- [Magentic-One — AutoGen Docs](https://microsoft.github.io/autogen/stable//user-guide/agentchat-user-guide/magentic-one.html)
- [AutoGen GitHub](https://github.com/microsoft/autogen)
- [Stripe AI-Powered Compliance Investigation Agents — ZenML LLMOps Database](https://www.zenml.io/llmops-database/ai-powered-compliance-investigation-agents-for-enhanced-due-diligence)
- [Introducing multi-agent collaboration capability for Amazon Bedrock — AWS](https://aws.amazon.com/blogs/aws/introducing-multi-agent-collaboration-capability-for-amazon-bedrock/)
- [Building Agentic Workflows with IBM watsonx Orchestrate on AWS](https://aws.amazon.com/blogs/ibm-redhat/building-agentic-workflows-with-ibm-watsonx-orchestrate-on-aws/)
- [Inside Agentforce: Atlas Reasoning Engine — Salesforce Engineering](https://engineering.salesforce.com/inside-the-brain-of-agentforce-revealing-the-atlas-reasoning-engine/)
- [Box Announces Next-Generation AI Agents](https://www.boxinvestorrelations.com/news-and-media/news/press-release-details/2025/Box-Announces-Next-Generation-AI-Agents-to-Drive-Intelligent-Workflows/)
- [Amazon Q Business orchestration — AWS](https://aws.amazon.com/about-aws/whats-new/2025/02/amazon-q-business-orchestration-user-query-management/)
