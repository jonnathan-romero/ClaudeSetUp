# Out-of-Scope Knowledge Base

The `.out-of-scope/` directory at the repo root stores persistent records of rejected enhancement requests. Two purposes:

1. **Institutional memory** — why a feature was rejected, so the reasoning isn't lost
2. **Deduplication** — when a new issue matches a prior rejection, surface the previous decision before re-litigating

## Directory structure

One file per **concept**, not per issue. Multiple issues requesting the same thing group under one file:

```
.out-of-scope/
├── dark-mode.md
├── plugin-system.md
└── graphql-api.md
```

## File format

Relaxed, readable — a short design document, not a database entry. Paragraphs and concrete reasoning that make the decision clear to a future reader.

```markdown
# Dark Mode

This project does not support dark mode or user-facing theming.

## Why this is out of scope

The rendering pipeline assumes a single color palette defined in `ThemeConfig`. Supporting multiple themes would require a theme context provider wrapping the entire component tree, per-component theme-aware style resolution, and a persistence layer for user theme preferences.

This is a significant architectural change that doesn't align with the project's focus on content authoring. Theming is a concern for downstream consumers who embed or redistribute the output.

## Prior requests

- #42 — "Add dark mode support"
- #87 — "Night theme for accessibility"
- #134 — "Dark theme option"
```

## Naming the file

Short kebab-case concept name: `dark-mode.md`, `plugin-system.md`. Recognizable enough that someone browsing the directory understands what was rejected without opening it.

## Writing the reason

Substantive — not "we don't want this" but **why**. Reference:

- Project scope or philosophy
- Technical constraints
- Strategic decisions

Reasons should be **durable**. Avoid temporary circumstances ("we're too busy right now") — those are deferrals, not rejections, and they belong in a backlog.

## When to check `.out-of-scope/`

During triage Step 1 (Gather context), read every file. When evaluating a new issue:

- Match by **concept similarity, not keyword** — "night theme" matches `dark-mode.md`
- If a match: surface to the maintainer:

  > _This is similar to `.out-of-scope/dark-mode.md` — we rejected this before because [reason]. Do you still feel the same way?_

The maintainer may:

- **Confirm** — append the new issue to the existing file's "Prior requests" list, then close it as `wontfix`
- **Reconsider** — delete or update the file; the new issue proceeds through normal triage
- **Disagree** — the issues are related but distinct; proceed with normal triage

## When to write to `.out-of-scope/`

**Only when an enhancement (not a bug) is rejected as `wontfix`.** Bugs are different — a closed bug isn't a rejected concept, it's "we don't think this is broken." Don't write `.out-of-scope/` for bugs.

Flow:

1. Maintainer decides the feature is out of scope
2. Check whether a matching `.out-of-scope/` file already exists (concept-similarity match)
3. If yes: append the issue to "Prior requests"
4. If no: create a new file with the concept name, decision, reason, and the issue as the first prior request
5. Post a comment on the issue explaining the decision and mentioning the file path
6. Close with `wontfix` + `enhancement` labels

## Updating or removing

If the maintainer changes their mind: delete the file. The skill does not need to reopen old issues — they're historical records.

The new issue that triggered the reconsideration proceeds through normal triage from `needs-triage`.
