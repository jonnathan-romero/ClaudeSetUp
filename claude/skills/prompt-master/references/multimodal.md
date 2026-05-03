# Multimodal prompting

Multimodal prompts aren't text prompts plus an attachment. Each modality changes what the model perceives, what it confuses, and what structures actually work.

## Table of contents

- [Vision (image input)](#vision-image-input)
- [PDF](#pdf)
- [Audio (transcription)](#audio-transcription)
- [Voice / Realtime agents](#voice--realtime-agents)
- [Image / video generation](#image--video-generation)
- [Cross-modal](#cross-modal)

---

## Vision (image input)

### Recipe

```
[image_1]
Image 1: <optional label>
[image_2]
Image 2: <optional label>
<system or user instructions go AFTER the images>
Task: <verb the model can verify against pixels — extract / locate / compare / transcribe>
Output: <strict schema, e.g. JSON with field names>
If <X> is not visible, return null for that field.
```

### Must-haves

1. **Image-first ordering.** Anthropic: "Claude works best when images come before text."
2. **Label multiple images inline** with `Image 1:` / `Image 2:`. Otherwise downstream references bind to the wrong image.
3. **Anchor answers to pixels.** Verbatim quotes, bounding boxes (`[ymin, xmin, ymax, xmax]` 0–1000 on Gemini/Qwen/Nova), or "if not present, say so."

### Pitfalls

- **"Describe this image"** → hallucination from priors. Use extractive tasks instead.
- **Counting, analog clocks, small (<200px) or rotated text, exact spatial layout** — Anthropic explicitly lists these as failure modes. Don't depend on them; pre-rotate, crop, upsample.

## PDF

### Recipe

```
[document: full PDF, placed BEFORE the question]
You are reading <doc title>. Use the PDF page numbers shown in the document footer.
Question: <specific, single-fact or extraction>
Answer format:
  - quote: "<verbatim from page N>"
  - page: <int>
  - confidence: <high|low>
If the answer is not stated, say "Not in document."
```

### Must-haves

1. **Place PDF before text.** Anthropic-explicit best practice.
2. **Use logical page numbers** from the PDF viewer in prompts, so Claude can cite them back.
3. **Cache long PDFs** with `cache_control: ephemeral` and use the Files API `file_id` for repeated queries.

### Pitfalls

- **Dense PDFs blow context** before the page limit (~1.5–3k tokens/page). Split or downsample.
- **AWS Bedrock Converse** falls back to text-only without the citations flag. Enable citations to keep the visual layer.
- **Pre-OCR vs native pass.** Pass natively when layout/figures matter. Pre-OCR only when scan quality is poor and you need predictable text.

## Audio (transcription)

### Recipe (Whisper-style)

```
initial_prompt: "<≤224 tokens of style-by-example>
  Domain terms used: Anthropic, Claude, OAuth, RAG, Llama 3.
  Speaker A: ...
  Speaker B: ..."
audio: <file>
```

### Must-haves

1. **Bias by example, not instruction.** Spell rare names exactly as you want them.
2. **Last 224 tokens only.** Put highest-value vocabulary at the end of the prompt.
3. **Synthetic prompts are fine** — generate a fictitious in-domain transcript with an LLM as a longer style template.

### Pitfalls

- **`initial_prompt` decays after the first 30s window.** For long audio, the next chunk's prompt becomes the previous chunk's output.
- **Audio overrides prompt.** You can't prompt an accent into existence.
- **Whisper follows style, ignores instructions.** "Format as Markdown" will not work.

## Voice / Realtime agents

### Recipe (sectioned, bullets)

```
# Role & Objective
- You are <role>. Success = <one line>.

# Personality & Tone
- Warm, concise, confident. 2–3 sentences per turn.
- If user interrupts, stop immediately and listen.

# Reference Pronunciations
- "Anthropic" → /ænˈθrɒpɪk/

# Tools
- get_order(order_id): use only after confirming ID aloud.

# Conversation Flow
- Greet → identify → resolve → confirm → close.

# Safety & Escalation
- On distress or out-of-scope → escalate_to_human().
```

### Must-haves

1. **Bullets > paragraphs.** OpenAI Realtime guide: "Clear, short bullets outperform long paragraphs."
2. **Cap turn length explicitly** ("2–3 sentences", "no lists over 3 items").
3. **Front-load critical context.** Don't make the agent call a tool to learn its own name or hours — latency is felt directly.

### Pitfalls

- **Long lists die in voice.** TTS reading 8 items = user gone. Summarize first, offer to enumerate.
- **Interruption is platform-handled, not prompt-handled.** VAD cancels generation. The prompt should describe behavior *after* a barge-in (acknowledge, don't restart from the top).

## Image / video generation

For per-tool syntax (Midjourney `--ar/--v/--style`, SD weight syntax + CFG, ComfyUI checkpoints, Sora camera direction, Flux's no-negative-prompts caveat, etc.) see [tool-routing.md](tool-routing.md). The recipe below is the modality-agnostic structure.

### Recipe (Subject + Action + Setting + Style + Camera + Lighting)

```
<Subject, vivid> <Action/State> in <Setting>,
<Style/Medium: photo / oil painting / 3D render>,
<Camera: 85mm lens, f/1.8, low angle>,
<Lighting: golden hour, rim light>,
<Mood/Color palette>.
[For video: + camera motion: "slow dolly-in", duration, audio cue]
```

### Must-haves

1. **Front-load the subject.** Flux, DALL-E 3 attend most to early tokens.
2. **Specify camera + lighting** explicitly for photoreal output.
3. **Reference images** when available — Flux 2, Sora, Veo 3.1 condition strongly on attached references for style/character.

### Pitfalls

- **Negative prompts don't apply to Flux** (CFG=1, flow matching). Frame exclusions positively ("clear blue sky" instead of "no clouds").
- **Weight syntax is SD-specific.** Flux/DALL-E 3 use natural emphasis ("prominently featuring") — don't paste `(word:1.4)` into them.

## Cross-modal

### Recipe

```
[image]
Context: <text the user already gave>
Task: From the image alone (do not infer from prior text), extract <fields> as JSON.
For each field: include a verbatim quote from the image OR null.
If a field appears in the user's text but NOT in the image, return null and add to "text_only" list.
```

### Must-haves

1. **Separate image-grounded vs text-grounded claims** in the schema. Forces attribution.
2. **Bounding boxes for grounding.** Ask for them when verifying the model actually saw the thing.
3. **Divide and conquer for complex screenshots/UIs.** Crop into regions, prompt each, then assemble (DCGen pattern, ~14% lift).

### Pitfalls

- **Language prior overrides weak vision.** If user text says "the receipt total is $42" and the image is blurry, the model "confirms" $42. Mitigation: "ignore numbers in the user message; report only what you can read in the image, character by character."
- **Multi-image confusion.** Without `Image 1:` / `Image 2:` labels, follow-up references like "the second image" frequently bind to the wrong one.

## Quick checklist before shipping a multimodal prompt

- [ ] Image / PDF placed *before* text
- [ ] Multi-image labels (`Image 1:` / `Image 2:`)
- [ ] Extractive task (not "describe")
- [ ] Output schema with verifiable fields (quote, bounding box, page number)
- [ ] Explicit "if not visible / not in document" sentinel
- [ ] For voice: bullets, turn-length cap, pronunciation guides
- [ ] For Whisper: ≤224 tokens, vocabulary by example at end
- [ ] For generation: front-loaded subject, camera + lighting, no negative prompts on Flux
- [ ] For PDFs: cache enabled if reused
- [ ] Doesn't depend on counting, analog clocks, or small text
