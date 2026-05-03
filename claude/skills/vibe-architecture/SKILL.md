---
name: vibe-architecture
description: 'Surfaces architectural friction and proposes deepening opportunities — refactors that turn shallow modules into deep ones (small interface hiding lots of behavior). Uses the vocabulary Module / Interface / Depth / Seam / Adapter / Leverage / Locality. Informed by `CONTEXT.md` domain glossary and existing ADRs. ALWAYS trigger when the user says `improve architecture`, `find refactoring opportunities`, `make this more testable`, `this codebase is hard to navigate`, `consolidate these modules`, `deepen this module`, or asks for architectural review or design improvements. Do NOT use to debug a specific bug — that''s `vibe-diagnose` (which may hand off here when no test seam exists). Do NOT use to write tests for new code without a bug — that''s `vibe-tdd`.'
---

# vibe-architecture

Surface architectural friction and propose **deepening opportunities** — refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

Use this skill as a recurring maintenance pass, not a one-shot — Beck's "invest in the design of the system every day."

## Glossary

Use these terms exactly in every suggestion. Consistent language is the point — don't drift into "component," "service," "API," or "boundary." Full definitions in [references/LANGUAGE.md](references/LANGUAGE.md).

- **Module** — anything with an interface and an implementation (function, class, package, slice).
- **Interface** — everything a caller must know to use the module: types, invariants, error modes, ordering, config. Not just the type signature.
- **Implementation** — the code inside.
- **Depth** — leverage at the interface: a lot of behaviour behind a small interface. **Deep** = high leverage. **Shallow** = interface nearly as complex as the implementation.
- **Seam** — where an interface lives; a place behaviour can be altered without editing in place. Every seam has an **enabling point** — the concrete place the swap happens. (Use this, not "boundary.")
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth: change, bugs, knowledge concentrated in one place.

Key principles (full list in [references/LANGUAGE.md](references/LANGUAGE.md)):

- **Deletion test**: imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.**
- **One adapter = hypothetical seam. Two adapters = real seam.** *Test fakes don't count toward the threshold — need two real production variants.*

This skill is *informed* by the project's domain model. The domain language gives names to good seams; ADRs record decisions the skill should not re-litigate.

## Process

### 1. Explore

Read the project's domain glossary (`CONTEXT.md`) and any ADRs in the area you're touching first.

**Read existing ADRs before proposing candidates** — if a refactor was previously rejected via an ADR, don't re-propose it. If you have a genuinely new angle on a previously-rejected candidate, frame it as *"supersedes ADR-NNNN"* and explain what's changed.

Then use the Agent tool with `subagent_type=Explore` to walk the codebase. Don't follow rigid heuristics — explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates

Present a numbered list of deepening opportunities. For each candidate:

- **Files** — which files/modules are involved
- **Problem** — why the current architecture is causing friction
- **Solution** — plain English description of what would change
- **Benefits** — explained in terms of locality and leverage, and also in how tests would improve

**Use `CONTEXT.md` vocabulary for the domain, and [references/LANGUAGE.md](references/LANGUAGE.md) vocabulary for the architecture.** If `CONTEXT.md` defines "Order," talk about "the Order intake module" — not "the FooBarHandler," and not "the Order service."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting. Mark it clearly (e.g. _"contradicts ADR-0007 — but worth reopening because…"_). Don't list every theoretical refactor an ADR forbids.

Do NOT propose interfaces yet. Ask the user: *"Which of these would you like to explore?"*

### 3. Grilling loop

Once the user picks a candidate, drop into a grilling conversation. Walk the design tree with them — constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive. Dependency strategy guidance: [references/DEEPENING.md](references/DEEPENING.md).

Side effects happen inline as decisions crystallize:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Add the term to `CONTEXT.md` — same discipline as `/vibe-grill` (see [../vibe-grill/references/CONTEXT-FORMAT.md](../vibe-grill/references/CONTEXT-FORMAT.md)). Create the file lazily if it doesn't exist.
- **Sharpening a fuzzy term during the conversation?** Update `CONTEXT.md` right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR, framed as: *"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"* Only offer when the reason would actually be needed by a future explorer to avoid re-suggesting the same thing — skip ephemeral reasons ("not worth it right now") and self-evident ones. Format: [../vibe-grill/references/ADR-FORMAT.md](../vibe-grill/references/ADR-FORMAT.md).
- **Want to explore alternative interfaces for the deepened module?** See [references/INTERFACE-DESIGN.md](references/INTERFACE-DESIGN.md) for the parallel sub-agent pattern.
