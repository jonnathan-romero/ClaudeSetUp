# Debugging Skill Activation

When a skill won't trigger, or triggers when it shouldn't. Walk these in order.

## Contents

- [The three failure modes](#the-three-failure-modes)
- [Diagnostic commands](#diagnostic-commands)
- [Mode 1: Token budget overflow](#mode-1-token-budget-overflow)
- [Mode 2: Frontmatter or YAML breakage](#mode-2-frontmatter-or-yaml-breakage)
- [Mode 3: Description design](#mode-3-description-design)
- [Over-triggering](#over-triggering)
- [Common pitfalls](#common-pitfalls)

## The three failure modes

A skill that won't trigger has one of three problems, in order of how often they occur:

1. **Token budget overflow** — too many skills installed, descriptions truncated silently
2. **Frontmatter / YAML breakage** — loader skipped the file
3. **Description design** — loader sees it, router doesn't pick it

Diagnose in this order; each is cheap to check.

## Diagnostic commands

| Command | What it shows |
|---|---|
| `/skills` | All loaded skills, descriptions as the router sees them, invocation mode |
| `/context` | Current token usage (confirms the skill's metadata is loaded) |
| `/doctor` | Schema validation errors in settings and SKILL.md |
| `/debug` | Interactive session debugging — ask why a skill didn't trigger |

If a skill is missing from `/skills`, it's mode 1 or 2. If it appears but doesn't trigger on the right prompts, it's mode 3.

## Mode 1: Token budget overflow

All skill names + descriptions pre-load into a listing budget that scales with the model's context window (`skillListingBudgetFraction`, default ~1% — ≈2K tokens at 200K, ≈10K at 1M). When you exceed the budget, the least-used skills' descriptions drop or truncate first. `SLASH_COMMAND_TOOL_CHAR_BUDGET` survives only as a fixed-count override.

**Symptoms**

- Skill missing from `/skills`, or appears with a truncated description
- Some skills load, others don't, with no obvious pattern
- Got worse after installing a new plugin

**Diagnose**

```bash
echo $SLASH_COMMAND_TOOL_CHAR_BUDGET   # only set if you've overridden the default
```

Inside Claude Code:
```
/skills
/doctor      # reports whether the skill-listing budget is overflowing
```
Count installed skills × average description length. If it exceeds ~1% of the model's context window, you're truncating.

**Fix**

- Tighten descriptions across the board (target ≤300 chars where you can)
- Front-load critical use cases — first sentence survives truncation
- Disable or uninstall unused skills/plugins
- Raise the budget: either set `skillListingBudgetFraction` higher in settings, or pin a fixed count with `export SLASH_COMMAND_TOOL_CHAR_BUDGET=20000` before launching Claude Code

## Mode 2: Frontmatter or YAML breakage

The skill file exists, but the loader rejects it.

**Symptoms**

- Skill missing from `/skills` entirely
- `/doctor` reports schema errors
- Skill worked yesterday, broke after editing

**Diagnose**

Validate the YAML directly:

```bash
python -c "import yaml; print(yaml.safe_load(open('SKILL.md').read().split('---')[1]))"
```

Confirm:
- File path is `name/SKILL.md`, not `name.md` and not `name/skill.md`
- Frontmatter opens with `---` on its own line at the start
- Frontmatter closes with `---` on its own line *with a blank line after it*
- `description` is on a single line — no `>` or `|` block scalars
- No tab characters in YAML (spaces only)
- Required fields present: `name`, `description`

**Fix**

- Disable Prettier's `proseWrap` for `.md` files in your editor; it reflows long descriptions and breaks the YAML
- If Prettier insists, escape multi-line as a JSON string inside the YAML
- After saving, `git diff` and look for unexpected line wrapping

## Mode 3: Description design

The skill loads, but the router doesn't pick it for the prompts you expect.

**Symptoms**

- `/skills` shows the skill correctly
- Manual `/skill-name` invocation works
- Auto-trigger fails on prompts you'd expect to match

**Diagnose**

1. Read the description that loaded (via `/skills`).
2. Try a prompt using the *exact words* from the description. Does it trigger? If yes, your description is too narrow.
3. Search for keyword collisions:
   ```
   grep -h "^description:" ~/.claude/skills/*/SKILL.md ~/.claude/plugins/*/skills/*/SKILL.md
   ```
   If multiple skills mention the same keywords, the router splits across them.

**Fix**

Apply patterns from `descriptions.md`:
- Lead with what + when
- Add verbatim user phrasings
- Add concrete trigger keywords (extensions, tool names, jargon)
- For collisions, add negative triggers ("Do NOT use for X")
- Push toward "ALWAYS trigger when..." if under-triggering

If you have access to `skill-creator`, run its description optimizer (`run_loop.py`) — it iterates the description automatically against an eval set.

## Over-triggering

The skill triggers on prompts where it shouldn't.

**Diagnose**

What in the description is over-broad? Common culprits:
- Generic verbs ("works with", "handles", "processes")
- Too many domain terms relative to scope
- Missing negative triggers

**Fix**

- Narrow the lead clause — what specifically does it do?
- Add explicit "Do NOT use for..." or "SKIP when..." lines
- Remove keywords that match adjacent domains

## Common pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| File named `skill.md` instead of `SKILL.md` | Loader skips it (case-sensitive on Linux) | Rename |
| Skill in `.claude/skills/name.md` (no directory) | Loader skips loose files | Create `name/` directory, move to `name/SKILL.md` |
| Settings in `.claude.json` instead of `.claude/settings.json` | Settings ignored | Move config to `.claude/settings.json` |
| Plugin skill installed but invisible | Namespace not applied | Run `/skills` — should appear as `plugin-name:skill-name` |
| Edits not reflected | New directories require restart | Restart Claude Code |
| `disable-model-invocation: true` set unintentionally | Skill never auto-triggers, only via `/name` | Remove the field or set `false` |
| `paths:` glob too narrow | Skill never auto-triggers because no file matches | Widen the glob or remove `paths:` entirely |
| Skill triggered but Claude ignored it | Effort/model override too low for the task | Bump `effort: high` or remove the override |
