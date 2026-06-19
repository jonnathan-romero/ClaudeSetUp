# Multi-turn & memory

Single-turn rules don't carry across long conversations. Persona drifts ~20–40% over 10–15 turns, the system prompt loses attention as history grows, and adversaries can incrementally walk the model off-task. Multi-turn prompts treat persistence as a first-class concern.

## Contents

- [Memory Block — carry forward prior session decisions](#memory-block--carry-forward-prior-session-decisions)
- [Re-anchor cadence](#re-anchor-cadence)
- [Rolling state summary](#rolling-state-summary)
- [Plan-and-solve with progress log (long-running agents)](#plan-and-solve-with-progress-log-long-running-agents)
- [Compaction-aware prompts](#compaction-aware-prompts)
- [Sub-agent / fork handoff](#sub-agent--fork-handoff)
- [Closing / handoff turn](#closing--handoff-turn)
- [Multi-turn jailbreak resistance](#multi-turn-jailbreak-resistance)
- [Selection rule](#selection-rule)

## Memory Block — carry forward prior session decisions

When the user's request references prior work, decisions, or session history, prepend a Memory Block to the prompt. Place it in the **first 30%** of the prompt so it survives attention decay.

```
## Context (carry forward)
- Stack and tool decisions established: [...]
- Architecture choices locked: [...]
- Constraints from prior turns: [...]
- What was tried and failed: [...]
```

Trigger phrases that should make you generate a Memory Block:
- "continue where we left off"
- "now add the other thing we discussed"
- "use the same stack"
- "keep going from yesterday"

When in doubt, ask the user to fill it in: "I'll add a Memory Block — list the decisions you want carried forward."

## Re-anchor cadence

Critical constraints (format rules, persona, refusal lines) drift after ~5–10 turns. Re-anchor by:

- Repeating the 3–5 most load-bearing constraints every 3–5 user turns.
- Either re-injecting the system rules or prepending them to the user message.
- XML tags work as cheap anchors: `<rules>...</rules>` reappearing in turn N reminds the model.

Don't re-state everything every turn — just what would degrade.

## Rolling state summary

For stateful tasks (game, tutorial, debugging session) where the model needs to know "where we are":

```
<state>
Phase: 3 of 5
Decided: stack=React+Vite+Tailwind, hosting=Vercel.
Currently working on: auth flow.
Open questions: token storage location.
</state>

[user's actual turn]
```

Update client-side after each turn. Cheap, survives compaction (it's in the user message), no tool calls.

## Plan-and-solve with progress log (long-running agents)

For multi-turn agentic work (>20 turns or hours of execution):

- An *initializer* turn produces `plan.md` + `progress.md` (memory tool or filesystem).
- Every working turn: read progress → do one step → update progress → mark step done **only after end-to-end verification**.
- Treat each turn as "engineers working in shifts, each new engineer arrives with no memory of the previous shift" (Anthropic's framing for the memory tool).

Template for the initializer:

```
You're starting a long-running agent task. Your context window may reset.

Step 1: Read or create `plan.md`. If absent, write a numbered plan based on the user's goal below.
Step 2: Read or create `progress.md`. If absent, initialize with all plan steps as TODO.
Step 3: Pick the next undone step. Do it. Verify it works end-to-end.
Step 4: Update `progress.md` with what you did + verification + next intended action. Mark complete only after verification.
Step 5: If a step fails twice, write the error to `progress.md` and stop for human review.

Goal: [user's actual goal]
```

## Compaction-aware prompts

When chats are expected to exceed the context window or run for days:

- Put **durable rules** in `CLAUDE.md` or system prompt — these survive compaction. **Conversation content does not.**
- Pass custom `instructions` to compaction (Anthropic API beta `compact_20260112`) that name what your domain *cannot* lose: file paths, decisions, error states.
- Default summarization is generic ("write down anything that would be helpful") — be specific:

```
instructions: |
  Preserve verbatim:
  - All file paths mentioned in tool calls
  - All architecture decisions ("we chose X because Y")
  - All open errors not yet resolved
  - Variable names and function signatures introduced
  Drop:
  - Step-by-step tool call traces (the outcomes are enough)
  - Re-stated system rules (they live in the system prompt)
  - Pleasantries
```

## Sub-agent / fork handoff

For sub-tasks that don't need conversation continuity (read-heavy exploration, parallelizable work, fresh-eyes review):

- Parent writes the brief to a file (`docs/brief.md`) or passes it inline.
- Subagent operates with clean context, returns a structured summary (≤2K tokens).
- Coordinator re-reads only the summary, not the subagent's full trace.

Trigger phrases that should suggest a sub-agent:
- "go read all the X files and tell me about Y"
- "explore the codebase and find Z"
- "review this PR" (review benefits from fresh eyes — see Cognition's Devin Review pattern)

In Claude Code, this is `context: fork` + `agent: <name>` in the skill frontmatter, or directly invoking a subagent from `.claude/agents/`.

## Closing / handoff turn

At the end of a session (just before context exhaustion or before handing to a new conversation):

```
Before we close, produce a handoff brief in this format:

## Decisions made
- [...]

## Files / paths touched
- [...]

## Open questions
- [...]

## Next action with owner
- [...]
```

Save to memory or paste at the top of the next conversation. This pattern lets multi-day work survive context resets.

## Multi-turn jailbreak resistance

Recent research (arXiv 2508.07646): multi-turn jailbreaks are approximately *equivalent to resampling single-turn attacks*. The right defense is base-model refusal robustness, not conversation-shape engineering.

Where conversation shape *does* matter:
- **Many-shot jailbreaks** (256+ fake dialogues in one prompt) genuinely exploit in-context learning at long context. If you allow users to paste arbitrary chat history, sanitize.
- **Gradual goal hijack** (slowly walking the model from "X is fine" to "do X" over many turns): re-anchoring critical refusal rules every 3–5 turns mitigates.

## Selection rule

Pick the lightest mechanism that survives the conversation length you actually expect:

```
prompt history (default) < scratchpad < rolling summary < compaction < memory tool < new conversation with handoff
```

| Conversation size | Use |
|---|---|
| < 10K tokens | nothing — system prompt holds |
| 10K – 150K | rolling summary or compaction |
| > 150K, single session | memory tool |
| Cross-session | memory tool + handoff brief |
| Cross-corpus recall | vector store + RAG (different problem) |

Match the mechanism to the actual problem. Adding memory tooling when you only have 20 turns is over-engineering.
