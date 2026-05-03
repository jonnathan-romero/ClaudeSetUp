# Skill, agent, and rule definition prompts

Special-case rules for prompts whose job is to *trigger* and *configure* an agent — Claude Code SKILL.md frontmatter, `.claude/agents/*.md` system prompts, Cursor `.mdc` rules, `.clinerules`, OpenAI Agents SDK instructions.

The principle: **the description is the product.** A perfect 500-line body with a vague description never runs.

## Contents

- [SKILL.md — what to audit](#skillmd--what-to-audit)
- [Subagent definitions (`.claude/agents/<name>.md`)](#subagent-definitions-claudeagentsnamemd)
- [Cursor / Cline / Aider conventions](#cursor--cline--aider-conventions)
- [Common skill-prompt failures](#common-skill-prompt-failures)
- [When triggering won't reliably fire](#when-triggering-wont-reliably-fire)
- [Audit checklist for a SKILL.md you're reviewing](#audit-checklist-for-a-skillmd-youre-reviewing)
- [How to optimize a skill description](#how-to-optimize-a-skill-description)

## SKILL.md — what to audit

### Frontmatter

- `name`: kebab-case, ≤64 chars, matches directory name. No surprises.
- `description`: ≤1024 chars, single line, third-person, leads with what + when. Concrete trigger phrases. Negative triggers when scope ambiguous.
- Optional fields (`allowed-tools`, `paths`, `model`, `effort`, `context: fork`, etc.) only when they pull weight.

### Description rubric (the high-leverage check)

A strong description has 4 parts in order:

1. **What** — third-person clause stating the action ("Extracts text and tables from PDFs").
2. **When** — concrete file context ("Use when working with .pdf files").
3. **Trigger keywords** — file extensions, tool names, domain jargon, verbatim user phrasings (in quotes).
4. **Negative triggers** — "Do NOT use for…" when scope overlaps another skill.

Pushy phrasing that works:
- "ALWAYS trigger when…"
- "Use this skill whenever…"
- "Trigger on any code that imports X, even if the user doesn't explicitly mention…"
- "Use proactively after…"

Polite hedging that fails:
- "Helps with documents" / "For data tasks" — no router keywords
- "You may want to consider…" / "This skill might be useful…"
- "I help you write commits" / "You can use this for…" — first/second person
- 1500-char descriptions explaining mechanics — burns token budget, truncates silently

### The Anthropic `pdf` skill is the bar

> "Use this skill whenever the user wants to do anything with PDF files."

That's it. Front-load aggressively, list user phrasings, add negative triggers if needed.

### Negative-trigger pattern

> "TRIGGER when: code imports `anthropic`/`@anthropic-ai/sdk`… SKIP: file imports `openai`/other-provider SDK, filename like `*-openai.py`, provider-neutral code, general programming/ML."

### Body

- ≤500 lines, imperative voice.
- Reference files one level deep, each with TOC if >100 lines.
- Don't reproduce reference content inline — link to it.
- Move long-form explanation to references; SKILL.md is operational.

## Subagent definitions (`.claude/agents/<name>.md`)

Frontmatter mostly the same as skills, plus:

- `tools`: allowlist (Read, Grep, Glob, Bash, …)
- `disallowedTools`: denylist
- `model`: `sonnet` / `opus` / `haiku` / `inherit` / explicit ID
- `permissionMode`: `default` / `acceptEdits` / `auto` / `dontAsk` / `plan`
- `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `isolation: worktree`, `effort`

Body **becomes the system prompt** — not progressive-disclosure instructions. Subagents receive only this body + basic env, not the parent's system prompt.

Anthropic's guidance: include phrases like "use proactively" in the description to combat under-triggering. Limit tools to the minimum required.

## Cursor / Cline / Aider conventions

- **Cursor `.mdc` rules**: `alwaysApply: true` (CLAUDE.md-equivalent always-loaded), description = router signal, `globs:` = path-scoped trigger.
- **`.clinerules`**: Markdown body, similar to CLAUDE.md. No frontmatter triggering.
- **`.cursorrules`** (legacy): single-file project rules.
- **OpenAI Agents SDK** (`agents.Agent(instructions=...)`): plain string. Treat like a system prompt; same auditing rules apply.

## Common skill-prompt failures

| Failure | Detection | Fix |
|---|---|---|
| Description too vague | "Helps with…", no concrete keywords | Apply the 4-part rubric |
| First/second person framing | "I help you…", "You can…" | Rewrite in third person |
| Description >1024 chars | character count | Trim to <300 chars if possible |
| YAML reflowed by Prettier | description on multiple lines, `>` or `|` block scalar | Force single line; disable `proseWrap` on SKILL.md |
| Body >500 lines | `wc -l SKILL.md` | Move detail into `references/<topic>.md` |
| Hardcoded absolute paths | `grep '/home/'` | Replace with relative paths or env vars |
| Embedded secrets | `grep -E 'sk-[a-zA-Z]\|Bearer'` | Strip; never commit secrets in prompts |
| Should have been a hook | "Always run X after Y" framing | Convert to a hook in `~/.claude/settings.json` |
| Should have been a subagent | Reads many files in isolation, returns summary | Convert to subagent with `tools` allowlist |
| Should have been CLAUDE.md | Always-on rule for one project | Move to `CLAUDE.md` |

## When triggering won't reliably fire

1. **Description doesn't match real user phrasing.** Read 5 real prompts a user might type. Rewrite description to match.
2. **Description over the token budget.** With many skills installed, long descriptions truncate. Front-load the first sentence.
3. **Cross-model variance.** A description that triggers on Opus may miss on Haiku. Test on the least capable target model.
4. **Confusing scope with siblings.** Two skills overlap. Add explicit negative triggers ("Do NOT use for X — use Y instead").

## Audit checklist for a SKILL.md you're reviewing

- [ ] `name` kebab-case, ≤64 chars, matches directory
- [ ] `description` ≤1024 chars, single line, third person
- [ ] First sentence has what + when
- [ ] Concrete trigger phrases (verbatim user wordings, file extensions, domain terms)
- [ ] Negative triggers if scope is ambiguous
- [ ] Body ≤500 lines, imperative voice
- [ ] References one level deep
- [ ] No hardcoded absolute paths, no embedded secrets
- [ ] No first/second person ("I", "you can")
- [ ] At least one should-trigger and one should-not-trigger eval prompt drafted

If 3+ items fail, the skill is more likely to mistrigger or under-trigger than work as intended.

## How to optimize a skill description

The skill-creator skill ships an automated optimizer (`scripts/run_loop.py`) that:

1. Generates 20 trigger eval queries (10 should-trigger, 10 should-not).
2. Runs each query 3× to get a reliable trigger rate.
3. Calls Claude to propose improvements based on what failed.
4. Iterates up to 5 times with held-out test split.

If the user is iterating on description quality, recommend the loop. Otherwise, hand-edit using the rubric above and re-test on a few queries manually.
