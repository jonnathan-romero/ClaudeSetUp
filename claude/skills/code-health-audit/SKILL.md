---
name: code-health-audit
description: Repo-wide code health audit that orchestrates parallel auditor agents across two families - duplication and simplification. ALWAYS trigger when the user wants to audit a whole repository for code quality rather than review a diff - "find repeated code", "what could be generalized", "DRY audit", "what should we simplify", "find overly complex code", "find dead code", "what can we delete", "where is the tech debt", "code health audit", "audit the repo for code quality/health", "what needs refactoring" - or before a refactor or cleanup sprint. Maps the repo with codebase-explorer scouts, runs the mechanical detectors once (jscpd for clones, lizard plus per-ecosystem linters for complexity and dead code), gates every candidate on git change history, fans out duplication-auditor and simplification-auditor agents, then merges everything into one ranked report. Read-only - proposes changes, never performs them. Do NOT use to review or simplify the current diff or recently-changed files (use /simplify or code-simplifier, which edit in place), or to hunt bugs (use /code-review). For a small repo or one narrow question, invoke @duplication-auditor or @simplification-auditor directly - this skill is the multi-agent orchestrator and it is deliberate overhead.
argument-hint: "[path] [--duplication-only|--simplification-only]"
allowed-tools: Agent, Read, Grep, Glob, Write, Bash(~/.claude/skills/code-health-audit/scripts/*), Bash(npx:*), Bash(uvx:*), Bash(cargo clippy:*), Bash(golangci-lint:*), Bash(git log:*), Bash(git ls-files:*)
---

# Code health audit (orchestrated)

Fan out a repo-wide audit across parallel auditor agents, then merge their findings into one ranked
report. A single agent handles a small repo fine; this skill exists for the case where one context
cannot hold the whole picture.

Two families, run together by default. Run one alone when the user asks for it:

- **Duplication** — logic that exists in more than one place and should be consolidated.
  Detector: `jscpd`. Agent: `@duplication-auditor`.
- **Simplification** — complexity, deep nesting, long signatures, dead code.
  Detector: `lizard` + per-ecosystem linters. Agent: `@simplification-auditor`.

**Read-only.** Propose changes and where they belong. Never perform the refactor, and never let a
spawned agent perform it either.

## The two rules that make this correct

**Never shard by directory.** Duplication is a global property. Give agent A `src/api/` and agent B
`src/workers/`, and the highest-value finding — the same logic reimplemented in both, neither aware
of the other — is invisible to both. Every agent sees the whole repo. What is sharded is **what
each one hunts for**, never **where it looks**. A user-supplied scope filters the *findings*; it
does not partition what gets read.

**Change history gates, metrics only nominate.** This governs both families. Duplication that never
co-changes is cheap to leave alone; complexity in code nobody edits costs nobody anything. The
empirical work is consistent here — controlling for size and change count erases most of the effect
attributed to static metrics, and high complexity scores predict nothing on their own. Default to
silence and make the survivors earn their place.

## Workflow

### 1. Map and scan, in parallel

**Spawn the mapping scout(s) first, in the background.** Before any auditor runs, get a repo map
from `codebase-explorer`: one agent by default; on a large repo or monorepo, up to three, each
mapping a different **aspect**, never a different directory. Tell each scout to write its map to
`<outdir>/map-<aspect>.md`, and between them cover:

- the shared-code layer (`utils/`, `lib/`, `common/`, or whatever the repo actually uses), with an
  inventory of its public helpers — this seeds the duplication family's existing-helper pass;
- module boundaries, layering, and placement conventions — this is what the merge step's placement
  proposals must respect;
- generated, vendored, and test trees — this feeds the exclusion list.

If the `codebase-explorer` agent is unavailable, proceed without a map and say so in Coverage.

**While the scouts work, run the detectors.** Run each detector **exactly one time** for the whole
audit. Every spawned agent reads the output files; none re-invokes a detector, because a fresh
`npx`/`uvx` resolve per agent wastes minutes for identical results.

```bash
~/.claude/skills/code-health-audit/scripts/scan.sh <path> <outdir>     # jscpd → ai report + JSON
uvx lizard --csv -o <outdir>/lizard.csv <path>                         # per-function metrics
~/.claude/skills/code-health-audit/scripts/hotspot.sh '*' '24 months ago' > <outdir>/hotspots.tsv
```

Then add the per-ecosystem detectors that apply to the languages actually present — `ruff` and
`vulture` for Python, `knip` for JS/TS, `clippy` for Rust, `golangci-lint` for Go. Detect the
languages from `git ls-files`; do not run a Python linter on a Go repo.

Default `<outdir>` to `.research/.health-scan` in the audited repo. Confirm `.research/` is
gitignored there before writing; if it is not, use a temp directory rather than leaving untracked
artifacts in someone's repo.

If `scan.sh` exits 3, `npx` is missing: skip the duplication family's mechanical pass and label that
half **DEGRADED (mechanical recall unknown)**. Any other non-zero exit (offline `npx`, jscpd crash)
gets the same treatment — skip the mechanical pass, label it DEGRADED, and say what failed.

### 2. Decide whether to fan out at all

**Collapse a family to a single agent invocation when its scan is small** — the duplication family
under ~8 clone pairs, the simplification family under ~10 lizard-flagged functions living in files
`hotspots.tsv` marks HOTSPOT. Eyeball the two output files for this; the decision needs an order of
magnitude, not an exact join. Collapsing one family while fanning out the other is fine. Say that
you are collapsing. Orchestration on a small repo is pure overhead and yields a worse report than
one agent holding the whole picture.

### 3. Fan out, in one message

Collect the scouts' maps first — fan-out waits on both the maps and the detectors. Then spawn
every agent in a single message so they run concurrently. Give each one the paths to the scan
outputs **and the map file(s)**, the exclusion list, an explicit instruction not to re-run any
detector, and **a unique output path** — `<outdir>/agents/<family>-<lens-or-batch>.md`. The agents default to one shared
report path; concurrent writers on the default clobber each other and leave the merge nothing to
read. Require every finding in the file to carry each site as `path:start-end`.

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

### 4. Merge — this is the real work

Several agents produce overlapping findings. Without a real merge the user gets several reports to
reconcile by hand, which is worse than one agent.

**Read each agent's report file from `<outdir>/agents/`.** The digests agents return are progress
signals; the files are the merge input — they hold the per-site spans that dedupe keys on. A
finding whose file entry lacks spans cannot be deduped; count it separately and say so.

1. **Dedupe.** Key each finding on its normalized span set — `(path, start_line, end_line)` per
   site, path relative to repo root. Two findings match when their spans overlap by more than half
   on both sides. Keep the better-argued one; merge the evidence.
2. **Cross-family conflicts are real and must be resolved, not averaged.** The two families can
   contradict each other: duplication says *extract these three copies into a helper*, while
   simplification says *this abstraction is already too tangled — inline it*. When both fire on the
   same code, prefer the cheaper error. Duplication is cheaper than a wrong abstraction, so a
   conflict resolves toward *leave it duplicated* unless the sites demonstrably co-change.
3. **Rank** by fix-worthiness: change-history evidence (co-change for duplication, relative churn
   for simplification) → actionability of the proposed step → blast radius → raw metric **last**.
   Span, occurrence count, and complexity score are what detectors sort by and the weakest
   predictors of whether a fix is worth making.
4. **Cross-check rejections.** If one agent rejected what another accepted, resolve it explicitly
   rather than letting the accepting agent win by default.

Gating helpers:

```bash
printf '%s\t%s\n' fileA fileB | ~/.claude/skills/code-health-audit/scripts/cochange.sh
~/.claude/skills/code-health-audit/scripts/hotspot.sh '*.py' '24 months ago'
```

**`THIN-HISTORY` means uninformative, not negative.** A young, squashed, or freshly-imported repo
shows no co-change and no churn for anything. Treating that as evidence against acting rejects every
finding. Apply the fallback at a repo level: when **more than half** of a family's candidate files
come back THIN-HISTORY, say so, drop that family's gate, and label its findings **UNGATED**. Below
that, gate per-file as normal and report the thin fraction in Coverage — never mix the two modes
silently.

### 5. Report

Write one merged report to `.research/code-health-audit.md` — same gitignore check as step 1; if
`.research/` is not ignored, write under the temp outdir instead and say so — and return a digest
plus the path. Never paste the full report inline, and never emit the per-agent reports separately.

```
# Code health audit — <repo/subtree>

## Coverage
Detectors + flags + thresholds. Files scanned / excluded. Agents spawned and what
each covered. The funnel for each family: N nominated → N gated in → N reported.
DEGRADED / UNGATED banners where they apply.

## Already solved elsewhere     <- duplication: the shared location already exists
## Extract now                  <- duplication
## Simplify now                 <- complexity, each with a concrete next step
## Possibly unreachable         <- dead code, split into safe-to-delete vs is-this-a-defect
## Considered and not reported  <- counts by reason; load-bearing, it makes the silence credible
```

## Standing rules

- **No silent caps.** State every cap — clusters per agent, agent count, findings reported — with
  how many items were dropped and the ranking that chose them. A truncated report that reads as
  complete is worse than no report.
- **Line numbers come from the tool.** Every span traces to detector output or a `Grep` hit.
  Neither you nor any spawned agent may estimate one.
- **Rejecting most candidates is success.** Most duplication should stay duplicated and most
  complexity is not worth touching. The rejection counts are what make the accepted list credible.
- **Never bundle a proposed simplification with a behavior change.** Refactors tangled with feature
  work are where the defect-injection signal actually lives. Propose pure, behavior-preserving
  changes only.
- **Every finding names a concrete next step.** Bug-prediction output that isn't actionable changes
  no behavior — this is measured, not theoretical. No next step, no entry.
- **Propose placement inside the repo's existing structure.** The scout map documents that
  structure — cite it. Never invent a `common/` in a repo with no such convention.
- **Migrations are append-only history.** Never propose consolidating or simplifying them.
