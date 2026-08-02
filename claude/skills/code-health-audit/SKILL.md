---
name: code-health-audit
description: Repo-wide health audit that orchestrates parallel auditor agents across three co-equal families - duplication, simplification, and documentation drift. ALWAYS trigger when the user wants a WHOLE-REPO audit spanning more than one family, rather than a diff review or a single-family ask - "code health audit", "audit the repo for code quality/health", "where is the tech debt", "what needs refactoring", "full audit of this repo", "find everything worth cleaning up", "duplication and dead code and doc drift" - or before a refactor, a cleanup sprint, or a release. Single-family phrasings ("find dead code", "DRY audit", "are the docs accurate") belong to the individual auditors - route there unless the ask spans families. Maps the repo with codebase-explorer scouts, runs the detectors once (jscpd, lizard, per-ecosystem linters), inventories the doc surface, applies each family's own evidence gate, fans out the three auditors, then merges into one ranked report. Read-only - proposes changes, never performs them. Do NOT use to review or simplify the current diff or recently-changed files (use /simplify or code-simplifier, which edit in place), or to hunt bugs (use /code-review). To actually FIX comments and log levels repo-wide rather than report on them, use the code-housekeeping skill - it edits, this one never does. For a small repo or one narrow question, invoke that family's auditor directly - this skill is the multi-agent orchestrator and it is deliberate overhead.
argument-hint: "[path] [--duplication-only|--simplification-only|--docs-only]"
allowed-tools: Agent, Read, Grep, Glob, Write, Bash(~/.claude/skills/code-health-audit/scripts/*), Bash(npx:*), Bash(uvx:*), Bash(cargo clippy:*), Bash(golangci-lint:*), Bash(git log:*), Bash(git ls-files:*)
---

# Repo health audit (orchestrated)

Fan out a repo-wide audit across parallel auditor agents, then merge their findings into one ranked
report. A single agent handles a small repo fine; this skill exists for the case where one context
cannot hold the whole picture.

**Three families, all first-class, all run together by default.** Run a subset only when the user
asks for one (`--duplication-only` / `--simplification-only` / `--docs-only`) or when the repo has
no surface for a family — and say which you ran either way:

| Family | Hunts | Scan artifact | Agent |
|---|---|---|---|
| **Duplication** | Logic that exists in more than one place and should be consolidated | `jscpd` | `@duplication-auditor` |
| **Simplification** | Complexity, deep nesting, long signatures, dead code | `lizard` + per-ecosystem linters | `@simplification-auditor` |
| **Documentation drift** | Prose docs (README, CLAUDE.md, AGENTS.md, install scripts, docstrings, comments) that disagree with what the code actually does | doc-surface inventory (no mechanical detector exists) | `@docs-drift-auditor` |

Docs drift belongs here and not in a separate pass: a doc that lies costs a human — or Claude — the
same wasted work that duplicated and tangled code does, and the merge step is where the three
families actually inform each other (a "delete this dead function" that the README documents is a
different finding than either family produces alone).

**Read-only.** Propose changes and where they belong. Never perform the refactor or the doc fix, and
never let a spawned agent perform one either.

## The two rules that make this correct

**Never shard by directory.** Duplication is a global property; so is a doc claim, which can point
anywhere in the tree. Give agent A `src/api/` and agent B `src/workers/`, and the highest-value
finding — the same logic reimplemented in both, neither aware of the other — is invisible to both.
Every agent sees the whole repo. What is sharded is **what each one hunts for**, never **where it
looks**. A user-supplied scope filters the *findings*; it does not partition what gets read.

**Each family carries its own evidence gate, and no family inherits another's.** Metrics and
detectors only nominate; the gate decides. The three gates are equal in standing and different in
kind:

| Family | Gate | Why this one |
|---|---|---|
| Duplication | **Git co-change** — the sites change together | Duplication that never co-changes is cheap to leave alone |
| Simplification | **Churn / hotspot** — the code is actually edited | Complexity in code nobody edits costs nobody anything |
| Documentation drift | **The verbatim quote pair** — the exact doc line *and* the exact code line it contradicts | The contradiction is present-tense and self-evidencing; it needs no history to be real |

The empirical work behind the first two is consistent: controlling for size and change count erases
most of the effect attributed to static metrics, and high complexity scores predict nothing on their
own. Default to silence there and make the survivors earn their place.

**That reasoning does not transfer to docs, and applying it there would be a bug.** A README line
contradicted by current code misleads the next reader whether the file was touched yesterday or
three years ago — a stable, never-edited module is where a stale doc survives longest and does the
most damage. Never gate a docs finding on churn, co-change, or hotspot status. Git provenance is a
**confidence input** for that family, not a filter: "the code changed in commit X after the doc was
last touched" earns `Confirmed`; its absence caps the finding at `Likely` and never drops it.

## Workflow

### 1. Map and scan, in parallel

**Spawn the mapping scout(s) first, in the background.** Before any auditor runs, get a repo map
from `codebase-explorer`: one agent by default; on a large repo or monorepo, up to four, each
mapping a different **aspect**, never a different directory. Tell each scout to write its map to
`<outdir>/map-<aspect>.md`, and between them cover:

- the shared-code layer (`utils/`, `lib/`, `common/`, or whatever the repo actually uses), with an
  inventory of its public helpers — this seeds the duplication family's existing-helper pass;
- module boundaries, layering, and placement conventions — this is what the merge step's placement
  proposals must respect;
- generated, vendored, and test trees — this feeds the exclusion list;
- **the doc surface and its ground truth** — where prose docs live, which are entry-point docs
  (README, CLAUDE.md, AGENTS.md, `docs/`), the install/setup scripts and config files those docs
  describe, and the CLI entrypoints — this seeds the docs family the way the helper inventory seeds
  duplication. Fold this into another scout's aspect on a small repo; do not drop it.

If the `codebase-explorer` agent is unavailable, proceed without a map and say so in Coverage.

**While the scouts work, run the scans.** Run each one **exactly one time** for the whole audit.
Every spawned agent reads the output files; none re-invokes a detector, because a fresh `npx`/`uvx`
resolve per agent wastes minutes for identical results.

```bash
~/.claude/skills/code-health-audit/scripts/scan.sh <path> <outdir>     # jscpd → ai report + JSON
uvx lizard --csv -o <outdir>/lizard.csv <path>                         # per-function metrics
~/.claude/skills/code-health-audit/scripts/hotspot.sh '*' '24 months ago' > <outdir>/hotspots.tsv
git ls-files '*.md' '*.rst' '*.txt' 'docs/*' > <outdir>/docs.txt       # prose surface inventory
```

Then add the per-ecosystem detectors that apply to the languages actually present — `ruff` and
`vulture` for Python, `knip` for JS/TS, `clippy` for Rust, `golangci-lint` for Go. Detect the
languages from `git ls-files`; do not run a Python linter on a Go repo.

Adjust the `docs.txt` patterns to what the repo actually uses. That inventory scopes the *prose*
surface only — docstrings and inline comments live in source and are the API-surface agent's
problem, not a gap in the inventory.

Default `<outdir>` to `.research/.health-scan` in the audited repo. Confirm `.research/` is
gitignored there before writing; if it is not, use a temp directory rather than leaving untracked
artifacts in someone's repo.

If `scan.sh` exits 3, `npx` is missing: skip the duplication family's mechanical pass and label that
half **DEGRADED (mechanical recall unknown)**. Any other non-zero exit (offline `npx`, jscpd crash)
gets the same treatment — skip the mechanical pass, label it DEGRADED, and say what failed. The docs
family has no mechanical pass to lose, so a detector failure never degrades it.

### 2. Decide whether to fan out at all

**Collapse a family to a single agent invocation when its surface is small** — the duplication
family under ~8 clone pairs, the simplification family under ~10 lizard-flagged functions living in
files `hotspots.tsv` marks HOTSPOT, the docs family under ~10 files in `docs.txt` **and** no
install/setup script. Eyeball the output files for this; the decision needs an order of magnitude,
not an exact join. Collapsing one family while fanning out another is fine. Say that you are
collapsing. Orchestration on a small repo is pure overhead and yields a worse report than one agent
holding the whole picture.

**An empty or missing scan artifact is not evidence of no findings.** Especially for docs, which has
no detector to report zero: `docs.txt` counts *files to read*, never *drift found*. A small doc
surface means one agent instead of three — never zero agents.

### 3. Fan out, in one message

Collect the scouts' maps first — fan-out waits on both the maps and the scans. Then spawn every
agent across all three families in a single message so they run concurrently. Give each one the
paths to the scan outputs **and the map file(s)**, the exclusion list, an explicit instruction not
to re-run any detector, and **a unique output path** — `<outdir>/agents/<family>-<lens-or-batch>.md`.
The agents default to one shared report path; concurrent writers on the default clobber each other
and leave the merge nothing to read. Require every finding in the file to carry each site as
`path:start-end` (for docs: a `doc-path:line` **and** a `code-path:line`).

**Duplication family — two axes.**

*Axis A, candidate clusters (dynamic).* Group the jscpd JSON's `duplicates` into clusters by
transitively joining pairs that share a file. Batch roughly 4–6 clusters per agent, capped at 4
agents. N follows from what the detector found, never from a directory count. A hub file (a
`utils.py` appearing in dozens of pairs) can chain nearly everything into one mega-cluster: when a
cluster exceeds ~8 pairs, split it by the hub's counterpart directory and say so, rather than
handing one agent the whole graph.

*Axis B, detector-blind lenses (fixed, 4).* jscpd already owns exact, renamed, and gapped clones —
that is Axis A's input. Do **not** spend an agent re-finding them. These hunt what a token detector
structurally cannot see:

| Lens | Hunts | Why the detector misses it |
|---|---|---|
| `semantic` | Same logic, different shape — different identifiers, control flow, decomposition | Shares no token sequence |
| `existing-helper` | Code written inline that a helper in this repo already implements | The two versions have nothing textually in common |
| `domain-constants` | The same magic number, regex, URL, error string, or validation rule in several places | Too few tokens to clear any threshold |
| `structural` | The same multi-step procedure rebuilt with different calls | Only the *sequence* repeats, not the text |

Paste each lens's table row into its agent's prompt — the lens definitions live here, not in the
agent body. For `existing-helper`, instruct the agent to build the shared-helper inventory
**first** and search against it — that inventory is small and bounded, which is what makes the
search tractable. Seed it from the scout map's helper inventory: verify against the code rather
than rebuilding from scratch. If the repo has no shared-code layer, skip this lens and say so.

**Simplification family — split by concern, never by directory.** Up to three agents:

| Agent | Covers |
|---|---|
| `complexity` | lizard/ruff/clippy/gocyclo outliers **intersected with hotspots**, plus the concrete extraction each one needs |
| `dead-code` | vulture/knip/`unused` candidates, with the dynamic-reachability searches the auditor's rules require |
| `signatures` | Long parameter lists, deep nesting, over-long functions — the smells that read as API friction rather than internal tangle |

Drop the `dead-code` agent when no dead-code detector ran. Drop `signatures` when the repo is small
enough that one agent covers both it and `complexity`.

**Docs family — split by concern, never by doc file.** Up to three agents. The split partitions
`@docs-drift-auditor`'s 10-item drift checklist; paste the assigned items into each agent's prompt
and tell it to read the whole doc surface, not a slice of it:

| Agent | Checklist items | Covers |
|---|---|---|
| `references` | 1, 6 | Stale renamed/removed files, dirs, symbols, scripts, and flags still named in prose; layout/structure claims vs the real tree — both a listed item that is gone and a new top-level item that is undocumented |
| `behavior` | 2, 3, 4, 5, 10 | Config keys, defaults, and merge semantics; install/setup step sequences vs the actual script; described behavior vs actual control flow; env vars vs the code that reads them; list-file / generated-artifact format claims |
| `api-surface` | 7, 8, 9 | CLI flags and example commands vs argparse/click definitions **read statically**; docstrings vs real signatures; version and dependency claims vs the lockfile |

`references` is the highest-yield agent — references rot silently — and `behavior` is the one no
tool can substitute for, because an install-sequence check is a careful read of a script that must
never be run. Give the `behavior` agent the scout map's install-script and config-file list. Collapse
to one agent when the repo is small (step 2); drop `api-surface` when the repo has no CLI, no
public API, and no lockfile, and say so in Coverage.

Two rules go in every docs agent's prompt, because they are where this family's false positives and
false negatives live:

- **Quote both sides verbatim or it is not a finding.** No doc-quote + code-quote pair, no entry.
- **Skip intentional simplification.** A doc may legitimately summarize or paraphrase. Flag only
  when *following the doc would mislead or break the reader*, not when the doc is merely less
  detailed than the code. Treating paraphrase as mismatch is this family's dominant false positive.

### 4. Merge — this is the real work

Several agents produce overlapping findings. Without a real merge the user gets several reports to
reconcile by hand, which is worse than one agent.

**Read each agent's report file from `<outdir>/agents/`.** The digests agents return are progress
signals; the files are the merge input — they hold the per-site spans that dedupe keys on. A
finding whose file entry lacks spans cannot be deduped; count it separately and say so.

1. **Dedupe, per family key.**
   - *Duplication and simplification:* key each finding on its normalized span set —
     `(path, start_line, end_line)` per site, path relative to repo root. Two findings match when
     their spans overlap by more than half on both sides.
   - *Docs drift:* a docs finding has **two** locations, so a single-span key would send every one
     of them to the un-dedupable pile. Key on the pair `(doc_path:line, code_path:line)`; two
     findings match when both sides refer to the same claim, allowing a few lines of slack on each.
   Keep the better-argued one; merge the evidence.
2. **Cross-family interactions are the payoff — resolve them, don't average them.**
   - *Conflict (duplication ↔ simplification).* Duplication says *extract these three copies into a
     helper*, simplification says *this abstraction is already too tangled — inline it*. When both
     fire on the same code, prefer the cheaper error. Duplication is cheaper than a wrong
     abstraction, so a conflict resolves toward *leave it duplicated* unless the sites demonstrably
     co-change.
   - *Corroboration (docs ↔ simplification).* "This function is dead, delete it" plus "the README
     documents this function" is **not** a conflict — it is evidence the dead-code call is wrong. A
     documented symbol is a contract surface, and `@docs-drift-auditor`'s direction-of-drift rule
     applies: the code may be the bug. Demote the deletion to *possible defect — verify the
     documented behavior still works* and keep both findings linked. Never resolve it by dropping
     the docs finding.
   - *Drift the proposals themselves create.* Every accepted extraction, deletion, or signature
     change invalidates any doc that describes it. Walk the accepted list against the docs family's
     doc surface and name the doc updates each proposal implies. This is a report section, not an
     afterthought.
3. **Rank** by fix-worthiness. Within duplication and simplification: change-history evidence
   (co-change, relative churn) → actionability of the proposed step → blast radius → raw metric
   **last**. Span, occurrence count, and complexity score are what detectors sort by and the weakest
   predictors of whether a fix is worth making. Within docs: the auditor's own severity — Critical
   (acting on the doc produces a wrong outcome) → Warning → Suggestion — with confidence as the
   tiebreak. Rank inside each family; do not force one scale across all three.
4. **Cross-check rejections.** If one agent rejected what another accepted, resolve it explicitly
   rather than letting the accepting agent win by default.

Gating helpers (duplication and simplification only — the docs family has no history gate):

```bash
printf '%s\t%s\n' fileA fileB | ~/.claude/skills/code-health-audit/scripts/cochange.sh
~/.claude/skills/code-health-audit/scripts/hotspot.sh '*.py' '24 months ago'
```

**`THIN-HISTORY` means uninformative, not negative.** A young, squashed, or freshly-imported repo
shows no co-change and no churn for anything. Treating that as evidence against acting rejects every
finding. Apply the fallback at a repo level: when **more than half** of a family's candidate files
come back THIN-HISTORY, say so, drop that family's gate, and label its findings **UNGATED**. Below
that, gate per-file as normal and report the thin fraction in Coverage — never mix the two modes
silently. This applies to duplication and simplification; docs findings are never THIN-HISTORY
because they were never history-gated.

### 5. Report

Write one merged report to `.research/code-health-audit.md` — same gitignore check as step 1; if
`.research/` is not ignored, write under the temp outdir instead and say so — and return a digest
plus the path. Never paste the full report inline, and never emit the per-agent reports separately.

```
# Repo health audit — <repo/subtree>

## Coverage
Detectors + flags + thresholds, and the doc-surface inventory. Files scanned /
excluded. Agents spawned and what each covered. The funnel for ALL THREE
families: N nominated → N gated in → N reported — a family that ran and found
nothing says so explicitly, and a family that did not run says why.
DEGRADED / UNGATED banners where they apply.

## Already solved elsewhere     <- duplication: the shared location already exists
## Extract now                  <- duplication
## Simplify now                 <- complexity, each with a concrete next step
## Possibly unreachable         <- dead code, split into safe-to-delete vs is-this-a-defect
## Docs that no longer match     <- docs drift, Critical → Warning → Suggestion,
                                   each with its doc-quote + code-quote pair
## Doc updates the proposals imply  <- drift the accepted changes above would create
## Considered and not reported  <- counts by reason, all three families; load-bearing,
                                   it makes the silence credible
```

## Standing rules

- **A family is skipped only when the user asked or the repo has no surface for it, and Coverage
  names it either way.** Three families run by default. Never silently drop one because its scan
  produced no file, because it has no mechanical detector, or because the other two filled the
  report — a missing family is the failure mode this skill is built to prevent.
- **No silent caps.** State every cap — clusters per agent, agent count, findings reported — with
  how many items were dropped and the ranking that chose them. A truncated report that reads as
  complete is worse than no report.
- **Line numbers come from the tool.** Every span traces to detector output or a `Grep` hit.
  Neither you nor any spawned agent may estimate one. Docs findings quote both sides verbatim from
  the real files — never from memory or from what a file "probably" says.
- **Rejecting most candidates is success.** Most duplication should stay duplicated, most
  complexity is not worth touching, and most doc imprecision is legitimate paraphrase. The rejection
  counts are what make the accepted list credible.
- **Never bundle a proposed simplification with a behavior change.** Refactors tangled with feature
  work are where the defect-injection signal actually lives. Propose pure, behavior-preserving
  changes only.
- **Every finding names a concrete next step** — for docs, the concrete replacement doc text.
  Bug-prediction output that isn't actionable changes no behavior; this is measured, not
  theoretical. No next step, no entry.
- **Propose placement inside the repo's existing structure.** The scout map documents that
  structure — cite it. Never invent a `common/` in a repo with no such convention.
- **Migrations are append-only history.** Never propose consolidating or simplifying them.
- **Never run the repo's own code.** No install scripts, no build or test commands, no documented
  example commands, no `<entrypoint> --help`. CLI flags and install steps are verified by reading
  the source statically. This binds every spawned agent.
