# Anti-Patterns

Common ways skills fail. Each entry: the pattern, why it breaks, the fix.

## Contents

- [Description anti-patterns](#description-anti-patterns)
- [Structure anti-patterns](#structure-anti-patterns)
- [Content anti-patterns](#content-anti-patterns)
- [Tooling and security anti-patterns](#tooling-and-security-anti-patterns)
- [Eval anti-patterns](#eval-anti-patterns)
- [Scope and overlap anti-patterns](#scope-and-overlap-anti-patterns)

## Description anti-patterns

### Vague catch-alls

`"Helps with documents"`, `"For data tasks"`, `"A useful tool"`.
**Why it breaks:** Router has no keywords to match against. Triggers either never or randomly.
**Fix:** What + when + concrete triggers. See `descriptions.md`.

### Polite hedging

`"You may want to consider this skill when..."`, `"This skill might be useful for..."`.
**Why it breaks:** Claude already under-triggers. Hedged language confirms the bias.
**Fix:** Imperative voice. "Use when...", "ALWAYS trigger when...".

### First or second person

`"I help you write commits"`, `"You can use this for..."`.
**Why it breaks:** Inconsistent with how Claude routes. Skill descriptions are operational metadata, not chat.
**Fix:** Third person. `"Drafts git commit messages..."`

### Block scalars in YAML

```yaml
description: >
  Multi-line description
  that gets reflowed
```
**Why it breaks:** Prettier and other formatters reflow these unpredictably. Some loaders strip newlines, some don't.
**Fix:** Single line. Disable `proseWrap` for SKILL.md if Prettier is in your project.

### Stuffing the description with body content

A 1500-char description that explains *how the skill works internally*.
**Why it breaks:** Description is for routing, not instruction. Burns budget. Truncates silently.
**Fix:** Routing info in description; mechanics in SKILL.md body.

## Structure anti-patterns

### Wrong file path

`.claude/skills/my-skill.md` (file at top level).
**Why it breaks:** Skills are directories. The loader skips loose `.md` files.
**Fix:** `.claude/skills/my-skill/SKILL.md`.

### Bloated SKILL.md (>500 lines)

Everything inline: full API tables, edge cases, examples, history.
**Why it breaks:** Burns context every time the skill triggers, even when most isn't needed.
**Fix:** Move topics into `references/<topic>.md`. Link from SKILL.md.

### Deeply nested references

`SKILL.md → references/index.md → references/topics/auth.md → references/topics/auth/oauth.md`.
**Why it breaks:** Claude previews (head) deeply nested files instead of reading them. Information loss.
**Fix:** One level deep. If a topic is huge, give it its own TOC inside one file.

### Reference files without TOCs

A 400-line `references/api.md` with no headings.
**Why it breaks:** Claude reads partial files; without a TOC, it doesn't know what it's missing.
**Fix:** Heading-anchored sections + a Contents list at the top.

### Unused subdirectories

Empty `scripts/`, `agents/`, `assets/` "for future use".
**Why it breaks:** Adds noise. Implies behavior that doesn't exist.
**Fix:** Add directories only when a file goes in.

## Content anti-patterns

### Documentation voice

"This skill provides a way to..." / "The purpose of this skill is to..."
**Why it breaks:** Claude follows imperative instructions better than expository prose. Wastes tokens.
**Fix:** Direct imperative. "Run pytest. Parse failures. For each failure..."

### ALL-CAPS MUSTs without reasoning

`"YOU MUST ALWAYS USE THE TEMPLATE"`.
**Why it breaks:** Claude responds to *theory of mind* — explain why and the rule sticks. Caps without rationale read as noise.
**Fix:** "Use the template — downstream parsers depend on the heading order."

### Voodoo constants

`"Set chunk_size = 4096"`, `"temperature: 0.3"` with no justification.
**Why it breaks:** Future-you can't tell if the number is load-bearing. Claude can't either.
**Fix:** One-line comment with the why. Or remove the constant if it's arbitrary.

### Time-sensitive details

`"As of last quarter..."`, `"The new API..."`, `"Recently added..."`.
**Why it breaks:** Memory rot. The skill ages into wrongness.
**Fix:** Encode rules and patterns; date stamp anything inherently temporal.

### Multiple equally-valid paths

"You can use approach A, or B, or C, depending on preference."
**Why it breaks:** Choice paralysis; Claude picks inconsistently across runs.
**Fix:** One default with explicit escape hatches. "Default: A. Use B if X. Use C if Y."

## Tooling and security anti-patterns

### Hardcoded absolute paths

`python /home/alice/projects/foo/scripts/run.py`.
**Why it breaks:** Skill works only on alice's machine.
**Fix:** Relative paths. Or `${CLAUDE_SKILL_DIR}/scripts/run.py` for skill-local references.

### Embedded secrets

API keys, tokens, OAuth secrets inline in SKILL.md.
**Why it breaks:** Skills get distributed via git. Secrets leak.
**Fix:** Environment variables. Document the env var name in SKILL.md.

### Forgetting `allowed-tools`

Skill calls `Bash(git ...)` ten times; user gets ten permission prompts.
**Why it breaks:** Friction. Users disable skills that prompt repeatedly.
**Fix:** Pre-approve with `allowed-tools: Bash(git *)`.

### Skill should be `disable-model-invocation: true`

Side-effect skills (`/deploy`, `/delete-account`) auto-invokable.
**Why it breaks:** Claude triggers them unintentionally.
**Fix:** `disable-model-invocation: true` for any skill with destructive or external side effects.

## Eval anti-patterns

### Forcing assertions on subjective skills

Pass/fail tests for a writing-style or design skill.
**Why it breaks:** Subjective output can't be objectively asserted. Tests become arbitrary.
**Fix:** Human review only. Skip the assertions phase.

### Non-discriminating assertions

`"output exists"`, `"no error thrown"` — pass for any non-empty output.
**Why it breaks:** Always green; gives false confidence.
**Fix:** Assertions that fail when the skill is doing the wrong thing.

### Overfitting to test cases

Iterating SKILL.md until 5 specific evals pass, with brittle phrasing.
**Why it breaks:** Production traffic doesn't look like the test set. Generalization breaks.
**Fix:** Treat evals as *samples* of millions of future runs. Generalize patterns; don't pattern-match prompts.

### Skipping the baseline

Running with-skill evals only, no without-skill comparison.
**Why it breaks:** Can't tell if the skill actually helped.
**Fix:** Parallel runs (with vs without). Aggregate the delta.

## Scope and overlap anti-patterns

### Multiple skills with overlapping descriptions

`pdf-extract`, `pdf-merge`, `pdf-utils` all advertising "work with PDFs".
**Why it breaks:** Router can't choose. Triggers inconsistently.
**Fix:** Tighten each scope. Or merge into one `pdf` skill with sections.

### Skills that should be sub-skills

Fifty single-function skills, each tiny.
**Why it breaks:** Burns description budget. Hard to discover.
**Fix:** Group into one skill with named sections, or one plugin with a router skill that delegates.

### Skills duplicating CLAUDE.md rules

A skill that says "always use 4-space indentation".
**Why it breaks:** That's a project rule. Lives in CLAUDE.md.
**Fix:** Move to CLAUDE.md. Skills are for *invocable* workflows, not always-on rules.

### Skills duplicating hooks

A skill that says "after every commit, run lint".
**Why it breaks:** Skills are requests Claude reasons over. Hooks are deterministic enforcement. The skill version will skip the lint sometimes.
**Fix:** Hook in `settings.json`. See `primitives.md`.
