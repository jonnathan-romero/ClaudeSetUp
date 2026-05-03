# Sub-Agent Prompt and Handoff Design

How to write a sub-agent prompt that survives the boundary, and how to structure what comes back. Anchored in Anthropic's four-part contract, Claude Code's "prompt-string-only" channel rule, and the OpenAI Agents SDK `input_filter` model for comparison.

## Contents

- [When to consult this](#when-to-consult-this)
- [The four-part contract (verbatim)](#the-four-part-contract-verbatim)
- [The canonical bad prompt](#the-canonical-bad-prompt)
- [Structured return schema](#structured-return-schema)
- [Citations as anti-hallucination](#citations-as-anti-hallucination)
- [Verbatim quotes for direct evidence](#verbatim-quotes-for-direct-evidence)
- [Scope boundaries](#scope-boundaries)
- [Output length contracts](#output-length-contracts)
- [Claude Code: prompt string is the only channel](#claude-code-prompt-string-is-the-only-channel)
- [Lossy vs lossless handoffs](#lossy-vs-lossless-handoffs)
- [Scratchpad and shared workspace](#scratchpad-and-shared-workspace)
- [OpenAI Agents SDK input_filter (for comparison)](#openai-agents-sdk-input_filter-for-comparison)
- [Decision triggers](#decision-triggers)
- [Anti-patterns](#anti-patterns)
- [Sources](#sources)

## When to consult this

Read this when authoring a sub-agent prompt, designing the return schema for a `.claude/agents/` definition, fanning out parallel sub-agents that must merge, deciding what to pass through a handoff, or debugging a sub-agent that returned something unusable. Skip for one-shot in-context Agent calls where the prompt content is the only variable — this is about the contract, not the wording.

## The four-part contract (verbatim)

From [Anthropic Engineering, "How we built our multi-agent research system"](https://www.anthropic.com/engineering/built-multi-agent-research-system) (Hadfield/Zhang/Lien/Scholz/Fox/Ford, 2025-06-13):

> "Each subagent needs an objective, an output format, guidance on the tools and sources to use, and clear task boundaries. Without detailed task descriptions, agents duplicate work, leave gaps, or fail to find necessary information."

Every sub-agent prompt is incomplete unless it ships all four parts. The failure modes are concrete and predictable — duplication, gaps, missed information.

### (a) Objective — terminal state, not a verb

The objective is what the sub-agent has produced when it is *done*. "Research X" is a verb. "Produce a list of the top 5 enterprise customers of company X with revenue figures sourced from 2024 10-Ks" is an objective.

If two reasonable readers of the prompt would do different things, the objective is underspecified.

**Failure when missing.** Each sub-agent infers a different terminus. Three sub-agents converge on three different "done" states. None of them is the orchestrator's question.

### (b) Output format — schema of the return value

The orchestrator must consume what the sub-agent emits. If the format is unspecified, you get prose of variable shape that the orchestrator must reparse — losing fidelity, wasting tokens, re-introducing the very problem you spawned the sub-agent to avoid.

**Failure when missing.** Un-mergeable summaries. Three parallel sub-agents return three differently-shaped prose blobs. The orchestrator either re-reads them (defeating context isolation) or picks one and discards the others.

### (c) Tool/source guidance — which tools, which corpora

Sub-agents pick tools based on descriptions and prior context. Without explicit guidance, they default to whatever seems plausible. Two parallel sub-agents both grep when one should grep and one should fetch. Both web-search when the answer is in `docs/`.

**Failure when missing.** Wrong tool selection, redundant tool calls, scope drift into wrong corpora.

### (d) Task boundaries — explicit don'ts and stop conditions

The negative space: what the sub-agent should *not* do, what it should *not* read, when it should stop. Examples: "do not make code changes," "do not follow links beyond depth 2," "stop after finding the first conclusive citation."

**Failure when missing.** Scope creep. The sub-agent investigates adjacent rabbit-holes, exhausts its turn budget, and returns a sprawling report that bleeds back into parent context.

### Decision rule

> **If you would not be confident showing the prompt to a colleague with no project context and asking them to execute it, it does not yet ship the four-part contract. Add the missing part before invoking.**

## The canonical bad prompt

From the same source, the failure they actually observed:

> "We started by allowing the lead agent to give simple, short instructions like 'research the semiconductor shortage,' but found these instructions often were vague enough that subagents misinterpreted the task."

And the concrete divergence:

> "One subagent explored the 2021 automotive chip crisis while 2 others duplicated work investigating current 2025 supply chains, without an effective division of labor."

A vague prompt forces each sub-agent to *infer* the task. Inference diverges across instances. Three sub-agents independently inferring "the semiconductor shortage" each pick a different referent — 2021 auto, 2025 general, China-Taiwan policy. The orchestrator gets three answers to three different questions.

### Tightening recipe

Convert each axis from implicit to explicit:

| Axis | Vague | Sharp |
|---|---|---|
| Subject | "the semiconductor shortage" | "automotive-grade MCU supply for Tier-1 OEMs, Q1 2024 - Q1 2025" |
| Question | "research" | "produce: (1) top 3 root causes, (2) 5 supplier responses, (3) 3 forward indicators" |
| Sources | (unspecified) | "prioritize SEC filings and trade publications; do not use Reddit/Twitter" |
| Time horizon | (unspecified) | "evidence dated 2024-01-01 or later" |
| Output shape | (unspecified) | "JSON with fields {root_causes: [{cause, evidence_url, confidence}], ...}" |
| Stop condition | (unspecified) | "stop after 5 distinct primary-source citations or 10 tool calls, whichever first" |

If two reasonable readers of the prompt would do different things, the prompt is underspecified.

## Structured return schema

### Why JSON beats prose

Sub-agents exist to *isolate* work. The whole point is that the parent does not have to re-read what the sub-agent read. If the sub-agent returns prose, the parent must do NLP on it — re-reading, re-summarizing, risking semantic drift. JSON eliminates that step: the parent does `result.summary`, `result.evidence`, `result.confidence` mechanically.

### Recommended schema

```json
{
  "summary": "1–3 sentences, the answer",
  "evidence": [
    {
      "claim": "string",
      "source": "file:line | URL#anchor",
      "quote": "verbatim text from source, ≤200 chars"
    }
  ],
  "confidence": "high | medium | low",
  "open_questions": ["string"],
  "unable_to_determine": ["string"],
  "tools_used": ["string"],
  "scope_notes": "what was intentionally out of scope"
}
```

Each field earns its place:

- `summary` — orchestrator's first read; must stand alone.
- `evidence` — every load-bearing claim, attached to a citation.
- `confidence` — lets the orchestrator decide whether to spawn a verification pass.
- `open_questions` — explicit tickets for follow-up sub-agents.
- `unable_to_determine` — distinguishes "I looked and found nothing" from "I did not look." Anthropic-standard hallucination defense.
- `tools_used` / `scope_notes` — lets the orchestrator detect redundancy when fanning out the next round.

### Worked example: code-review return

```json
{
  "summary": "Two correctness defects and one style issue in src/auth/session.py.",
  "evidence": [
    {
      "claim": "Session token is compared with == enabling timing attack",
      "source": "src/auth/session.py:84",
      "quote": "if token == stored_token:"
    },
    {
      "claim": "Expiration check uses naive datetime.now() instead of UTC",
      "source": "src/auth/session.py:112",
      "quote": "if datetime.now() > self.expires_at:"
    }
  ],
  "confidence": "high",
  "open_questions": [
    "Is the project standard to use hmac.compare_digest or constant_time_compare?"
  ],
  "unable_to_determine": [],
  "tools_used": ["Read", "Grep"],
  "scope_notes": "Did not review tests/ or callers of these functions."
}
```

### Worked example: research-fanout return

```json
{
  "summary": "Three primary causes for Q4 latency regression in checkout: a deploy of v4.12 (Oct 14), a dependency upgrade, and increased holiday traffic.",
  "evidence": [
    {
      "claim": "p99 checkout latency rose from 240ms to 410ms on Oct 14",
      "source": "https://grafana.internal/d/checkout#oct14",
      "quote": "p99 step from 240 to 410 at 14:02 UTC"
    }
  ],
  "confidence": "medium",
  "open_questions": [
    "Was the dependency upgrade reverted on Oct 18?"
  ],
  "unable_to_determine": [
    "Whether holiday traffic alone would have triggered the regression without the deploy."
  ],
  "tools_used": ["WebFetch", "Grep"],
  "scope_notes": "Did not investigate downstream services (payments, inventory)."
}
```

### Three ways to enforce structure

In order of strictness:

1. **Anthropic Structured Outputs.** `output_config.format = json_schema` with `strict: true` uses constrained decoding to *guarantee* a valid response: *"Always valid: No more `JSON.parse()` errors. Type safe: Guaranteed field types and required fields. Reliable: No retries needed for schema violations."* First request pays a grammar-compilation latency cost; cached for 24h. Limits: 20 strict tools, 24 optional params, 16 union-typed params per request. Source: [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs).
2. **Single-tool-forced.** Define one tool (e.g., `return_findings`) with the schema as `input_schema`, set `tool_choice: {"type": "tool", "name": "return_findings"}`. The model is forced to emit a `tool_use` block matching the schema. Pydantic AI's default Tool Output mode: *"the output JSON schema of each output type (or function) is provided to the model as the parameters schema of a special output tool."* Works on virtually any tool-using model.
3. **Prompted output.** Describe the schema in the prompt and hope. Pydantic AI: *"it's up to the model to interpret those instructions correctly."* Use only when constrained decoding and tools are unavailable.

### Decision rule

> **If two or more sub-agent outputs will be merged programmatically by the parent, require structured output. If a single sub-agent's prose will be appended to the parent context for the model to read, prose is acceptable but should still include explicit section headers (`## Summary`, `## Evidence`, `## Confidence`).**

### Trade-off

Schema rigidity drops nuance the sub-agent might have wanted to convey. The fix: include one narrow free-text field (`scope_notes` or `surprises`) and make every other field structured. Do not let the entire return value be free text.

## Citations as anti-hallucination

### Why prose summaries hallucinate

When a sub-agent summarizes prose-to-prose, there is no mechanical check on whether each clause traces to source. The model can interpolate plausible-sounding bridge claims with no penalty. Force every load-bearing claim to carry a `file:line` (for code/local sources) or `URL#anchor` (for web), and the bar to fabricate rises sharply: the model must also fabricate a location, which is verifiable.

### The CitationAgent pattern

> "Once sufficient information is gathered, the system exits the research loop and passes all findings to a CitationAgent, which processes the documents and research report to identify specific locations for citations. This ensures all claims are properly attributed to their sources."

Research and citation are separate passes by separate agents. The researcher gathers; a downstream agent re-reads documents alongside the draft and locates supporting passages. Two upsides: the researcher is not distracted by citation overhead; the citation agent's only job is grounding, so it catches unsupported claims by their absence in the source corpus.

### Decision rule

> **If a claim is load-bearing — a recommendation, a fact a downstream agent will act on, a number that will appear in user-facing output — require citation. If a claim is contextual or descriptive, citation is optional but encouraged.**

In practice: every item in `evidence[]` must have `source`. The `summary` field can be unsourced because each clause should trace back to an `evidence` item.

### Spot-check or it does not stick

If you require citations but never *check* a sample, the sub-agent learns to fabricate plausible-looking ones too. Pair the citation requirement with a sampled re-read — either by a CitationAgent pass or by the orchestrator before acting.

## Verbatim quotes for direct evidence

When the question is "what does the spec say?" or "what does the contract require?" or "what error did the build emit?", **summarization is the wrong move.** A summarized policy is a different policy. Force the sub-agent to quote.

### Schema addition

```json
"evidence": [
  {
    "claim": "...",
    "source": "...",
    "quote": "verbatim text from source, ≤200 chars"
  }
]
```

The `quote` field must be character-for-character from the source. The `claim` is the sub-agent's interpretation. The orchestrator (or a human) compares the two and flags interpretive drift.

### When to require quotes

- **Legal / contractual / policy text** — paraphrase changes meaning.
- **Error messages and stack traces** — the exact text is the diagnostic signal.
- **API contracts, schema definitions, type signatures** — paraphrase loses precision.
- **Disputed factual claims** — quoting forces grounding.
- **Anything a human will sign off on** — auditors want primary text.

This aligns with the prompt-engineering guide's "Ground responses in quotes" pattern: *"For long document tasks, ask Claude to quote relevant parts of the documents first before carrying out its task. This helps Claude cut through the noise of the rest of the document's contents."* Source: [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices).

### Decision rule

> **If the answer must be defensible (legal, policy, factual, contract, error diagnosis), require verbatim quotes. If the answer is a synthesis or recommendation, summary is fine but cite the underlying sources.**

## Scope boundaries

Boundaries are the *don't* part of the four-part contract. They take three forms.

### (a) Behavioral don'ts in the prompt

Spelled out as imperatives:

- "Do not make code changes; report findings only."
- "Do not follow external links beyond the document you are given."
- "Do not recurse — if you find a question that needs further research, list it in `open_questions` and stop."
- "Do not fetch more than 10 documents; stop after the first 5 with confidence ≥ medium."

### (b) Stop conditions tied to deliverables

The single most underused pattern. Default sub-agent behavior is to keep going until budget exhausts. Explicit stop conditions cap effort: *"Stop when you find the first commit that introduces the regression"* converts an open-ended search into a bounded one.

### (c) Tool restriction enforced by the harness

Limiting tools is the strongest scope guarantee because it is enforced by the harness, not by model compliance. In Claude Code:

- `tools: Read, Grep, Glob` — allowlist; sub-agent literally cannot Edit or Write.
- `disallowedTools: Write, Edit` — denylist; sub-agent inherits everything else.
- `permissionMode: plan` — read-only exploration, harness-enforced.
- Built-in `Explore` subagent ships with: *"Read-only tools (denied access to Write and Edit tools)"* — Anthropic ships scope-restriction by default.

Source: [Create custom subagents](https://code.claude.com/docs/en/sub-agents).

`PreToolUse` hooks can enforce sub-scope even within allowed tools — e.g., a `db-reader` that allows `Bash` but blocks any non-`SELECT` SQL via a shell validator.

### Decision rule

> **If the sub-agent has any reason to wander (broad task, ambiguous corpus, agentic tools available), set explicit scope boundaries in three places: behavioral don'ts in the prompt, stop conditions tied to deliverables, and tool/permission restrictions enforced by the harness.**

## Output length contracts

### Why bound length

- **Context economy.** The whole point of a sub-agent is to keep verbose work *out of* the parent's context. A 5000-word return undoes the win. From the Claude Code docs: *"the subagent does that work in its own context and returns only the summary."* If the summary is not summary-shaped, you have kept the costs of the sub-agent without the benefit.
- **Forces distillation.** A length cap demands a model judgment about what is load-bearing. *"Return ≤500 words"* converts open-ended dump into prioritized synthesis.

### How to bound length

- **Word/token cap.** *"Return your final answer in ≤500 words."*
- **Section cap.** *"Return at most one page; use these sections: Summary, Evidence (≤5 items), Confidence, Open Questions."*
- **Item cap.** *"List the top 3 — not more — root causes."*
- **Schema-enforced.** Required-fields-only with no `additionalProperties` — the model cannot pad with extra fields.

### Risks of arbitrary caps

A cap that is too tight drops critical context. Mitigations:

- Pair the cap with an *escape hatch* — a `truncated_for_length: true` field with an external artifact reference.
- Cap the *summary*, not the *evidence*. Evidence items can be many; the summary is the prose part that must be short.
- Do not cap if the deliverable is an artifact (generated code, a long document) — the cap belongs on the *report about* the artifact, not the artifact itself.

### Decision rule

> **If the sub-agent's output will pollute the parent's context, cap the prose summary length and demand structured distillation. If the output is an artifact (code, document, dataset), do not cap the artifact — write it to disk and pass a reference.**

## Claude Code: prompt string is the only channel

### The rule

From [the subagent docs](https://code.claude.com/docs/en/sub-agents):

> "Subagents receive only this system prompt (plus basic environment details like working directory), not the full Claude Code system prompt."

And:

> "Each subagent runs in its own context window with a custom system prompt, specific tool access, and independent permissions."

The parent's only channel to a sub-agent is the prompt string passed via the Agent tool (plus the sub-agent's pre-configured system prompt and the working directory). A sub-agent does **not** see:

- The parent's conversation history.
- The parent's reasoning so far.
- Other sub-agents' results.
- Files that were Read into parent context.
- Errors and tool outputs from earlier in the parent's session.

### The /fork exception

The sole exception is a *forked* subagent — explicitly opt-in via `CLAUDE_CODE_FORK_SUBAGENT=1` — which "inherits the entire conversation so far instead of starting fresh." Use forks when the sub-agent's job is genuinely a *continuation* of the parent's work (e.g., refactor proposal extending a long debugging conversation). Do not default to fork — it transfers the parent's context cost into the sub-agent and defeats isolation.

### What this means in practice

The parent must explicitly include in the sub-agent prompt:

- **File paths** (absolute) the sub-agent should read — not "the file we discussed" but `/abs/path/to/file.py`.
- **Error messages and stack traces** verbatim — not "the error we saw."
- **Decisions made so far** — "We have ruled out X; do not re-investigate it."
- **Context the sub-agent needs to interpret the task** — names of relevant systems, versions, conventions.
- **The deliverable** — see four-part contract.
- **Prior sub-agent results, if relevant** — distilled, not dumped.

### Anti-pattern

> Spawning a sub-agent with: "Continue investigating that bug we were looking at."

The sub-agent has no idea what bug, no error message, no file paths, no hypotheses already considered. It will start from zero, often re-doing work and reaching different conclusions.

### The corrective pattern

A sub-agent prompt is a self-contained brief. A reviewer with no other context should be able to read it and execute the task. Same "golden rule" as Anthropic's general prompt engineering guidance: *"Show your prompt to a colleague with minimal context on the task and ask them to follow it. If they'd be confused, Claude will be too."*

### Subagent inheritance summary

| Channel | Parent → sub-agent | Notes |
|---|---|---|
| Conversation history | No | Forked subagents only |
| System prompt | No (sub-agent has its own) | Set in the `.claude/agents/` file |
| Tool list | No (sub-agent has its own `tools:`) | Allowlist or full set |
| Permission mode | No (independent) | Set per agent file |
| Working directory | Yes | Auto-injected |
| Prompt string | Yes | The only Claude-controlled channel |
| Files Read by parent | No | Pass paths, not contents |
| Other sub-agents' results | No | Parent must distill and re-pass |
| `memory:` directory contents | Yes (first 200 lines / 25 KB) | Persistent, cross-session |
| `skills:` content | Yes | Injected at startup |

### Decision rule

> **If the parent has context the sub-agent needs to do the job correctly, include it explicitly in the prompt string. Never assume the sub-agent will re-derive context the parent already has — it costs tokens, it diverges from what the parent knows, and in the common case the sub-agent literally cannot access it.**

## Lossy vs lossless handoffs

Three patterns, picked by what the *next* consumer of the work needs.

### (a) Summary handoff (lossy) — when the parent only needs the answer

Sub-agent returns a distilled summary; raw evidence and intermediate reasoning are discarded with the sub-agent's context.

Use when:

- The parent will *act on* the answer, not re-derive it.
- No downstream agent needs the evidence trail.
- The sub-agent is a leaf in the workflow.

This is the default Claude Code subagent pattern: *"the subagent does that work in its own context and returns only the summary."*

### (b) Full-trace handoff (lossless) — when reasoning matters downstream

Pass not just the conclusion but the chain of reasoning, evidence list, and tool-call trace.

Use when:

- A reviewer or auditor will examine the work.
- A follow-up agent needs to extend the reasoning, not just consume the conclusion.
- The conclusion is contested or low-confidence and the parent may need to re-evaluate.

In the OpenAI Agents SDK, this is the default before an `input_filter` is applied: the receiving agent gets the full transcript of `input_history`, `pre_handoff_items`, and `new_items`.

### (c) Artifact-by-reference — the right answer for large outputs

Sub-agent writes the full output to disk (or to an external store) and returns a *path or URL plus a short summary*. Anthropic, verbatim:

> "Subagents call tools to store their work in external systems, then pass lightweight references back to the coordinator. This prevents information loss during multi-stage processing and reduces token overhead from copying large outputs through conversation history."

Use when:

- The output is large (long doc, dataset, generated code, full transcripts).
- Multiple downstream consumers may want it (do not duplicate by re-passing).
- The parent might never need to read the full thing — it just needs to know it exists.

The handoff payload becomes:

```json
{
  "summary": "1–3 sentences",
  "artifact_path": "/abs/path/to/output.md",
  "artifact_size": "12 KB / 320 lines",
  "schema_or_format": "Markdown with sections: Findings, Evidence, Recommendations"
}
```

### Decision rule

> **Default to summary handoff. If a follow-up agent will need the reasoning, pass full trace. If the artifact is large or has multiple downstream consumers, write it to disk and pass a reference.**

## Scratchpad and shared workspace

### When sub-agents write to a shared file vs message-pass

**Message-pass** is the default: sub-agent returns a value, parent ingests it, parent decides what to do next. Simple, local, no coordination problems.

**Shared workspace** (filesystem, memory store, or a `progress.txt`/`tests.json` file) wins when:

- The work spans multiple context windows (parent compacts, sub-agent finishes later, a third agent picks up).
- Multiple sub-agents need to coordinate without going through the parent.
- The state is structured enough to be read mechanically (e.g., a JSON status file).

Anthropic's prompting best-practices guide endorses this for long-horizon work: *"Have the model write tests in a structured format... keep track of them in a structured format (e.g., `tests.json`). This leads to better long-term ability to iterate."* And: *"Use git for state tracking: Git provides a log of what's been done and checkpoints that can be restored."*

### Claude Code's specific mechanisms

- `memory: project | user | local` — provisions a persistent directory at `~/.claude/agent-memory/<name>/` (user) or `.claude/agent-memory/<name>/` (project). The first 200 lines / 25 KB of `MEMORY.md` are auto-injected on each invocation. Persists across sessions and conversations.
- `isolation: worktree` — gives the sub-agent its own git worktree as workspace; auto-cleaned if no changes.
- `skills:` — full skill content injected at startup; the sub-agent does not have to discover and load it.

Source: [Create custom subagents](https://code.claude.com/docs/en/sub-agents).

### The artifact pattern restated

> "Subagents call tools to store their work in external systems, then pass lightweight references back to the coordinator."

This is the canonical answer for outputs that do not fit in a message: write to a tool-managed store, return the handle. The coordinator decides whether to read the artifact, fan it out to other sub-agents, or just remember the handle.

### Decision rule

> **Use message-pass for small, single-consumer results. Use shared workspace (memory file, git, scratchpad JSON) for state that survives across context windows or coordinates multiple agents. Use artifact-by-reference for any output too large to inline.**

## OpenAI Agents SDK input_filter (for comparison)

Claude Code's "prompt-string-only" channel is one design point. The OpenAI Agents SDK takes the opposite default — full transcript through — and exposes an `input_filter` hook on every handoff. From the [docs](https://openai.github.io/openai-agents-python/handoffs/):

> "input_filter is a function that receives the existing input via a `HandoffInputData`, and must return a new `HandoffInputData`."

`HandoffInputData` exposes `input_history`, `pre_handoff_items`, `new_items`, `input_items`, and `run_context` — everything the receiving agent could see by default. The filter prunes what actually crosses the boundary.

### Prebuilt filters

| Filter | Purpose | When to use |
|---|---|---|
| `remove_all_tools` | "Filters out all tool items: file search, web search and function calls+output." | Hand off to a different specialty: the new agent does not need the previous agent's tool trace, just the conclusions. |
| `nest_handoff_history` | "Summarize the previous transcript for the next agent." | History is too long; compress before passing. |
| `default_handoff_history_mapper` | "Return a single assistant message summarizing the transcript." | Default summarization; reference implementation for custom mappers. |

Nested handoffs default to collapsing prior transcript: *"the runner collapses the prior transcript into a single assistant summary message and wraps it in a `<CONVERSATION HISTORY>` block."*

### Mapping to Claude Code

| Concern | OpenAI Agents SDK | Claude Code |
|---|---|---|
| Default handoff payload | Full transcript | Empty (only prompt string + working dir) |
| Filter for tool noise | `remove_all_tools` | Built-in (sub-agent does not see parent tools) |
| Compress long history | `nest_handoff_history` | Parent must distill before passing |
| Pass full history | Default | `CLAUDE_CODE_FORK_SUBAGENT=1` |
| Tool restriction | Per-agent tools list | `tools:` allowlist, `disallowedTools:`, `permissionMode:` |

Claude Code's defaults are stricter (less leaks), so the work shifts to the parent: you must *explicitly include* the context the sub-agent needs. The OpenAI SDK's defaults are looser, so the work shifts to the filter: you must *explicitly remove* the context the sub-agent does not need. Same problem, opposite priors.

### Decision rule

> **If the receiving agent does not need the sender's tool calls, strip them (`remove_all_tools` in OpenAI SDK; default behavior in Claude Code). If the receiving agent does not need history, pass only the handoff payload — saves tokens, prevents contamination from the sender's reasoning. If the history is essential but long, summarize it before passing.**

Source: [OpenAI Agents SDK — Handoffs](https://openai.github.io/openai-agents-python/handoffs/) and [handoff_filters reference](https://openai.github.io/openai-agents-python/ref/extensions/handoff_filters/).

## Decision triggers

A skill is only useful when it converts triggers into actions. The table below compresses everything above.

| Trigger | Action | Why |
|---|---|---|
| The sub-agent could plausibly misinterpret the request. | Write the **four-part contract** explicitly: objective, output format, tool guidance, boundaries. | Prevents the semiconductor-shortage failure: divergent inferences → duplication and gaps. |
| Two or more sub-agent outputs will be merged by the parent. | Require **structured output** (JSON schema, `strict: true`, or single-tool-forced). | Mechanical merge; no NLP-on-prose round-trip. |
| A claim in the output is load-bearing (will be acted on or shown to user). | Require **citation** with `file:line` or `URL#anchor`. | Forces grounding; raises the bar to fabricate. |
| The answer must be defensible (legal/policy/factual/error). | Require **verbatim quotes** for direct evidence. | Paraphrase changes meaning. |
| The sub-agent has any reason to wander (broad task, agentic tools, ambiguous corpus). | Set **scope boundaries** in three places: behavioral don'ts in prompt, explicit stop conditions, tool/permission restrictions in the harness (`tools:`, `disallowedTools:`, `permissionMode: plan`). | Prompt compliance is best-effort; harness restrictions are enforced. |
| The sub-agent's output will pollute the parent's context. | Cap **summary length** and demand distillation. Do not cap artifact size; write the artifact to disk. | Preserves the context-isolation win. |
| The parent will need raw evidence later, or multiple consumers will use the output. | Store **artifact externally**, pass lightweight reference. | Avoids re-passing large blobs through conversation history. |
| The sub-agent does not need the parent's conversation history. | Do not pass it. Default in Claude Code; explicitly filter in OpenAI SDK with `input_filter`. | Saves tokens, avoids contamination from upstream framing. |
| A follow-up agent needs the reasoning, not just the conclusion. | Pass **full trace**, not summary. | Conclusion-only handoffs are lossy; reasoning-required tasks fail without the chain. |
| The parent has context the sub-agent needs (file paths, error text, prior decisions). | Include it **explicitly** in the prompt string. | The Agent-tool prompt string is the only channel; the sub-agent cannot re-derive parent context unless `fork`. |
| Same sub-agent type spawned more than 2-3 times with the same instructions. | Promote to a named sub-agent file with `description`, `tools`, `model`, `prompt`. | Reusability; consistent scope; testable in isolation. |

## Anti-patterns

Each is a concrete failure observed in the cited sources or trivially derivable from them.

1. **One-line sub-agent prompts** — "research X." Reproduces the Anthropic semiconductor failure. Always write the four-part contract.
2. **No output format specified** — sub-agent picks its own shape; parent cannot merge. Fan out N sub-agents and you get N shapes and N reparses.
3. **No tool guidance** — sub-agent picks the wrong tool, or duplicates a tool another sub-agent is using, or fans out web search when the answer is in a file already passed to the parent.
4. **No scope boundaries** — sub-agent recurses, follows links, investigates adjacent topics, exhausts turn budget, returns sprawling output. Especially failure-prone when the sub-agent has Bash or WebFetch.
5. **Sub-agent returns raw tool dumps** — defeats the entire context-isolation purpose. The parent now has to read the same logs/files/search results the sub-agent was supposed to digest. Always require distillation; use `summary` + `evidence` schema.
6. **Citation-free summaries treated as ground truth** — if you do not require citations, you cannot tell hallucination from fact. If you require citations but never *check* a sample, the sub-agent learns to fabricate plausible-looking ones. Pair citation requirements with spot-checks.
7. **Same handoff format for all sub-agent types** — a code-reviewer's output is not a researcher's output is not a debugger's output. Each sub-agent type should have a tailored return schema. Reusing one schema across types either over-constrains some agents or under-constrains others.
8. **Assuming sub-agent inherits parent context** — file paths, error messages, decisions, and prior sub-agent results must be passed explicitly via the Agent tool's prompt string. The sub-agent's only inputs are: its own system prompt, the prompt string, and the working directory. Forks excepted.
9. **No stop condition** — open-ended sub-agent runs to budget exhaustion. Always include a stop condition tied to deliverables ("stop after 5 confirmed citations" or "stop when you reproduce the failing test").
10. **Length caps on artifacts** — capping a generated document or codebase at "500 words" truncates the work. Cap the *report about* the artifact, not the artifact itself; write the artifact to disk.
11. **Spawning sub-agents for trivially small tasks** — Anthropic explicitly warns: *"Claude Opus 4.6 has a strong predilection for subagents and may spawn them in situations where a simpler, direct approach would suffice. For example, the model may spawn subagents for code exploration when a direct grep call is faster and sufficient."* Sub-agents have spawn overhead and context-rebuild cost. Use them when the work is verbose, parallelizable, or scoped; not for one-shot lookups.
12. **Pass-through of parent reasoning** — passing the parent's full reasoning trail when the sub-agent only needs the task pollutes the sub-agent's context with parent biases. Use `remove_all_tools` (OpenAI SDK) or rely on Claude Code's default isolation.

## Sources

- [How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system) — Anthropic Engineering, 2025-06-13. The four-part contract, semiconductor-shortage example, CitationAgent, artifact-by-reference, scaling rules of thumb.
- [Create custom subagents](https://code.claude.com/docs/en/sub-agents) — Claude Code docs. Subagent inheritance, prompt-string-only channel, `tools`/`disallowedTools`/`permissionMode`, `memory`, `isolation`, `skills`, hooks, the `Explore` built-in.
- [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) — Anthropic platform docs. Clarity, ground-in-quotes, the "show your prompt to a colleague" rule.
- [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) — Anthropic platform docs. `output_config.format`, `strict: true`, JSON schema enforcement, schema limits.
- [Tool use with Claude](https://platform.claude.com/docs/en/build-with-claude/tool-use/overview) — Anthropic platform docs. `tool_choice`, single-tool-forced pattern.
- [OpenAI Agents SDK — Handoffs](https://openai.github.io/openai-agents-python/handoffs/) and [handoff_filters reference](https://openai.github.io/openai-agents-python/ref/extensions/handoff_filters/) — `input_filter`, `on_handoff`, `input_type`, prebuilt filters, `RECOMMENDED_PROMPT_PREFIX`.
- [Pydantic AI output modes](https://pydantic.dev/docs/ai/core-concepts/output/) — ToolOutput / NativeOutput / PromptedOutput trade-offs.
