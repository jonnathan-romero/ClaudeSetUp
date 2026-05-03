# Generator meta-prompt

This is the meta-prompt that drives `generate` mode. It's editable — read it, then override per the user's needs if their domain calls for different defaults.

The shape is deliberate: short, declarative, walks the pipeline. Don't paragraph-explain — the SKILL.md body already does that.

## Contents

- [The meta-prompt](#the-meta-prompt)
- [How to use](#how-to-use)
- [What to vary](#what-to-vary)
- [What to never do](#what-to-never-do)

---

## The meta-prompt

```
You are writing a prompt for {{target_model}} on behalf of {{user_role}}.

Goal: {{user_goal}}

Operating constraints:
- Target model: {{target_model}}
- Output expected from the prompt you write: {{expected_output_shape}}
- Audience for the model's output: {{audience}}
- Where this prompt will be used: {{system | user | agent | skill | template}}
- Reuse expectation: {{one-shot | reused | cached}}

Pipeline (run in order):

1. Pick the relevant domain recipe from references/domain-recipes.md.
   Selected: {{selected_recipe}}

2. Determine the structural format per references/model-branching.md.
   - Claude target → XML tags (<role>, <context>, <instructions>, <examples>, <output_format>)
   - GPT target → markdown headers (# Role, # Instructions, # Output Format)
   - Reasoning model → see references/reasoning-models.md (skip CoT, prefer zero-shot)

3. Draft the prompt:
   - Imperative voice, positive instructions ("do X" not "don't Y")
   - Explicit output format (schema + example)
   - 3-5 examples ONLY IF format precision matters more than free-form quality
   - State scope explicitly (Opus 4.7 won't generalize from one item to all)
   - For reasoning models: short, direct, no CoT scaffolding

4. Audit the draft against references/anti-patterns.md (15 items). Fix any flagged.

5. If reuse_expectation is "cached", apply references/caching.md:
   - Static prefix → variable suffix
   - Volatile tokens (timestamps, IDs, user names) outside the cached block
   - Tools sorted deterministically

6. Generate 3 test inputs and a judge rubric. See references/eval-playbook.md.
   Each test input should exercise a different boundary (typical, edge, near-failure).
   Rubric: 1-3 binary criteria the user can hand-grade in <5 minutes.

Output format:

## Generated prompt

```
<the prompt itself, ready to copy>
```

## What I chose and why

- Domain recipe: {{recipe}} — {{1-line reason}}
- Structure: {{XML/markdown/etc.}} — {{1-line reason}}
- Examples: {{N or "none"}} — {{1-line reason}}
- Reasoning controls: {{n/a or specific}} — {{1-line reason}}

## Test inputs

1. {{typical}}
2. {{edge}}
3. {{near-failure}}

## Judge rubric (binary)

- [ ] Output matches schema in {{output_format}}
- [ ] {{task-specific criterion 1}}
- [ ] {{task-specific criterion 2}}

## Open questions / what to verify

- {{anything ambiguous from intent capture}}
- {{model-class assumption to confirm}}
```

---

## How to use

When generating a prompt:

1. Fill the variables at the top from the user's intent capture.
2. Walk the pipeline in order. Don't skip steps.
3. Output in the format shown.
4. If a step is skipped (e.g., "user said no examples"), say so explicitly with a one-line reason.

## What to vary

- For very short prompts (one-line user prompts), drop the role/context structure and just sharpen the request.
- For voice / realtime, switch to the bullet-list structure in references/multimodal.md.
- For SKILL.md descriptions, switch to the rubric in references/skill-prompts.md.

## What to never do

- Add tipping, threats, or "you are a world-class expert" tactics — see references/folklore-audit.md.
- Add CoT scaffolding to a reasoning-model target.
- Invent fake examples that contradict the user's intent.
- Skip the test inputs and rubric without the user explicitly opting out.
