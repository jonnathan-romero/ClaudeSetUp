# vibe-issue-triage

A Claude Code skill that moves issues through the framework's 5-state × 2-category triage state machine. Produces durable artifacts on terminal states: an **Agent Brief** comment for `ready-for-agent` / `ready-for-human` issues, and a `.out-of-scope/<concept>.md` entry when an enhancement is closed as `wontfix`.

Slash command: `/vibe-issue-triage`. Auto-triggers on triage phrases (see frontmatter).

## Dates

- **Created:** 2026-05-03

## Source

Adapted from Matt Pocock's `triage` (https://github.com/mattpocock/skills).

The body — the 5-state × 2-category state machine, the AI-disclaimer prefix, the two flows ("show what needs attention" + per-issue triage), the recommend-and-wait approval gate, the bug-reproduction sub-flow with three reportable outcomes, the session-resume choreography, the quick-override path, and the `.out-of-scope/` knowledge-base format — is **full parity with Pocock**.

Three intentional deviations from the original — all "cleared deferrals" from upstream skills:

1. **Sharpened description with negative triggers.** Routes PRD-writing to `vibe-prd` and slicing to `vibe-issues`. Same skill-density argument as the rest of the framework.
2. **Agent Brief gains a `Verification` field.** Required for `ready-for-agent`, optional for `ready-for-human`. ≥1 executable check (test command, curl, screenshot diff). This is the falsifiability rule that was deferred from `vibe-issues`'s debate; it lands here because the Agent Brief is what AFK agents actually consume.
3. **Agent Brief gains a `Repo policies in effect` field.** Inline (not linked) policies from `CLAUDE.md` / `AGENTS.md` / `docs/agents/` that apply to this issue. The Agent Brief is the only surface every agent platform reliably reads (Copilot Coding Agent, OpenHands resolver, Aider, claude-code-action all behave differently with respect to CLAUDE.md). This is the policy-propagation that was deferred from `vibe-prd`'s debate.

Plus one related revision **to `vibe-init`** (not this skill): add `bug` and `enhancement` rows to the seed `triage-labels.md` mapping, so the category labels have a defined repo string just like the five state labels.

What we deliberately did NOT add (after a debate pass):

- No `duplicate` as a 6th terminal state — Pocock's collapse into `wontfix` is lossy but not broken; keeps 5-state symmetry
- No `needs-info` / `needs-repro` split — only worth it for high-volume repos
- No verbatim interface-name pinning in the brief — Matt's "what changes" is fine for non-benchmark use
- No `Aliases` or `Revisit if` sections in `.out-of-scope/` files — semantic matching from prose is enough at typical scale; would become N/A filler

## Files

- `SKILL.md` — main skill instructions
- `references/AGENT-BRIEF.md` — Agent Brief format spec, including the new Verification + Repo policies fields and two worked examples
- `references/OUT-OF-SCOPE.md` — `.out-of-scope/<concept>.md` format spec
