# Tool Design and ACI for Multi-Agent

How tool count, tool descriptions, and per-agent tool surface drive the decision to spawn sub-agents — and how to scope tools when you do. Read before designing a sub-agent's tool list, before adding an MCP server, or when tool selection (not reasoning) is what's failing.

## Contents

- [When to consult this](#when-to-consult-this)
- [Tool-count thresholds](#tool-count-thresholds)
- [Anthropic ACI principles](#anthropic-aci-principles)
- [The tool-testing agent](#the-tool-testing-agent)
- [Sub-agent tool restriction](#sub-agent-tool-restriction)
- [Sub-agent tool-set recipes](#sub-agent-tool-set-recipes)
- [Deterministic work belongs in tools](#deterministic-work-belongs-in-tools)
- [MCP scoping in multi-agent](#mcp-scoping-in-multi-agent)
- [Tool output as a context bomb](#tool-output-as-a-context-bomb)
- [Parallel tool calls inside one agent](#parallel-tool-calls-inside-one-agent)
- [Tool-selection failures and mitigations](#tool-selection-failures-and-mitigations)
- [Tool-side vs agent-side responsibility](#tool-side-vs-agent-side-responsibility)
- [Decision triggers](#decision-triggers)
- [Anti-patterns](#anti-patterns)
- [Sources](#sources)

## When to consult this

Read this when scoping the tool surface of a sub-agent, when authoring `.claude/agents/*.md` frontmatter, when an agent is choosing the wrong tool, when tool definitions are eating the context window, when deciding whether an MCP server should be global or inline, or when a tool output is about to flood the parent context. Skip for choosing the parent agent's prompt strategy or for wall-clock parallelism alone — see the parallel-fanout reference for that.

## Tool-count thresholds

The single most under-appreciated trigger for spawning sub-agents is not parallelism — it is tool-selection accuracy degradation as the tool catalog grows. Tool definitions also burn the context window before the agent does any work.

Anthropic's [Tool Search Tool docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool) state plainly: **"Claude's ability to correctly pick the right tool degrades significantly once you exceed 30–50 available tools."**

Concrete numbers Anthropic published in [Introducing advanced tool use](https://www.anthropic.com/engineering/advanced-tool-use) (Nov 2025):

- A typical multi-server MCP setup (GitHub + Slack + Sentry + Grafana + Splunk = 58 tools) consumes **~55K tokens of context before the conversation begins**.
- At Anthropic internally, **tool definitions consumed 134K tokens before optimization**.
- Per-server breakdowns: GitHub 35 tools / ~26K tokens; Slack 11 tools / ~21K tokens; Jira ~17K tokens; Sentry 5 tools / ~3K tokens; Grafana 5 tools / ~3K tokens; Splunk 2 tools / ~2K tokens.

With Tool Search Tool enabled, Opus 4 jumped from **49% → 74%** accuracy and Opus 4.5 from **79.5% → 88.1%** purely by hiding most tools behind a search interface. Context dropped from ~77K → ~8.7K tokens (~95% preserved).

| Tool count visible to one agent | Action |
|---|---|
| < 10 | Single agent. No special handling. |
| 10–30 | Single agent. Invest in tool descriptions. |
| 30–50 | Specialize via sub-agents OR enable [Tool Search Tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool). |
| > 50 | Mandatory: Tool Search Tool, sub-agent specialization, or both. |
| > 200 (multi-MCP) | Tool Search Tool with `defer_loading: true` is essentially required. |

The pattern: "specialized sub-agents = narrower tool surface per agent" beats "more agents for parallelism" as a justification. SWE-Bench analysis (Scale Labs, 2025) confirms it — **tool-use inefficiency accounts for 42% of smaller-model failures** and on Sonnet 4 **35.6% of failures are context overflow**, both directly mitigated by narrowing the per-agent tool set.

Counter-data point worth knowing: ablation studies on SWE-bench Verified found that stripping Sonnet 4.5 down to bash + read + write + edit changed performance very little. Translation: usually you can delete most of your tools. The right move is often "fewer tools" before "more sub-agents."

## Anthropic ACI principles

From [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents), Appendix 2: *Prompt engineering your tools*.

The headline quotes:

- **"Tool definitions and specifications should be given just as much prompt engineering attention as your overall prompts."**
- **"Think about how much effort goes into human-computer interfaces (HCI), and plan to invest just as much effort in creating good agent-computer interfaces (ACI)."**
- **"Successful agents depend on carefully crafting your agent-computer interface (ACI) through thorough tool documentation and testing."**

Five concrete rules:

1. **Give the model tokens to "think" before it commits.** Tool schemas that force minimal output before commitment cause errors. Allow scratch room or chain-of-thought before the structured call.
2. **Keep formats close to what the model has seen on the internet.** Markdown over custom XML. JSON over bespoke serializers.
3. **No formatting overhead.** Don't make the model count tokens, count brackets, or maintain offsets.
4. **Poka-yoke arguments — make tools impossible to misuse.** Anthropic's SWE-bench agent originally took relative file paths; switching to **absolute filepaths** eliminated a class of CWD bugs. Claude Code's Read/Edit tools enforce required absolute paths — that is poka-yoke in action.
5. **Tool definitions should include "example usage, edge cases, input format requirements, and clear boundaries from other tools."** "Clear boundaries" is what separates similar tools so the model picks the right one.

Apply these to every tool spec — including the `description:` field of a sub-agent, which functions as a tool definition for the parent.

## The tool-testing agent

From [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) (Anthropic, Jun 2025):

> "Bad tool descriptions can send agents down completely wrong paths."

Anthropic built an agent whose only job was to abuse other tools with weird inputs, observe failures, and rewrite the tool descriptions. **Result: 40% decrease in task completion time** for downstream agents using the rewritten descriptions.

Practical recipe when authoring a new tool or sub-agent:

1. Write the first-pass description.
2. Spawn a sub-agent with the brief: "Try to break this tool. Pass weird, ambiguous, malformed, edge-case inputs. Report every failure mode, every confusion."
3. Rewrite the description to close those gaps.
4. Re-run a small task suite with the new description and confirm the failures are gone.

Skipping this pass leaves a free 40% performance gain on the table.

What the testing agent typically catches:

- Argument names that read one way to humans and another to the model (`name` meaning "display name" vs "internal id").
- Missing edge-case coverage (empty list, very long string, unicode, paths with spaces).
- Implicit defaults the description never mentions.
- Two tools whose descriptions don't say which to prefer when both apply.
- Output formats the description claims but the tool doesn't actually emit.

Apply the same pass to a sub-agent's `description:` field — it is a tool definition for the parent and is selected by the same mechanism.

## Sub-agent tool restriction

Source: [Claude Code sub-agents docs](https://code.claude.com/docs/en/sub-agents).

Sub-agents are configured via Markdown + YAML frontmatter. The `tools:` field is an **allowlist**; `disallowedTools:` is a **denylist**. If both are set, denylist applies first, then the allowlist resolves against what remains. Omitting `tools:` inherits the parent's full surface.

Built-in sub-agents and their restrictions — these are the canonical reference patterns:

| Sub-agent | Tools | Model | Purpose |
|---|---|---|---|
| Explore | Read-only (Write/Edit denied) | Haiku | Codebase search and analysis |
| Plan | Read-only (Write/Edit denied) | Inherits | Plan-mode research |
| General-purpose | All tools | Inherits | Multi-step research + modification |

When tool restriction is the right move:

- **If untrusted input flows in** (PR review, fact-checking, web-fetched content), **prefer a read-only `tools:` allowlist** because tool restriction is the cheapest defense against indirect prompt injection — instructions can be ignored, the tool list cannot be expanded by the model.
- **If the task is fundamentally read-only** (research, code review, exploration), **enforce read-only via `tools:` allowlist** rather than instructions in the prompt, because runtime enforcement is the only guarantee.
- **If a destructive operation is needed only sometimes**, **prefer narrow `tools:` plus `permissionMode: dontAsk`** instead of inheriting everything, because broad inheritance defeats the point of the sub-agent.
- **If a sub-agent needs only one MCP server's tools**, **define `mcpServers:` inline on that sub-agent** because keeping the MCP server out of `.mcp.json` keeps its tool descriptions out of the parent's context.

For finer-grained control than `tools:`, use a `PreToolUse` hook with a validation script (e.g. block `INSERT|UPDATE|DELETE` in Bash for a `db-reader` sub-agent). The docs ship this as a worked example.

## Sub-agent tool-set recipes

Concrete `tools:` allowlists for common sub-agent shapes. Copy these into frontmatter directly.

| Sub-agent shape | `tools:` value | Notes |
|---|---|---|
| Read-only research / analysis | `Read, Grep, Glob` | No shell. Cannot run commands or write. Safest default. |
| Read-only research with shell | `Read, Grep, Glob, Bash` | Adds `git log`, `ls`, `wc`. Pair with a `PreToolUse` hook if Bash worries you. |
| Test execution | `Bash, Read, Grep` | Reads code, runs the test command, greps for matches. No edits. |
| Code modification | `Read, Edit, Write, Grep, Glob` | Standard "write a patch" surface. No shell — pair with a separate test sub-agent. |
| Code modification + tests | `Read, Edit, Write, Grep, Glob, Bash` | Full self-contained build/test/edit loop. |
| Untrusted-input handler | `Read, Grep, Glob` (plus `WebFetch` only if required) | Strip Write/Edit/Bash. Treat fetched content as data, not instructions. |
| Orchestrator (parent) | (omit `tools:` — inherits everything) | The only place full inheritance is appropriate. Restrict children, not the parent. |
| MCP-scoped specialist | `mcp__github__*` only, plus `Read` | Define MCP server inline; do not expose unrelated tools. |
| Full access | (omit `tools:` field entirely) | The dangerous default. Use only for the orchestrator. |

Frontmatter shape for an inline-MCP sub-agent (kept out of `.mcp.json`):

```yaml
---
name: github-triage
description: Triages GitHub issues with the github MCP tools.
tools: Read, Grep
mcpServers:
  github:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
---
```

The parent conversation never sees the GitHub tool descriptions. Only this sub-agent does.

Frontmatter shape for an untrusted-input handler (web-fetched content, PR diffs, unknown user-uploaded files):

```yaml
---
name: doc-summarizer
description: Summarizes a fetched web page or untrusted document. No write access. No shell.
tools: Read, Grep, WebFetch
disallowedTools: Bash, Edit, Write
permissionMode: dontAsk
---
```

Frontmatter shape for a test-execution sub-agent that returns a distilled summary:

```yaml
---
name: test-runner
description: Runs the project test suite and returns only failures, slow tests, and coverage deltas.
tools: Bash, Read, Grep
---
```

## Deterministic work belongs in tools

The single most violated rule. From [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents):

> Agents trade latency and cost for capability. Use them only when the task genuinely benefits from non-deterministic decision making.

Anything with a single correct answer derivable by an algorithm should be a tool/function, not an agent invocation. Specifically:

- Parsing JSON / YAML / TOML
- Sorting, deduping, set operations
- Schema validation (jsonschema, pydantic)
- Running a script that already works
- Calling a deterministic API (`curl`, `gh`, `bq`)
- Diffing two strings or files
- Computing hashes, base64, regex matching
- Running a linter, a test command, a build command

Why it matters:

- **Cost.** Every sub-agent spawn re-pays the tool-use system-prompt overhead (346 tokens per request for `auto`/`none` `tool_choice`, per the API docs) plus the sub-agent's system prompt plus the new turn loop.
- **Latency.** Sub-agents start cold and need to gather context.
- **Hallucination risk.** An LLM asked to "sort this list" can get it wrong. A `sorted()` call cannot.
- **Cache.** Sub-agents have separate prompt caches. Repeated deterministic work in fresh sub-agents is the worst case for caching.

**If a sub-agent's body is essentially "run `<command>`, parse output, return result", prefer a Bash tool call** because the sub-agent overhead buys nothing.

Edge case worth flagging: if the deterministic work produces a 50K-line stdout dump, *then* the sub-agent's value is **context isolation** (see the context-bomb section), not the work itself. The sub-agent runs the tool, distills the answer, returns 200 tokens. That is legitimate.

## MCP scoping in multi-agent

Source: [modelcontextprotocol.io](https://modelcontextprotocol.io/introduction), Anthropic MCP connector docs, [Claude Code subagents docs](https://code.claude.com/docs/en/sub-agents).

MCP is an open protocol that lets a server expose tools/resources/prompts to any MCP client. Anthropic's analogy: "USB-C for AI applications."

Sharing pattern: one MCP server can be referenced by name from multiple sub-agent definitions (`mcpServers: [github]`). The connection is shared with the parent session if referenced by name; an inline definition spawns a fresh connection scoped to the sub-agent and is torn down when it finishes.

Hardcode vs MCP server:

| Hardcode (Bash command, in-prompt instruction, custom Tool) | Spin up an MCP server |
|---|---|
| One-off, single-agent use | Used by 2+ agents/sessions |
| Trivial wrapper around a CLI | Stateful (auth, sessions, caches) |
| Tool definition is < 200 tokens | Many tools that share auth/transport |
| You need to ship in 5 minutes | Cross-app reuse (Claude Desktop + Code + ChatGPT) |
| Pure-local script | Remote service / SaaS |

Risks of MCP in a multi-agent setup:

1. **Single point of failure.** If the MCP server is down or slow, every agent referencing it stalls. Mitigation: timeouts (`connect_timeout_seconds`), strict-mode failure handling, graceful degradation to alternate tools.
2. **Context tax on every agent that loads it.** A 17K-token Jira server in `.mcp.json` is loaded into every sub-agent that inherits the parent's MCP config. Mitigation: define MCP servers inline on the sub-agents that need them, not globally.
3. **Tool poisoning / indirect prompt injection.** The MCPTox benchmark (45 real MCP servers, 353 tools, 20 LLMs) measured tool-description-injection attack success rates as high as **72.8%** on some models. Counter-intuitively, more capable models can be more vulnerable because they follow hidden instructions more reliably. Mitigation: vet MCP servers, prefer inline scoped servers over global, restrict the tool list per sub-agent.
4. **Cross-server data exfiltration.** A malicious MCP server can poison its tool descriptions to read data from co-installed trusted servers. Multi-MCP setups multiply attack surface.

**If multiple sub-agents need the same external capability, prefer one named MCP server referenced by each** because duplicating tool defs across agent files burns context and breaks single-source-of-truth. **But scope it inline per sub-agent** unless the parent itself also needs it.

## Tool output as a context bomb

This is the killer use case for sub-agents in Claude Code, and the official docs lead with it:

> "Use one when a side task would flood your main conversation with search results, logs, or file contents you won't reference again: the subagent does that work in its own context and returns only the summary."

> "One of the most effective uses for subagents is isolating operations that produce large amounts of output. Running tests, fetching documentation, or processing log files can consume significant context. By delegating these to a subagent, the verbose output stays in the subagent's context while only the relevant summary returns to your main conversation."

Sub-agents typically return **1,000–2,000 tokens of distilled summary** to the parent ([Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)).

**If a tool's output dumps > 5K tokens (test runs, log scrapes, large file reads, web pages, OpenAPI specs), prefer wrapping the call in a sub-agent for context isolation** because the sub-agent absorbs the verbose output and returns a 1–2K-token summary. This is independent of parallelism — the sub-agent serves only as a context cell.

Trigger phrases that should fire this rule:

- "Run the full test suite" (tests usually dump 10K+)
- "Read all files in this directory" (especially with > 5 files)
- "Find every reference to X across the codebase and tell me about each" (Grep dumps)
- "Fetch this documentation page and answer questions about it"
- "What does this 2000-line log file say went wrong?"
- "Diff these two large generated files"
- "Crawl this OpenAPI spec and tell me which endpoints accept Y"

What the sub-agent should return to the parent:

- A 1–2K-token structured summary, not the raw output.
- Cited identifiers (file paths, line numbers, test names) so the parent can do its own follow-up Read.
- Explicit "unknowns" — gaps the parent must resolve.
- No raw stack traces, no full diffs, no log slices unless the parent specifically asked.

If the parent then needs the underlying material, it can fetch it directly with a targeted Read or Grep — far cheaper than carrying 50K tokens of unfiltered context the whole conversation.

## Parallel tool calls inside one agent

The rule that prevents most premature multi-agent designs.

From [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system):

> Subagents using **3+ tools in parallel** alongside parallel subagent spawning **cut research time by up to 90% for complex queries.**

**If wall-clock latency is your only reason to spawn sub-agents, prefer parallel tool calls inside one agent first** because the Claude API supports parallel `tool_use` blocks in a single response and Claude Code's Read/Grep/Glob/Bash tools can all be issued concurrently in one assistant turn.

Single-agent parallel tool use is cheaper than multi-agent because:

- One context, one prompt cache, one system prompt.
- No coordination overhead — no parent has to merge results.
- No risk of inconsistent reasoning across agents.

Escalate to sub-agents only when:

1. Combined tool output would blow the parent context (see the context-bomb section), or
2. Sub-tasks need *different* tool/permission profiles, or
3. Sub-tasks need genuinely independent reasoning chains (rare).

## Tool-selection failures and mitigations

Symptoms that tool-selection (not reasoning) is what's failing:

| Symptom | Diagnosis |
|---|---|
| Agent picks the wrong tool with similar-sounding name | Tool descriptions lack "clear boundaries from other tools." |
| Agent forgets a tool exists and reinvents it inline | Too many tools — relevant one buried; description doesn't surface keywords the user used. |
| Right tool, wrong args | Schema lacks examples; argument descriptions too terse. |
| Agent calls a tool, sees output, calls it again with same args | Output formatting doesn't make the result legible. |
| Agent does 10 sequential calls when 1 would do | Granularity wrong — tool too low-level; consider a composite tool. |

From [Introducing advanced tool use](https://www.anthropic.com/engineering/advanced-tool-use): **"The most common failures are wrong tool selection and incorrect parameters, especially when tools have similar names."**

Mitigations in priority order:

1. **Better tool descriptions first** (tool-testing agent recovers 40% of completion time).
2. **Fewer tools** — delete or merge before specializing.
3. **Specialization via sub-agents** — narrow per-agent tool set.
4. **Tool Search Tool** — for catalogs > 50 tools.
5. **Explicit `tool_choice`** — force a specific tool when you know which is right (`tool_choice: {"type": "tool", "name": "x"}` uses 313 tokens vs 346 for `auto`).

## Tool-side vs agent-side responsibility

General rule: **move state and error handling into the tool whenever possible.** Reasons:

- Agent prompts stay short → cheaper and faster.
- Tool behavior is reused across all callers.
- Tool can be tested deterministically.
- Less surface area for the model to forget rules.

Belongs in the tool:

- Argument validation (raise structured error before the call hits the underlying API)
- Idempotency keys
- Output truncation / pagination defaults
- Retry with backoff for transient errors
- Default values
- Format normalization (e.g. always return ISO 8601 dates)

Belongs in the prompt:

- *When* to call which tool
- How to interpret results
- What to do on a permanent failure (which alternate tool, when to give up)
- The semantic goal that guides argument choice

**If you find yourself writing retry-loop or validation logic in the system prompt, prefer moving it into the tool wrapper** because Anthropic's guidance is that tools should be "self-contained, robust to error, and extremely clear with respect to their intended use."

What sub-agents should do when a tool call fails:

1. **Read the error.** Sub-agent prompts should explicitly require reading stderr/stack trace, not retrying blindly.
2. **Retry only on transient errors** (rate limit, network blip). Never on 4xx-class errors.
3. **Fall back to an alternate tool** when one exists (Grep fails → Glob+Read; gh CLI fails → curl to API).
4. **Bubble up failures the parent cares about**, distill the rest. A sub-agent that swallows a "couldn't find the file" error and returns "no results" is a disaster.

Worked example — splitting responsibility for a `gh issue create` wrapper:

| Concern | Lives where | Why |
|---|---|---|
| Title length validation, label normalization, body-template injection | Tool wrapper | Deterministic, always applies, every caller benefits. |
| Retry on 429 with exponential backoff | Tool wrapper | Transient, identical strategy every time. |
| Choice of repo, choice of labels, choice of assignee | Prompt | Semantic, depends on the task. |
| Decision to fall back to email when GitHub is down for 10+ minutes | Prompt | Cross-tool decision, depends on user policy. |

Mixing these — e.g. encoding "if 429, wait" in the prompt — bloats every system prompt by 50+ tokens for behavior that should run in 5 lines of Python inside the wrapper.

## Decision triggers

| If… | Then… | Because |
|---|---|---|
| Tool count visible to one agent > 30 | Specialize via sub-agents OR enable Tool Search Tool | Tool-selection accuracy degrades past 30–50 tools (Anthropic Tool Search docs) |
| Tool definitions consume > 10K tokens | Enable Tool Search Tool with `defer_loading: true` | ~85% context reduction; preserves prompt cache |
| A single tool's output is > 5K tokens | Wrap in a sub-agent for context isolation | Sub-agent absorbs output, returns 1–2K-token summary |
| Work is deterministic (parse, sort, validate, run command) | Use a tool/script, NOT a sub-agent | Sub-agents add latency, cost, hallucination risk |
| Multiple sub-agents need the same external capability | Define an MCP server, reference by name | Avoid duplicated schemas, share auth/transport |
| Sub-agent must be safe (no writes, no destructive ops) | Set `tools:` allowlist explicitly | Restriction enforced at runtime; instruction-only is bypassable |
| Untrusted content (web fetch, PR diff, user-uploaded doc) enters context | Process inside a sub-agent with read-only tools | Limits blast radius of indirect prompt injection / tool poisoning |
| Latency is the only problem | Use parallel tool calls in one agent first | 3+ parallel tools in one agent gets most of the 90% speedup |
| Tool failure is transient | Retry inside the tool wrapper, not the prompt | Keeps prompts simple; reusable across callers |
| Two tools have similar names | Rewrite descriptions with explicit "use this tool when… NOT this one" | Prevents the most common failure: wrong-tool selection |
| MCP server needed by ONE sub-agent only | Define inline in that sub-agent's `mcpServers` field | Keeps tool defs out of parent context |
| About to spawn a sub-agent that will only run one tool | Stop. That's a tool call, not a sub-agent | Anti-pattern — the spawn overhead buys nothing |
| Frontier model (Opus/Sonnet) is making tool-selection errors | The problem is your tool catalog, not the model | Even Opus 4 went 49% → 74% just by hiding tools behind search |

## Anti-patterns

Fire these as red flags during a tool-design review pass.

1. **Sub-agent that wraps a single deterministic tool call.** That is a Bash invocation. The sub-agent overhead (system prompt, fresh context, separate cache, coordination round-trip) buys nothing.
2. **Sub-agent with the parent's full tool list** (no `tools` field, no `disallowedTools`). You paid the spawn cost and got zero specialization. Either restrict the toolset or use `/fork` instead (forks share the cache).
3. **Verbose, unfocused tool definitions.** Multi-paragraph descriptions, vague boundaries. They dilute the prompt budget and confuse selection. Aim for: one-line purpose, when to use, when NOT to use, one example.
4. **Tools that return raw stderr/stdout** to a context-constrained agent. Wrap with truncation and structured fields. If output is intrinsically large, pair with the sub-agent context-isolation pattern.
5. **The same tool re-defined in every sub-agent's config.** Promote to an MCP server (or a shared agent-level skill).
6. **Hand-coded retry/validation in agent prompts** that should live in the tool. ("If the API returns 429, wait 5 seconds and try again.") Move to tool wrapper.
7. **Tools with arguments that can be misused.** Relative paths when absolute would prevent CWD bugs; free-form strings when an enum would constrain. Apply poka-yoke.
8. **Spawning a sub-agent purely for parallelism** when parallel tool use within one agent would do.
9. **MCP server defined globally in `.mcp.json`** when only one sub-agent needs it — burns context for every sub-agent that inherits.
10. **Naming two tools similarly** (`get_user`, `fetch_user`, `lookup_user`). Guarantees selection errors. Rename and namespace (`db_get_user`, `api_fetch_user`).
11. **Skipping the tool-testing pass.** Anthropic gets a 40% completion-time speedup from this; not doing it leaves free performance on the table.
12. **Forgetting that sub-agents cannot spawn sub-agents** ([per Claude Code docs](https://code.claude.com/docs/en/sub-agents)). If you design a coordinator-of-coordinators, the main session must be the top coordinator. Discovering this at runtime is a planning failure.

## Sources

- [Anthropic — Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) — ACI principles, Appendix 2 "Prompt engineering your tools," poka-yoke / absolute paths.
- [Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) — tool-testing agent (40% improvement), 3+ parallel tools per sub-agent, 90% speedup, scaling rules.
- [Anthropic — Introducing advanced tool use](https://www.anthropic.com/engineering/advanced-tool-use) — 134K-token tool overhead, 55K-token MCP setup, per-server token cost breakdown, programmatic tool calling 37% reduction.
- [Anthropic — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — sub-agent isolation returning 1–2K tokens, just-in-time retrieval, tools "self-contained, robust to error."
- [Claude Code — Sub-agents docs](https://code.claude.com/docs/en/sub-agents) — built-in sub-agents, `tools` allowlist + `disallowedTools` denylist, `mcpServers` inline scoping, `PreToolUse` hooks, frontmatter spec.
- [Claude API — Tool Search Tool docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool) — "Claude's ability to correctly pick the right tool degrades significantly once you exceed 30–50 available tools," Opus 4: 49%→74%, Opus 4.5: 79.5%→88.1%, `defer_loading` semantics.
- [Claude API — Tool use overview](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview) — system-prompt token costs (346 / 313 by `tool_choice`), strict mode, client vs server tools.
- [Model Context Protocol — Introduction](https://modelcontextprotocol.io/introduction) — MCP architecture, "USB-C for AI applications."
- [Arcade — Anthropic Tool Search Test: 4,000 Tools, 60% Success](https://arcade.dev/blog/anthropic-tool-search-4000-tools-test) — empirical scaling test.
- [SWE-Bench Pro Technical Report](https://static.scale.com/uploads/654197dc94d34f66c0f5184e/SWEAP_Eval_Scale%20(9).pdf) — failure-mode taxonomy: 35.6% context overflow on Sonnet 4, 42% tool-use inefficiency on smaller models.
- [arXiv 2508.16260 — MCPVerse benchmark](https://arxiv.org/html/2508.16260v2) — most models degrade with larger tool sets; Claude-4-Sonnet is an exception.
- [Invariant Labs — MCP Tool Poisoning Attacks](https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks) and [MCPTox benchmark](https://www.practical-devsecops.com/mcp-security-vulnerabilities/) — 72.8% attack success on o1-mini, cross-server exfiltration, defenses.
- [Microsoft — Protecting against indirect prompt injection in MCP](https://developer.microsoft.com/blog/protecting-against-indirect-injection-attacks-mcp).
- [Simon Willison — MCP prompt injection problems](https://simonwillison.net/2025/Apr/9/mcp-prompt-injection/).
