# Named templates

Recognizable prompt frameworks. Use only when one fits the task cleanly — don't force a template name onto a task that doesn't need it. The named structure helps when the user asks by name ("write me a CO-STAR prompt") or when the user wants a recognizable shape.

For tool-specific recipes, see [tool-routing.md](tool-routing.md). For task domains, see [domain-recipes.md](domain-recipes.md).

## Index

| Template | Best for |
|---|---|
| [A — RTF](#a--rtf) | Simple one-shot tasks |
| [B — CO-STAR](#b--co-star) | Professional documents, business writing |
| [C — RISEN](#c--risen) | Complex multi-step projects |
| [D — CRISPE](#d--crispe) | Creative work, brand voice |
| [E — Chain of Thought](#e--chain-of-thought) | Logic, math, debugging — *non-reasoning models only* |
| [F — Few-Shot](#f--few-shot) | Format-locked output, pattern replication |
| [G — File-Scope](#g--file-scope) | Cursor / Windsurf / Copilot — code editing AI |
| [H — ReAct + Stop Conditions](#h--react--stop-conditions) | Claude Code / Devin / autonomous agents |
| [I — Visual Descriptor](#i--visual-descriptor) | Midjourney / DALL-E / SD / Sora / Runway |
| [J — Reference Editing](#j--reference-editing) | Editing an existing image with a reference |
| [K — ComfyUI](#k--comfyui) | ComfyUI node-based image workflows |
| [L — Decompiler](#l--decompiler) | Breaking down / adapting / splitting existing prompts |

---

## A — RTF
*Role, Task, Format. Fast one-shot tasks where the request is clear.*

```
Role: [Who the AI is — one sentence]
Task: [Precise verb + what to produce]
Format: [Exact output format and length]
```

Example:
```
Role: Senior technical writer.
Task: Write a one-paragraph description of what a REST API is.
Format: Plain prose, 3 sentences max, no jargon, non-technical audience.
```

## B — CO-STAR
*Context, Objective, Style, Tone, Audience, Response. Professional documents, business writing, marketing content.*

```
Context: [Background the AI needs]
Objective: [What success looks like]
Style: [formal / conversational / technical / narrative]
Tone: [authoritative / empathetic / urgent / neutral]
Audience: [who reads this; their knowledge level]
Response: [format, length, structure]
```

## C — RISEN
*Role, Instructions, Steps, End Goal, Narrowing. Complex multi-step projects.*

```
Role: [Expert identity]
Instructions: [Overall task in plain terms]
Steps:
  1. [First action]
  2. [Second action]
  3. [Continue as needed]
End Goal: [What the final output must achieve]
Narrowing: [Constraints, scope limits, exclusions]
```

## D — CRISPE
*Capacity, Role, Insight, Statement, Personality, Experiment. Creative work, brand voice.*

```
Capacity: [Capability or expertise needed]
Role: [Specific persona to adopt]
Insight: [Key background insight]
Statement: [Core task or question]
Personality: [Tone — witty / authoritative / casual / sharp]
Experiment: [Variants or alternatives to explore]
```

## E — Chain of Thought
*For logic, math, debugging, multi-factor analysis — on standard models only.*

**Do NOT use on reasoning models** (o1/o3/o4-mini, Claude+thinking, GPT-5/5.1, R1, Qwen3-thinking, Gemini 2.5 thinking). They reason internally and CoT scaffolding degrades output. See [reasoning-models.md](reasoning-models.md).

```
[Task statement]

Before answering, think through this carefully:
<thinking>
1. What is the actual problem being asked?
2. What constraints must the solution respect?
3. What are the possible approaches?
4. Which approach is best and why?
</thinking>

Give your final answer in <answer> tags only.
```

## F — Few-Shot
*When format is easier to show than describe.*

```
[Task instruction]

Here are examples of the exact format needed:

<examples>
  <example>
    <input>[example input 1]</input>
    <output>[example output 1]</output>
  </example>
  <example>
    <input>[example input 2]</input>
    <output>[example output 2]</output>
  </example>
</examples>

Now apply this exact pattern to: [actual input]
```

Rules:
- 2–5 examples is the sweet spot. More rarely helps; more wastes tokens.
- Examples must include edge cases, not just easy ones.
- Most-representative example LAST (recency bias).
- If you've re-prompted twice for the same format issue, switch to few-shot rather than rewriting instructions.
- **Skip on DeepSeek-R1** — examples consistently degrade R1.

## G — File-Scope
*For Cursor, Windsurf, Copilot, and any AI that edits code in a codebase. Most common failure: editing the wrong file or breaking existing logic — this template prevents both.*

```
File: [exact/path/to/file.ext]
Function/Component: [exact name]

Current Behavior:
[What this code does right now — be specific]

Desired Change:
[What it should do after the edit — be specific]

Scope:
Only modify [function / component / section].
Do NOT touch: [list everything to leave unchanged]

Constraints:
- Language/framework: [specify version]
- Do not add dependencies not in [package.json / requirements.txt]
- Preserve existing [type signatures / API contracts / variable names]

Done When:
[Exact condition that confirms the change worked]
```

## H — ReAct + Stop Conditions
*For Claude Code, Devin, AutoGPT, and autonomous agents. Runaway loops are the biggest cost killer — stop conditions are not optional.*

```
Objective:
[Single, unambiguous goal in one sentence]

Starting State:
[Current file structure / codebase state / environment]

Target State:
[What should exist when the agent is done]

Allowed Actions:
- [Specific action the agent may take]
- Install only packages listed in [requirements.txt / package.json]

Forbidden Actions:
- Do NOT modify files outside [directory/scope]
- Do NOT run the dev server or deploy
- Do NOT push to git
- Do NOT delete files without showing a diff first
- Do NOT make architecture decisions without human approval

Stop Conditions:
Pause and ask for human review when:
- A file would be permanently deleted
- A new external service or API needs to be integrated
- Two valid implementation paths exist and the choice affects architecture
- An error cannot be resolved in 2 attempts
- The task requires changes outside the stated scope

Checkpoints:
After each major step, output: ✅ [what was completed]
At the end, output a full summary of every file changed.
```

## I — Visual Descriptor
*For Midjourney, DALL-E 3, Stable Diffusion, Sora, Runway.*

```
Subject: [Main subject — specific, not vague]
Action/Pose: [What the subject is doing]
Setting: [Where the scene takes place]
Style: [photorealistic / cinematic / anime / oil painting / vector / etc.]
Mood: [dramatic / serene / eerie / joyful / etc.]
Lighting: [golden hour / studio / neon / overcast / candlelight / etc.]
Color Palette: [dominant colors or named palette]
Composition: [wide shot / close-up / aerial / Dutch angle / etc.]
Aspect Ratio: [16:9 / 1:1 / 9:16 / 4:3]
Negative Prompts: [blurry, watermark, extra fingers, distortion, low quality]
Style Reference: [artist / film / aesthetic reference if applicable]
```

Tool-specific syntax (full notes in [tool-routing.md](tool-routing.md)):
- **Midjourney**: comma-separated, `--ar 16:9 --v 6 --style raw`, `--no` for negatives.
- **Stable Diffusion**: `(word:1.3)` weight syntax, CFG 7–12, mandatory negative prompt.
- **DALL-E 3**: prose works; add "do not include text in the image" unless needed.
- **Flux**: natural language; **no negative prompts**, no weight syntax.
- **Sora / Runway / Kling**: add camera movement, duration, audio cue.

## J — Reference Editing
*For editing an existing image with a reference. Different from generation — never describe the whole scene from scratch, only the delta.*

Tell the user first: "Attach your reference image to [tool name] before sending this prompt."

```
Reference image: [attached / URL]
What to keep exactly the same: [list everything that must not change]
What to change: [specific edit only — be precise]
How much to change: [subtle / moderate / significant]
Style consistency: maintain the exact style, lighting, and mood of the reference
Negative prompt: [what to avoid introducing]
```

Tool-specific:
- **Midjourney**: `--cref [image URL]` (character) or `--sref` (style).
- **DALL-E 3**: use the Edit endpoint in ChatGPT (not Generate).
- **Stable Diffusion**: img2img mode, denoising strength 0.3–0.6.

## K — ComfyUI
*Node-based — always Positive and Negative as separate blocks. Ask for the checkpoint model before writing.*

Ask first: "Which checkpoint model are you using? (SD 1.5, SDXL, Flux, or other)"

```
POSITIVE PROMPT:
[subject], [style], [mood], [lighting], [composition], [quality boosters: highly detailed, sharp focus, 8k]

NEGATIVE PROMPT:
[blurry, low quality, watermark, extra limbs, bad anatomy, distorted, oversaturated]

CHECKPOINT: [model name]
SAMPLER: Euler a (default starting point)
CFG SCALE: 7 (raise for stricter prompt adherence)
STEPS: 20–30
RESOLUTION: [width × height — divisible by 64]
```

Model-specific:
- **SD 1.5**: <75 tokens per block; weighted syntax.
- **SDXL**: longer prompts OK; mix natural language with weights.
- **Flux**: natural language; less weighted syntax.

## L — Decompiler
*For breaking down / adapting / simplifying / splitting an existing prompt. Analysis and adaptation, not building from scratch.*

Detect which sub-task:
- **Break down** — explain what each part of the prompt does
- **Adapt** — rewrite for a different tool while preserving intent
- **Simplify** — remove redundancy and tighten without losing meaning
- **Split** — divide a complex one-shot into a cleaner sequence

For Adapt: ask "What tool is the original prompt from, and what tool are you adapting it for?"

### Break-down output
```
Original prompt: [paste]

Structure analysis:
- Role/Identity: [what role is assigned and why]
- Task: [what action is being requested]
- Constraints: [what limits are set]
- Format: [what output shape is expected]
- Weaknesses: [what is missing or could cause wrong output]

Recommended fix: [rewritten version with gaps filled]
```

### Adapt output
```
Original ([source tool]): [original prompt]

Adapted for [target tool]:
[rewritten prompt using target tool syntax and best practices]

Key changes made:
- [change 1 and why]
- [change 2 and why]
```

### Simplify output
```
Original (N words / M tokens): [paste]
Simplified (N' words / M' tokens):

[trimmed prompt]

Removed:
- [phrase 1] — [reason: redundant / decorative / didn't carry meaning]
- [phrase 2] — [reason]

Kept (load-bearing):
- [phrase 1] — [why]
```

### Split output
```
Original prompt: [paste]

This prompt is doing [N] things. Split into [N] sequential prompts:

Prompt 1 — [what it handles]:
[prompt block]
Done when: [criterion]

➡️ Run this first, paste output here, then ask for Prompt 2.

Prompt 2 — [what it handles]:
[prompt block]
Done when: [criterion]
```
