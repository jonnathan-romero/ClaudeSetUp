# vibe-architecture

A Claude Code skill that surfaces architectural friction in a codebase and proposes **deepening opportunities** — refactors that turn shallow modules into deep ones (small interface hiding lots of behavior). Use as a recurring maintenance pass, not a one-shot.

Slash command: `/vibe-architecture`. Auto-triggers on architecture-review phrases (see frontmatter).

## Dates

- **Created:** 2026-05-03

## Source

Adapted from Matt Pocock's `improve-codebase-architecture` (https://github.com/mattpocock/skills).

The body — the eight-term vocabulary (Module, Interface, Implementation, Depth, Seam, Adapter, Leverage, Locality), the four principles (depth is interface-only / deletion test / interface = test surface / one-adapter-hypothetical-two-adapters-real), the dependency categories in DEEPENING.md, the parallel sub-agent pattern in INTERFACE-DESIGN.md, the rejected framings, and the grilling-loop side-effects (CONTEXT.md updates inline, the exact ADR offer framing) — is **full parity with Pocock**.

Five intentional deviations from the original, all small and surgical:

1. **Sharpened description with negative triggers.** Routes bug-debugging to `vibe-diagnose` and test-writing-without-a-bug to `vibe-tdd`. Same skill-density argument as the rest of the framework.

2. **Added "enabling point" to the Seam definition** in `references/LANGUAGE.md`. Feathers' original concept names the concrete place where the swap actually happens (constructor argument, config value, registry key, env var). Without it, "seam" is abstract; with it, the seam is operable.

3. **Added "Hexagonal architecture / ports & adapters" to rejected framings** in `references/LANGUAGE.md`. Many readers schooled in hexagonal will assume our "seam/adapter" is just a rename — one paragraph clarifies that hexagonal is a topological special case (port = seam at the application boundary), while our seam is more general.

4. **Added test-double carve-out to the two-adapter rule** in both `references/LANGUAGE.md` and `references/DEEPENING.md`. Pocock's "two adapters = real seam" rule is silent on whether test fakes count. Without the carve-out, every TDD-driven seam trivially passes the rule. The carve-out: test fakes don't count; need two **real production** variants.

5. **Added idempotency rule and ADR-aware sub-agent briefs:**
   - In `SKILL.md` Step 1 (Explore): "Read existing ADRs before proposing candidates — if a refactor was previously rejected via an ADR, don't re-propose it. If you have a new angle, frame it as 'supersedes ADR-NNNN.'" Prevents drift across re-runs.
   - In `references/INTERFACE-DESIGN.md` Step 2: "Include ADRs that touch the target seam in each sub-agent's brief, summarized as one-line constraints." Prevents parallel sub-agents from proposing designs that contradict accepted decisions. Filtered to relevant ADRs only — full ADR text would dilute attention and defeat the divergence the parallel pattern depends on.

Plus the standard rename-driven adjustments: slash command `/vibe-architecture`, cross-references to `/vibe-grill`'s `references/CONTEXT-FORMAT.md` and `ADR-FORMAT.md`, `/vibe-init` bootstrap suggestion when fully green-field.

What we deliberately did NOT add (caught during build/debate as gold-plating):

- No explicit "handoff entry from `vibe-diagnose`" step — Pocock's skills are self-contained; the user invokes `vibe-architecture` and provides the seam issue as input naturally. Hardwiring an entry point creates inter-skill coupling that rots if either skill changes.
- No adopting `vibe-grill`'s three-criteria ADR gate — different decision moments justify different gates. `vibe-grill`'s captures *affirmative* decisions; `vibe-architecture`'s narrower "would prevent re-suggestion" rule fits *negative* decisions (rejected refactors). Forcing unification = false uniformity.
- No hardcoded sub-agent count cap (e.g., "never exceed 5") — bakes today's empirical fan-out research into permanent skill prose. Pocock's "3+" is sufficient; the `agent-orchestration` skill exists for fan-out guidance.
- No `references/python-deepening.md` with Manager-class-smell / Protocol-budget rules — these are opinions dressed as rules that misfire on legitimate DDD-style codebases (`UserService` is a real pattern). Pocock's deletion test and two-adapter rule already catch the bad cases for any language.

## Files

- `SKILL.md` — main skill instructions (vocabulary preview, three-step process)
- `references/LANGUAGE.md` — full vocabulary + four principles + rejected framings
- `references/DEEPENING.md` — dependency categories, seam discipline, testing strategy
- `references/INTERFACE-DESIGN.md` — parallel sub-agent pattern for exploring alternative interfaces

## Cross-skill references

- `CONTEXT.md` updates during architectural grilling follow [vibe-grill's CONTEXT-FORMAT spec](../vibe-grill/references/CONTEXT-FORMAT.md)
- ADR offers during architectural grilling follow [vibe-grill's ADR-FORMAT spec](../vibe-grill/references/ADR-FORMAT.md)
- `vibe-diagnose` may flag a "no good test seam" finding for follow-up here; the user pastes the finding into the conversation when invoking this skill (no special entry point needed)
