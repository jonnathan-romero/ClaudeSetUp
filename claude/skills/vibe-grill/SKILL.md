---
name: vibe-grill
description: Socratic plan-interview with persistent doc side-effects — stress-tests a design or feature plan against the project's `CONTEXT.md` glossary and existing ADRs, then updates those docs inline as terms resolve and offers ADRs when decisions are hard to reverse. ALWAYS trigger when the user has a concrete plan or design to grill against an existing codebase's domain model, mentions walking down a design tree, says "grill my plan", "stress-test this proposal", "challenge this design against the docs", or wants to evolve `CONTEXT.md` / ADRs through dialogue. Do NOT use for open-ended pressure-testing without a plan — that's `grill-me`. Do NOT use to extract a fuzzy idea into a concrete plan — that's `process-interviewer`.
---

# vibe-grill

A Socratic plan-interview that pressure-tests a concrete plan against the project's existing domain language and architectural decisions, **and leaves durable artifacts behind** — `CONTEXT.md` updates and ADRs — as the conversation crystallises decisions.

The skill's job is to turn a vague-but-promising plan into one that uses the right vocabulary, doesn't contradict prior decisions, and deposits its learnings back into the repo's documentation as a side-effect.

## What to do

Interview the user relentlessly about every aspect of their plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead of asking the user.

## Process

### 1. Read the project's setup

Before grilling, learn how this repo is configured:

- **`docs/agents/domain.md`** if it exists — it codifies how consumer skills should read `CONTEXT.md` and ADRs (vocabulary discipline, ADR-conflict flagging). The same guidance applies to you as a producer when proposing new terms.
- **`CONTEXT.md`** at the repo root, or **`CONTEXT-MAP.md`** if multi-context (read each `CONTEXT.md` relevant to the topic at hand).
- **`docs/adr/`** — read ADRs that touch the area being discussed. In multi-context repos, also check `src/<context>/docs/adr/`.

If any of these files don't exist, proceed silently — they'll be created lazily when needed (see below).

### 2. Walk the design tree

Decompose the plan into discrete decisions. Resolve dependencies between them one at a time. For every question, propose your recommended answer up front so the user can correct it cheaply.

Prefer exploring the codebase over asking the user. If a fact can be verified by reading the code (a function's behavior, a schema's shape, an existing call site), check rather than ask.

### 3. Apply four moves during the session

#### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately:

> Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?

#### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term:

> You're saying 'account' — do you mean the **Customer** or the **User**? Those are different things.

#### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent edge cases that probe the boundaries between concepts:

> What if a Customer places two Orders, the first is partially fulfilled, and they cancel before the second ships?

#### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it:

> You said partial cancellation is possible, but the code at `src/orders/cancel.py` only cancels entire Orders — which is right?

### 4. Update `CONTEXT.md` inline

When a term resolves during the conversation, update `CONTEXT.md` *right then* — don't batch. The whole point is durable artifacts; batched updates tend to be forgotten.

Format spec: [references/CONTEXT-FORMAT.md](references/CONTEXT-FORMAT.md).

Don't couple `CONTEXT.md` to implementation details. Only include terms meaningful to a domain expert; general programming concepts (timeouts, retry behavior, utility patterns) don't belong even if the project uses them heavily.

If `CONTEXT.md` doesn't exist yet, create it the moment the first term is resolved.

### 5. Offer ADRs sparingly

Only offer to write an ADR when **all three** are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip it. ADRs are scarce by design.

Format spec: [references/ADR-FORMAT.md](references/ADR-FORMAT.md).

If `docs/adr/` doesn't exist yet, create it the moment the first ADR is needed.

## File structure (single vs multi-context)

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                 ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

When multiple contexts exist, infer which one the current topic relates to. If unclear, ask.
