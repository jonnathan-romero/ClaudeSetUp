# Caching & token efficiency

When a prompt will be reused (system prompts, agent loops, RAG with stable templates), structure shapes cost as much as content does.

## Contents

- [The single rule](#the-single-rule)
- [Anthropic prompt caching](#anthropic-prompt-caching)
- [OpenAI prompt caching](#openai-prompt-caching)
- [What to put where](#what-to-put-where)
- [Anti-patterns that break caching](#anti-patterns-that-break-caching)
- [Compression: only when caching is impossible](#compression-only-when-caching-is-impossible)
- [Stack the discounts](#stack-the-discounts)
- [TTL choice](#ttl-choice)
- [Quick cache audit checklist](#quick-cache-audit-checklist)

## The single rule

**Static prefix → variable suffix.** Order fields by mutation frequency, ascending:

```
[ system prompt ]
[ tool definitions ]
[ long static context: CLAUDE.md, examples, RAG docs ]
[ conversation history ]
[ current user turn ]
```

Any byte change in the prefix is a full cache miss. Treat the cached prefix like a hash key.

## Anthropic prompt caching

- Opt-in via `cache_control: { type: "ephemeral", ttl: "5m" | "1h" }`.
- Up to 4 explicit breakpoints per request.
- Minimum prefix size: 1024–4096 tokens depending on model.
- Cache hit = 0.1× input price (~90% off). 5m write = 1.25×. 1h write = 2×.
- Lookback = 20 blocks per breakpoint.
- Invalidation cascade: `tools → system → messages` — change at any level invalidates that level and everything after.

Diagnose hit rate via `cache_read_input_tokens`, `cache_creation_input_tokens`, `ephemeral_5m_input_tokens`, `ephemeral_1h_input_tokens` in the API response. Treat <80% hit rate as a bug.

## OpenAI prompt caching

- Automatic for prompts ≥1024 tokens.
- Hashed on the first ~256 tokens.
- TTL ~5–10 min (up to 1 hour).
- Exact byte-for-byte prefix match.
- Up to ~50% input discount, ~80% latency reduction.
- `prompt_cache_key` improves routing/hit rate for grouped requests.

## What to put where

| Section | Goes in cached prefix? | Why |
|---|---|---|
| System prompt with stable rules | ✅ | Reused across all turns |
| Tool definitions | ✅ | Stable schema |
| CLAUDE.md / project conventions | ✅ | Project-wide invariants |
| Long static context (RAG docs, manuals, knowledge base) | ✅ | Reused per query against same corpus |
| Few-shot examples | ✅ | Stable per task type |
| Conversation history | ✅ until current turn | Append, don't edit |
| Current user input | ❌ — variable suffix | Changes every turn |
| Timestamps / dates | ❌ in prefix | Truncate to day if needed in system |
| User identity / session vars | ❌ in prefix | Put in user message |
| Random IDs, ETags, telemetry | ❌ ever in prefix | Cache poison |

## Anti-patterns that break caching

1. **Timestamp in system prompt** (`Today is {now}`) — invalidates every request. Use day-granularity if needed.
2. **User name / session in system** (`Hello {user.name}`) — same. Move to user message.
3. **Non-deterministic tool ordering** — changing tool order invalidates the tools cache, cascades down.
4. **Whitespace drift** — trailing newline differences are full misses. Normalize the prefix builder.
5. **Mid-session system edits** — breaks the prefix from that point forward. Append, don't rewrite.
6. **Sub-1024-token "cached" prefix** — silently no-ops; the cache doesn't kick in.
7. **Breakpoint placed after volatile content** — wasted breakpoint slot.

## Compression: only when caching is impossible

Caching is lossless and the discount is larger. Only compress when the prefix won't repeat (one-shot long inputs).

| Technique | When |
|---|---|
| **LLMLingua-2** | Task-agnostic compression of static context that you want to cache once and reuse |
| **LongLLMLingua** | Long-context RAG where each query gets a different relevant subset — but breaks caching (question-aware) |
| **Hand compression** (dedup, abbreviation) | Bloated boilerplate; deterministic and cache-friendly |
| **Pruning irrelevant context** ("context engineering") | Always — Anthropic's smallest-possible-set framing |

**Rule:** if a prefix runs ≥3 times within TTL, **cache, don't compress**.

## Stack the discounts

- Batch API: 50% off.
- Cache hit: 90% off.
- Combined: ~95% off the eligible tokens.

For async-tolerant workloads with stable prefixes, this is the single biggest cost lever available.

## TTL choice

- Default 5m: refresh on every hit is free; pays for itself when call cadence is < 5 min.
- 1h: only when cadence is slower than 5 min and amortized over many hits (1h write costs 2× input vs 1.25× for 5m).

## Quick cache audit checklist

When reviewing a system/agent prompt for cache-friendliness:

1. Is the prefix ≥1024 tokens (Anthropic minimum)?
2. Are timestamps / user identity / session vars *outside* the prefix?
3. Are tools sorted deterministically?
4. Is whitespace normalized?
5. Are breakpoints placed on the *last* invariant block?
6. Is the system prompt edited mid-session, or appended-only?
7. For `<3` reuses, would compression be cheaper than caching?

If you change any of these, expect cache hit rate to swing. Monitor `cache_read_input_tokens`.
