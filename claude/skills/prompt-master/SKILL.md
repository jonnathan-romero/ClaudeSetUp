---
name: prompt-master
description: Writes, edits, reviews, and improves prompts of every kind — Claude/GPT/Gemini user prompts, system prompts, agent system prompts in .claude/agents/, SKILL.md frontmatter descriptions, subagent definitions, tool descriptions, RAG/extraction templates, voice/realtime instructions, and any LLM template string. ALWAYS trigger when the user says "write a prompt", "fix this prompt", "make my prompt better", "review my prompt", "is this prompt good", "improve the system prompt", "this prompt isn't working", "help me prompt", "tune this prompt", or pastes a multi-line prompt asking for feedback or rewrite. Also trigger when editing files matching *.md in .claude/skills/, .claude/agents/, .claude/commands/, .cursor/rules/, .clinerules, prompts/, or files containing prompt template strings sent to LLM APIs (anthropic.messages.create, openai.chat.completions.create, generate_content, llm.invoke). Do NOT use for general copy-editing of non-prompt content — use writing/style skills for that.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch
effort: high
---

# Prompt Master

Two modes for working on prompts: **generate** a new prompt from a goal, or **improve** an existing one with a diff. Both run as deterministic pipelines, not free-form rewrites.

The body of this skill is the operating manual — concrete rules, the pipeline, and pointers to references. Read the relevant reference for any concept you need detail on; do not reproduce content from references inline.

## When this skill triggers

- User pastes a prompt and asks for feedback, review, or a rewrite → **improve** mode.
- User describes a goal but has no draft yet ("write me a prompt that classifies tickets…") → **generate** mode.
- User pastes a complex multi-task prompt and wants to break it down, adapt across tools, simplify, or split into steps → **decompose** mode.
- User edits a `SKILL.md`, `.claude/agents/*.md`, `.cursor/rules/*`, or other prompt definition file → see [skill-prompts.md](references/skill-prompts.md) — special-case rules apply.
- Ambiguous → ask one targeted question, do not guess.

## Detect target tool first, then model class

Two questions before any editing — surface them up front:

1. **What tool / surface is this prompt for?** Cursor, Claude Code, Midjourney, ChatGPT, Bolt, Comet, ElevenLabs, etc. Per-tool routing rules live in [tool-routing.md](references/tool-routing.md). The same content needs different syntax across ~40 named tools.
2. **What model class?** Reasoning vs non-reasoning, Claude vs GPT vs open-weight. See [model-branching.md](references/model-branching.md) and [reasoning-models.md](references/reasoning-models.md). Many "improvements" hurt the wrong model.

If unclear on either, ask. The same edit can help one tool/model and hurt another.

## Model class quick reference

| Class | Examples | Read |
|---|---|---|
| Non-reasoning Claude/GPT | Claude no-thinking, GPT-4o, GPT-4.1 | classic rules in this file |
| Reasoning | Claude + extended thinking, o1/o3, GPT-5/5.1, DeepSeek-R1, Gemini 2.5 Thinking | [reasoning-models.md](references/reasoning-models.md) — many rules flip |
| Cross-provider portable | targets multiple vendors | [model-branching.md](references/model-branching.md) |

When unclear, ask: "Which model is this prompt for?" — the answer changes the advice.

## The three modes

### Generate (blank → first draft)

Use when the user states a goal but has no prompt yet.

Pipeline (run in order, do not skip):

1. **Capture intent** — Ask up to 3 questions covering: target tool, target model, expected input/output shape, success criteria, audience/tone, deployment context. Stop asking when you have enough; do not interrogate.
2. **Look up the tool recipe** — If the target tool is in [tool-routing.md](references/tool-routing.md), read that section. ~40 tools covered (Claude Code, Cursor, Bolt, v0, Midjourney, Sora, ElevenLabs, Zapier, etc.) — each has its own syntax conventions and gotchas.
3. **Pick a task recipe** — Match the task to one of the domain recipes in [domain-recipes.md](references/domain-recipes.md) (RAG, agentic, extraction, creative, support, summarization, etc.). Combine with the tool recipe.
4. **Optionally pick a named template** — RTF, CO-STAR, RISEN, CRISPE, Few-Shot, File-Scope, ReAct+Stop, Visual Descriptor, etc. live in [templates.md](references/templates.md). Use only when it fits cleanly; don't force a framework name onto a task.
5. **Apply structural rules** — Choose XML tags (Claude) or markdown sections (GPT) per [model-branching.md](references/model-branching.md). Static prefix → variable suffix per [caching.md](references/caching.md) when the prompt will be reused. For multi-turn use, see [multi-turn.md](references/multi-turn.md) — Memory Block, re-anchor cadence, plan/progress files.
6. **Draft the prompt** — Imperative voice, positive instructions, explicit output format, 3–5 examples if format matters more than free-form quality.
7. **Add 3 test inputs and a judge rubric** — These ship with the prompt. See [eval-playbook.md](references/eval-playbook.md). Skip only if the user says they don't need them.
8. **Present** in the user's preferred output style — see [Output style](#output-style-full-vs-terse) below.

Generic skeleton (Claude target):

```
<role>You are a [domain expert] specialized in [task].</role>

<context>
{{static context goes here, before the question}}
</context>

<instructions>
1. Numbered, sequential, positive ("do X" not "don't Y").
2. Each step ≤ one sentence.
3. State scope explicitly — Opus 4.7 won't generalize.
</instructions>

<examples>
<example>
<input>...</input>
<output>...</output>
</example>
</examples>

<output_format>
{{schema or sample shape}}
</output_format>

<input>{{user_input}}</input>
```

### Improve (existing → diff with rationale)

Use when the user pastes a prompt or points at a file.

Pipeline (run in order, do not skip):

1. **Read the prompt fully** — including embedded examples, schemas, and any system/user split. Do not start suggesting until you have it all.
2. **Detect target model class** — see above. If unclear, ask. The same edit can help one class and hurt another.
3. **Run the issue-detector pass** — invoke `scripts/audit.py` against the user's prompt. The script walks the regex-tractable subset — 7 of the 15 anti-patterns in [anti-patterns.md](references/anti-patterns.md) (plus an all-caps style check) and 5 folklore tactics from [folklore-audit.md](references/folklore-audit.md) — returning structured JSON with line numbers + suggested fixes. Pass `--target-model reasoning` if applicable. The script catches the mechanically-detectable issues; pair its output with manual review for the patterns regex can't catch (contradicting examples, conflicting persona, false-premise hallucination).
   ```bash
   python3 scripts/audit.py user_prompt.md --target-model reasoning
   ```
4. **Run the folklore audit** — strip evidence-thin tactics (tipping, threats, "you are a world-class expert" for accuracy, "take a deep breath" on reasoning models). See [folklore-audit.md](references/folklore-audit.md). Each removal gets a citation.
5. **Cross-check domain conventions** — if the prompt is RAG, agentic, vision, etc., apply the relevant recipe from [domain-recipes.md](references/domain-recipes.md). Note any missing must-haves.
6. **Cross-check model-class rules** — if reasoning model, walk [reasoning-models.md](references/reasoning-models.md). Strip CoT scaffolding, drop few-shot if R1, etc.
7. **Cross-check cache-friendliness** — if the prompt will be reused, walk [caching.md](references/caching.md). Move volatile tokens out of the static prefix.
8. **Draft the rewrite** — Apply the proposed fixes. Preserve the user's intent ruthlessly: do not add new policies, do not expand scope, do not rewrite few-shot examples unless they contradict the rules.
9. **Output an annotated rewrite** — The new prompt with inline change comments tagged to the anti-pattern that justified each edit. Then a unified diff at the bottom for copy-paste.
10. **Hand control back** — Surface 1–3 follow-up questions if the user's intent was ambiguous. Suggest 3 test inputs to verify the rewrite. Do not iterate further without user input.

The meta-prompt that drives the improver is in [meta-improver.md](references/meta-improver.md).

### Decompose (break down / adapt / simplify / split)

Use when the user pastes an existing prompt and wants something *other* than a quality improvement.

Detect which sub-task they want:

| Sub-task | Trigger phrasing | Output |
|---|---|---|
| **Break down** | "explain what this prompt does", "walk me through this", "decompile" | Annotated structural analysis: role, task, constraints, format, weaknesses |
| **Adapt** | "convert this from X to Y", "make this work in Cursor instead of Claude Code", "port to Midjourney" | Original + rewritten version using target tool's syntax + key changes list |
| **Simplify** | "this is too long", "tighten this", "remove redundancy" | Trimmed prompt + change list (which sentences earned removal) |
| **Split** | "split this into steps", "break into a sequence", "this does too many things" | Numbered Prompt 1 / Prompt 2 / … with handoff between them |

Pipeline:

1. **Identify which sub-task** from the user's phrasing. If unclear, ask.
2. **Read the source prompt fully** + identify target tool(s).
3. **For Adapt:** look up *both* tools in [tool-routing.md](references/tool-routing.md). Translate idioms (XML→markdown, prefill→system instruction, weights→natural language).
4. **For Split:** identify task seams (each "and then" / each major output is a candidate split). Each sub-prompt should be runnable on its own with its own success criteria.
5. **Output in the format from the table above.** For Split, label each as "Prompt N — what it handles" and add `➡️ Run this first, then ask for Prompt N+1` between them.

Decompose mode does **not** apply the full anti-patterns audit unless the user also asks for improvement — that's improve mode. The user often wants a faithful split, not a quality rewrite.

## Hard rules

- **Detect-then-suggest, do not blind-rewrite.** Every change must point to a detected issue. Vague "I made it better" is not allowed.
- **Cap self-critique at one iteration.** Same-model self-improvement loops degrade — see [eval-playbook.md](references/eval-playbook.md). If the user wants more iterations, run them with explicit external feedback (a different model, a test set, or human review) between rounds.
- **Preserve user-supplied few-shot examples** unless they actively contradict the prompt's rules. Examples are how the user pinned the desired behavior; rewriting them silently erases that signal.
- **Convert every "don't X" to "do Y"** with the reason. Negation underperforms direction; the why lets the reader generalize.
- **State scope explicitly on Opus 4.7+.** "Apply this formatting to every section, not just the first one" beats "format the section."
- **Do not add CoT scaffolding to reasoning-model prompts.** "Think step by step" on o-series / GPT-5 / Claude+thinking is at best redundant and at worst measurably harmful — see [reasoning-models.md](references/reasoning-models.md).
- **Output format must be explicit.** "Return JSON" is not a schema. Either supply a schema in-prompt, recommend the API's structured-output feature, or both.
- **Do not invent meta-prompts.** The skill ships its own (generator + improver). They are documented and editable; the user can read them and override them.

## Special-case: editing a SKILL.md / agent definition

When the user is editing files in `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, `.cursor/rules/`, `.clinerules/`, or similar, switch to skill-prompt mode:

- The **description** is the product. A perfect 500-line body with a vague description never runs.
- Apply the description rubric in [skill-prompts.md](references/skill-prompts.md): third person, what+when in the first sentence, verbatim user phrasings, pushy framing, negative triggers.
- Triggering reliability is testable — the loop in [eval-playbook.md](references/eval-playbook.md) covers description optimization.

## Special-case: multimodal prompts

When the prompt involves images, PDFs, audio, voice/realtime, or generation, switch to modality-specific recipes in [multimodal.md](references/multimodal.md). Common pitfalls (image-after-text, "describe this image", `initial_prompt` over 224 tokens, paragraph-style voice prompts, Flux negative prompts) are flagged there.

## Output style: full vs terse

Default is **full output** — appropriate when the user wants to learn, audit, or iterate:

1. The rewritten / generated prompt in a code block.
2. A short list of changes with anti-pattern tags ("removed negation, anti-pattern 2"; "added schema, anti-pattern 5"). For improver mode, follow with a unified diff.
3. 3 test inputs the user can run, plus a judge rubric. Mention [eval-playbook.md](references/eval-playbook.md) if they want to scale up.

Switch to **terse output** when the user signals they just want the artifact ("just give me the prompt", "skip the explanation", "make it short"):

```
🎯 Target: [tool name] / [model class]
💡 [One sentence — what was optimized and why]

[the prompt block, ready to paste]
```

Terse omits the issues table, anti-pattern tags, and rubric. Keep the safety nets: still warn if you've stripped folklore tactics or made a load-bearing edit (one line, no table).

For decompose mode, use the format from the sub-task table above; terse vs full applies to the wrapping, not the body.

If you can't make a confident call (e.g., target tool unclear, intent contradicts user examples), ask one targeted question instead of guessing — even in terse mode.

## Why this exists

Prompt engineering folklore is full of tactics that don't replicate, and rules that flip silently between model classes. This skill encodes evidence-grounded rules so you don't have to re-derive them every time. Cite the relevant reference below whenever a user asks "why" — every claim in this skill traces back to one.

## Deeper references

- [tool-routing.md](references/tool-routing.md) — ~40 named tools (Claude Code, Cursor, Cline, Bolt, v0, Lovable, Midjourney, DALL-E, SD, Sora, Kling, ElevenLabs, ComfyUI, Zapier, Comet, Atlas, Devin, etc.) with per-tool syntax + gotchas
- [templates.md](references/templates.md) — named framework templates (RTF, CO-STAR, RISEN, CRISPE, Few-Shot, File-Scope, ReAct+Stop, Visual Descriptor, ComfyUI, Decompiler)
- [anti-patterns.md](references/anti-patterns.md) — 15 failure modes with bad-example/fix pairs
- [model-branching.md](references/model-branching.md) — Claude vs GPT, reasoning vs non-reasoning rules
- [reasoning-models.md](references/reasoning-models.md) — when classic rules flip
- [domain-recipes.md](references/domain-recipes.md) — coding, agentic, RAG, extraction, creative, support, summarization, vision, voice, PDF, long-running agent
- [folklore-audit.md](references/folklore-audit.md) — what to strip and why (tipping, threats, expert personas, etc.)
- [caching.md](references/caching.md) — cache-friendly structure rules
- [multi-turn.md](references/multi-turn.md) — Memory Block, re-anchor cadence, plan/progress files, sub-agent handoffs
- [multimodal.md](references/multimodal.md) — vision/PDF/audio/voice/generation recipes
- [skill-prompts.md](references/skill-prompts.md) — SKILL.md descriptions and agent system prompts
- [eval-playbook.md](references/eval-playbook.md) — measure improvement, not vibes
- [meta-generator.md](references/meta-generator.md) — the prompt that drives generate mode
- [meta-improver.md](references/meta-improver.md) — the prompt that drives improve mode
