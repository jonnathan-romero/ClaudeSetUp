# What's Worth Building

Which subagents people actually create, and the higher-leverage long-tail ideas worth building rather than copying. Use this when deciding *whether* a job deserves a subagent and *what shape* it should take. Grade every candidate against the rubric below.

## Contents
1. [The rubric — what makes a good subagent](#1-the-rubric)
2. [Subagent vs skill vs hook](#2-subagent-vs-skill-vs-hook)
3. [The consensus-core agents](#3-the-consensus-core)
4. [High-leverage long-tail picks](#4-high-leverage-long-tail-picks)
5. [Low-signal categories to skip](#5-low-signal-categories)

---

## 1. The rubric

A subagent is worth building when the job is:
- **Isolated / fresh-eyes** — benefits from *not* seeing the prior conversation (unbiased verification, review).
- **Read-many, write-little** — explores 10+ files or compares versions, emits a small artifact.
- **Parallelizable** — 3+ independent pieces of work that don't depend on each other.
- **Restricted-tool** — review/research wants read-only; only implementation wants Edit/Write.

Worst-fit (don't make a subagent): sequential dependent work, same-file parallel edits, small quick fixes, latency-sensitive tasks, "too many specialists." The highest-leverage agents are the **analysis/audit/explain** shapes — not the "write this function" shapes the base model already does well inline.

## 2. Subagent vs skill vs hook

The decision rule:
- **Reusable instructions / workflow that runs in the main context** → **skill**
- **Deterministic automation that must run every time on an event** → **hook**
- **Delegated work where you only need the result back** → **subagent**

A large fraction of the "long-tail" ideas below ship in the wild as *skills*, *commands*, or *GitHub Actions* — not as `.claude/agents/` files. That's exactly where the leverage is: the *capability* exists, but the *subagent packaging* (isolated context, restricted tools, parallel) is rare.

## 3. The consensus-core

These recur across the official docs and both major catalogs (wshobson 192 agents, VoltAgent 154+). High-signal, well-understood:

- **code-reviewer** — read-only (deny Edit/Write), runs on `git diff`, fresh-eyes per PR.
- **debugger** — adds Edit (fixing needs mutation); isolates verbose logs/stack traces out of the main context.
- **test-automator / test-runner** — test output is high-volume; the docs cite "run the suite and report only the failing tests" as a top use.
- **security-auditor** — focused prompt + restricted tools; runs in parallel to the reviewer for a different lens.
- **performance-engineer**, **database-optimizer / db-reader** — profiling and query work produce large output worth isolating; pairs with the read-only-DB hook pattern.
- **api-documenter / docs** — separable, artifact-producing.

Naming note: some practitioners argue against the exact names `code-reviewer`/`debugger`/`test-writer`, preferring job-shaped, action-oriented names (`pr-reviewer`, `repo-explorer`, `test-runner`) that route better. Both camps agree on the underlying jobs.

## 4. High-leverage long-tail picks

Past the front-page favorites — ranked by leverage × rarity for a solo dev. Each is a read-many/write-little, fresh-context job:

1. **Documentation-drift detector** — diffs what the code actually does (CLI flags, signatures, env vars, `install.sh` steps) against what the README/docstrings claim. Read-only, no edit authority, parallel per-doc. Near-absent as an agent (only *generators* exist). The strongest gap for anyone whose README drifts from their install script.
2. **Fresh-eyes adversarial / design critic (lightweight)** — reviews a plan or diff *without* seeing the prior conversation and must surface ≥1 real risk. The literal textbook subagent use-case ("a subagent that does not see our previous discussion"). Heavyweight multi-agent panels exist; the cheap single-agent version is underused. Counters self-review rubber-stamping on solo work.
3. **Python dead-code + unused-dependency auditor** — wraps `vulture` / `deptry` / `ruff --select F401`, synthesizes a prune list. Whole-tree read-only scan, parallel with other audits. Existing tools are JS-first (knip/jscpd); the Python-native agent is an open niche.
4. **Flaky-test hunter** — runs the suite N times in isolation, bisects non-determinism, reports unstable tests + likely cause. Reruns pollute the main context; the job is self-contained and parallelizable. Genuinely near-absent as an agent.
5. **Scoped single-hop migration agent** — *not* a generic "modernizer" but one targeted job loaded with the migration guide (Pydantic v1→v2, argparse→click, `setup.py`→`pyproject.toml`). Caveat: keep it to one independent module — big migrations are sequential, a subagent worst-case.
6. **Repo-onboarding / architecture-mapper** — explores the tree, infers architecture, emits a quick-start + Mermaid diagram. The canonical "explore 10+ files" delegation signal. Common as a skill, rare as a dedicated subagent.
7. **API-surface / breaking-change diff** — diffs the public surface (exported functions, CLI, config schema) between two git refs, flags breaking changes. Read-only two-version comparison.
8. **Changelog / release-notes from git diff** — reads the commit range, categorizes Added/Changed/Fixed, emits Keep-a-Changelog markdown. The diff is large and noisy — ideal to isolate from the parent context. Solved in the wild with Actions/skills, not subagents.

**Honorable mentions:** `dx-optimizer` pointed at your own dotfiles workflow; a "CLAUDE.md / skills conflict detector" modeled on the SEO-cannibalization "detect overlap across N artifacts" shape — surfaces duplicate or contradictory rules across a skill collection.

## 5. Low-signal categories

Skip these for a personal config — they bulk out the big catalogs but add little:
- The dozens of language-`pro` agents (`python-pro`, `rust-pro`, …) — redundant with base-model capability.
- Business / SEO / marketing agents — out of scope for dev work.
- Generic "modernizer" agents — the *scoped* single-hop version (pick #5) is far more reliable than a catch-all.
