---
name: vibe-init
description: Bootstraps the vibe-* engineering framework in this repo. Writes a `## Agent skills` block to AGENTS.md/CLAUDE.md, scaffolds `docs/agents/` (issue tracker, triage labels, domain docs), and drops a `VIBE-README.md` at the repo root explaining the framework. Run before first use of `vibe-issues`, `vibe-prd`, `vibe-issue-triage`, `vibe-diagnose`, `vibe-tdd`, `vibe-architecture`, or `vibe-grill` — or if those skills appear to be missing context about the issue tracker, triage labels, or domain docs.
disable-model-invocation: true
---

# vibe-init

Scaffold the per-repo configuration that the vibe-* engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

Plus a `VIBE-README.md` at the repo root so contributors and other agents can self-orient on what the framework is and which slash commands exist.

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use
- `VIBE-README.md` at repo root — present already (re-run case)?

### 2. Present findings and ask

Summarise what's present and what's missing. Then walk the user through the three decisions **one at a time** — present a section, get the user's answer, then move to the next. Don't dump all three at once.

Assume the user does not know what these terms mean. Each section starts with a short explainer (what it is, why these skills need it, what changes if they pick differently). Then show the choices and the default.

**Section A — Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `vibe-issues`, `vibe-issue-triage`, and `vibe-prd` read from and write to it — they need to know whether to call `gh issue create` or write a markdown file under `.scratch/`. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. Otherwise (or if the user prefers), offer local markdown.

- **GitHub** — issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **Local markdown** — issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)

**Section B — Triage label vocabulary.**

> Explainer: When the `vibe-issue-triage` skill processes an incoming issue, it moves it through a state machine — needs evaluation, waiting on reporter, ready for an AFK agent to pick up, ready for a human, or won't fix. To do that, it needs to apply labels (or the equivalent in your issue tracker) that match strings *you've actually configured*. If your repo already uses different label names (e.g. `bug:triage` instead of `needs-triage`), map them here so the skill applies the right ones instead of creating duplicates.

The five canonical roles:

- `needs-triage` — maintainer needs to evaluate
- `needs-info` — waiting on reporter
- `ready-for-agent` — fully specified, AFK-ready (an agent can pick it up with no human context)
- `ready-for-human` — needs human implementation
- `wontfix` — will not be actioned

Default: each role's string equals its name. Ask the user if they want to override any. If their issue tracker has no existing labels, the defaults are fine.

**Section C — Domain docs.**

> Explainer: Most vibe-* skills (`vibe-grill`, `vibe-prd`, `vibe-issues`, `vibe-issue-triage`, `vibe-diagnose`, `vibe-architecture`) read a `CONTEXT.md` file to learn the project's domain language, and `docs/adr/` for past architectural decisions. They need to know whether the repo has one global context or multiple (e.g. a monorepo with separate frontend/backend contexts) so they look in the right place.

Confirm the layout:

- **Single-context** — one `CONTEXT.md` + `docs/adr/` at the repo root. Most repos are this.
- **Multi-context** — `CONTEXT-MAP.md` at the root pointing to per-context `CONTEXT.md` files (typically a monorepo).

### 3. Confirm and edit

Show the user a draft of everything about to be written:

- The `## Agent skills` block going into `CLAUDE.md` / `AGENTS.md` (see step 4 for selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`
- The contents of `VIBE-README.md` (the framework explainer — same content in every repo, copied verbatim from this skill's seed)

Let them edit before writing. Then list every file about to be written or overwritten and ask for a single "proceed?" confirmation. On re-runs all generated files are overwritten — git is the safety net (the user can `git diff` and `git restore` if a customization was lost).

### 4. Write

**Pick the markdown file to edit:**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask the user which one to create — don't pick for them.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa) — always edit the one that's already there.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout — "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Then write the four documents using the seed templates in this skill folder:

- [assets/issue-tracker-github.md](./assets/issue-tracker-github.md) → `docs/agents/issue-tracker.md` (when GitHub is chosen)
- [assets/issue-tracker-local.md](./assets/issue-tracker-local.md) → `docs/agents/issue-tracker.md` (when local-markdown is chosen)
- [assets/triage-labels.md](./assets/triage-labels.md) → `docs/agents/triage-labels.md`
- [assets/domain.md](./assets/domain.md) → `docs/agents/domain.md`
- [assets/vibe-readme-template.md](./assets/vibe-readme-template.md) → `VIBE-README.md` at the repo root (copy verbatim — pure-static framework explainer; same content in every repo)

### 5. Done

Tell the user the setup is complete and which vibe-* skills will now read from these files. Mention they can edit `docs/agents/*.md` and `VIBE-README.md` directly later — re-running this skill is only necessary if they want to switch issue trackers or restart from scratch.
