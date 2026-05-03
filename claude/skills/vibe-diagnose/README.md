# vibe-diagnose

A Claude Code skill that drives a disciplined six-phase debugging loop for hard bugs and performance regressions. Phase 1 (build a fast, deterministic, agent-runnable feedback loop) IS the skill — everything else consumes that signal.

Slash command: `/vibe-diagnose`. Auto-triggers on debugging phrases (see frontmatter).

## Dates

- **Created:** 2026-05-03

## Source

Adapted from Matt Pocock's `diagnose` (https://github.com/mattpocock/skills).

The body — the six phases (reproduce → minimise → hypothesise → instrument → fix → regression-test), the 10 ranked feedback-loop methods, the iterate-on-the-loop discipline, the falsifiability rule, the `[DEBUG-a4f2]` cleanup-grep pattern, the `Measure first, fix second` perf discipline, the no-correct-seam architectural finding, the `what would have prevented this bug?` post-mortem question, and the handoff to `/vibe-architecture` — is **full parity with Pocock**.

The HITL bash template (`scripts/hitl-loop.template.sh`) is **ported verbatim** from Pocock's source.

Two intentional deviations from the original:

1. **Sharpened description with negative triggers.** Routes test-writing-without-a-bug to `vibe-tdd` and architectural-deepening to `vibe-architecture`. Same skill-density argument as the rest of the framework.

2. **Phase 6 gains two checklist items** addressing documented agent-debugging failure modes:
   - **"The full test suite passes, not just the new regression test"** — addresses regressive-patch failures (~29% of agent fixes break unrelated code per arXiv 2503.15223).
   - **"The fix addresses the underlying invariant, not just the user-visible symptom"** — addresses divergent-fix failures (~47% of agent fixes pass tests but solve a similar-but-different bug). Requires the agent to articulate the invariant in one sentence; if they can't, they've made the symptom go away without understanding the cause.

Plus the standard rename-driven adjustments: slash command `/vibe-diagnose`, `/vibe-init` bootstrap suggestion when fully green-field, handoff target `/vibe-architecture` instead of `/improve-codebase-architecture`.

One added reference file:

- **`references/python-debugging-tools.md`** — Python tool defaults for each of the 10 feedback-loop methods (pytest, hypothesis, httpx, Playwright Python, syrupy, VCR.py, etc.), the py-spy default for the perf branch, the non-determinism kit (pytest-repeat, pytest-randomly, hypothesis stateful, faulthandler), and pytest regression-test idioms. Loaded only when the agent is debugging a Python project.

What we deliberately did NOT add (caught during build as gold-plating):

- No new "loop validation" step between Phase 1 and Phase 2 — Pocock's existing Phase-2 checklist already requires "the loop produces the failure mode the **user** described — not a different failure that happens to be nearby"
- No softening of the "no log everything" rule — Pocock's rule is already scoped to Phase 4 (Instrument); broad tracing in Phase 1/2 is implicitly allowed
- No early adoption of `vibe-architecture`'s vocabulary in Phase 5 — `vibe-architecture` isn't built yet; vocabulary should be defined there, not preempted here
- Allspaw's two-question post-mortem split — overkill for tightly-scoped bug fixes; Matt's open-ended `what would have prevented this bug?` is sufficient
- A separate `references/seam-handoff.md` — one paragraph in Phase 5 covers it

## Files

- `SKILL.md` — main skill instructions (six phases inline)
- `references/python-debugging-tools.md` — Python tool defaults per feedback-loop method
- `scripts/hitl-loop.template.sh` — bash template for human-in-the-loop reproduction (last-resort feedback loop)
