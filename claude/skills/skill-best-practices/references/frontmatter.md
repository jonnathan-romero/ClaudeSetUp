# Frontmatter Reference

Every SKILL.md field, with examples and when to use it.

## Contents

- [Required fields](#required-fields)
- [Invocation control](#invocation-control)
- [Tool access](#tool-access)
- [Arguments](#arguments)
- [Auto-activation by file path](#auto-activation-by-file-path)
- [Subagent execution](#subagent-execution)
- [Compute overrides](#compute-overrides)
- [Hooks](#hooks)
- [Shell selection](#shell-selection)
- [What does NOT exist](#what-does-not-exist)

## Required fields

### `name`

- Kebab-case (`my-skill`, not `my_skill` or `MySkill`)
- ≤64 characters
- Lowercase letters, numbers, hyphens only
- Must match the containing directory name
- Becomes the slash command: `/my-skill`

```yaml
name: skill-best-practices
```

### `description`

- Claude Code truncates the `description` + `when_to_use` *combined* at 1536 chars (`maxSkillDescriptionChars`); the 1024 figure is the open-standard author cap — stay under 1024 for portability and headroom
- Third person, imperative voice
- Lead with **what** + **when** in the first sentence
- Include concrete trigger phrases — file extensions, verbatim user wordings, domain terms
- Add negative triggers when scope is ambiguous

```yaml
description: Extract text and tables from PDFs. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction. Do NOT use for image-only files.
```

See `descriptions.md` for the full pattern library.

## Invocation control

### `disable-model-invocation`

Set `true` to prevent Claude from auto-triggering. The skill runs only when the user types `/name`. The description is *excluded* from Claude's context (Claude doesn't know it exists). Use for side-effect actions.

```yaml
---
name: deploy
description: Deploy to production
disable-model-invocation: true
allowed-tools: Bash(kubectl *) Bash(helm *)
---
```

### `user-invocable`

Set `false` to hide from the `/` menu. Only Claude can invoke it. The description *stays* in Claude's context. Use for background knowledge.

```yaml
---
name: legacy-monolith-context
description: Architecture and conventions of the legacy monolith
user-invocable: false
---
```

## Tool access

### `allowed-tools`

Pre-approves tools so Claude doesn't prompt mid-skill. Does *not* expand permissions beyond your settings — your global permission rules still apply.

Two valid forms:

```yaml
allowed-tools: Bash(git add *) Bash(git commit *) Read Grep
```

```yaml
allowed-tools:
  - Bash(git add *)
  - Bash(git commit *)
  - Read
  - Grep
```

Pattern syntax matches permission rules: `ToolName` (any use) or `ToolName(pattern *)` (matched use).

## Arguments

### `arguments` and `argument-hint`

Declare positional inputs to the skill, accessible inside SKILL.md.

```yaml
---
name: fix-issue
description: Fix a GitHub issue by number
arguments: [issue, branch]
argument-hint: "[issue-number] [branch]"
---

Check out `$branch`, read issue $issue, implement the fix, run tests.
```

- `arguments` → string ("issue branch") or list (`[issue, branch]`)
- `argument-hint` → autocomplete display after `/fix-issue `
- Reference inside body as `$name` (or `$0`/`$1` if unnamed)
- `$ARGUMENTS` always expands to the full input string

Multi-word arguments use shell quoting: `/fix-issue "OAuth login broken" main`.

## Auto-activation by file path

### `paths`

Glob patterns. Claude auto-loads the skill only when the active file matches.

```yaml
paths: "src/**/*.tsx,src/**/*.jsx"
```

```yaml
paths:
  - "src/**/*.py"
  - "tests/**/*.py"
```

Use for language- or module-specific skills (a React component skill, a Rails controller skill) so they don't bloat the description budget across unrelated repos.

## Subagent execution

### `context: fork` + `agent`

Run the skill in a fresh subagent. The skill body becomes the subagent's task; it inherits no conversation history and reports back a summary.

```yaml
---
name: deep-research
description: Research a topic across the codebase
context: fork
agent: Explore
---

Find every call site of $ARGUMENTS, read surrounding code, summarize findings.
```

Built-in `agent` values: `Explore`, `Plan`, `general-purpose`. Custom agents from `.claude/agents/` also work.

Trade-off: forked context isolates noise but loses conversation history. Use for read-heavy or research-heavy work where the result is a summary.

## Compute overrides

### `model`

Switch model just for this skill's invocation.

```yaml
model: claude-opus-4-7   # or `inherit` to keep session model
```

### `effort`

Adjust reasoning depth.

```yaml
effort: high   # low | medium | high | xhigh | max
```

Use `high` for architecture, migrations, complex reasoning. Use `low` for fast lookups.

## Hooks

### `hooks`

Skill-scoped lifecycle hooks (fired only while the skill is active). Format mirrors `settings.json`.

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      type: command
      command: scripts/safety-check.sh
```

Loaded at session start; restart Claude Code after edits. Full spec: https://code.claude.com/docs/en/hooks.

## Shell selection

### `shell`

Default `bash`. Use `powershell` on Windows when `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`.

```yaml
shell: bash
```

Affects `` !`command` `` injection blocks inside SKILL.md.

## What does NOT exist

Clearing up common confusions:

- **No `version` / `schema_version` field.** Skills version with their containing plugin (via git tags), not in SKILL.md.
- **No `requires` / `dependencies` field on a skill.** Plugin-level dependencies live in `.claude-plugin/plugin.json`.
- **No compiled `.skill` artifact in everyday use.** A skill is a directory; `skill-creator`'s `package_skill.py` produces zips for transport, but installs are git-based.
- **No reserved field for "category" or "tags".** Those live on the plugin/marketplace manifest.
