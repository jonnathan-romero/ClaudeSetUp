# How Subagents Actually Behave

Operational mechanics and failure modes beyond "here's a list of agents" — drawn from the official docs, Anthropic's multi-agent-research engineering post, and filed bugs. Use this when choosing a model, debugging delegation, reasoning about cost, or designing parallel/orchestrated work.

## Contents
1. [Model selection & resolution order](#1-model-selection)
2. [Proactive-invocation reliability](#2-proactive-invocation-reliability)
3. [Context isolation — what loads, what it costs](#3-context-isolation)
4. [Orchestration limits — no nested subagents](#4-orchestration-limits)
5. [Enforcement via hooks](#5-enforcement-via-hooks)
6. [Parallelization gotchas](#6-parallelization)
7. [Anti-patterns & when not to delegate](#7-anti-patterns)

---

## 1. Model selection

`model` accepts `sonnet`, `opus`, `haiku`, `fable`, a full ID (e.g. `claude-opus-4-8`), or `inherit` (default).

**Resolution order** (first wins): `CLAUDE_CODE_SUBAGENT_MODEL` env var → per-invocation `model` param → the definition's `model` frontmatter → the main conversation's model.

Per-model fit:
- **Haiku** — high-volume file ops, doc generation, search summarization. Watch for weak subtle reasoning / multi-step plans.
- **Sonnet** — the workhorse: code review, refactoring, debugging, test writing.
- **Opus** — security audits, architectural critique, gnarly debugging. Latency + cost; overkill for cleanup.

Anthropic's canonical multi-agent pattern is an **Opus lead orchestrating Sonnet subagents**, which outperformed single-agent Opus by 90.2% on their research eval — the "expensive orchestrator + cheaper workers" shape. Picking the right model per agent is where most cost optimization happens.

## 2. Proactive-invocation reliability

The router delegates based on three signals: **your request, the `description` field, and current context.** The documented trick is to put "use proactively" in the description.

**But it's unreliable.** A filed bug (anthropics/claude-code#5688, closed *not planned*) reports that even all-caps "you MUST use this agent proactively" never triggered auto-delegation. Practitioner consensus agrees: Claude frequently handles a task inline rather than delegating, even when the agent's description clearly matches.

**The escape hatches, in order of reliability:**
- **`@-mention`** — guarantees the subagent runs for one task. The only *guaranteed* trigger.
- **Session-wide** — `--agent` flag / `agent` setting makes the whole session use that agent.
- A well-written, situation-shaped description still helps when delegation *does* fire.

**Implication for design:** don't stake a critical workflow on auto-routing. Assume the user (or you, from the main thread) will invoke the agent explicitly, and write the description so it's easy to *find and choose*, not just auto-match.

## 3. Context isolation

A non-fork subagent starts **fresh**: it does *not* see your conversation history, the skills you've invoked, or the files already read.

**What it does receive:** its own system prompt (not the full Claude Code system prompt) + a delegation message summarizing the task + every level of CLAUDE.md/memory + a git-status snapshot + any preloaded skills. (Built-in Explore/Plan skip the memory load.)

**The cost of isolation:**
- **Restate-the-rule tax.** "Ignore the `vendor/` directory" must be repeated in the delegation prompt — the agent has no other way to know.
- **No memory across runs.** Each invocation is a fresh instance unless persistent memory is explicitly enabled.
- **Token multiplication.** Each agent opens its own context window; multi-agent workflows run roughly **4–15× the tokens** of a single-agent session (Anthropic: ~4× vs chat for one agent, ~15× for multi-agent; practitioners report 4–7×). Order-of-magnitude, not precise — but real.

**When isolation hurts** — and the escape hatches:
- **Fork** — a subagent that *inherits the entire conversation* instead of starting fresh. Drops input isolation; use when a named agent would need too much background to be useful.
- **`/btw`** — a quick question against your full context, no tool access, answer discarded. No spawn.
- Docs' own "use the main conversation when": the task needs frequent back-and-forth; multiple phases share significant context (planning → implementation → testing); latency matters.

## 4. Orchestration limits

**Hard rule: subagents cannot spawn subagents.** The `Agent` tool is unavailable inside a subagent even when listed in `tools`. Only a *main-thread* agent (`claude --agent`) can spawn, and it can allowlist which types via `tools: Agent(worker, researcher), …`. (The built-in Plan agent exists precisely to gather context *without* nesting.)

**Workarounds for "orchestrator" designs:**
1. **Main-thread orchestration** — keep all delegation in the top session; only it holds the `Agent` tool.
2. **Sequential chaining** — each subagent returns to the main conversation, which passes relevant context to the next.
3. **Skills** instead of nested delegation (they run in the main context).
4. **Agent teams** for sustained parallelism beyond one session — each worker gets its own independent context.

Subagents report back to the main conversation and **can't talk to one another.**

## 5. Enforcement via hooks

`tools`/`disallowedTools` are static allow/deny lists. When you need a *conditional* rule the list can't express ("Bash, but SELECT only"), use a `PreToolUse` hook:

```yaml
name: db-reader
tools: Bash
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-readonly-query.sh"
```

The hook reads the tool call as JSON on stdin; **exit code 2 blocks the call** and feeds the error back to Claude. A script that greps the command for `INSERT|UPDATE|DELETE|DROP|…` and exits 2 is a deterministic gate independent of whether the model "respects" its prompt — belt-and-suspenders with a prose reminder in the body. `PostToolUse` can chain enforcement too (e.g. lint after every `Edit|Write`).

Frontmatter hooks are scoped to the agent and torn down when it finishes. **Caveat:** plugin subagents silently ignore `hooks`, `mcpServers`, and `permissionMode`.

## 6. Parallelization

Spawn multiple subagents for **independent** investigations; Claude synthesizes the findings. Anthropic's lead spawns 3–5 in parallel and cut research time up to 90%. It works best when the paths don't depend on each other.

**Gotchas:**
- **Same-file parallel edits = conflict.** Two agents editing one file is "a recipe for conflict"; run sequentially.
- **`cd` does not persist** between a subagent's Bash calls, nor affect the main working directory.
- **`isolation: worktree`** gives each agent an isolated repo copy (auto-cleaned if unchanged) — but 3+ concurrent worktree spawns can race on `.git/config.lock` (anthropics/claude-code#34645) and leave an orphaned `worktree-agent-*` branch. Worktrees also *don't* isolate process/env/DB, and `node_modules` isn't shared.
- **Returning many detailed results re-floods the parent context** — have parallel agents return summaries, not dumps.
- **Background subagents auto-deny** any tool call that would otherwise prompt; a clarifying-question tool call silently fails while the agent continues.

## 7. Anti-patterns

- **Auto-delegation often just doesn't fire** (§2). Headline disappointment: you build the agent, Claude does the work inline.
- **"Don't spawn agents because you can."** Subagents excel for read-heavy research and exploration, *not* parallel coding.
- **Overhead beats benefit for small work.** For quick, targeted edits the main conversation is faster — delegation latency + 4–15× tokens aren't worth it.
- **Multi-agent is the wrong tool for coupled coding more often than people think.** Most coding has fewer truly parallel tasks than research, and agents are not yet great at real-time coordination. Anthropic gates multi-agent on "tasks where the value is high enough to pay for the increased performance."
- **Dangerous config:** `permissionMode: bypassPermissions` skips prompts including writes to `.git`, `.claude`, `.vscode`. Name collisions within one scope are discarded *without warning*.

**Net:** the criticism is real but bounded. No serious source says subagents are useless — the consistent message is *narrow them*. They win for isolated, parallel, read-heavy, high-volume-output, bounded work; they lose for small edits, tightly-coupled multi-phase coding, and anything needing shared context.
