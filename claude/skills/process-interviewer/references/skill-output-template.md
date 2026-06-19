# Skill Spec Output Template

After the interview is complete and the user wants a skill built, produce a **skill spec** — not the SKILL.md itself — using this structure. Save as a markdown file in the workspace.

Do NOT generate the SKILL.md. The spec is the handoff artifact: pass it to `skill-best-practices` (the quality bar) and `skill-creator` (the build/eval workflow), which own skill authoring. Your job is to capture everything the interview surfaced so those skills can build without re-interviewing the user.

## Spec Document Structure

```markdown
# Skill Spec: [skill-name]

## Frontmatter Draft
- **name:** [lowercase-with-hyphens, ≤64 chars, gerund form preferred]
- **description:** [Draft of what it does + when to trigger. Third person, concrete trigger phrases, slightly pushy. skill-best-practices will refine this — capture the triggers the user described.]
- **negative triggers:** [When this skill should NOT fire, if scope is ambiguous]

## Purpose
[One sentence: what problem this skill solves and for whom]

## Inputs and Outputs
**Input:** [What the skill receives — format, source]
**Output:** [What it produces — format, destination]

## Structure Outline
[The sections the SKILL.md body should contain, and any references/ or scripts/ files the interview implied are needed. One line each.]

## Key Behaviors
[The core steps or rules the skill must enforce, in order. Each specific enough that the builder needs no further clarification. Mark freedom level where it matters: exact-script vs. preferred-pattern vs. judgment-call.]

## Edge Cases and Failure Modes
[What was surfaced in Phase 3: malformed input, refusal conditions, missing dependencies, and how each should be handled.]

## Examples
[Concrete input/output pairs the user gave during the interview. These are the highest-value part of the spec — preserve them verbatim.]

## Open Questions
[Anything left unresolved. Should be minimal if the interview was thorough.]
```

## Writing Guidelines

- Capture the user's own language and concrete examples verbatim — they are what prevent the builder from guessing.
- Be specific enough that `skill-creator` could build the skill without going back to the user.
- Flag any assumptions you made or areas where the user was uncertain.
- Do not pad the spec with general skill-authoring advice — `skill-best-practices` supplies that.

## After Producing the Spec

1. Save the spec to the workspace folder.
2. Present it to the user with a one-line summary of what the skill will do.
3. Tell the user the next step: hand this spec to `skill-best-practices` and `skill-creator` to build and eval the actual SKILL.md.
