# Anatomy of a Subagent Definition

How real, well-regarded subagent files are built — distilled from Anthropic's official examples, wshobson/agents (36k★), and VoltAgent/awesome-claude-code-subagents (21k★). Use this when writing or reviewing the structure of a definition file.

## Contents
1. [The `description` field — the delegation trigger](#1-the-description-field)
2. [The `tools` field — granted, denied, or omitted](#2-the-tools-field)
3. [The `model` field — pinned vs inherited](#3-the-model-field)
4. [System-prompt structure — two archetypes](#4-system-prompt-structure)
5. [Output-format conventions](#5-output-format-conventions)
6. [The five traits best-in-class agents share](#6-the-five-traits)

---

## 1. The `description` field

This is the one field the router reads to decide delegation, so write it for the router. Three description *dialects* appear in the wild:

**(a) Capability + proactive trigger** (Anthropic, wshobson):
> "Expert code review specialist. Proactively reviews code for quality, security, and maintainability. **Use immediately after writing or modifying code.**"

**(b) "Use this agent when…" conditional** (VoltAgent) — spells out invocation conditions, never uses "PROACTIVELY":
> "Use this agent when you need to conduct comprehensive code reviews focusing on code quality, security vulnerabilities, and best practices."

**(c) Action-oriented, status-driven** (indie) — verb-first, names the state transition:
> "Convert an enhancement markdown into a structured PM spec; ask clarifying questions; set status READY_FOR_ARCH."

All three work. What fails is a description that lists the agent's résumé ("Elite expert specializing in…") and bolts "Use PROACTIVELY" on the end as an afterthought — it leans on a keyword instead of a genuine trigger condition. **Mediocre descriptions describe the agent; great ones describe the user's situation.**

Caveat carried over from operations: the proactive phrasing is documented but unreliable as an *auto*-trigger (see `operations.md` §2). Write the description well regardless — it still drives routing when delegation does fire, and it's what an `@-mention`-ing user scans to pick the agent.

## 2. The `tools` field

Three strategies, and they diverge meaningfully:

- **Explicit read-only allowlist** (Anthropic code-reviewer): `tools: Read, Grep, Glob, Bash` — no Edit/Write. Anthropic frames this as the whole point: *"a focused subagent with limited tool access (no Edit or Write)."*
- **Allowlist that adds `Edit` because the job mutates** (Anthropic debugger): `tools: Read, Edit, Bash, Grep, Glob`. *"Unlike the code reviewer, this one includes Edit because fixing bugs requires modifying code."*
- **Omitted entirely → inherits everything.** Every wshobson agent surveyed omits `tools`, so a "read-only-sounding" reviewer can in fact Write and Edit. This is the laxest pattern and the most common review-time finding.

Also available:
- **Denylist:** `disallowedTools: Write, Edit` keeps Bash + MCP but blocks file mutation. Precedence: `disallowedTools` is applied *first*, then `tools` resolves against what remains; a tool in both is removed.
- **Restrict spawnable agents** (main-thread agents only): `tools: Agent(worker, researcher), Read, Bash` allowlists which subagent types may be spawned.

**Review rule:** the clearest tell of a weak definition is an audit/review/research agent that omits `tools` (silent full inheritance) or grants `Write`/`Edit` it never needs. Match the grant to the verb in the description.

## 3. The `model` field

Observed pattern across the corpus:

| Job shape | Typical `model` | Why |
|---|---|---|
| Deep / high-stakes analysis (review, security audit, architecture) | `opus` | Reasoning quality matters most |
| Procedural workhorse (debug, test-gen, refactor) | `sonnet` | Balance of capability and speed |
| Cheap, high-volume reads (search, doc summarization) | `haiku` | Fast and low-cost; weak on multi-step reasoning |
| Thin specialist that should track the caller | `inherit` (default) | Matches whatever model the caller runs |

Anthropic's data-scientist example pins `model: sonnet` "for more capable analysis"; the built-in Explore agent pins Haiku for fast read-only search. Resolution order and per-model tradeoffs are in `operations.md` §1.

## 4. System-prompt structure

Two clearly separable archetypes.

### Archetype A — terse operational checklist (~25–40 lines)
Anthropic's examples and wshobson's terse debugger share an identical skeleton:
1. **One-line role** — "You are a senior code reviewer ensuring high standards of code quality and security."
2. **`When invoked:` numbered workflow** (3–5 steps) — "1. Run git diff to see recent changes  2. Focus on modified files  3. Begin review immediately"
3. **A domain checklist** (bulleted)
4. **An output-format block** — "Provide feedback organized by priority:"
5. **A one-line closing constraint** — "Focus on fixing the underlying issue, not the symptoms."

This is scannable, cheap on context, and the recommended default for most agents.

### Archetype B — encyclopedic persona (200–300+ lines)
Heavyweight template: `## Expert Purpose` → `## Capabilities` (8–10 sub-sections) → `## Behavioral Traits` → `## Knowledge Base` → `## Response Approach` (numbered) → `## Example Interactions`.

The high-value section is **`## Behavioral Traits`** — it encodes *how* the agent acts, not just what it checks:
> "Never trusts user input and validates everything at multiple layers"
> "Maintains a constructive and educational tone in all feedback"

The `## Capabilities` taxonomy is mostly keyword bait that signals breadth but rarely changes behavior — it's context paid for on every run. Prefer Archetype A unless the domain genuinely needs the persona depth; when you do use B, make sure the Behavioral Traits block is doing real work.

## 5. Output-format conventions

Good agents prescribe the shape of the return. Recurring conventions:

- **Severity-tiered findings** (dominant): "Critical issues (must fix) / Warnings (should fix) / Suggestions (consider improving)." VoltAgent's auditor uses a 4-tier Critical/High/Medium/Low scale.
- **Fixed per-issue template:** Anthropic's debugger mandates five fields for every issue — *Root cause → Evidence → Specific fix → Testing approach → Prevention*.
- **Dedicated `## Output Format` section** (cleanest): separates *what to do* from *what to return*, e.g. wshobson's test-automator organizing tests by type.
- **Quantified summary / delivery notification** (VoltAgent): a closing status line + JSON progress object. Double-edged — it models a crisp summary but invented example numbers ("47 files, 89%") risk the agent fabricating metrics. Use it as a *format* template, not a content one.

## 6. The five traits

Best-in-class definitions converge on these:

1. **A description that states *when*, not just *what*** — written for the router, packed with the caller's trigger nouns.
2. **Tool grants that match the verb** — reviewer read-only; fixer/tester gets Edit. The grant is a deliberate boundary, not a default.
3. **A `When invoked:` numbered workflow** — forces a deterministic, grounded start.
4. **A prescribed output contract** — severity tiers, a fixed per-issue template, or an `## Output Format` section, so every run returns the same shape.
5. **A closing constraint that resolves ambiguity** — one line telling the agent what to optimize when torn ("fix the underlying issue, not the symptoms").
