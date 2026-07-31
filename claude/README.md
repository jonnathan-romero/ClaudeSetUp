# `~/.claude` source tree

This directory is mirrored into `~/.claude/` by [`install.sh`](../install.sh). It holds the
custom **agents**, **skills**, and **hooks** that extend Claude Code, plus the global `CLAUDE.md`,
`settings.json`, and `statusline-command.sh`.

- **Agents** (`agents/*.md`) — subagents the main loop delegates to. Each runs in its own
  fresh context and returns a result. Invoke explicitly with `@<name>`, or let the model
  delegate based on the description.
- **Skills** (`skills/<name>/SKILL.md`) — capabilities and domain knowledge the model loads
  on demand. Description-triggered, or invoked directly as `/<name>`.
- **Hooks** (`hooks/*.sh`) — shell scripts Claude Code fires automatically on tool/agent
  lifecycle events (wired up in `settings.json`). Not model-invoked; best-effort (each exits 0
  so it never blocks the turn).

> **Maintaining this file:** the tables below are hand-maintained. When you add, remove, or
> rename an agent, skill, or hook, update the matching table. This rule is also recorded in the
> project-root [`CLAUDE.md`](../CLAUDE.md).

---

## Agents

All agents inherit the session model. All but one are **read-only reporters** — they investigate
and return (or write) a report; they never edit the files they audit. The exception is
**comment-janitor**, which edits in place; it is marked in the table below.

| Agent | What it does | Tools |
|-------|--------------|-------|
| **adversarial-reviewer** | Fresh-eyes critic for a plan, design, idea, or code — reviews the artifact *without* the prior conversation and surfaces concrete risks (unstated assumptions, failure modes, missing alternatives, blast radius). Defends a CLEAN verdict rather than manufacturing issues. Writes each report to a unique `<slug>-<UTC stamp>-$RANDOM` path (or the one its caller assigns), so concurrent reviewers never overwrite each other. | WebFetch, WebSearch, Read, Grep, Glob, Bash, Write |
| **agent-skill-auditor** | Audits the whole `skills/` + `agents/` set: YAML/frontmatter validity, per-description trigger quality, cross-file trigger collisions, agent tool-grant safety, agent body structure. Writes a severity-tiered report. | Read, Grep, Glob, Bash, Write |
| **codebase-explorer** | Maps a local code checkout — locates where things live *and* explains how they work — and writes a synthesized map where every claim carries a `file:line` ref. Honors CLAUDE.md, runs on the session model, keeps file dumps out of context, saves the map to a file. The deep, conventions-aware counterpart to the built-in Haiku `Explore`. | Read, Grep, Glob, Bash, Write |
| **comment-janitor** ✎ | **Edits in place.** Repo-wide comment/docstring cleanup for the agent-written codebase. Splits every comment on one property: *is this claim verifiable by reading the adjacent code?* Restatement, step narration, banners, commented-out code, and `Args:` entries echoing a typed signature are deleted; a stated rationale, constraint, invariant, or claim about an external system is **never** deleted — it returns as a structured question for the caller to put to the user. Public docstrings are compressed to their core, private ones deleted after a repo-wide reachability grep. Allow-list not deny-list (deny-list misses fail silently); Python at full strength, other languages restricted to commented-out code + banners. Verifies every file before moving on (AST *and* token stream — an AST check alone passes while comments are mangled), reverts the file on failure, appends to a manifest for a scoped undo. Never commits, never adds a comment, never touches code, never edits a file that was dirty at run start. | Read, Edit, Grep, Glob, Bash, Write |
| **doc-researcher** | Researches a question across a corpus of local documents (PDF, docx/odt/epub, xlsx/pptx, archives) and writes a synthesized report where every claim carries a verbatim quote + source filename. | Bash, Read, Write, Grep |
| **docs-drift-auditor** | Finds where prose docs (README, CLAUDE.md, install scripts, docstrings, comments) disagree with what the code actually does. Flags each with a verbatim doc-quote + code-quote. | Read, Grep, Glob, Bash, Write |
| **duplication-auditor** | Repo-wide DRY audit: runs jscpd (via `npx`) for the mechanical pass, adds an existing-helper pass that finds logic hand-rolled inline when a repo helper already does it, ranks by git co-change rather than span, then triages against a rejection catalog (rule of three, wrong-abstraction, unrelated modules). Proposes placement; never refactors. | Read, Grep, Glob, Bash, Write |
| **memory-auditor** | Audits the persistent memory store (`MEMORY.md` index + `memory/*.md` notes) for stale facts, contradictions, duplicates, broken `[[links]]`, index⇄folder drift, and frontmatter breakage. | Read, Grep, Bash, Write |
| **simplification-auditor** | Repo-wide code-health pass: `lizard` (~29 languages) plus per-ecosystem linters nominate complex/dead code, then **git change history gates every finding** — a threshold crossing alone is not a finding, and complexity in code nobody edits is never reported. Dead-code proposals are capped at internal, non-reflective symbols, and "unused" that looks deliberate is reported as a possible defect rather than a deletion. | Read, Grep, Glob, Bash, Write |
| **web-researcher** | Researches a topic across many web pages and returns thorough findings with verbatim quotes + source URLs for every claim, keeping large page dumps out of the main context. | WebFetch, WebSearch, Read, Write, Bash |

---

## Hooks

Shell scripts in `hooks/`, fired automatically by Claude Code on tool/agent lifecycle events
(registered in [`settings.json`](settings.json)). They are mirrored into `~/.claude/hooks/` with
delete semantics, exactly like `agents/` and `skills/`.

| Hook | Event (matcher) | What it does |
|------|-----------------|--------------|
| **black-format.sh** | PostToolUse (`Write\|Edit\|MultiEdit`) | Formats edited `.py`/`.pyi` files with Black — prefers a `black` on `PATH`, falls back to `uvx black`. |
| **save-agent-prompts.sh** | PreToolUse (`Task\|Agent`) | Saves each subagent's prompt + metadata as a timestamped markdown file under `<project>/.agents/`, named by `tool_use_id`. Appends `.agents/` to the repo-root `.gitignore` (with a trailing-newline guard) and writes files owner-only (`umask 077`). |
| **save-agent-results.sh** | PostToolUse (`Task\|Agent`) | Appends the finished subagent's returned result to that same `.agents/` file (matched by `tool_use_id`); if no prompt file exists, writes a fresh combined prompt+result record. |

---

## Skills

`★` marks the cross-session planning triad — see [The planning triad](#the-planning-triad-rolling-plan--handoff--agent-brief) below.
The **Assets** column notes bundled `scripts/` (executable helpers) and `references/`
(progressive-disclosure docs loaded on demand). Helpers used by **more than one** skill live in
[`skills/_shared/`](skills/_shared/README.md) — one folder per helper, referenced by absolute
installed path (e.g. `~/.claude/skills/_shared/review_diff/review-diff.sh`). `_shared/` has no
`SKILL.md`, so Claude Code never loads it as a skill.

| Skill | What it does | Notes |
|-------|--------------|-------|
| **rolling-plan** ★ | Progressive (rolling-wave) planning across sessions in a `.plan/` folder: a master plan plus numbered child plans whose steps each fit one session. Detail the near term, keep the far term coarse, defer decisions to the last responsible moment. | references · shared `review_diff` · human-in-the-loop |
| **handoff** ★ | Compacts the volatile conversation into a `.handoffs/` snapshot so a fresh session can resume — goal, progress, what worked/didn't, decisions, next steps. | shared `review_diff` |
| **agent-brief** ★ | Authors a self-contained brief that an autonomous builder + reviewer agent pair executes unattended, with machine-checkable acceptance criteria. Saves to `.briefs/` or a GitHub issue. | references · shared `review_diff` |
| **realign-plan** | The periodic reconciliation pass over a whole `.plan/` effort: sweeps every plan + `.research/` + the actual code for cross-plan contradictions, assumptions that hardened into decisions, and plan-vs-code drift, then interviews to re-confirm intent and compacts accreted history — rewriting the plan files in place. Pairs with `rolling-plan`; human-in-the-loop. | references · shared `review_diff` |
| **agent-best-practices** | Authoritative reference + checklist for writing/reviewing subagent definitions (`agents/*.md`): description quality, tool grants, model choice, when to delegate. | references |
| **skill-best-practices** | Authoritative reference + checklist for writing/reviewing `SKILL.md` skills: trigger accuracy, progressive disclosure, anatomy, failure-mode catalog. | references |
| **claude-md-architect** | Authors/audits `CLAUDE.md` files and routes a new rule to the right primitive (CLAUDE.md vs skill vs hook vs slash command vs subagent). Covers size limits, anti-patterns, security. | references |
| **prompt-master** | Writes, edits, and reviews prompts of every kind — system/user prompts, agent definitions, SKILL.md descriptions, tool descriptions, extraction templates. | scripts, references |
| **process-interviewer** | Relentless interviewer that extracts a complete, unambiguous plan from your head *before* building. Use to scope a fuzzy idea into a concrete plan. | references |
| **grill-me** | Open-ended adversarial interviewer — pressure-tests a plan, design, or half-formed thought. You steer; output isn't templated. | — |
| **gh-search** | Searches/discovers repos, code, issues, PRs, and commits across GitHub via `gh search` + read-only `gh api`. Knows the search qualifiers and the 1000-result cap. Read-only. | references |
| **docker** | Authors and debugs Docker + docker-compose setups — Dockerfiles, `compose.yaml`, `.dockerignore`, `.env` — with copy-paste templates and the critical rules (multi-stage, non-root, no `:latest`, secrets, healthchecks, layer cache). Python/uv is the worked example; otherwise language-agnostic. | references |
| **file-search** | Searches *inside* binary documents and archives plain grep can't read (PDF, docx, xlsx, pptx, zip/tar, sqlite) via `rga`, plus finds files by name with `fd`. | scripts, references |
| **arch-wiki** | Reads and searches the offline ArchWiki from the `arch-wiki-docs` package (2500+ pages, no network). Renders the MediaWiki HTML to a plain-text cache so Grep actually finds things, and prints pages by section to keep context small. | scripts |
| **agent-browser** | Browser automation via the `agent-browser` CLI: navigate, log in, fill forms, scrape, screenshot, test local web apps, check visual regressions. | scripts, references |
| **colors** | Generates and critiques color palettes (UI scales, brand, dataviz colormaps) using OKLCh and color theory; computes WCAG/APCA contrast via coloraide. | scripts, references |
| **code-health-audit** | Repo-wide health audit, orchestrated across three co-equal families. Spawns `codebase-explorer` scout(s) to map the repo (shared-code layer, conventions, exclusion trees, doc surface) while running the scans **once** globally (jscpd for clones, lizard + per-ecosystem linters for complexity/dead code, a doc-surface inventory), then fans out `@duplication-auditor`, `@simplification-auditor`, and `@docs-drift-auditor` agents and merges them into one ranked report. Each family carries **its own evidence gate** — co-change for duplication, churn for simplification, the verbatim doc-quote + code-quote pair for docs drift — and none inherits another's, so a stale doc in never-touched code is never filtered out by a hotspot rule. Never shards by directory; resolves duplication↔simplification conflicts toward leaving code duplicated; treats "delete this dead function" + "the README documents it" as corroboration that the deletion is wrong; collapses to a single agent per family on small repos. | scripts · `/code-health-audit [path]` |
| **comment-cleanup** | Cleans up the comments and docstrings in one specified file: reads it plus a hop or two of surrounding code, drops redundant/obvious comments, and re-adds only minimal succinct ones — while preserving functional directives (shebangs, `# noqa`/`# type` pragmas, license headers, runtime docstrings) and changing comments only, never code. The **one-file, human-in-the-loop** counterpart to the `@comment-janitor` agent — use the skill when you want to watch the diff, the agent when the job is repo-scale. | `/comment-cleanup <file>` |
| **matplotlib-plot-style** | Applies the user's matplotlib styling preferences to any plotting code. Triggers on any matplotlib import/figure/plot. | — |
| **humanizer** | Removes signs of AI-generated writing from prose (em-dash overuse, rule-of-three, hedge-stacking, sycophantic openers, and the rest of the catalog). | — |
| **caveman** | Ultra-compressed response mode — cuts ~75% of tokens while keeping technical accuracy. **Sticky**: stays on until "stop caveman" / "normal mode". | `/caveman` · sticky |

---

## The planning triad: rolling-plan + handoff + agent-brief

Three skills cooperate to carry work across context resets. They split along one axis —
**what is volatile vs what is durable** — and hand off to each other at well-defined seams.

| Skill | Role | Where the human is |
|-------|------|--------------------|
| **rolling-plan** | Plan a multi-session effort; defer decisions to the last responsible moment. | In the loop at **every step**. |
| **handoff** | Snapshot the volatile conversation so a fresh agent resumes mid-effort. | Hands off **between sessions**. |
| **agent-brief** | Compile one unit of work into a brief an agent builds **unattended**. | Front-loads decisions, then **steps away**. |

### The core split: volatile vs durable

The context window is volatile; the filesystem is not. Anything that must outlast the session
goes to disk. The triad keeps two kinds of state in two kinds of file:

- **Durable** (the plan) → `rolling-plan` writes `.plan/` files that survive resets: the
  master plan, child plans, the interview, and `Decisions Made` with their rationale. This is
  the source of truth.
- **Volatile** (the conversation) → `handoff` snapshots the *uncommitted* reasoning — what was
  mid-edit, what was just learned, verbatim user corrections — into `.handoffs/`. It is
  regenerated each reset, so nothing load-bearing should live *only* here; decisions get
  **promoted** into the plan before snapshotting.

### Working folders (all git-ignored local working memory)

| Folder | Owner | Holds |
|--------|-------|-------|
| `.plan/` | rolling-plan | `00-master-plan.md`, `NN-name-plan.md` child plans, `00-interview.md` |
| `.handoffs/` | handoff | `handoff-<timestamp>.md` session snapshots |
| `.briefs/` | agent-brief | `NN-step.md` briefs + `NN-step-result.md` outcome / stop-and-log reports |
| `.research/` | (shared) | `NN-*.md` research findings linked from plan/brief files |

Each is referenced from the others by relative path (e.g. a plan step links
`Brief: ../.briefs/NN-step.md`). Keep these names consistent — a link that points at a file a
sibling skill never writes is the classic failure mode.

### The seams (how they connect)

- **rolling-plan → agent-brief (`offload`).** When a step is understood well enough to specify
  fully, `rolling-plan` hands it to `agent-brief`, which expands the coarse step into a full
  brief (drawing the *why* from `.plan/00-interview.md` and locked choices from `Decisions
  Made`), writes `.briefs/NN-step.md`, and links it from the step.
- **agent-brief → rolling-plan (write-back).** The brief runs **builder → independent
  reviewer**. Only after the reviewer passes the acceptance criteria does the agent flip the
  step `[x]` and fill its `Outcome`. On failure it stops and logs to `.briefs/NN-step-result.md`
  — the step is left for you. (This reviewer gate is the one sanctioned exception to "a human
  diff-reviews substantive plan edits.")
- **agent-brief → handoff (on failure).** A failed brief also triggers a `handoff` so the
  volatile context isn't lost; the handoff's Session Context records which brief failed and
  where its result file is.
- **handoff → rolling-plan (on resume).** Resuming after a reset, read the most recent handoff
  for conversation context, then run rolling-plan's `status` to re-orient against the durable
  plan. Treat not-yet-executed step Goals as provisional guesses to re-confirm, not settled
  spec.

### The reconciliation pass: realign-plan

`realign-plan` is the family's fourth skill — *not* part of the triad (it doesn't carry work
**forward**), but the **maintenance pass** that keeps a long-running `.plan/` honest. Where
rolling-plan edits the plan as you go and handoff/agent-brief move one increment, realign-plan
steps back and reconciles the **whole** effort at once. It runs only when a `.plan/` already
exists, in a single pass:

- **Sweep** every `.plan/` file + `.research/` + the actual code for cross-plan contradictions,
  assumptions that quietly hardened into decisions, and plan-vs-code drift.
- **Interview** to re-confirm intent now that more is known, and refine the now-near-term steps
  rolling-plan deliberately left coarse.
- **Compact** accreted history — folding superseded reasoning into `Decisions Made` — and
  rewrite the plan files in place.

Run it periodically — after a big arc change, or when resuming an effort buried in history — not
every session. It is **not** rolling-plan's per-step `re-plan` (which rewrites one step's
*downstream* after a single research finding); realign-plan reconciles *across* plans.

### Which one to reach for

- **Planning a multi-session effort with unknowns** → `rolling-plan`. (Skip it for a single
  session with no unknowns — that's just ceremony.)
- **Running low on context mid-task / stopping for the day** → `handoff`.
- **A unit of work is fully specified and you want an agent to build it unattended** →
  `agent-brief`.
- **A long-running `.plan/` effort has drifted — plans contradict each other or the code** →
  `realign-plan` (a periodic reconciliation pass, not part of the triad but the same family).

The key distinction between `rolling-plan` and `agent-brief`: rolling-plan is
**human-in-the-loop** and *defers* decisions because a human resolves them at each step;
agent-brief *front-loads* the unrecoverable decisions precisely because there is **no human at
the decision points** during an unattended run.
