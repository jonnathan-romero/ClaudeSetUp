# Skill vs. Other Primitives

Before writing a SKILL.md, confirm a skill is the right answer. The five primitives Claude Code exposes solve different problems.

## Contents

- [Decision matrix](#decision-matrix)
- [Skill vs. CLAUDE.md](#skill-vs-claudemd)
- [Skill vs. hook](#skill-vs-hook)
- [Skill vs. subagent](#skill-vs-subagent)
- [Skill vs. slash command](#skill-vs-slash-command)
- [Skill vs. MCP server](#skill-vs-mcp-server)
- [Decision tree](#decision-tree)

## Decision matrix

| | Skill | CLAUDE.md | Hook | Subagent | Slash Command | MCP Server |
|---|---|---|---|---|---|---|
| **Triggered by** | Claude (auto) or user (`/name`) | Always loaded | Lifecycle event | Claude delegates | User types `/name` | Tool calls |
| **Determinism** | Claude reasons | Claude reasons | Deterministic | Claude reasons (isolated) | Claude reasons | External system |
| **Context cost** | Description always; body on use | Always loaded | Zero | Isolated | Body on use | Tool descriptions only |
| **Best for** | On-demand expertise / workflow | Always-on rules | Enforcement | Read-heavy isolated tasks | (Mostly merged into skills) | External tools (DB, browser, Slack) |
| **Worst for** | Always-on rules; enforcement | One-off workflows | Judgment calls | Tasks needing conversation history | (Use a skill) | Local-only logic |

## Skill vs. CLAUDE.md

**CLAUDE.md** is for project-wide *rules* that should apply to every interaction in that repo: language version, formatting, libraries to prefer, never-do constraints. It's always loaded.

**Skill** is for *invocable workflows* or domain expertise the model should reach for in specific situations.

| Use CLAUDE.md when | Use a skill when |
|---|---|
| The instruction applies to *every* turn in this project | The instruction applies only when the user is doing X |
| Under 200 lines of always-on guidance | Reference material >200 lines |
| Never invoked, just absorbed | Sometimes invoked explicitly via `/name` |

A skill that says "always use 4-space indentation" should be a CLAUDE.md line. A skill that walks through a security review checklist should stay a skill.

## Skill vs. hook

Hooks are shell commands the harness runs on lifecycle events (`PreToolUse`, `PostToolUse`, `Stop`, etc.). They run *every time* the event fires. No reasoning, no skipping.

Skills are content Claude *might* apply if the description matches.

| Use a hook when | Use a skill when |
|---|---|
| It must run *every time* on event X | It applies sometimes, based on context |
| The action is deterministic (run a command, block a tool, log a line) | The action requires judgment |
| Failure should block the operation | Skipping is acceptable |

Examples:
- "Block `rm -rf /` everywhere" → **hook**
- "Review pending changes for security issues when asked" → **skill**
- "Run lint after every edit, no exceptions" → **hook**
- "Help me write a commit message" → **skill**

If you find yourself writing "always" or "never skip" in a SKILL.md, it should probably be a hook.

## Skill vs. subagent

Subagents are isolated workers with their own context window. They take a task, work in isolation, and return a summary.

| Use a subagent when | Use a skill when |
|---|---|
| Task reads many files; you don't want them in main context | Task is small or interactive |
| Specialized agent type fits (Explore, Plan) | Standard reasoning is fine |
| You want parallel work (multiple subagents) | Sequential work is fine |
| The output is a summary, not a back-and-forth | You want conversation continuity |

A skill *can* run inside a subagent via `context: fork` + `agent:` — best of both worlds when a skill needs to do heavy reading.

## Skill vs. slash command

In current Claude Code, slash commands are largely subsumed by skills (skills also expose `/name`). The legacy `commands/` directory still works, but new authoring should use skills with appropriate `disable-model-invocation` and `user-invocable` flags.

- User-only invocation, no auto-trigger → skill with `disable-model-invocation: true`
- Auto-trigger plus optional manual invocation → regular skill (default behavior)
- Background knowledge Claude reads but users don't slash-invoke → skill with `user-invocable: false`

## Skill vs. MCP server

MCP servers *connect* Claude to external systems and expose tool calls. They're for capability — DB access, browser control, Slack posting, GitHub APIs.

Skills *teach* Claude how and when to use those tools.

| Use an MCP server when | Use a skill when |
|---|---|
| You need to reach an external system | You need to encode workflow or judgment |
| The integration is tools (function calls) | The integration is instructions (text) |
| Multiple skills will share the connection | The expertise is self-contained |

Pattern: an MCP server provides Postgres tool calls; a skill documents your schema and query conventions. They compose.

## Decision tree

```
Does it have to run every time on an event?
├── Yes → hook
└── No
    ├── Does it need to reach an external system?
    │   ├── Yes → MCP server (and maybe a skill that documents its use)
    │   └── No
    │       ├── Is it an always-on project rule?
    │       │   ├── Yes → CLAUDE.md line
    │       │   └── No
    │       │       ├── Is it read-heavy and benefits from isolation?
    │       │       │   ├── Yes → subagent (or skill with context: fork)
    │       │       │   └── No → skill
```

If the answer comes out "skill," continue with `descriptions.md` and the SKILL.md template in the parent skill.
