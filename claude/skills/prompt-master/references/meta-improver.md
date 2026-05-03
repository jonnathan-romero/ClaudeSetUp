# Improver meta-prompt

This is the meta-prompt that drives `improve` mode. It's editable — read it, then override per the user's needs if their domain calls for different defaults.

Posture inherited from OpenAI's Dev-Rewriter: **preserve intent ruthlessly**. Don't add policies, don't expand scope, don't rewrite user-provided few-shot examples unless they contradict the rules.

## Contents

- [The meta-prompt](#the-meta-prompt)
- [How to use](#how-to-use)
- [What to vary](#what-to-vary)
- [What to never do](#what-to-never-do)
- [Iteration policy](#iteration-policy)

---

## The meta-prompt

```
You are improving an existing prompt for {{target_model}} on behalf of {{user_role}}.

Original prompt:
"""
{{user_prompt}}
"""

Operating constraints:
- Target model: {{target_model}}
- Where this prompt is used: {{system | user | agent | skill | template}}
- User's stated complaint (if any): {{complaint}}
- Reuse expectation: {{one-shot | reused | cached}}

Pipeline (run in order, do NOT skip):

1. READ the prompt fully. Note: role/persona, instructions, examples, output format, embedded variables.

2. DETECT TARGET MODEL CLASS.
   If unclear, STOP and ask the user.
   - Reasoning model (o-series, GPT-5, Claude+thinking, R1, Gemini 2.5 thinking) → references/reasoning-models.md
   - Non-reasoning Claude / GPT → continue with classic rules

3. ISSUE-DETECTOR PASS.
   Walk all 15 anti-patterns in references/anti-patterns.md.
   For each detected issue, record:
   - which anti-pattern (number)
   - location in the prompt (quote the relevant line)
   - why it fails (one sentence)
   - proposed fix (one sentence)
   Do NOT edit yet.

4. FOLKLORE AUDIT.
   Walk references/folklore-audit.md. For each tactic detected:
   - tipping / threats / expert personas (for accuracy) / EmotionPrompt / "take a deep breath" on reasoning / etc.
   - Mark for removal with citation.

5. DOMAIN CHECK.
   If the prompt is for a specific domain (RAG, agentic, vision, voice, extraction, etc.), apply references/domain-recipes.md.
   Note any missing must-haves.

6. MODEL-CLASS CHECK.
   If reasoning model: walk references/reasoning-models.md. Strip CoT scaffolding. Drop few-shot if R1. etc.

7. CACHE-FRIENDLINESS CHECK.
   If reuse_expectation is "reused" or "cached", walk references/caching.md.
   Move volatile tokens out of the static prefix.

8. DRAFT THE REWRITE.
   Apply the proposed fixes. PRESERVE USER INTENT RUTHLESSLY:
   - Do NOT add new policies
   - Do NOT expand scope
   - Do NOT rewrite user-supplied few-shot examples unless they contradict the rules
   - Do NOT silently change variable names or format

9. WRITE THE OUTPUT in the format shown below.

10. STOP. Do not iterate. If the user wants another pass, they will say so.

Output format:

## Detected issues

| # | Location | Anti-pattern | Why it fails | Fix |
|---|----------|--------------|--------------|-----|
| 1 | "..." | 2 (negation) | Pink-elephant effect | Convert to "do X" |
| 2 | "..." | 5 (format ambiguity) | "JSON" without schema | Provide schema |
...

## Annotated rewrite

```
<the rewritten prompt, with inline change markers>
[change: removed negation, anti-pattern 2 — use "respond directly" instead]
```

## Unified diff

```diff
--- original.prompt
+++ rewritten.prompt
@@ -1,3 +1,5 @@
-Don't be verbose.
+Respond directly. Your output is read aloud, so favor short sentences.
+
@@ -12,4 +14,6 @@
-Output as JSON.
+Output JSON matching this schema:
+{ "title": string, "tags": string[] }
```

## Removed / modified folklore

| What | Why | Cite |
|------|-----|------|
| "I'll tip you $200" | Doesn't replicate on frontier models | Wharton GAIL 2024 |
...
(Empty if none.)

## Test inputs you can run

1. {{typical}}
2. {{edge}}
3. {{near-failure}}

## Judge rubric (binary)

- [ ] Output matches schema
- [ ] {{task-specific criterion}}

## Open questions / what to verify

- {{anything ambiguous from the original}}
- {{model-class assumption}}
- {{any change the user might want to revert}}
```

---

## How to use

When improving a prompt:

1. Fill the variables at the top from intent capture.
2. Walk the pipeline in order. Steps 1–7 are detection only — do not edit.
3. Step 8 drafts the rewrite using only the issues you detected.
4. Output in the format shown.
5. STOP at step 10. The improver runs ONE pass.

## What to vary

- For SKILL.md / agent definitions: route to references/skill-prompts.md and apply the description rubric in addition to the standard pipeline.
- For multimodal: route to references/multimodal.md and apply modality-specific recipes.
- For very short prompts (1–3 lines): the diff format may be overkill. Skip the unified diff; keep the issue table + annotated rewrite.

## What to never do

- Add new policies, examples, or scope the user didn't ask for.
- Rewrite user few-shot examples unless they contradict the prompt's rules.
- Run a second improvement pass without the user asking.
- Output a rewrite without explaining each change (no "I made it better" hand-waves).
- Strip something the user added without naming it (every removal cites the anti-pattern or folklore entry).

## Iteration policy

The improver runs ONCE. If the user wants more iterations:

1. They must provide explicit feedback ("the rewrite still does X — please address that").
2. OR provide an external signal (test results, judge scores, sample outputs).
3. OR explicitly ask for a different model class to critique (e.g., "have GPT-5 review this").

Same-model self-improvement past 1 iteration degrades — see references/eval-playbook.md.
