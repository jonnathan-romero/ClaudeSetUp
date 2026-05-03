# vibe-* engineering framework

A bundle of Claude Code skills for agentic software engineering, organised around four ways agent-assisted coding goes wrong. Each skill is a countermeasure to a named failure mode.

## The four failure modes

| # | Failure | Countermeasure |
|---|---|---|
| 1 | **Misalignment** — the agent didn't do what you wanted | `/vibe-grill` |
| 2 | **Verbosity** — the agent uses 20 words where 1 will do | `CONTEXT.md` glossary discipline (built into `/vibe-grill`) |
| 3 | **Broken code** — output doesn't actually work | `/vibe-tdd`, `/vibe-diagnose` |
| 4 | **Ball of mud** — agents accelerate entropy | `/vibe-architecture`, `/vibe-prd` |

## Skills

| Slash command       | Purpose                                                                       |
| ------------------- | ----------------------------------------------------------------------------- |
| `/vibe-init`        | Bootstrap this framework in a new repo (you ran this to get here)             |
| `/vibe-grill`       | Socratic interview that stress-tests a plan and updates `CONTEXT.md` + ADRs   |
| `/vibe-prd`         | Synthesise the current conversation into a published PRD                      |
| `/vibe-issues`      | Break a PRD into independently-grabbable vertical-slice issues                |
| `/vibe-issue-triage`| Move issues through the 5-state triage pipeline; produces Agent Briefs        |
| `/vibe-diagnose`    | Six-phase debugging loop for hard bugs and performance regressions            |
| `/vibe-architecture`| Surface deepening opportunities (shallow modules → deep modules)              |
| `/vibe-tdd`         | Test-driven development with the red-green-refactor loop                      |

## Artifacts the framework produces

- **`CONTEXT.md`** — the project's domain glossary. Lazy-created and updated by `/vibe-grill` (primary) and `/vibe-architecture` (during architectural grilling) when terms get resolved.
- **`docs/adr/`** — architectural decision records. Lazy-created by `/vibe-grill` or `/vibe-architecture` when the first ADR is needed. ADRs are short — often a single paragraph.
- **`docs/agents/`** — per-repo configuration this framework consumes (issue tracker, triage labels, domain docs). Created by `/vibe-init`. Edit directly to customise.
- **`.out-of-scope/`** — institutional memory of rejected feature requests, with reasoning. Created by `/vibe-issue-triage` when an enhancement is closed as `wontfix`.
- **`.scratch/`** — only if you chose local-markdown for the issue tracker. Stores PRDs and issues as files: `.scratch/<feature>/PRD.md` and `.scratch/<feature>/issues/NN-slug.md`.

## Workflow

```
[once per repo]
  /vibe-init
       │
       ▼
[interactive]
  /vibe-grill           →   produces / updates CONTEXT.md and ADRs
       │
       ▼
  /vibe-prd             →   publishes a PRD
       │
       ▼
  /vibe-issues          →   breaks the PRD into vertical-slice issues
       │
       ▼
  /vibe-issue-triage    →   posts Agent Brief, applies state label
       │
       ▼
[implementation — AFK agent or you]
  Pick up `ready-for-agent` issue; read CONTEXT.md and Agent Brief; open PR
       │
       ▼
[recurring]
  /vibe-tdd             →   while implementing, when behaviour matters
  /vibe-diagnose        →   when a bug is hard
  /vibe-architecture    →   every few days; surface deepening opportunities
```

## Per-repo configuration

This repo's specifics — which issue tracker, which label vocabulary, single vs multi-context — live in `docs/agents/`. Edit those files directly to change behavior; you don't need to re-run `/vibe-init`.

## References

The framework draws on:

- John Ousterhout, *A Philosophy of Software Design* — deep modules
- Hunt & Thomas, *The Pragmatic Programmer* — tracer bullets, fast feedback
- Eric Evans, *Domain-Driven Design* — ubiquitous language
- Kent Beck, *Extreme Programming Explained* — invest in design every day
- Matt Pocock's `mattpocock/skills` — the original framework these skills are adapted from
