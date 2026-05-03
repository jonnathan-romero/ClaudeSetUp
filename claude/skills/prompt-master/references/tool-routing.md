# Tool routing

When the user names a target tool (or it's obvious from context), apply the per-tool rules below in addition to the general structural / model-class rules. Each tool has its own syntax conventions and gotchas.

If the user's tool isn't listed: identify the closest match by category, apply that recipe, and flag the substitution.

## Table of contents

**Coding agents (in-IDE / autonomous)**
- [Claude Code](#claude-code) — [Cursor / Windsurf](#cursor--windsurf) — [Cline](#cline) — [Aider](#aider) — [GitHub Copilot](#github-copilot) — [Continue](#continue) — [Devin / SWE-agent](#devin--swe-agent) — [Antigravity](#antigravity)

**Full-stack generators**
- [Bolt](#bolt) — [v0](#v0) — [Lovable](#lovable) — [Figma Make](#figma-make) — [Google Stitch](#google-stitch) — [Replit Agent](#replit-agent)

**Browser / computer-use agents**
- [Perplexity Comet](#perplexity-comet) — [OpenAI Atlas](#openai-atlas) — [Claude in Chrome](#claude-in-chrome) — [Anthropic Computer Use](#anthropic-computer-use)

**Research / orchestration**
- [Perplexity Search](#perplexity-search) — [Manus](#manus) — [OpenAI Deep Research](#openai-deep-research)

**LLM chat / API surfaces**
- [Claude (claude.ai / API)](#claude-claudeai--api) — [ChatGPT / GPT-4o / GPT-5.x](#chatgpt--gpt-4o--gpt-5x) — [OpenAI o-series / reasoning](#openai-o-series--reasoning) — [Gemini 2.x / 3 Pro](#gemini-2x--3-pro) — [DeepSeek-R1](#deepseek-r1) — [Qwen 2.5 / Qwen 3](#qwen-25--qwen-3) — [Llama / Mistral](#llama--mistral) — [Ollama (local)](#ollama-local) — [MiniMax](#minimax)

**Image generation**
- [Midjourney](#midjourney) — [DALL-E 3](#dall-e-3) — [Stable Diffusion](#stable-diffusion) — [Flux](#flux) — [Imagen](#imagen) — [SeeDream](#seedream) — [ComfyUI](#comfyui)

**Image editing (reference-based)**
- [Reference editing notes](#reference-editing-notes)

**Video generation**
- [Sora](#sora) — [Runway Gen-3](#runway-gen-3) — [Kling](#kling) — [LTX Video](#ltx-video) — [Dream Machine (Luma)](#dream-machine-luma) — [Veo](#veo)

**3D**
- [Meshy](#meshy) — [Tripo](#tripo) — [Rodin](#rodin) — [Unity AI](#unity-ai) — [Blender AI](#blender-ai)

**Voice / audio**
- [ElevenLabs](#elevenlabs) — [OpenAI Realtime / Voice](#openai-realtime--voice) — [Whisper (transcription)](#whisper-transcription)

**Workflow / no-code**
- [Zapier](#zapier) — [Make](#make) — [n8n](#n8n)

---

## Coding agents (in-IDE / autonomous)

### Claude Code
- Agentic — runs tools, edits files, executes commands.
- Always include: starting state + target state + allowed actions + forbidden actions + stop conditions + checkpoints.
- **Stop conditions are mandatory.** Runaway loops burn the most credit.
- Opus 4.x over-engineers — add: "Only make changes directly requested. Do not add files, abstractions, or features."
- Always scope to specific files/directories — never give a global instruction without a path anchor.
- Human-review triggers: "Stop and ask before deleting any file, adding any dependency, or affecting the database schema."
- For multi-step: split into sequential prompts and tell the user to run them in order.

### Cursor / Windsurf
- File path + function name + current behavior + desired change + do-not-touch list + language and version.
- Never give a global instruction without a file anchor.
- "Done when:" line is mandatory — defines when the agent stops editing.
- For complex tasks: split into sequential prompts rather than one large prompt.
- Cursor MDC rules (`.cursor/rules/*.mdc`): use `globs:` for path-scoped triggers, `alwaysApply: true` for always-on rules.

### Cline
- Agentic VS Code extension; powered by Claude/GPT/etc.
- Match prompting style to the underlying model (see model-branching.md).
- Specify file scope explicitly. "Ask before running terminal commands" / "Ask before installing dependencies."
- Cline shows a task list before executing — write prompts that let the user review/adjust.

### Aider
- Conventions live in `.aider.conf.yml` and `CONVENTIONS.md`.
- Aider operates on a *map* of the codebase — be specific about which files matter for the task.
- For commits: Aider auto-commits; include the commit message convention in conventions if you have one.

### GitHub Copilot
- Write the exact function signature, docstring, or comment immediately before invoking.
- Copilot completes what it predicts, not what you intend — leave no ambiguity in the comment.
- Describe input types, return type, edge cases, and what the function must NOT do.

### Continue
- Open-source Cursor-like with custom slash commands and rules.
- Rules live in `.continuerules` or `.continue/config.json`.
- Same pattern as Cursor: file anchor + scoped change + done-when.

### Devin / SWE-agent
- Fully autonomous — can browse web, run terminal, write and test code.
- Very explicit starting state + target state required.
- **Forbidden actions list is critical** — Devin will make decisions you didn't intend without explicit constraints.
- Scope the filesystem: "Only work within `/src`. Do not touch infrastructure, config, or CI files."

### Antigravity
- Google's agent-first IDE, powered by Gemini 3 Pro.
- Task-based prompting — describe outcomes, not steps.
- Prompt for an Artifact (task list, implementation plan) before execution so you can review it first.
- Browser automation built-in — include verification steps: "After building, verify UI at 375px and 1440px using the browser agent."
- Specify autonomy level: "Ask before running destructive terminal commands."

## Full-stack generators

### Bolt
- Defaults to bloated boilerplate — scope explicitly.
- Specify: stack, version, what NOT to scaffold, clear component boundaries.
- Be explicit which parts are frontend vs backend vs database.
- Add: "Do not add authentication, dark mode, or features not explicitly listed."

### v0
- Vercel-native — assume Next.js + Tailwind + shadcn/ui unless you specify otherwise.
- Best for component-level UI; less strong on full apps.
- Specify if you need non-Next.js output.

### Lovable
- Responds well to design-forward descriptions — include visual/UX intent.
- Reference design systems explicitly ("Material 3 colors", "Apple HIG spacing").
- Add: "Single component, no routing, no auth" when scoping.

### Figma Make
- Design-to-code native — reference your Figma component names directly.
- Specify the target framework (React/Vue/SwiftUI) explicitly.

### Google Stitch
- Prompt-to-UI focused — describe the interface goal, not the implementation.
- Add: "match Material Design 3 guidelines" for Google-native styling.

### Replit Agent
- Builds and deploys end-to-end inside Replit.
- Include: tech stack preferences, database choice, deployment target.
- Replit has built-in DB (Replit DB / Postgres) — specify which one.

## Browser / computer-use agents

### Perplexity Comet
- Best at web research, comparison, and data extraction.
- Describe outcomes, not navigation: "Find the cheapest direct flight from X to Y, no Boeing 737 Max."
- Add explicit permission boundaries: "Do not make any purchase. Research only."
- Stop conditions for irreversible actions: "Ask before submitting any form or completing any transaction."

### OpenAI Atlas
- Stronger for multi-step commerce and account management.
- Same boundary discipline as Comet — explicit "do not pay / do not submit" lines.
- Atlas can hold sessions (logged-in state) longer than Comet — useful for account-bound tasks.

### Claude in Chrome
- Anthropic's browser agent — same trust model as Computer Use.
- Wrap retrieved content as untrusted input (indirect prompt injection risk).

### Anthropic Computer Use
- Screen + mouse + keyboard control.
- Resize/pad caveats: coordinates returned by the model assume the rescaled viewport — pre-resize images yourself for predictability.
- Combine with vision rules in [multimodal.md](multimodal.md).

## Research / orchestration

### Perplexity Search
- Specify mode: search vs analyze vs compare.
- Add citation requirements: "Cite every claim with a URL. Mark anything you can't cite as [unverified]."
- Reframe hallucination-prone questions as grounded queries.

### Manus
- Multi-agent orchestrator — describe the end deliverable, not the steps.
- Specify the output artifact type (report / spreadsheet / code / summary).
- For long multi-step tasks: add verification checkpoints — chained steps compound hallucination risk.

### OpenAI Deep Research
- Same shape as Manus: name the deliverable, set citation expectations, add "flag low-confidence claims" instruction.
- Long latency — set scope tightly to avoid 30+ minute runs that drift.

## LLM chat / API surfaces

### Claude (claude.ai / API)
- XML tags for multi-section prompts: `<context>`, `<task>`, `<constraints>`, `<output_format>`, `<example>`.
- Be explicit and specific — Claude follows literally, doesn't infer.
- Provide the *why* alongside *what* — Claude generalizes from explanations.
- Opus 4.7: state scope explicitly, dial back ALL-CAPS, prefill on the last assistant turn is deprecated.
- Always specify output format and length explicitly.

### ChatGPT / GPT-4o / GPT-5.x
- Markdown headers as primary structure (`# Role`, `# Instructions`, `# Output Format`, `# Examples`).
- Start with the smallest prompt that achieves the goal — add structure only when needed.
- GPT-4.1+ is more literal — one explicit sentence beats hinting.
- GPT-5: contradictions disproportionately damage performance — audit aggressively.
- GPT-5.1 has `reasoning_effort: none` for retrieval/format tasks.
- Constrain verbosity: "Respond in under 150 words. No preamble. No caveats."

### OpenAI o-series / reasoning
- Use **developer messages**, not system messages.
- SHORT clean instructions — these models reason across thousands of internal tokens.
- **Do NOT add CoT scaffolding** — degrades output.
- Prefer zero-shot first; add few-shot only if strictly needed and tightly aligned.
- Markdown is suppressed by default — add "Formatting re-enabled" on line 1 if you want it back.

### Gemini 2.x / 3 Pro
- Strong at long-context and multimodal — leverage the large context window.
- Prone to hallucinated citations — always: "Cite only sources you are certain of. If uncertain, say [uncertain]."
- Drifts from strict output formats — use explicit format locks with a labelled example.
- For grounded tasks: "Base your response only on the provided context. Do not extrapolate."

### DeepSeek-R1
- Reasoning-native — do NOT add CoT instructions.
- **Avoid system prompt entirely** — put all instructions in the user turn.
- **Do not provide examples** — few-shot consistently degrades R1.
- Temperature 0.5–0.7 (0.6 recommended), top_p 0.95.
- Outputs reasoning in `<think>` tags by default — add "Output only the final answer, no `<think>` content" if needed.

### Qwen 2.5 / Qwen 3
- Qwen 2.5: excellent instruction-following + JSON output. Provide a clear system prompt defining the role.
- Qwen 3 thinking mode (`/think` or `enable_thinking=True`): treat exactly like o-series — short, no CoT, no scaffolding.
- Qwen 3 non-thinking mode: treat like Qwen 2.5.

### Llama / Mistral
- Shorter prompts work better — these models lose coherence with deeply nested instructions.
- Simple flat structure — avoid heavy nesting.
- Be more explicit than you would with Claude or GPT — instruction following is weaker.
- Always include a role in the system prompt.

### Ollama (local)
- **Always ask which model is running first** — Llama3, Mistral, Qwen2.5, CodeLlama all behave differently.
- System prompt is the most impactful lever — include it in the output so the user can set it in their Modelfile.
- Shorter prompts > complex ones — local models lose coherence with deep nesting.
- Temperature 0.1 for coding/deterministic, 0.7–0.8 for creative.
- For coding: CodeLlama or Qwen2.5-Coder, not general Llama.

### MiniMax
- OpenAI-compatible API — prompts that work with GPT transfer directly.
- M2.7: 1M context window. M2.5-highspeed: 204K + optimized for speed.
- Temperature must be 0–1 inclusive — prompts that set higher fail.
- May output reasoning in `<think>` tags — add suppression line if not wanted.

## Image generation

### Midjourney
- Comma-separated descriptors, **not prose**.
- Order: subject → style → mood → lighting → composition.
- Parameters at end: `--ar 16:9 --v 6 --style raw`.
- Negative prompts via `--no [unwanted elements]`.
- Reference image: `--cref [URL]` (character) or `--sref [URL]` (style).

### DALL-E 3
- Prose works. Describe foreground / midground / background separately for complex scenes.
- Add: "Do not include any text in the image" unless text is needed.
- Less responsive to weight syntax than SD — use natural emphasis ("prominently featuring").

### Stable Diffusion
- `(word:1.3)` weight syntax. CFG 7–12.
- **Negative prompt is mandatory.** Always include "blurry, low quality, watermark, extra limbs, bad anatomy."
- Steps: 20–30 for drafts, 40–50 for finals.
- For SDXL: handles longer prompts and more natural language than SD 1.5.

### Flux
- Natural-language paragraphs, not comma-keyword soup.
- **Does NOT support classical negative prompts** (CFG=1, flow matching). Frame exclusions positively ("clear blue sky" instead of "no clouds").
- **Weight syntax doesn't transfer from SD** — use natural emphasis.
- Front-load the subject — Flux attends most to early tokens.

### Imagen
- Vertex AI Imagen 3 / Imagen 4.
- Prose with explicit style anchors.
- Add safety filter awareness — Imagen rejects prompts with people in many configurations.

### SeeDream
- Strong at artistic and stylized generation.
- Specify art style explicitly (anime, cinematic, painterly) **before** scene content.
- Mood and atmosphere descriptors work well.
- Negative prompt recommended.

### ComfyUI
- Node-based workflow — not a single prompt box.
- **Always ask which checkpoint model is loaded** before writing — syntax/token limits differ.
- Output two **separate** blocks: Positive Prompt and Negative Prompt. Never merge them.
- SD 1.5: <75 tokens per block, weighted syntax.
- SDXL: longer prompts OK, mix natural language with weights.
- Flux: natural language only, less weighted syntax.

## Reference editing notes

When the user has an existing image and wants to modify it:

- Tell the user to attach the reference to the tool first.
- Build the prompt around the **delta only** — what changes, what stays the same.
- Midjourney: `--cref` (character) or `--sref` (style).
- DALL-E 3: use the Edit endpoint (in ChatGPT with image editing enabled), not Generate.
- Stable Diffusion: img2img mode with denoising strength 0.3–0.6.
- Always include "what to keep" + "what to change" + "how much to change" + a negative prompt.

## Video generation

### Sora
- Describe as if directing a film shot.
- Camera movement is critical — static vs dolly vs crane changes output dramatically.
- Specify: shot type (wide, close-up), motion (static, slow dolly-in, handheld), duration, audio cue.

### Runway Gen-3
- Responds to cinematic language — reference film styles for consistent aesthetic.
- Specify camera lens / focal length explicitly for photoreal output.

### Kling
- Strong at realistic human motion.
- Describe body movement explicitly.
- Specify camera angle and shot type.

### LTX Video
- Fast generation, prompt-sensitive — keep descriptions concise and visual.
- Specify resolution and motion intensity explicitly.

### Dream Machine (Luma)
- Cinematic quality — reference lighting setups, lens types, color grading styles.

### Veo
- Veo 3 / 3.1 (Google) prompt structure: subject + context + action + style + camera + composition + ambiance.
- Strong on physics + motion realism.
- Add audio direction explicitly (Veo 3+ generates audio).

## 3D

### Meshy
- Best for game assets and teams.
- Format: style keyword (low-poly / realistic / stylized) + subject + key features + primary material + texture detail + technical spec.
- Negative prompt: "no background, no base, no floating parts."
- Specify export use: game engine (GLB/FBX), 3D printing (STL), web (GLB).

### Tripo
- Fastest for clean topology.
- Best for rapid prototyping and concept assets.

### Rodin
- Highest quality for photorealistic prompts.
- Slower and more expensive — reserve for final assets.

### Unity AI
- Unity 6.2+ (replaces retired Muse).
- `/ask` for documentation/project queries, `/run` for editor automation, `/code` for C# generation/review.
- Be precise — state exactly what needs to happen in the Editor.
- Generators (text-to-sprite, text-to-texture, text-to-animation): describe asset type, art style, technical constraints (resolution, palette, loop or one-shot).

### Blender AI
- BlenderGPT and similar generate Python scripts that execute in Blender.
- Be specific about geometry, material names, and scene context.
- Include "apply to selected object" or "apply to entire scene" to disambiguate.

## Voice / audio

### ElevenLabs
- Specify emotion, pacing, emphasis markers, speech rate directly.
- Use SSML-like markers for emphasis and pauses.
- Prose descriptions ("read this dramatically") don't translate — specify parameters.

### OpenAI Realtime / Voice
- Bullets > paragraphs (see [multimodal.md](multimodal.md) for full recipe).
- Cap turn length explicitly ("2–3 sentences").
- Pronunciation guides for hard words.
- Front-load critical context — latency is felt directly by the user.

### Whisper (transcription)
- `initial_prompt` ≤224 tokens (last 224 only kept).
- Bias by example, not instruction — Whisper follows style, ignores commands.
- Last-token weighted: put highest-value vocabulary at the end of the prompt.

## Workflow / no-code

### Zapier
- Trigger app + trigger event → action app + action + field mapping. Step by step.
- Auth requirements noted explicitly: "assumes [app] is already connected."
- For multi-step Zaps: number each step and specify what data passes between them.

### Make (Integromat)
- Same shape as Zapier but more flexible mapping.
- Specify modules and connections explicitly.
- Note iterators / aggregators when fan-out / fan-in is needed.

### n8n
- Self-hosted; nodes-and-connections paradigm.
- Specify trigger node, transformation nodes, action nodes.
- Code nodes (JavaScript/Python): be explicit about input/output shape.
