# Model branching

Many "improvements" help one model class and hurt another. Always detect first.

## Quick decision tree

1. Does the API call use `extended_thinking`, `reasoning_effort`, `thinking`, or target o-series / GPT-5 / R1 / Gemini 2.5 thinking? → **Reasoning model.** See [reasoning-models.md](reasoning-models.md). Most classic CoT/few-shot rules flip.
2. Is the target Claude (any version)? → use **XML structure**.
3. Is the target GPT-4-class? → use **markdown structure**.
4. Cross-provider portable? → markdown headers + tagged embedded content.

## Claude vs GPT (non-reasoning)

| Pattern | Claude | GPT-4-class | Recommendation |
|---|---|---|---|
| Primary delimiter | XML tags (`<instructions>`, `<context>`, `<example>`) | Markdown headers (`# Role`, `# Instructions`, `# Output Format`) | Use what the target prefers; for portable prompts, markdown outer + XML inner for embedded payloads |
| Embedded documents | XML wrapped (`<document index="1">`) | XML or pipe-delimited; **JSON discouraged** for documents | XML wins on both |
| Roles | system, user, assistant | system, developer, user, assistant | Strip "developer" framing when porting to Claude |
| Output priming / prefill | First-class on Claude (deprecated on 4.6+ last-turn) | Not meaningfully supported | Don't rely on prefill in GPT version |
| Markdown in output | Renders by default | o-series suppresses unless "Formatting re-enabled" on line 1 | OpenAI-specific; do not paste into Claude |
| Long-context placement | Documents before question (up to 30% lift) | Instructions at *both* ends (top + bottom) | Both vendors agree on top placement |
| Aggressive language ("CRITICAL: You MUST") | Dial back on 4.5+; over-triggers anti-laziness | Works but unnecessary | Use plain emphasis on Claude |
| Few-shot wrap | `<example>` / `<examples>` tags | Markdown `# Examples` section | Match the target |
| Tool registration | `tools` field in API, not in prompt | `tools` field in API, not in prompt | Same advice both sides |

## What stays the same

- 3–5 examples is the sweet spot.
- Most-representative example LAST (recency bias).
- Static prefix → variable suffix for cache-friendliness.
- Positive instructions beat negative.
- Explicit output format / schema beats inferred.

## OpenAI-specific quirks

- **GPT-4.1+ is more literal.** A single explicit sentence beats hinting. Avoid relying on inference.
- **GPT-5 is sensitive to contradictions.** Burns reasoning tokens reconciling. Audit aggressively.
- **GPT-5.1 added `none` reasoning mode.** Forces no reasoning tokens — useful for retrieval/format tasks.
- **o-series default-suppresses markdown.** Add "Formatting re-enabled" on the first line of the developer message if you want markdown back.
- **JSON for embedded documents performs poorly.** Use XML or pipe-delimited.

## Claude-specific quirks

- **Opus 4.7 is more literal.** State scope explicitly: "apply to every section, not just the first".
- **Prefill on the last assistant turn is deprecated on 4.6+.** Returns 400 on Mythos Preview. Replace with Structured Outputs, "respond directly without preamble" instruction, or tool calling.
- **Avoid the word "think"** when extended thinking is *off* on Opus 4.5. Use "consider", "evaluate", "reason through" instead.
- **Tool use + extended thinking** requires `tool_choice: auto` or `none`. Forced tool selection (`any` or named) is forbidden.

## DeepSeek-R1 (outlier)

- Avoid system prompt entirely. Put everything in the user turn.
- Do not provide examples. Few-shot consistently degrades R1.
- Temperature 0.5–0.7 (0.6 recommended), top_p 0.95.
- Drop CoT scaffolding completely; R1 has its own `<think>` block.

## Gemini 2.5

- 2.5 Pro: dynamic thinking by default (128–32768 tokens), can't be disabled.
- 2.5 Flash: 0–24576 tokens; set `thinkingBudget=0` to disable.
- Flash Lite: doesn't think by default. Treat as classic non-reasoning model.

## Cross-provider portable prompts

If the prompt must work on multiple vendors:

- Outer structure: markdown headers (most portable).
- Embedded payloads: XML tags (works on both Claude and GPT).
- Drop prefill (Claude-only).
- Drop "developer message" framing (OpenAI-only).
- Drop "Formatting re-enabled" line (OpenAI-only).
- Use the conservative subset of structured-output features (basic JSON Schema, no `oneOf`, no recursion).
