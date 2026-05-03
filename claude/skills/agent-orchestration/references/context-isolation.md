# Context Isolation: The Other Reason to Spawn

Sub-agents are not just a parallelism tool. They are a context-management tool. A single serial sub-agent, used purely to absorb noisy exploration, is often the right call — and is the case future-Claude most often misses.

The trigger is not "can I run things in parallel?" but "will doing this in the parent pollute its context?" When in doubt, spawn.

## Contents

- [The unifying frame: a separate axis from parallelism](#the-unifying-frame-a-separate-axis-from-parallelism)
- [Academic evidence for long-context degradation](#academic-evidence-for-long-context-degradation)
  - [Lost-in-the-Middle — positional degradation](#lost-in-the-middle--positional-degradation)
  - [RULER — claimed vs. effective context length](#ruler--claimed-vs-effective-context-length)
  - [NoLiMa — degradation under non-literal retrieval](#nolima--degradation-under-non-literal-retrieval)
  - [Context rot and the attention budget — Anthropic's framing](#context-rot-and-the-attention-budget--anthropics-framing)
- [Anthropic's stated rationale](#anthropics-stated-rationale)
  - [Claude Code sub-agents docs](#claude-code-sub-agents-docs)
  - [Agent SDK sub-agents docs](#agent-sdk-sub-agents-docs)
  - [Effective context engineering for AI agents](#effective-context-engineering-for-ai-agents)
  - [Position in the broader context-engineering toolkit](#position-in-the-broader-context-engineering-toolkit)
  - [Multi-agent research system](#multi-agent-research-system)
- [Quantitative spawn triggers](#quantitative-spawn-triggers)
- [Qualitative spawn triggers](#qualitative-spawn-triggers)
- [Context-state triggers](#context-state-triggers)
- [Anti-triggers: when not to spawn](#anti-triggers-when-not-to-spawn)
- [Concrete examples: spawn vs do-not-spawn](#concrete-examples-spawn-vs-do-not-spawn)
- [Cost dimensions of context](#cost-dimensions-of-context)
- [Summarization-loss tradeoffs](#summarization-loss-tradeoffs)
- [Mitigations: shaping the sub-agent contract](#mitigations-shaping-the-sub-agent-contract)
- [The file-handoff escape hatch](#the-file-handoff-escape-hatch)
- [Reading sub-agent reports as the parent](#reading-sub-agent-reports-as-the-parent)
- [Common failure modes](#common-failure-modes)
- [Estimating spawn cost vs pollution cost](#estimating-spawn-cost-vs-pollution-cost)
- [Pre-spawn checklist](#pre-spawn-checklist)
- [Default rule when uncertain](#default-rule-when-uncertain)
- [Sources](#sources)

## The unifying frame: a separate axis from parallelism

Most multi-agent literature leads with parallelism — the BrowseComp gains, the wall-clock reductions from concurrent sub-agents. That framing dominates the discourse and crowds out the second axis. Treat the two as orthogonal:

| Axis | Question it answers | Win condition |
|---|---|---|
| **Parallelism** | Can multiple sub-agents work *concurrently*? | Wall-clock latency, breadth coverage |
| **Context isolation** | Can a sub-agent's exploration be *quarantined* from the parent? | Parent context cleanliness, attention quality, downstream reasoning |

A serial single sub-agent gets you isolation without parallelism, and that is frequently the right call. The framing "use multiple sub-agents for parallel work" doesn't fire on serial tasks, so future-Claude under-spawns. Bias the other direction: spawn when in doubt.

A **context firewall** is a sub-agent whose job is to absorb noisy, exploratory work and return only a distilled answer. The parent's context window only ever sees:

- The original task description.
- The sub-agent's final summary (typically 1,000–2,000 tokens).

It does *not* see: the 50 files the sub-agent read, the 20 grep results it scanned, the 5 hypotheses it tested and rejected, the raw stdout of the test runner, the entire 4,000-line config it parsed, or the failed tool calls along the way. All of that lives and dies inside the sub-agent's own context window.

The architectural mechanism is hard isolation. From the [Claude Code sub-agents docs](https://code.claude.com/docs/en/sub-agents): "The subagent does not receive the parent's conversation history or tool results." The only channel from parent to subagent is the Agent tool's prompt string; the only return channel is the sub-agent's final message.

Even Claude Code's `/fork` feature — which deliberately inherits the *whole* parent conversation — preserves the *output* isolation property: "The fork's own tool calls still stay out of your conversation and only its final result comes back, so your main context window stays clean." Even forks honor it. The principle is that pervasive.

The asymmetric framing matters. Parallelism is a *latency* optimization; you only do it when wall-clock time is binding. Context isolation is a *quality* optimization; you do it whenever quality of the parent's reasoning is at stake — which, on a long-running session, is essentially always. Future-Claude that only reaches for sub-agents under the parallelism frame will systematically miss the isolation case, which is the more common one.

## Academic evidence for long-context degradation

Four converging lines of evidence say the same thing: as a context window fills, the model's effective use of that context degrades nonlinearly. This is the why behind the firewall.

### Lost-in-the-Middle — positional degradation

Liu et al., [*Lost in the Middle: How Language Models Use Long Contexts*](https://arxiv.org/abs/2307.03172) (TACL 2024, arXiv:2307.03172):

> "Performance is often highest when relevant information occurs at the beginning or end of the input context, and significantly degrades when models must access relevant information in the middle of long contexts, even for explicitly long-context models."

Implication: as a parent agent's context grows, load-bearing facts — decisions, requirements, the user's actual ask — get buried mid-context and become harder to attend to. Spawning a sub-agent keeps those facts near the front of the parent's window where they remain retrievable.

This is not just a quirk of small models. Liu et al. tested explicitly long-context models and found the U-shaped curve persists. The implication for a long-running Claude Code session: every accumulated tool result pushes the user's original ask further into the middle of the window, where the model attends to it less, even though it remains technically visible.

### RULER — claimed vs. effective context length

Hsieh et al., [*RULER: What's the Real Context Size of Your Long-Context Language Models?*](https://arxiv.org/abs/2404.06654) (COLM 2024, arXiv:2404.06654):

> "While these models all claim context sizes of 32K tokens or greater, only half of them can maintain satisfactory performance at the length of 32K."

Implication: a model's *advertised* context window is not its *effective* context window. Long-horizon agents that fill their windows are operating in the degraded regime by definition.

RULER goes beyond simple needle-in-a-haystack tests by requiring multi-step retrieval, multi-hop reasoning, and aggregation across long contexts — closer to what an agent actually does. The benchmark measures the gap between marketed length and useful length, and the gap is large. Treat your effective working window as a meaningful fraction of the marketed one, not the whole thing, and treat sub-agent isolation as the lever that gives you back the rest.

### NoLiMa — degradation under non-literal retrieval

Modarressi et al., [*NoLiMa: Long-Context Evaluation Beyond Literal Matching*](https://arxiv.org/abs/2502.05167) (ICML 2025, arXiv:2502.05167):

> "At 32K tokens, 11 models drop below 50% of their strong short-length baselines. Even GPT-4o... experiences a reduction from an almost-perfect baseline of 99.3% to 69.7%."

Implication: the everyday case for an agent — synthesizing scattered semantic clues with no literal lexical match — degrades much faster than benchmarks suggest. Real agentic reasoning lives in the regime NoLiMa measures, not the regime needle-in-a-haystack measures.

NoLiMa is the most damning of the three benchmarks for the agent use case. Vanilla needle-in-a-haystack lets the model exploit literal lexical overlap between the query and the buried fact. Real agent work — "given these scattered clues across this codebase, what is the auth flow?" — has no such shortcut. The model must do latent retrieval. NoLiMa shows that even frontier models lose ~30 percentage points at 32K tokens when the literal-match shortcut is removed. That degradation is the regime your parent agent is in once its context is full.

All three benchmarks point the same direction: the model's effective working window is smaller than its marketed one, and the gap widens as the task moves away from literal lookup toward agent-style synthesis. Each new tool result the parent absorbs eats into a budget that is smaller than it looks.

### Context rot and the attention budget — Anthropic's framing

Anthropic, [*Effective context engineering for AI agents*](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) (Sep 29, 2025):

> "Studies on needle-in-a-haystack style benchmarking have uncovered the concept of context rot: as the number of tokens in the context window increases, the model's ability to accurately recall information from that context decreases... Context, therefore, must be treated as a finite resource with diminishing marginal returns."

> "LLMs have an 'attention budget' that they draw on when parsing large volumes of context. Every new token introduced depletes this budget by some amount... This results in n² pairwise relationships for n tokens. As context length increases, a model's ability to capture these pairwise relationships gets stretched thin, creating a natural tension between context size and attention focus."

> "Models develop their attention patterns from training data distributions where shorter sequences are typically more common than longer ones. This means models have less experience with, and fewer specialized parameters for, context-wide dependencies."

Three cost dimensions track context length: dollars, latency (time-to-first-token grows with context), and quality. The third is the one most often underweighted, and the one this entire skill is about.

The n² framing is worth holding on to. Every new tool result block multiplies the number of pairwise relationships the model is asked to maintain. A parent that has read 30 files isn't paying linear attention cost; it's paying quadratic-ish attention cost on every subsequent reasoning step. A sub-agent that absorbs those 30 reads and returns a one-paragraph summary has effectively converted quadratic cost into linear cost for the parent.

## Anthropic's stated rationale

Three official sources articulate Anthropic's reason for sub-agents. Each frames context isolation, not parallelism, as the lead benefit.

### Claude Code sub-agents docs

From the [sub-agents docs](https://code.claude.com/docs/en/sub-agents):

> "Subagents are specialized AI assistants that handle specific types of tasks. Use one when a side task would flood your main conversation with search results, logs, or file contents you won't reference again: the subagent does that work in its own context and returns only the summary."

The benefits list leads with:

> "Subagents help you: Preserve context by keeping exploration and implementation out of your main conversation."

The built-in **Explore** agent is described as:

> "A fast, read-only agent optimized for searching and analyzing codebases... Claude delegates to Explore when it needs to search or understand a codebase without making changes. This keeps exploration results out of your main conversation context."

In the "Common patterns" section under "Isolate high-volume operations":

> "One of the most effective uses for subagents is isolating operations that produce large amounts of output. Running tests, fetching documentation, or processing log files can consume significant context. By delegating these to a subagent, the verbose output stays in the subagent's context while only the relevant summary returns to your main conversation."

### Agent SDK sub-agents docs

From the [Agent SDK sub-agents docs](https://code.claude.com/docs/en/agent-sdk/subagents), where "Context isolation" is listed as the first benefit:

> "Context isolation — Each subagent runs in its own fresh conversation. Intermediate tool calls and results stay inside the subagent; only its final message returns to the parent... a `research-assistant` subagent can explore dozens of files without any of that content accumulating in the main conversation. The parent receives a concise summary, not every file the subagent read."

### Effective context engineering for AI agents

The canonical articulation, from [the Sep 29, 2025 post](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). It lists three context-engineering techniques for long-horizon work — compaction, structured note-taking, and **sub-agent architectures** — and describes the third as:

> "Sub-agent architectures provide another way around context limitations. Rather than one agent attempting to maintain state across an entire project, specialized sub-agents can handle focused tasks with clean context windows. The main agent coordinates with a high-level plan while subagents perform deep technical work or use tools to find relevant information. Each subagent might explore extensively, using tens of thousands of tokens or more, but returns only a condensed, distilled summary of its work (often 1,000-2,000 tokens). This approach achieves a clear separation of concerns — the detailed search context remains isolated within sub-agents, while the lead agent focuses on synthesizing and analyzing the results."

Two numbers to internalize: tens of thousands of internal tokens, 1,000–2,000 returned. That is a 10–50× compression target, and it is the implicit budget for any spawn-for-isolation decision.

### Position in the broader context-engineering toolkit

The Anthropic context-engineering post lists three techniques for managing long-horizon context. Sub-agent architectures are one of the three; understanding the alternatives clarifies when to reach for which.

- **Compaction.** Summarize the existing conversation into a smaller form. Lossy by definition. Best for keeping a single agent going past its window. Risk: "overly aggressive compaction can result in the loss of subtle but critical context whose importance only becomes apparent later."
- **Structured note-taking.** Externalize key state (plan, decisions, constraints) into files the agent re-reads on demand. Lossless if the notes are good. Best for protecting load-bearing facts across long horizons. Risk: stale notes drift from reality.
- **Sub-agent architectures.** Quarantine exploratory work in a fresh-context sub-agent; receive only a distilled summary. Lossy on the sub-agent's intermediate steps, lossless on what the parent already had. Best for isolating noisy explorations from the parent.

These compose. The Anthropic multi-agent research post describes the LeadResearcher using all three: spawning sub-agents for parallel exploration (sub-agent architecture), saving its plan to memory (note-taking), and presumably compacting older conversation as the session grows. For most Claude Code work, sub-agent architectures are the most under-used of the three relative to their value.

### Multi-agent research system

From [*How we built our multi-agent research system*](https://www.anthropic.com/engineering/built-multi-agent-research-system) (Jun 13, 2025):

> "The essence of search is compression: distilling insights from a vast corpus. Subagents facilitate compression by operating in parallel with their own context windows, exploring different aspects of the question simultaneously before condensing the most important tokens for the lead research agent. Each subagent also provides separation of concerns — distinct tools, prompts, and exploration trajectories — which reduces path dependency."

And from the long-horizon conversation management appendix:

> "When context limits approach, agents can spawn fresh subagents with clean contexts while maintaining continuity through careful handoffs. Further, they can retrieve stored context like the research plan from their memory rather than losing previous work when reaching the context limit."

The post also describes Anthropic's internal mechanism: the LeadResearcher saves its plan to Memory because "if the context window exceeds 200,000 tokens it will be truncated and it is important to retain the plan."

## Quantitative spawn triggers

Run these checks before any exploratory tool chain. If any one fires, spawn.

- **10× rule.** Will the exploration likely produce ≥10× more tokens than the answer needs? Spawn. This matches Anthropic's "tens of thousands of tokens... returns only 1,000–2,000 tokens" compression target. The rule is calibrated against Anthropic's stated number, not an invented one — when the post says sub-agents condense from "tens of thousands" down to "1,000–2,000," that *is* a 10–50× ratio. If your expected ratio is below 10×, the firewall isn't worth its overhead; if it's above, it almost always is.
- **File-count rule.** Will I likely Read ≥3 files I won't reference again? Spawn. Each file the parent reads adds its full text to the conversation history forever, even if only one line mattered. Three throwaway reads is the empirical inflection point where the parent's window starts visibly degrading.
- **Tool-count rule.** Will I likely make ≥5 exploratory tool calls (greps, reads, bashes) for a single sub-question? Spawn. Tool result blocks are large — a single grep can return hundreds of lines, a single bash invocation can dump test output, log lines, or stack traces. Five such blocks for one logical question is enough pollution to justify a sub-agent.
- **Output-size rule.** Is the input I need to read ≥1,000 lines or ≥30K tokens? Spawn. Reading a 30K-token file into the parent costs 30K tokens of attention budget for the rest of the session. Reading it into a sub-agent costs 30K tokens for the duration of one sub-agent invocation, then those tokens are gone.

## Qualitative spawn triggers

- **Unknown-depth rule.** Do I not yet know how deep this investigation goes? Spawn. Unknown depth is the canonical case — you cannot bound the pollution in advance, and a parent that commits to an exploration without depth bounds will routinely overshoot. The sub-agent boundary acts as a structural depth limit: whatever it consumes stays inside.
- **Try-and-fail rule.** Am I going to try multiple approaches expecting some to fail? Spawn. Failed approaches are pure noise to the parent; they pollute its window and bias future reasoning toward the failure mode. Worse, failed-approach context invites the parent to repeat the failure later because the abandoned hypothesis remains in the attention surface.
- **Negative-result rule.** Is the likely outcome "no, X doesn't exist here" after extensive search? Spawn. Negative results from extensive search are especially polluting — the parent carries the entire search transcript for a one-bit answer. A sub-agent returns "X is not present in the codebase; I checked Y, Z, and W locations" in 100 tokens; the parent's alternative is carrying the full transcript of every grep that returned empty.
- **Verbose-tool rule.** Am I about to invoke a tool known to dump huge output (full test runs, web fetches of large pages, full log files)? Spawn. The Claude Code docs name this case explicitly. Test runners, log tails, web fetches of long documentation pages, database dumps, and raw API responses all qualify.
- **Multiple-hypothesis rule.** Am I exploring three or four different theories about how something works, expecting only one to pan out? Spawn. The investigation itself is high-noise; only the conclusion is high-signal.
- **Unrelated-substack rule.** Is this sub-question conceptually orthogonal to the main task? Spawn. Conceptually orthogonal context is the most attention-distorting kind — the parent ends up weighing irrelevant signals when reasoning about the main task.

## Context-state triggers

These don't depend on the task — they depend on the parent's current state. When they fire, bias even more aggressively toward spawning.

- **Heavy-context rule.** Is the parent context already ≥50% full? Bias *strongly* toward spawning. Lost-in-the-middle and context-rot effects accelerate non-linearly past this point. The cost of polluting an already-heavy parent is much higher than the cost of polluting a fresh one — for the same amount of new noise, you push more existing tokens into the degraded mid-context zone.
- **Long-horizon rule.** Has this conversation already gone many turns and accumulated lots of tool results? Bias toward spawning. Each new tool result deepens the rot. Long-horizon agents that don't aggressively spawn end up in the regime RULER and NoLiMa describe — nominally functional, effectively impaired.
- **Load-bearing-decisions rule.** Has the parent context accumulated important decisions, plans, or constraints I need to keep accessible? Bias toward spawning to protect what's already there. The parent's working memory is the resource you're conserving. A 5K-token detour into exploration risks burying the architectural decision the user spent 20 turns making.
- **Approaching-truncation rule.** Is the conversation approaching the model's context limit (e.g., past 150K tokens on a 200K-window model)? Bias *very* strongly toward spawning, and consider writing key decisions to memory before context truncation. Anthropic's multi-agent post describes the LeadResearcher saving its plan to memory because "if the context window exceeds 200,000 tokens it will be truncated and it is important to retain the plan."

## Anti-triggers: when not to spawn

Context isolation has real cost. A sub-agent has:

- **Startup overhead.** Its own system prompt, tool definitions, CLAUDE.md, skills it needs preloaded. This can easily be 5–20K tokens before the agent does anything productive.
- **Latency.** Fresh prompt, no shared cache. (Fork mode is the exception; named subagents have separate caches per the Claude Code docs.)
- **Information loss risk.** The summary is lossy by design.
- **Re-discovery cost.** The sub-agent doesn't know what the parent already knows; it may re-read files the parent already read.

Skip isolation when:

- **The parent will need the raw context anyway.** If the next step after the search is "now edit those files," the parent needs file paths *and* their contents. A sub-agent that returns a summary forces the parent to re-read. The cleanest workaround is the file-handoff pattern (see below) — but if even that is overkill, just keep the work in the parent.
- **The question is small and answerable inline.** "Is there a `package.json` in the repo root?" — one Glob call. Spawning is pure overhead. The rule of thumb: if the entire investigation fits in one tool call and a one-line answer, do not spawn.
- **Known-location lookups.** "Read line 42 of `~/.claude/settings.json`." Just Read it. No exploration needed. Spawning here adds latency and startup cost for zero context-management benefit.
- **Sub-agent overhead exceeds savings.** For a question whose exploration would cost ~3K tokens in the parent, spawning a sub-agent (which incurs ~10K tokens of system prompt + tool defs + CLAUDE.md just to start) is a net loss. The sub-agent's startup cost is paid every time; only spawn when the saved pollution would cost more than the startup overhead.
- **The summary loses information the parent needs.** If you'll need to cite specific lines, quote verbatim text, or perform follow-up edits on the same files, the lossy summary will force re-work. (Or use the file-handoff mitigation below.)
- **Iterative tasks needing tight feedback loops.** The sub-agents docs are explicit: "Use the main conversation when: the task needs frequent back-and-forth or iterative refinement; multiple phases share significant context (planning → implementation → testing); you're making a quick, targeted change; latency matters." Tight loops require shared context to flow naturally; spawning fragments that flow.
- **The task is already in context.** If you just read a file and now need to ask a question about it, don't spawn — that throws away the work you already did. Per the docs: "For a quick question about something already in your conversation, use `/btw` instead of a subagent. It sees your full context but has no tool access."
- **Latency is the binding constraint.** If the user is waiting interactively and the question is small enough that the parent can answer it faster than a sub-agent can boot, just answer.

## Concrete examples: spawn vs do-not-spawn

### Spawn — context-isolation reasons

- **"Find all the places in this codebase that handle authentication."** Open-ended search, unknown depth, exploration produces many file reads. Spawn, even though serial. The parent gets back a structured list with `file:line` citations; it does not get back the contents of every auth-adjacent file.
- **"Diagnose why the test is failing."** Unknown investigation depth, will likely read multiple files and run multiple commands, may try wrong hypotheses first. Spawn. Even one failed approach (e.g., "I thought it was the database; it wasn't") wastes 5–20K tokens of parent context that the parent would otherwise carry forever.
- **"Read this 4,000-line config file and tell me where the timeout is set."** Huge input, tiny answer. Classic 1000:1 work-to-answer ratio. Spawn. The parent gets back: "timeout is set on line 1247: `connect_timeout=30s`."
- **"Audit this codebase for SQL injection risks."** Unknown breadth, possibly negative findings (which are even noisier). Spawn. Negative findings from a security audit are the worst case: extensive search, one-bit answer, lots of pollution if done in the parent.
- **"Summarize everything in this 80K-token API documentation that's relevant to authentication."** Pure compression task. Spawn. This is the canonical compression-axis case Anthropic describes in the multi-agent post.
- **"Run the test suite and tell me which tests fail and why."** Full test output is enormous; you only need the failure list. Spawn — the sub-agents docs use this exact example under "Isolate high-volume operations."
- **"Try three approaches to detecting the database schema (introspection, migration files, model definitions) and report which works."** Two of three will produce dead-end exploration. Spawn. Only the winning approach returns to the parent; the failed two are quarantined.
- **"What version of React does this project use, and where is it pinned?"** Looks like a one-line answer but discovery requires checking `package.json`, lockfile, possibly a monorepo structure. If you don't already know the layout — spawn.
- **"Find every TODO that mentions performance."** Unknown breadth, file scan, likely many false positives to filter. Spawn.

### Do not spawn — overhead exceeds savings

- **"Quickly check if `X` exists in `~/.claude/settings.json`."** One Read call. Do not spawn.
- **"What does this function I just looked at do?"** Already in context. Do not spawn — answer inline.
- **"Edit line 42 of `foo.py` to change `True` to `False`."** Targeted, known location. Do not spawn.
- **"Run `git status` and tell me if anything is staged."** One Bash call, tiny output. Do not spawn.
- **"Fix the failing test we just diagnosed together."** Parent already has the diagnosis context; the sub-agent would have to re-derive it. Do not spawn — the parent should make the fix.
- **"Add the import we just decided on to `main.py`."** Trivial edit, full context already in parent. Do not spawn.
- **"Walk me through the file you just opened, section by section."** The whole point is incremental discussion of context the parent already holds. Do not spawn.
- **"Refactor this function we've been editing together."** Iterative loop on shared context. Do not spawn.

## Cost dimensions of context

Anthropic's context-engineering post identifies three cost dimensions that scale with context length:

1. **Money.** Tokens cost dollars. A bloated parent context multiplies cost on every subsequent turn because the entire history is reprocessed.
2. **Latency.** Time-to-first-token grows with context length. A heavy parent feels sluggish; a fresh sub-agent feels snappy.
3. **Quality.** The one most often underweighted. Per the post: "context, therefore, must be treated as a finite resource with diminishing marginal returns."

Of these, quality is the load-bearing reason for context isolation. Money and latency you can pay; degraded reasoning you cannot easily recover from. A parent that has lost-in-the-middle'd the user's original ask cannot "try harder" to remember it — the attention pattern is what it is for the rest of the session.

## Summarization-loss tradeoffs

Sub-agent summaries are *necessarily* lossy — that's the entire point. Anthropic's [multi-agent research post](https://www.anthropic.com/engineering/built-multi-agent-research-system) warns directly:

> "The art of compaction lies in the selection of what to keep versus what to discard, as overly aggressive compaction can result in the loss of subtle but critical context whose importance only becomes apparent later."

And about the "game of telephone" risk in multi-stage handoffs:

> "Direct subagent outputs can bypass the main coordinator for certain types of results, improving both fidelity and performance... This prevents information loss during multi-stage processing."

Two failure modes to design against:

1. **Lossy compression of load-bearing detail.** The summary smooths over the file path, the line number, the exact value, the precise interface signature — exactly the things the parent will need next.
2. **Vague-prompt → vague-summary cascade.** The Anthropic post is explicit: "We started by allowing the lead agent to give simple, short instructions like 'research the semiconductor shortage,' but found these instructions often were vague enough that subagents misinterpreted the task."

Both are addressable by shaping the sub-agent's contract upfront.

A third, subtler failure mode: **premature consensus.** A sub-agent that converges too quickly on a hypothesis returns a confident summary that bakes in a wrong premise. The parent reads the summary, accepts the premise, and now both agents are wrong. Mitigations 1–6 below all push back on this by demanding citations, verbatim quotes, and explicit "open questions" sections — these force the sub-agent to externalize its reasoning rather than smooth over uncertainty.

## Mitigations: shaping the sub-agent contract

Build these into every sub-agent prompt. They're cheap to specify and dramatically reduce re-verification cost.

### Demand citations

For every claim, require `file:line` or `file:line-range`. Cheap to ask, and a citation that points back to the source costs ~10 tokens but saves the parent a re-read.

### Demand verbatim quotes for load-bearing claims

"Quote the exact code/config text for any value, signature, or interface you reference." A 50-token verbatim quote is dramatically cheaper than re-reading the file later, and it forecloses any summarization-induced ambiguity.

### Ask for a structured report, not prose

A schema like:

```
## Summary (2-3 sentences)
## Key findings (bulleted)
## File references (path:line for each)
## Verbatim excerpts (for any quoted text/code)
## Open questions / things I couldn't determine
```

forces the sub-agent to surface what it doesn't know rather than smoothing it over. The "open questions" section is the highest-leverage line — it converts unknown-unknowns into known-unknowns the parent can act on.

### Specify the question precisely

Vague prompts produce vague summaries. State the exact decision the parent needs to make and the exact form of the answer it needs back. Per the Anthropic multi-agent post: short, vague instructions get misinterpreted.

### Ask for the artifact path, not the artifact

For large outputs (long code, big tables, multi-file diffs), have the sub-agent write to a file and return the path. Per the multi-agent post's "Subagent output to a filesystem" appendix:

> "Subagents call tools to store their work in external systems, then pass lightweight references back to the coordinator. This prevents information loss during multi-stage processing and reduces token overhead from copying large outputs through conversation history."

This is the escape hatch when verbatim fidelity matters more than the parent's token budget can absorb.

### Bound the report length

Tell the sub-agent "Return ≤500 words" so it stays disciplined; otherwise it may dump tool outputs back to you and defeat the entire purpose. The Anthropic 1,000–2,000-token target is a reasonable upper bound; tighter is fine when the question is narrower.

### Specify negative-result format

If the answer might be "no, X doesn't exist," tell the sub-agent how to report that compactly. Otherwise it will dump everything it checked as evidence of thoroughness. A line like "If you find X is not present, return a one-paragraph negative report listing the locations you checked, not the contents of those locations" prevents the worst pollution-by-thoroughness pattern.

### Forbid pass-through dumps

Add an explicit prohibition: "Do not include raw tool output, file contents, or grep results in your report. Quote at most 5 lines verbatim per claim." Without this, a sub-agent that doesn't know what to summarize will hedge by including everything, which exactly defeats the firewall.

## The file-handoff escape hatch

When the parent will need raw context for a follow-up step, the file-handoff pattern preserves both isolation *and* fidelity. The sub-agent writes its findings — extracted snippets, structured tables, intermediate artifacts — to a file, then returns only the path and a one-paragraph summary. The parent reads the file on demand, so its context window holds the path token until needed, not the artifact's full contents.

This is the canonical workaround for the "I'll need the raw context anyway" anti-trigger. From the Anthropic multi-agent post:

> "Subagents call tools to store their work in external systems, then pass lightweight references back to the coordinator. This prevents information loss during multi-stage processing and reduces token overhead from copying large outputs through conversation history."

Use it when:

- The sub-agent's work product is large but the parent needs lossless access to specific parts (e.g., a refactored module, a generated test suite, a migration plan).
- A downstream sub-agent in a chain needs the previous one's full output, and you want to avoid telephone-game degradation.
- The artifact is structured (JSON, table, code) and the parent will query specific fields rather than the whole thing.

The pattern composes well with citations: the sub-agent returns "Report at `/tmp/auth-audit.md`; 7 issues found; highest severity is SQL injection in `users.py:142`." The parent has the headline, knows where to look for detail, and pays no token cost for the detail until it actually reads the file.

## Reading sub-agent reports as the parent

The firewall only works if the parent treats the sub-agent's report as the authoritative artifact and resists the temptation to "go look for itself." Three habits keep the firewall intact:

- **Trust the citations.** When the sub-agent says "auth flow lives in `src/auth/middleware.py:42-78`," cite that location in your own response without re-reading the file. Re-reading defeats the entire compression you just paid for.
- **Re-spawn for follow-ups, don't expand inline.** If the sub-agent's report raises a new question, spawn a fresh sub-agent for the follow-up (or extend the original sub-agent's scope) rather than chasing the question in the parent. Each inline chase undoes some of the original isolation.
- **Treat "open questions" as calls for another sub-agent, not for you.** When the sub-agent flags something it couldn't determine, the right next move is usually a targeted second spawn, not the parent grinding through the gap.

The pattern that breaks the firewall fastest: parent spawns sub-agent → sub-agent returns a clean summary → parent says "let me just verify that" → parent re-reads the same files the sub-agent already read. The verification cost the parent more tokens than skipping the sub-agent entirely.

## Common failure modes

Things that look like context isolation but aren't, ordered by frequency:

- **Pseudo-isolation: spawn-then-re-read.** Parent spawns a sub-agent, sub-agent returns a clean summary with citations, parent then reads every cited file "to confirm." Net result: parent context now contains both the sub-agent's full report *and* the cited files. Worse than not spawning. Fix: trust citations until something forces verification.
- **Token-cost ignored: spawn for trivia.** Parent spawns a sub-agent for a one-line lookup. The sub-agent's startup cost (system prompt + tool defs + skills + CLAUDE.md) dwarfs the lookup cost. Net result: more tokens, more latency, no isolation benefit because there was nothing to isolate. Fix: respect the anti-triggers.
- **Vague-prompt → vague-summary cascade.** Parent spawns a sub-agent with a one-line prompt; sub-agent returns a generic summary; parent re-spawns or asks follow-ups; second sub-agent has to re-discover what the first one half-discovered. Fix: invest in the sub-agent prompt; specify the exact decision and answer format.
- **Telephone game in chains.** Sub-agent A's summary feeds sub-agent B's prompt; B's summary feeds C's; by C, load-bearing detail is gone. Per the multi-agent post: "Direct subagent outputs can bypass the main coordinator for certain types of results, improving both fidelity and performance." Fix: file-handoff for chained work, or have B and C re-derive from source rather than depend on A's distillation.
- **Negative-result dump.** Parent asks "does X exist?"; sub-agent searches extensively and finds no; sub-agent returns a 5,000-token report listing everything it checked. Defeats the purpose. Fix: specify negative-result format up front.
- **Partial spawn: too narrow a scope.** Parent spawns a sub-agent for one specific lookup, then spawns a second for a related lookup, then a third — each paying startup cost. If three lookups are part of one conceptual investigation, spawn one sub-agent with the full investigation as its scope.

## Estimating spawn cost vs pollution cost

Quick mental arithmetic before any borderline spawn decision:

- **Spawn cost** ≈ (sub-agent system prompt + tool definitions + relevant CLAUDE.md + relevant skills) + (sub-agent's exploration tokens) + (returned summary). The first bucket — startup overhead — is paid once per spawn and typically lands in the 5–20K-token range. The exploration is ephemeral; it does not enter the parent.
- **Pollution cost** ≈ (every token the parent consumes during the same exploration) × (multiplier for degraded reasoning over the rest of the session). The multiplier is the part the napkin math gets wrong — context rot is real but hard to price. Treat it as ≥1.5× when the parent is past 50% full, ≥2× past 75%.
- **Comparison.** Spawn when (pollution cost) > (spawn cost). When the parent is fresh and the exploration is small, do not spawn. When the parent is heavy or the exploration is large, spawn. The middle band is where the qualitative triggers (unknown depth, try-and-fail, negative result) tip the decision.

The hidden term is the cost of *future* parent reasoning over a polluted window, which compounds over the rest of the session. That is what makes the asymmetry favor spawning when in doubt: an unnecessary spawn costs you one round-trip and is over; an unnecessary pollution costs you every subsequent turn.

## Pre-spawn checklist

Walk this checklist before any non-trivial exploratory step. The bias is intentional: every "yes" is a vote to spawn, no "yes" required to spawn anyway when the parent context is heavy.

1. **Will exploration produce ≥10× more tokens than the answer?** If yes → spawn.
2. **Will I read ≥3 files I won't need again?** If yes → spawn.
3. **Will I make ≥5 exploratory tool calls?** If yes → spawn.
4. **Is the input ≥1,000 lines or ≥30K tokens?** If yes → spawn.
5. **Do I know the depth of this investigation?** If no → spawn.
6. **Will I try multiple approaches expecting some to fail?** If yes → spawn.
7. **Is the likely outcome a negative result after extensive search?** If yes → spawn.
8. **Is the parent context already ≥50% full?** If yes → spawn even on lower-cost questions.
9. **Are there load-bearing decisions in the parent context I want to protect?** If yes → bias toward spawning.
10. **Do I genuinely need the raw context for the next step?** If yes → keep in parent, *or* use file-handoff.
11. **Is this a one-line lookup at a known location?** If yes → just do it inline.
12. **Is the answer already in my current context?** If yes → answer inline (`/btw` if appropriate).

## Default rule when uncertain

If exploration is open-ended and the parent context is already non-trivial, spawn. The cost of an unnecessary sub-agent is one extra round-trip; the cost of polluting a long-running parent context is degraded reasoning for the rest of the session. The asymmetry favors spawning.

A reframed version of the same rule, for the gut check before any exploratory tool chain: imagine the parent's context window five turns from now, after this exploration. If it's full of grep results, file dumps, and dead-end tool calls you'll never reference again, spawn now. If it's full of decisions, code being edited, and active reasoning the parent will keep using, keep the work in the parent.

Restate the unifying message: sub-agents are a context-management tool first and a parallelism tool second. Treat the parent's context as a precious, lossy resource with diminishing-returns capacity, and spawn sub-agents to keep that resource clean for the load-bearing reasoning the parent actually has to do. The trigger is not "can I parallelize?" but "will this work pollute my context?" — and the answer is yes more often than future-Claude defaults to.

## Sources

- Anthropic, [*Effective context engineering for AI agents*](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), Sep 29, 2025 — *the* primary source for the context-firewall framing; explicitly names compaction, structured note-taking, and sub-agent architectures as long-horizon context-management techniques.
- Anthropic, [*How we built our multi-agent research system*](https://www.anthropic.com/engineering/built-multi-agent-research-system), Jun 13, 2025 — frames sub-agents as compression, with the appendix on long-horizon conversation management and filesystem hand-off pattern.
- Anthropic, [Claude Code sub-agents docs](https://code.claude.com/docs/en/sub-agents) — current canonical docs; "Preserve context" is the lead benefit; "Isolate high-volume operations" pattern.
- Anthropic, [Agent SDK sub-agents docs](https://code.claude.com/docs/en/agent-sdk/subagents) — "Context isolation" listed as the first benefit; states what subagents do/don't inherit.
- Liu, N. F., et al., [*Lost in the Middle: How Language Models Use Long Contexts*](https://arxiv.org/abs/2307.03172), TACL 2024, arXiv:2307.03172 — positional degradation in long contexts.
- Hsieh, C.-P., et al., [*RULER: What's the Real Context Size of Your Long-Context Language Models?*](https://arxiv.org/abs/2404.06654), COLM 2024, arXiv:2404.06654 — claimed vs. effective context size; only ~half of 32K-claim models perform satisfactorily at 32K.
- Modarressi, A., et al., [*NoLiMa: Long-Context Evaluation Beyond Literal Matching*](https://arxiv.org/abs/2502.05167), ICML 2025, arXiv:2502.05167 — 11 of evaluated models drop below 50% baseline at 32K when literal-match shortcuts are removed; GPT-4o falls from 99.3% to 69.7%.
