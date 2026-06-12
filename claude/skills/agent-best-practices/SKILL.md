---
name: agent-best-practices
description: 'Authoritative reference and quality checklist for writing Claude Code subagents (.claude/agents/*.md definition files). ALWAYS trigger when authoring, reviewing, debugging, or improving a subagent / agent definition, choosing a subagent''s model or tools, or deciding whether to delegate work to a subagent at all. Use when the user asks to "write an agent", "create a subagent", "review this agent", "why won''t my agent trigger", "should this be a subagent", "what tools should this agent have", or mentions agent frontmatter, the description/tools/model fields, proactive delegation, context isolation, agent parallelization, or .claude/agents files. Do NOT use for authoring SKILL.md skills (use skill-best-practices) or for general prompt writing (use prompt-master).'
---

# Agent Best Practices

Quality bar and structural reference for authoring Claude Code **subagents** — the `.md` definition files under `.claude/agents/` (or a plugin's `agents/`). Sibling to `skill-best-practices`: that skill governs SKILL.md authoring, this one governs subagent definitions. They answer different questions — *"is this a skill or a subagent?"* lives in both, but everything downstream (frontmatter fields, system-prompt shape, tool boundaries, delegation mechanics) is agent-specific here.

## When to invoke this skill

- Writing a new subagent definition file
- Reviewing or critiquing an agent before committing it
- Debugging an agent that won't auto-delegate, or fires when it shouldn't
- Choosing an agent's `model` or `tools` grant
- Deciding whether a job should be a subagent at all (vs. main conversation, a fork, a skill, or a hook)

Run the pre-publish checklist below before declaring an agent done.

## The one thing to internalize first

A subagent is an **isolated Claude instance with its own context window** that does *one job*, returns a result, and disappears. It does **not** see your conversation, the files you've read, or the skills you've invoked. That single fact drives every design decision: the best subagents are **read-many-files, write-little, fresh-context** jobs (review, audit, research, explain) — not the "write this function" work the base model already does well inline. If a job needs your accumulated context, frequent back-and-forth, or low latency, it should *not* be a subagent. See [`references/operations.md`](references/operations.md).

## Pre-publish checklist

| # | Check | How to verify |
|---|---|---|
| 1 | Frontmatter parses as valid YAML; closing `---` on its own line | `python -c "import yaml; yaml.safe_load(open('agent.md'))"` |
| 2 | `name` is kebab-case, matches the filename (`code-reviewer` → `code-reviewer.md`) | Visual |
| 3 | `description` states **when to delegate**, written for the router — not a resume of the agent's expertise | See [`references/anatomy.md`](references/anatomy.md) |
| 4 | `tools` grant matches the agent's verb — a *reviewer/auditor* is read-only (no `Edit`/`Write`); a *fixer* gets `Edit` | See [`references/anatomy.md`](references/anatomy.md) |
| 5 | `tools` is **not omitted** on a review/audit/research agent (omitting it silently inherits Write/Edit) | Visual |
| 6 | `model` chosen deliberately (deep analysis → opus; procedural → sonnet; cheap high-volume reads → haiku; thin specialist → inherit) | See [`references/operations.md`](references/operations.md) |
| 7 | System prompt opens with a `When invoked:` numbered workflow that forces a deterministic start | Visual |
| 8 | Output contract is prescribed (severity tiers, fixed per-issue template, or an `## Output Format` section) | Visual |
| 9 | Any rule the agent can't infer from fresh context is restated in the body (it won't see `vendor/`-ignore rules, etc.) | Visual |
| 10 | No `Agent` tool in the grant (subagents can't spawn subagents); no absolute paths or secrets | `grep -E 'Agent|/home/|sk-[a-zA-Z0-9]' agent.md` |

## Top mistakes that break subagents

1. **Description is a bio, not a trigger.** "Elite code review expert specializing in..." tells the router *what the agent is*, not *when to call it*. The router matches on the user's situation — write "Use immediately after writing or modifying code" or "Use this agent when you need to audit dependencies for CVEs." Lead with the trigger condition.
2. **Cargo-culting "MUST BE USED PROACTIVELY."** The phrase is documented, but auto-delegation is *unreliable* — there's a confirmed bug (anthropics/claude-code#5688) where it never fired. An `@-mention` is the **only guaranteed trigger**. Don't stake a critical agent on auto-routing; expect to invoke it explicitly. See [`references/operations.md`](references/operations.md).
3. **Omitting `tools` on a "read-only" agent.** Omitted `tools` = inherits *every* tool. A code-reviewer or security-auditor that can silently `Write` and `Edit` is a contradiction. Treat the tool list as a security boundary.
4. **Subagent for the wrong shape of work.** Small targeted edits, latency-sensitive tasks, tightly-coupled multi-phase work (plan → implement → test sharing context), and anything needing back-and-forth are *worst-fit*. The overhead — 4–15× token multiplication and fresh-context startup latency — outweighs the benefit. Do it in the main conversation.
5. **Assuming the subagent sees your chat.** It starts fresh. If it must "ignore the `vendor/` directory" or "use the v2 API," restate that in the agent body or the delegation prompt — it has no other way to know.
6. **Designing an orchestrator subagent that spawns workers.** Subagents **cannot nest.** The `Agent` tool is unavailable inside a subagent even if listed. Orchestration only works from the main thread; otherwise chain agents sequentially or use a skill.
7. **Encyclopedic taxonomy bloat.** A 200-line `## Capabilities` list of buzzwords helps keyword-matching a little but mostly burns context every run without changing behavior. The part that earns its tokens is `## Behavioral Traits` — *how* to act ("Never trusts user input"), not *what* it knows.

## Core design principles

### 1. The description is a routing rule, not a bio
The `description` is the single field the router uses to decide delegation. Write it for the dispatcher: name the *situation* that should trigger the agent ("Use this agent when…", "Use immediately after…"), packed with the trigger nouns the caller will actually use. Mediocre descriptions list the agent's qualifications; great ones describe the user's moment of need.

### 2. Tool grants are a security boundary — match them to the verb
A *reviewer* gets `Read, Grep, Glob, Bash` (no `Edit`). A *debugger/fixer* adds `Edit` because fixing requires mutation. An *auditor* might be `Read, Grep, Glob` (not even Bash). Decide the grant from the agent's job, and use `disallowedTools` or a `PreToolUse` hook when the allowlist is too coarse to express the rule ("Bash, but SELECT only"). See [`references/anatomy.md`](references/anatomy.md) and [`references/operations.md`](references/operations.md).

### 3. Right-size the model
Pin `opus` for deep, high-stakes analysis (security audit, architectural critique); `sonnet` for the procedural workhorse jobs (debug, test-gen, refactor); `haiku` for cheap, high-volume reads (search, doc summarization — watch for weak multi-step reasoning); `inherit` for a thin specialist that should track whatever the caller runs. Anthropic's own pattern is an Opus lead orchestrating Sonnet workers.

### 4. Force a deterministic start, prescribe a deterministic end
The most-copied structural element across good agents is a `When invoked:` numbered workflow (`1. Run git diff` / `1. Capture the error and stack trace`) that grounds the agent before it reasons. Pair it with a fixed output contract (severity tiers, or a root-cause→evidence→fix→test→prevention template) so every invocation returns the same shape. That repeatability is what makes a subagent *reusable* rather than a one-off prompt.

### 5. Restate what the fresh context can't see
Isolation is the feature *and* the cost. The agent gets its own system prompt + the delegation message + CLAUDE.md/memory + a git-status snapshot — nothing else. Bake any non-obvious constraint into the body or the delegation prompt.

### 6. Don't delegate work that wants to stay home
Reach for the main conversation (or `/btw` for a quick context-aware question, or a *fork* when the agent needs the whole conversation) when the task is small, latency-sensitive, iterative, or shares heavy context across phases. Subagents win for isolated, parallelizable, read-heavy, high-volume-output jobs — and lose for almost everything else.

## Frontmatter quick reference

| Field | Required | Notes |
|---|---|---|
| `name` | yes | kebab-case, matches the filename |
| `description` | yes | The routing trigger — when to delegate, in the caller's words |
| `tools` | no | Allowlist. **Omitted = inherits ALL tools.** Match to the agent's verb |
| `disallowedTools` | no | Denylist; applied *before* `tools`. A tool in both is removed |
| `model` | no | `opus` / `sonnet` / `haiku` / `fable` / full ID / `inherit` (default `inherit`) |
| `permissionMode` | no | e.g. `plan` for read-only enforcement |
| `isolation` | no | `worktree` runs the agent in a temp git worktree (auto-cleaned if unchanged) |
| `hooks` | no | `PreToolUse` / `PostToolUse` gates, scoped to this agent, torn down when it finishes |
| `mcpServers` | no | Per-agent MCP connections |

**Plugin caveat:** plugin subagents *silently ignore* `hooks`, `mcpServers`, and `permissionMode` — those fields only work in user/project agents. Full field-by-field detail and examples in [`references/anatomy.md`](references/anatomy.md).

## When something should NOT be a subagent

Quick gut check before writing any agent file:

- Must run *every* time on an event (post-edit, pre-commit) → **hook**
- Reusable instructions/workflow that should run in the *main* context with your history → **skill**
- A quick context-aware question with no tools and a throwaway answer → **`/btw`**
- Needs the entire current conversation to be useful → **fork** (a subagent that inherits the conversation), not a fresh agent
- Small, targeted, latency-sensitive, or tightly-coupled multi-phase work → **main conversation**
- Reads many files in isolation and returns a summary; runs in parallel with peers; needs restricted tools → **subagent** ✅

The decision rule from the ecosystem: *reusable instructions → Skills; deterministic automation → Hooks; delegated work needing only the result → Subagents.*

## Deeper references

- [`references/anatomy.md`](references/anatomy.md) — dissecting a definition file: description dialects, `tools` strategies, `model` choices, the two system-prompt archetypes, output-format conventions, and the five traits best-in-class agents share.
- [`references/operations.md`](references/operations.md) — how subagents actually behave: model resolution order, proactive-trigger unreliability and the escape hatches, context-isolation costs and token multipliers, the no-nesting rule and its workarounds, hook enforcement, and parallelization gotchas.
- [`references/ideas.md`](references/ideas.md) — what's worth building: the consensus-core agents, the long-tail high-leverage picks, and the subagent-vs-skill-vs-hook decision.
