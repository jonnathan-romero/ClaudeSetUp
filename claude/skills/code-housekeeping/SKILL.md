---
name: code-housekeeping
description: Repo-wide hygiene sweep that EDITS files in place, orchestrated across two agents - @comment-janitor (deletes redundant comments and docstrings) and @logging-plumber (demotes over-loud log levels). ALWAYS trigger when the user wants a whole-repo cleanup that actually changes files - "clean up the comments and logging across this repo", "housekeep this codebase", "the AI comments and logs are noise repo-wide", "tidy up this repo", "run the janitors over this codebase" - or after a burst of agent-written code, or before handing a codebase to other agents. Runs the two families in FIXED waves (comments, then logging - the verifiers' baselines make the reverse order fail), computes the already-dirty exclusion set exactly once and passes it verbatim to every instance, verifies every file before keeping it, and collapses hundreds of per-site flags into a handful of claim-level decisions to put to the user. Do NOT use for ONE named file (use the comment-cleanup or add-logging skills, the watch-the-diff counterparts), and do NOT use for a read-only audit of duplication, complexity, dead code, doc drift, or repo structure - that is code-health-audit, which never edits anything.
argument-hint: "[path] [--comments-only|--logging-only]"
allowed-tools: Agent, AskUserQuestion, Read, Grep, Glob, Write, Bash(git:*), Bash(uvx ruff:*), Bash(npx:*), Bash(mkdir:*), Bash(cp:*)
---

# Repo housekeeping (orchestrated, and it edits)

Fan out a repo-wide hygiene sweep across the two editing agents, then merge what they could not
decide into one small set of questions for the user.

**This skill changes files.** That is the whole point of it, and it is what separates it from
`code-health-audit`, which runs a superficially similar fan-out and is read-only in every branch.
Never blur the two: if the user wants to *know* what is wrong, that is the audit; if they want it
*fixed*, this is the skill.

| Family | Does | Agent | Proof |
|---|---|---|---|
| **Comments** | Deletes restatement, step narration, banners, commented-out code, `Args:` entries echoing a typed signature; compresses public docstrings | `@comment-janitor` | AST-with-docstrings-dropped **and** a comment-filtered token stream |
| **Logging** | Demotes over-loud INFO narration to DEBUG; renames `.warn`→`.warning` | `@logging-plumber` | resolved log statements deleted from both ASTs, remainder compared |

**The two are not symmetric, and the report must not present them as if they were.**
`@comment-janitor` deletes at volume and queues the exceptions. `@logging-plumber` makes two narrow
edits and queues nearly everything it finds — it is a finder that also fixes a small class. Expect
the comment family to dominate the diff and the logging family to dominate the question queue.

## The four rules that make this correct

**1. The wave order is fixed: comments first, then logging. This is not a preference.**

The two verifiers take their "before" snapshot from different places, and only one order survives it:

| Agent | Baseline | Consequence |
|---|---|---|
| `@comment-janitor` | `git show "HEAD:$f"` | Needs the file **clean**. A prior wave's edits read as unexplained changes → exit 1 → it reverts. |
| `@logging-plumber` | `cp "$f" "$tmp/before"` (working tree) | Tolerates a prior wave. Its proof sees only its own change. |

Verified empirically, not reasoned: a docstring compressed in wave 1 then demoted in wave 2 passes
when the plumber baselines on the working tree, and fails `UNSAFE: a docstring was demoted, lost, or
altered` when it baselines on HEAD. Run logging first and the comment wave reverts every file the
plumber touched. **Never reorder the waves, and never let an agent substitute a HEAD baseline.**

The same asymmetry governs the *apply* pass, which is why the comment questions are asked and applied
**between** the waves rather than at the end — see step 4. Deferring them until after wave 2 would
put comment-janitor back on a file whose HEAD→current diff now contains a log-level change, and its
revert-to-HEAD would take both waves' work with it.

**2. The exclusion set is computed ONCE, here, and passed verbatim to every instance in every wave.**

```bash
{ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
```

Files the user had in flight when the run started. Both agents forbid recomputing it, and this skill
is the sole computer of it — because by wave 2 the working tree is dirty *with wave 1's own edits*,
and a recomputed set would exclude exactly the files wave 2 exists to finish. Recomputing anywhere is
a deadlock, not a slowdown.

Use this form rather than parsing `git status --porcelain`: porcelain's rename form is
`R old -> new`, so a naive `awk '{print $NF}'` silently drops the old path, and paths containing
spaces break field splitting outright.

**3. Shard by file — and note this inverts `code-health-audit`'s rule.**

That skill forbids sharding by directory because duplication is a global property: the highest-value
finding is invisible to any agent that sees only half the tree. Here the mutation is *file-local* —
a redundant comment and an over-loud log level are decidable from the file plus a hop of context — so
splitting the candidate list across instances loses nothing.

What sharding does cost is **claim coverage**: a single claim ("this `# upstream returns dupes`
comment is load-bearing") recurs across files that landed in different instances. That is why both
agents emit **sites, never totals**, and why the per-family merge (steps 4 and 6) is mandatory rather
than cosmetic. Shard
the work; never shard the claim.

**4. A verified exit 0 is not compliance.** Both verifiers prove *containment* — that nothing outside
the family changed. Neither checks that the agent stayed inside its own lanes. For the plumber
specifically, a promotion, an `ERROR→WARNING` demotion, and `.exception`→`.error` all pass. So the
plumber's **per-site demotion list is the only review surface for band compliance, and the merge must
reproduce it in full** — never summarised, never collapsed to a count.

## Workflow

### 1. Preflight — once, before any agent runs

```bash
mkdir -p <outdir>/agents
{ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u > <outdir>/excluded.txt
```

Default `<outdir>` to `.research/.housekeeping` in the target repo. **Confirm `.research/` is
gitignored there before writing**; if it is not, use a temp directory rather than leaving untracked
artifacts in someone's repo — this skill must not create the mess it exists to clean.

Refuse to proceed only if `git` cannot run. A dirty tree is normal and is what `excluded.txt` is for;
it is never a reason to abort.

**Run the nominating detectors exactly once for the whole run.** Every spawned instance reads these
files; none re-invokes a detector, because a fresh `npx`/`uvx` resolve per instance costs minutes for
identical output.

```bash
uvx ruff check --no-cache --ignore-noqa --select ERA001 --output-format json . > <outdir>/era001.json
uvx ruff check --no-cache --select G,LOG,PLE1205,PLE1206,TRY400 --output-format json . > <outdir>/logrules.json
npx --yes cloc@2.6.0-cloc --by-file --json --quiet . > <outdir>/cloc.json
```

The cloc pin is counter-intuitive and deliberate: on npm the plain versions are a stale wrapper
(`cloc@2.10` ships upstream **1.94**), while the `-cloc`-suffixed line is the real redistribution
(`cloc@2.6.0-cloc` ships upstream **2.06**). Confirm with `npx --yes cloc@<v> --version` before
changing it.

If a detector fails or its tool is missing, label that family **DEGRADED (mechanical recall
unknown)** in Coverage and let its agents nominate by reading. A missing detector never cancels a
family.

### 2. Decide the fan-out

Count candidates per family from the detector output and the tracked-file list, minus `excluded.txt`.

- **Under ~20 candidate files in a family → one instance.** Each agent already caps itself at 20
  files, so a single instance covers the whole family and holds the whole claim picture, which makes
  the merge better. Orchestration below that threshold is pure overhead.
- **Above it → batch ~20 files per instance, capped at 4 instances per family.** State the cap, how
  many files it dropped, and the ranking that chose them.
- Collapsing one family while fanning out the other is fine and common — the comment family usually
  has far more candidates.

**Total coverage is `instances × 20`, and anything beyond it is dropped.** Say the number out loud in
Coverage. A run that silently covered 80 of 400 candidate files while reading as complete is worse
than no run.

### 3. Wave 1 — `@comment-janitor`

Spawn the wave's instances in a single message so they run concurrently. Give each one:

- its **batch** of repo-relative paths, and the instruction that **the supplied batch replaces the
  agent's own 20-file cap — cover exactly it, do not re-select or re-cap within it.** Both agents
  carry an unqualified "Cap the run at 20 files" in their Selection section alongside "Cover exactly
  that batch" in Orchestrated mode; without this line an instance may apply its internal cap *on top*
  of the batch and silently cover fewer files than the Coverage arithmetic claims;
- `<outdir>/excluded.txt` and the instruction to **use it verbatim, never recompute**;
- `<outdir>/era001.json` and `<outdir>/cloc.json`, with an explicit instruction not to re-run either;
- a **unique output path**: `<outdir>/agents/comments-<batch>.md` and `…/comments-<batch>.manifest`.
  The agents default to one shared path; concurrent writers on the default clobber each other and
  leave the merge nothing to read.

**Wait for every wave-1 instance to finish before continuing.** Wave 2's correctness depends on wave
1's edits being settled on disk, and a plumber instance that starts while a janitor instance is
mid-file baselines on a half-written file.

### 4. Round 1 — merge, ask, and apply the comment answers

**All of this happens before wave 2 starts, and the ordering is forced.** `@comment-janitor` baselines
on `git show "HEAD:$f"`, so once the plumber has changed a log level in a file, the HEAD→current diff
contains an AST change that the comment verifier reads as *code changed* → exit 1 → and its revert is
`git checkout -- <file>`, back to HEAD. That would destroy **both** waves' verified edits on that
file and invalidate a manifest the user may be relying on. Applying comment answers while the tree
still holds comment-only changes is what avoids it.

Asking per family rather than once at the end costs nothing, because a cross-family merge is
impossible by construction: the two `scope-tag` vocabularies are disjoint
(`convention`/`external-system`/`performance`/`invariant-ordering`/`history-compat`/`todo-unlinked`
versus `removal`/`level-boundary`/`traceback-loss`/`format-bug`/`style-migration`/
`duplicate-logging`/`dormant-guard`/`promotion`), so no comment claim and logging claim can ever
share a `claim-key`. The merge that carries the value is **across instances within a family**, and
that is preserved here in full.

**Merge.** Read every `<outdir>/agents/comments-*.md` — the digests the agents return are progress
signals; the files are the merge input.

1. **Collapse by `claim-key` across instances.** Identical `claim-key` → one decision carrying the
   union of all sites. This is where 200 flags become ~15 questions.
2. **Order so a fundamental answer moots its dependents.** Within a `scope-tag`, a claim whose sites
   are a superset of another's comes first — answering "all `# upstream returns dupes` comments are
   real" settles every per-file instance beneath it. Record what each answer mooted; it goes in the
   report.
3. **Collect the funnel while you are in the files.** Sum each instance's `N comments read → N
   deleted → N queued`, plus its skipped-dirty / skipped-unverified / dropped counts. Nothing else
   collects these, and Coverage cannot be written without them.

**Ask.** Use `AskUserQuestion`, up to 4 per call, in that ranked order — highest-leverage claim first,
so an early answer can moot later ones. Re-rank after each call with mooted claims removed, and keep
going until the queue is empty or the user stops. **There is no cap and the user stops whenever they
like**; every round says how many claims remain, and a subset is never presented as the whole queue.
Put both `if-confirmed` and `if-denied` to the user — for several `kind`s (notably `unlinked-todo`)
the safe default is not obvious from the claim alone.

**Apply.** Only if something actionable was answered. Re-invoke the affected instances with the
answered questions, the same exclusion set, and new unique output paths. Answers are decisions — the
agents are told not to re-litigate one, and neither should this skill. Every applied file verifies
exactly as in the first pass: an answer is authority to make the edit, never authority to skip the
proof.

If the user stopped early, unanswered claims carry forward to the report in `claim-key` form.

### 5. Wave 2 — `@logging-plumber`

Same shape as wave 1, with `<outdir>/logrules.json` and output paths
`…/logging-<batch>.{md,manifest}` — including the same batch-replaces-the-cap instruction.

Two more instructions belong in every wave-2 prompt, because they are this wave's failure modes:

- **Revert from your own `$tmp/before` copy, never `git checkout -- <file>`.** In wave 2 the file is
  dirty *by design*, so `git checkout --` reverts to HEAD and destroys wave 1's verified edits —
  silently invalidating a manifest that another agent already wrote and the user may rely on to undo.
- **Files dirtied by wave 1 are still in scope.** Only `excluded.txt` is out of scope. An instance
  that treats "dirty" as "skip" will skip nearly everything wave 1 touched.

### 6. Round 2 — merge, ask, and apply the logging answers

Identical to round 1, over `<outdir>/agents/logging-*.md`, with two additions:

- **The funnel shape differs**: `N call sites → N resolved → N demoted / N renamed / N queued /
  N observed`. Sum it across instances the same way.
- **Extract the per-site demotion list from every instance and keep it whole** (rule 4). It is not a
  question queue and it is never collapsed to a count — it is the only review surface for band
  compliance, because the verifier proves containment and not lanes.

The plumber has no HEAD-baseline hazard, so its apply pass is safe at any point after wave 2.

### 7. Report

Write one merged report to `<outdir>/code-housekeeping.md` and return a digest plus the path. Never
paste the full report inline, and never emit the per-agent reports separately.

```
# Repo housekeeping — <repo/subtree>

## Coverage
Waves run and instances per wave. Files scanned / edited / skipped-dirty /
skipped-unverified / dropped to the cap — and the cap itself, with the ranking
that chose what survived. Detectors + flags, DEGRADED banners where they apply.
Per-family funnels, both stated even when one family did nothing:
  comments: N read → N deleted → N queued
  logging:  N call sites → N resolved → N demoted / N renamed / N queued

## What changed
Per family, by category, with counts and representative file:line examples.
The diff is the exhaustive list; this is the orientation.

## Demoted log levels (per site, in full)
Reproduced verbatim from the plumber's reports, never summarised. The verifier
proves containment, not band compliance, and in-repo xrefs cannot see alert
rules living in SaaS consoles — so this list is the review surface for both.
Scan it against your own dashboards before committing.

## Decisions you made
Each answered claim, what it resolved, how many sites it covered, and how many
downstream questions it mooted.

## Still open
Unanswered claims in claim-key form, ready for a later run.

## Left alone deliberately
Counts by reason, both families. Load-bearing — it is what makes the edits
credible and the silence trustworthy.

## Undo
git restore --pathspec-from-file=<combined manifest>
Restores every file both waves touched, back to HEAD. It does NOT touch the
files in excluded.txt — your in-flight work is safe. Note this undoes BOTH
waves for any file both touched; there is no partial undo of wave 2 alone.

## Commit
Two recipes, both valid. Pick one:

  (a) Two commits, one per family — each independently reviewable and
      revertable, and only the comment sweep gets registered in
      .git-blame-ignore-revs:

        git commit --pathspec-from-file=<comments manifest> -m "chore: remove redundant comments (no code change)"
        git rev-parse HEAD >> .git-blame-ignore-revs   # annotate the SHA with a `# <what it was>` line above it
        git config blame.ignoreRevsFile .git-blame-ignore-revs
        git commit --pathspec-from-file=<logging manifest> -m "chore: demote noisy logs to debug (no code change)"

  (b) One housekeeping commit across both manifests — simpler history, but it
      cannot be registered in .git-blame-ignore-revs, because doing so would
      also hide the log-level changes, and those are semantic: a future reader
      running git blame should see them.

The `git config` line in (a) is per-clone and opt-in — every other contributor
runs it themselves or still sees the comment commit on every line it touched.
GitHub and GitLab honour the file automatically; local `git blame` does not.
```

## Standing rules

- **Never commit, stage, stash, branch, or rewrite history — and never let a spawned agent do it.**
  The working tree is the deliverable; the user commits.
- **The exclusion set is computed once, by this skill, and is never recomputed by anyone.**
- **Never reorder the waves.** Comments, then logging. Rule 1 is a verified property of the two
  verifiers, not a stylistic choice.
- **A family is skipped only when the user asked (`--comments-only` / `--logging-only`) or the repo
  has no surface for it, and Coverage names it either way.**
- **No silent caps.** Instances per family, files per instance, total coverage, questions per round —
  state each with what it dropped and the ranking that chose the survivors.
- **Line numbers come from a tool** — a detector hit or a `Grep` result. Neither this skill nor any
  spawned agent may estimate one.
- **Never run the repo's own code** to decide anything: no install scripts, no build, no documented
  example commands. A cheap test suite may be run after edits, but a green suite is never reported as
  verification — mutation tools exclude logging and comment lines by default precisely because tests
  do not kill those mutants.
- **Rejecting most candidates is success.** Most comments that survive should survive, and a repo
  whose log levels all defend themselves is a real result. The "left alone deliberately" counts are
  what make the edits credible.
- **If both families edited nothing, say so and show both funnels.** That is a clean bill of health,
  not a failed run.
