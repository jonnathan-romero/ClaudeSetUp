---
name: skill-best-practices
description: Authoritative reference and quality checklist for writing Claude Code Agent Skills. ALWAYS trigger when authoring, reviewing, debugging, or improving a SKILL.md, including alongside skill-creator. Use when the user asks to "write a skill", "review this skill", "is my skill good", "why won't my skill trigger", "what's wrong with this description", or mentions SKILL.md authoring, frontmatter fields, trigger accuracy, progressive disclosure, anti-patterns, skill anatomy, or debugging skill activation failures. Pairs with skill-creator — skill-creator runs the build/eval workflow, this skill supplies the principles, structural conventions, and failure-mode catalog.
---

# Skill Best Practices

Quality bar and structural reference for authoring Claude Code Agent Skills. Pairs with `skill-creator`: skill-creator runs the build → eval → iterate workflow; this skill is the style guide and failure-mode catalog you consult during it.

## When to invoke this skill

- Writing a new SKILL.md
- Reviewing or critiquing a skill before publish
- Debugging a skill that won't trigger or over-triggers
- Deciding whether something should be a skill at all (vs. hook, subagent, slash command, MCP server)
- Optimizing a skill description for trigger accuracy

If `skill-creator` is also active, layer this skill's principles into each of its phases. Run the pre-publish checklist below before declaring a skill done.

## Pre-publish checklist

| # | Check | How to verify |
|---|---|---|
| 1 | Frontmatter parses as valid YAML; closing `---` on its own line | `python -c "import yaml; yaml.safe_load(open('SKILL.md'))"` |
| 2 | `name` is kebab-case, ≤64 chars, matches directory name | Visual |
| 3 | `description` + `when_to_use` ≤1536 chars (Claude Code listing cap; stay ≤1024 for open-standard portability), third person, leads with what + when | See `references/descriptions.md` |
| 4 | Description includes concrete trigger phrases (file extensions, verbatim user wordings, domain terms) | See `references/descriptions.md` |
| 5 | Description includes negative triggers if scope is ambiguous ("Do NOT use for...") | See `references/descriptions.md` |
| 6 | SKILL.md body ≤500 lines; deeper detail moved to `references/` | `wc -l SKILL.md` |
| 7 | Reference files one level deep, each with its own TOC if >100 lines | Visual |
| 8 | No hardcoded absolute paths, no embedded secrets, no API keys | `grep -E '/home/|sk-[a-zA-Z0-9]|Bearer ' SKILL.md` |
| 9 | Imperative voice; no "I can", "you can", or first-person framing | Visual |
| 10 | At least one should-trigger eval prompt and one near-miss should-not-trigger prompt drafted | `evals/evals.json` (via skill-creator) |

## Top mistakes that break skills (read first)

1. **Vague description.** "Helps with documents" never triggers. Lead with what + when; list concrete user phrasings. See `references/descriptions.md`.
2. **YAML reflowed by Prettier.** Keep `description` on a single line. Do not use `>` or `|` block scalars. Disable `proseWrap` for SKILL.md.
3. **Token budget overflow.** All skill descriptions pre-load into a listing budget that scales with the model's context window (`skillListingBudgetFraction`, default ~1% — roughly 2K tokens at 200K, 10K at 1M; `SLASH_COMMAND_TOOL_CHAR_BUDGET` survives only as a fixed-count override). With many skills installed, the least-used descriptions drop first. Keep each one tight.
4. **Wrong path.** It is `name/SKILL.md`, not `name.md`. Skills are directories.
5. **Should have been a hook.** "Always run X after Y" is a hook, not a skill. Skills are requests Claude reasons over; hooks are deterministic enforcement. See `references/primitives.md`.
6. **Treating SKILL.md as documentation.** Skills are operational instructions in imperative voice. Move long-form explanation to `references/`.
7. **Voodoo constants.** Every magic number (`IC > 0.02`, `temperature: 0.3`) needs a one-line justification, or omit it.
8. **Forcing assertions on subjective skills.** Style/design/writing skills don't take pass/fail evals — use human review only.

## The five principles

### 1. Progressive disclosure

Three loading tiers:
- **Metadata** (name + description) — always in context, ~100 tokens
- **SKILL.md body** — loads when the skill triggers
- **References / scripts / assets** — load only when explicitly read

Keep SKILL.md ≤500 lines. Move detail into `references/<topic>.md` files one level deep, each with its own TOC. Idle cost stays near zero; Claude navigates to exactly what it needs.

### 2. Pushy descriptions beat polite ones

Claude under-triggers by default. Anthropic's flagship `pdf` skill opens with: *"Use this skill whenever the user wants to do anything with PDF files."* That's the bar.

- Third person, imperative ("Processes X", not "I help with X")
- "ALWAYS trigger when..." beats "Consider using when..."
- List concrete user phrasings verbatim
- Include file extensions, domain terms, exact tool names
- Add negative triggers when scope is ambiguous

See `references/descriptions.md` for annotated examples.

### 3. Match freedom to fragility

- **High freedom** (prose guidance) — open-ended judgment: code review, design feedback, planning
- **Medium freedom** (templates + pseudocode) — preferred patterns with room to adapt
- **Low freedom** (exact scripts) — fragile or destructive operations: migrations, deploys, formula recalc

Anthropic's `xlsx` skill mandates `scripts/recalc.py`; `docx` ships `scripts/office/` for unpack/pack/validate. If a step must run identically every time, ship the script and tell the skill to invoke it.

### 4. Test across models

A description that triggers reliably on Opus may fail on Haiku. If the skill must work for everyone, optimize for the least capable model: more explicit triggers, shorter SKILL.md body, more concrete examples.

### 5. Observe, don't assume

Build evals first. Run with-skill vs without-skill in parallel. Watch the real output before extending SKILL.md. Iterate on real failures; generalize patterns rather than overfitting to the test set. The full eval workflow lives in `skill-creator` — this skill is the rubric you grade against.

## Skill structure

```
skill-name/
├── SKILL.md          # required, ≤500 lines, imperative voice
├── references/       # loaded on demand
│   ├── topic-a.md
│   └── topic-b.md
├── scripts/          # deterministic helpers; not loaded into context
│   └── helper.py
├── assets/           # templates, sample outputs
└── agents/           # only when using context: fork to delegate work
```

Add subdirectories only when needed. Most skills are SKILL.md alone. Add `scripts/` when the same code would otherwise be regenerated each run; add `references/` when content is >100 lines or addresses orthogonal sub-topics; add `assets/` for templates Claude fills in.

Reference files from SKILL.md with relative links: `See [descriptions.md](references/descriptions.md)`. Keep references one level deep — Claude previews deeper files instead of reading them whole.

## Frontmatter quick reference

| Field | Required | Notes |
|---|---|---|
| `name` | yes | kebab-case, ≤64 chars, matches directory |
| `description` | yes | combined with `when_to_use` ≤1536 chars (stay ≤1024 for portability), third person, what + when, concrete triggers |
| `allowed-tools` | no | Pre-approve to skip prompts: `Bash(git *) Read` |
| `arguments` | no | Positional args; reference as `$name` in body |
| `argument-hint` | no | Autocomplete hint shown after `/skill-name` |
| `disable-model-invocation` | no | `true` for side-effect skills like `/deploy` (manual-only) |
| `user-invocable` | no | `false` for background-knowledge skills (Claude reads, users can't slash-invoke) |
| `paths` | no | Glob list; auto-trigger only when working on matching files |
| `context: fork` + `agent` | no | Run the skill in an isolated subagent |
| `model` / `effort` | no | Override per-skill compute |

Full reference with examples: `references/frontmatter.md`.

## Authoring workflow alongside skill-creator

`skill-creator` runs the procedural loop; this skill is the quality gate at each step.

| skill-creator phase | What this skill contributes |
|---|---|
| Capture intent | Use `references/primitives.md` to confirm a *skill* is the right primitive (not hook/subagent/MCP/CLAUDE.md) |
| Write SKILL.md | Apply the five principles. Use the frontmatter quick reference. Apply `references/descriptions.md` to the description field |
| Draft test cases | Include both should-trigger and near-miss should-not-trigger prompts (8–10 each) |
| Run evals | Use `references/anti-patterns.md` to interpret failures |
| Iterate | If the skill won't trigger, walk `references/debugging.md`'s three failure modes in order |
| Pre-publish | Run the checklist at the top of this file |

## When something should NOT be a skill

Quick gut check before writing any SKILL.md:

- Must run *every* time on an event (post-edit, pre-commit) → **hook**
- Reads many files in isolation, returns a summary → **subagent** (or skill with `context: fork`)
- Connects to an external system (DB, browser, Slack) → **MCP server**
- One-time prompt, never reused → just type the prompt
- Always-on rule for one project → `CLAUDE.md`

Full decision matrix: `references/primitives.md`.

## Deeper references

- [`references/frontmatter.md`](references/frontmatter.md) — every frontmatter field with usage examples
- [`references/descriptions.md`](references/descriptions.md) — writing descriptions that trigger reliably
- [`references/anti-patterns.md`](references/anti-patterns.md) — failure modes catalog
- [`references/debugging.md`](references/debugging.md) — diagnostic playbook for skills that won't trigger
- [`references/primitives.md`](references/primitives.md) — skill vs subagent vs hook vs slash command vs MCP
