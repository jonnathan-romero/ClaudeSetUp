---
name: skill-best-practices
description: Authoritative reference and quality checklist for writing Claude Code Agent Skills. ALWAYS trigger when authoring, reviewing, debugging, or improving a SKILL.md, including alongside skill-creator. Use when the user asks to "write a skill", "review this skill", "is my skill good", "why won't my skill trigger", "what's wrong with this description", "is this skill safe to install", or mentions SKILL.md authoring, frontmatter fields, trigger accuracy, progressive disclosure, anti-patterns, skill anatomy, skill security, or debugging skill activation failures. Pairs with skill-creator — skill-creator runs the build/eval workflow, this skill supplies the principles, structural conventions, and failure-mode catalog. Do NOT use for authoring agent definitions (use agent-best-practices) or general prompt writing (use prompt-master).
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
| 10 | Trigger evals drafted — 8–10 should-trigger prompts and 8–10 *genuinely tricky* near-miss should-not-trigger prompts | `evals/evals.json` (via skill-creator) |
| 11 | No secrets, no untrusted-source content, `allowed-tools` scoped to the minimum; third-party skills audited before install | See `references/security.md` |

## Top mistakes that break skills (read first)

1. **Vague description.** "Helps with documents" never triggers. Lead with what + when; list concrete user phrasings. See `references/descriptions.md`.
2. **YAML reflowed by Prettier.** Keep `description` on a single line. Do not use `>` or `|` block scalars. Disable `proseWrap` for SKILL.md.
3. **Token budget overflow.** All skill descriptions pre-load into a listing budget that scales with the model's context window (`skillListingBudgetFraction`, default ~1% — roughly 2K tokens at 200K, 10K at 1M; `SLASH_COMMAND_TOOL_CHAR_BUDGET` survives only as a fixed-count override). With many skills installed, the least-used descriptions drop first. Keep each one tight.
4. **Wrong path.** It is `name/SKILL.md`, not `name.md`. Skills are directories.
5. **Should have been a hook.** "Always run X after Y" is a hook, not a skill. Skills are requests Claude reasons over; hooks are deterministic enforcement. See `references/primitives.md`.
6. **Treating SKILL.md as documentation.** Skills are operational instructions in imperative voice. Move long-form explanation to `references/`.
7. **Voodoo constants.** Every magic number (`IC > 0.02`, `temperature: 0.3`) needs a one-line justification, or omit it.
8. **Forcing assertions on subjective skills.** Style/design/writing skills don't take pass/fail evals — use human review only.
9. **Trusting a skill you didn't audit.** SKILL.md is executable trust — its body is instructions Claude follows, its scripts run with your permissions. Read every file before installing a third-party skill; never ship secrets or broad `allowed-tools` in your own. See `references/security.md`.

## Core principles

### 1. Earn every token

The context window is a public good, and Claude is already very smart. Only add what Claude doesn't already know or wouldn't do by default. For each paragraph ask: *does this justify its token cost?* Don't explain what a PDF is, restate general programming practice, or document what a linter already enforces — that's the difference between a ~50-token instruction and a bloated ~150-token one that says the same thing. Spend your tokens on the non-obvious: project conventions, fragile sequences, the failures you've actually seen.

### 2. Progressive disclosure

Three loading tiers:
- **Metadata** (name + description) — always in context, ~100 tokens
- **SKILL.md body** — loads when the skill triggers
- **References / scripts / assets** — load only when explicitly read

Keep SKILL.md ≤500 lines. Move detail into `references/<topic>.md` files one level deep, each with its own TOC. Idle cost stays near zero; Claude navigates to exactly what it needs.

**Lifecycle matters once it triggers.** In Claude Code the invoked body enters the conversation as a single message and stays there the rest of the session — Claude does *not* re-read the file on later turns. Two consequences: write **standing instructions, not one-time steps** ("when editing X, do Y" — not "first, do Y"), and remember every body line is a *recurring per-turn* cost, not a one-time load. After compaction only the first ~5K tokens of each skill are re-attached (25K combined), so keep load-bearing guidance near the top.

### 3. Pushy descriptions beat polite ones

Claude under-triggers by default. Anthropic's flagship `pdf` skill opens with: *"Use this skill whenever the user wants to do anything with PDF files."* That's the bar.

- Third person, imperative ("Processes X", not "I help with X")
- "ALWAYS trigger when..." beats "Consider using when..."
- List concrete user phrasings verbatim
- Include file extensions, domain terms, exact tool names
- Add negative triggers when scope is ambiguous

See `references/descriptions.md` for annotated examples.

### 4. Match freedom to fragility

- **High freedom** (prose guidance) — open-ended judgment: code review, design feedback, planning
- **Medium freedom** (templates + pseudocode) — preferred patterns with room to adapt
- **Low freedom** (exact scripts) — fragile or destructive operations: migrations, deploys, formula recalc

Anthropic's `xlsx` skill mandates `scripts/recalc.py`; `docx` ships `scripts/office/` for unpack/pack/validate. If a step must run identically every time, ship the script and tell the skill to invoke it.

### 5. Test across models

A description that triggers reliably on Opus may fail on Haiku. If the skill must work for everyone, optimize for the least capable model: more explicit triggers, shorter SKILL.md body, more concrete examples.

### 6. Observe, don't assume

Build evals first. Run with-skill vs without-skill in parallel. Watch the real output before extending SKILL.md. Iterate on real failures; generalize patterns rather than overfitting to the test set.

Test the two failure layers **separately** — they have different fixes:
- **Triggering** (does it activate on the right prompts?) — governed by the description. Test with 8–10 should-trigger prompts and 8–10 *genuinely tricky* near-misses (queries that share keywords but need something else). The near-misses are what catch over-triggering; obvious negatives ("write a fibonacci function" for a PDF skill) test nothing.
- **Behavior** (once active, is the output better than baseline?) — governed by the body and scripts.

Two caveats that trip people up: a simple one-step query won't trigger a skill *even with a perfect description* (Claude just does it directly), so test with realistic, multi-step prompts. And always test in a **fresh session** — leftover context from authoring masks gaps in the written instructions. The full eval workflow lives in `skill-creator` — this skill is the rubric you grade against.

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
| `name` | yes | kebab-case, ≤64 chars, matches directory; prefer gerund form (`processing-pdfs`, not `helper`/`utils`); no XML tags, no reserved words `claude`/`anthropic` |
| `description` | yes | non-empty; combined with `when_to_use` ≤1536 chars (stay ≤1024 for portability); third person, what + when, concrete triggers; no XML tags |
| `when_to_use` | no | Extra trigger phrases / example requests; appended to `description` in the listing and counts toward the 1536-char cap |
| `allowed-tools` | no | Pre-approve to skip prompts: `Bash(git *), Read` (comma-separated — unambiguous when a pattern contains spaces). *Pre-approves, does not restrict* — scope it narrowly on shared skills |
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
| Write SKILL.md | Apply the core principles. Use the frontmatter quick reference. Apply `references/descriptions.md` to the description field |
| Draft test cases | Include both should-trigger and near-miss should-not-trigger prompts (8–10 each) |
| Run evals | Use `references/anti-patterns.md` to interpret failures |
| Iterate | If the skill won't trigger, walk `references/debugging.md`'s failure modes in order |
| Pre-publish | Run the checklist at the top of this file; audit per `references/security.md` if the skill ships to others or came from elsewhere |

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
- [`references/security.md`](references/security.md) — threat model, auditing untrusted skills, scoping tool access
