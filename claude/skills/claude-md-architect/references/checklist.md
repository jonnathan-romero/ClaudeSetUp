# CLAUDE.md audit & authoring checklist

The complete checklist used by Author and Audit modes. Rules first,
then 1–2 worked examples per major rule.

## Contents

1. Size
2. Structure
3. Content categories
4. Style of rules
5. Contradictions
6. Voice consistency
7. @ imports
8. Hierarchy & precedence
9. Anti-patterns to flag in audits
10. The load-bearing test
11. Two memory surfaces (current)

## 1. Size

- **Target under 200 lines.** This is now official
  (https://code.claude.com/docs/en/memory): "Longer files consume more
  context and reduce adherence." Community sweet spot is tighter still
  (~40–120 lines).
- **No hard limit on CLAUDE.md** — it loads in full regardless of
  length. The 200-line / 25KB *hard truncation* applies to auto-memory
  `MEMORY.md`, not CLAUDE.md. The in-product "too long" warning scales
  with the model's context window.
- A 50-line targeted file outperforms a vague 200-line file. Anthropic's
  own model: a project CLAUDE.md costs ~1,800 tokens, re-sent every turn,
  every session.

**Example — bloated rule list:**

```
- Use 2-space indents
- Don't use semicolons
- Use single quotes
- Use trailing commas
- ... 47 more
```

Better: link to a config file. `Style: see .editorconfig and ruff.toml.`

## 2. Structure

Recommended order:

1. One-line project context (what this repo is)
2. Code style & language tooling
3. Build / test commands the model can't guess
4. Architecture overview (one paragraph)
5. Gotchas / non-obvious constraints
6. Repo etiquette

Use H1 for major sections, H2 for subsections. Use bullets, not prose,
for rules. Use bash code fences for exact commands.

## 3. Content categories

**Belongs in CLAUDE.md:**
- Build / test / lint commands
- Architectural decisions ("we use X because Y")
- Non-default code style
- Domain glossary
- Recurring gotchas Claude has hit before

**Does NOT belong:**
- Anything inferable from reading the code
- Transient task notes
- Secrets, API keys, internal URLs (see `security.md`)
- Single-section rules (use path-scoped `.claude/rules/` instead)
- "Run X every time" automation (use a hook)

**The boundary test:** would a new teammate need this to be productive?
If yes, keep. If Claude figures it out by reading two files, drop.

## 4. Style of rules

- **Specific & verifiable** beats vague. "Use 2-space indentation"
  beats "format properly".
- Imperative voice. "Use X" beats "We generally prefer X".
- Avoid `DON'T X` — negation activates the concept being rejected.
  Reframe to a positive: "Use Y" instead of "Don't use X".
- Explain WHY for any non-obvious rule, in one short clause.
- **Emphasis (IMPORTANT / YOU MUST) is a dial, not a default.** Official
  best-practices says it improves adherence; the prompt-engineering docs
  say *dial it back* on Opus 4.5/4.6+, which over-trigger on aggressive
  language. Reserve it for the few rules Claude actually keeps breaking —
  if every line is IMPORTANT, none is. Flag pervasive emphasis in audits.

**Example — vague vs specific:**

Bad: `Pay attention to code quality.`
Good: `Run ruff check and pytest before claiming a task is done.`

**Example — negation reframed:**

Bad: `Don't use print().`
Good: `Use logging.getLogger(__name__) for library code; reserve print() for one-off scripts.`

## 5. Contradictions

Two rules that contradict each other cause Claude to ignore both.

- "Always add type hints" + "Skip obvious local vars" — these don't
  contradict if the second is scoped (`signatures only`).
- "Use uv" + "Run pip install -r requirements.txt" — actual
  contradiction. Pick one.

Audit fix: pick one, delete the other, or scope each clearly.

## 6. Voice consistency

CLAUDE.md addresses Claude. Use second-person imperative. Avoid
third-person ("Claude should") and first-person ("I want Claude to").
The model handles second-person imperative best.

## 7. @ imports

`@path/to/file.md` syntax loads imported files into context at session
start. They count toward your token budget.

- Prefer relative paths from the file containing the import.
- Recursion limit: 4 hops (current docs; older docs said 5).
- Imports help organization but do NOT save context — imported files
  load in full at launch.
- For real context savings, use `.claude/rules/` with path-scoped
  YAML frontmatter — those load only when matching files are touched.
- Don't import secrets-bearing files.

## 8. Hierarchy & precedence

**Files CONCATENATE — they do NOT override each other.** This is the
most common myth to avoid. There is no key-level merge with a "winner":
every discovered file's text is stacked into context, and if two rules
contradict, "Claude may pick one arbitrarily"
(https://code.claude.com/docs/en/memory). Resolve conflicts by
*removing* them, not by relying on precedence.

Load order, broadest → most specific (most specific is read *last* —
the only "precedence" that exists is this soft positional effect, not a
guarantee):

1. Managed policy (macOS `/Library/Application Support/ClaudeCode/CLAUDE.md`,
   Linux/WSL `/etc/claude-code/CLAUDE.md`) — the only hard floor; cannot
   be excluded.
2. User (`~/.claude/CLAUDE.md`)
3. Project (`./CLAUDE.md` or `.claude/CLAUDE.md`)
4. Local (`./CLAUDE.local.md`, gitignored) — appended after `CLAUDE.md`
   within the same directory.

Claude also walks *up* the tree from the working directory, loading
every ancestor file at launch. Subdirectory CLAUDE.md files below the
cwd load **on demand** when Claude reads a file there (and don't survive
`/compact` — only the project-root file is re-injected).

Personal preferences → user. Team-shared rules → project. Machine-
specific overrides → local.

## 9. Anti-patterns to flag in audits

- **Kitchen sink** — every preference dumped in. Delete rules Claude
  follows without them.
- **Stale rules** — references to old tools, deprecated APIs, model
  names that no longer exist.
- **Hook impersonation** — rules like "after every commit run X"
  belong in `settings.json` hooks, not CLAUDE.md.
- **Skill impersonation** — multi-step procedures with branches belong
  in a Skill.
- **Comment rot** — TODOs from six months ago, "we'll move this
  later" notes. Delete or actually move.

## 10. The load-bearing test

For each line, ask: would Claude make a mistake without this rule? If
you can't think of a concrete past mistake, the rule isn't
load-bearing. Delete.

## 11. Two memory surfaces (current)

CLAUDE.md is human-authored. Claude Code also now has **auto memory**
(`MEMORY.md`, Claude-written, per-repo, machine-local; v2.1.59+). When
auditing, know which surface you're in: CLAUDE.md holds *instructions
and rules you write*; auto memory holds *learnings Claude accumulates*.
Don't migrate auto-memory content into CLAUDE.md wholesale. Use
`/memory` to see exactly which files are loaded.

## References

- https://code.claude.com/docs/en/memory.md
- https://code.claude.com/docs/en/best-practices
- https://www.humanlayer.dev/blog/writing-a-good-claude-md
