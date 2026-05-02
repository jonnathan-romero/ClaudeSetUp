# Writing Descriptions That Trigger Reliably

The description is the only field Claude's router sees at idle. A perfect 500-line SKILL.md with a vague description never runs. Spend disproportionate time here.

## Contents

- [Anatomy of a strong description](#anatomy-of-a-strong-description)
- [The "what + when" lead](#the-what--when-lead)
- [Pushy phrasing](#pushy-phrasing)
- [Concrete trigger phrases](#concrete-trigger-phrases)
- [Negative triggers](#negative-triggers)
- [Length and budget](#length-and-budget)
- [Annotated good examples](#annotated-good-examples)
- [Annotated bad examples and fixes](#annotated-bad-examples-and-fixes)
- [Pattern library](#pattern-library)

## Anatomy of a strong description

A strong description has four parts in order:

1. **What** — one clause stating what the skill does (third person, imperative)
2. **When** — concrete contexts and verbatim user phrasings
3. **Trigger keywords** — file extensions, exact tool names, domain terms
4. **Negative triggers** — only if scope is ambiguous

Worked example, annotated:

```
Extract text and tables from PDFs.    ← what
Use when working with PDF files       ← when (file context)
or when the user mentions PDFs,
forms, or document extraction.        ← verbatim phrasings + domain terms
Do NOT use for image-only files.      ← negative trigger
```

## The "what + when" lead

Claude's router scans the first sentence first. Front-load both.

| Bad | Good |
|---|---|
| "Helps with documents" | "Extracts text and tables from PDFs. Use when working with .pdf files." |
| "A skill for testing" | "Runs pytest, parses failures, and proposes fixes. Use when tests fail or the user asks to 'run the tests'." |
| "Useful for git tasks" | "Drafts and reviews git commit messages from staged diffs. Use when the user asks to 'commit', 'write a commit message', or 'review my changes'." |

## Pushy phrasing

Claude under-triggers by default. Lean toward over-recall on triggers, then trim with negatives if you over-trigger.

- "ALWAYS trigger when..." > "Consider using when..."
- "Use this skill whenever..." > "This skill may help with..."
- "Trigger on any code that imports matplotlib, even if the user doesn't explicitly mention styling" — explicit override of the model's bias

Anthropic's `pdf` skill canonical opening: *"Use this skill whenever the user wants to do anything with PDF files."* Note the absolute scope.

## Concrete trigger phrases

The router matches on exact tokens. Include:

- **File extensions** — `.pdf`, `.xlsx`, `.tsx`
- **Tool names** — `pytest`, `kubectl`, `terraform`
- **Domain jargon** — `Sharpe ratio`, `IC analysis`, `CSP header`
- **Verbatim user phrasings** — wrap the actual sentences a user would type
- **Output formats** — "the deliverable must be a spreadsheet file"

Example (matplotlib-plot-style):

> "ALWAYS use this skill when generating matplotlib charts, figures, plots, or visualizations. Trigger on any code that imports matplotlib, creates figures, or plots data — even if the user doesn't explicitly mention styling."

## Negative triggers

When scope overlaps with another skill or with general assistance, prevent false positives.

```
SKIP: file imports `openai`/other-provider SDK,
filename like `*-openai.py`/`*-generic.py`,
provider-neutral code, general programming/ML.
```

```
Do NOT use for simple lookups.
Use only for full report generation workflows.
```

## Length and budget

- Per-skill cap: 1024 chars for `description`. Combined `description` + `when_to_use` cap: 1536 chars. Stay under 1024 to leave headroom.
- Global budget: all skill descriptions in a session pre-load into `SLASH_COMMAND_TOOL_CHAR_BUDGET` (~8K default). With many skills installed, long descriptions truncate silently.
- Prioritize the first sentence — it survives truncation.

## Annotated good examples

**process-interviewer (this repo)**

> "Relentless process interviewer that extracts a complete, unambiguous plan from the user's head before any building begins. Use when the user wants to plan a complex task, design a process, build a skill, create a workflow, scope a project, or says things like 'I want to build', 'let's plan', 'help me think through', 'I have an idea for', 'scope this out', 'interview me'..."

Why it works: lists 6+ verbatim user openings, names the abstract category ("plan a complex task"), describes the *behavior* ("relentless").

**xlsx (Anthropic)**

> "Use this skill any time a spreadsheet file is the primary input or output. This means any task where the user wants to: open, read, edit, or fix an existing .xlsx, .xlsm, .csv, or .tsv file... The deliverable must be a spreadsheet file."

Why it works: defines scope by *deliverable*, lists every relevant extension, uses absolute scope ("any time").

**fact-checker (this repo)**

> "Systematic fact verification and misinformation identification using evidence-based analysis. Use when: verifying claims, checking facts, identifying misinformation, evaluating source credibility, or when user asks to 'fact check', 'verify', 'is this true'..."

Why it works: front-loads what, lists actions and verbatim phrasings, separates them visually.

## Annotated bad examples and fixes

**Bad:** `"A helpful skill for working with data"`
**Why it fails:** No what, no when, no triggers, generic. Won't trigger reliably for anything.
**Fix:** `"Profiles tabular datasets — column types, null rates, outliers, distributions. Use when the user asks to 'profile this data', 'check data quality', or mentions a CSV/Parquet file they want to understand."`

**Bad:** `"Use this when you need help"`
**Why it fails:** Second person, no scope, infinite trigger.
**Fix:** `"Reviews pending git changes for security issues — secrets, injection patterns, missing auth. Use when the user asks to 'security review', 'audit changes', or mentions reviewing a PR for vulnerabilities."`

**Bad:** `"Skill for the deploy workflow including pre-deploy checks and post-deploy validation and rollback procedures and notification of stakeholders and..."`
**Why it fails:** Run-on, buries triggers, no clear scope. Also probably should be `disable-model-invocation: true`.
**Fix:** Split: a deploy skill (`disable-model-invocation: true`) and a pre-deploy check skill — each tightly scoped.

## Pattern library

Templates that compose well:

```
[VERB] [OBJECT]. Use when [FILE-CONTEXT] or when the user
mentions [DOMAIN-TERMS] or asks to [VERBATIM-PHRASES].
Do NOT use for [NEGATIVE-SCOPE].
```

```
[ROLE] that [BEHAVIOR]. ALWAYS trigger when [CONTEXT-1],
[CONTEXT-2], or the user says [PHRASE-1], [PHRASE-2],
[PHRASE-3]. Pairs with [OTHER-SKILL] — [BOUNDARY].
```

```
[CAPABILITY] for [DOMAIN]. Use any time [SCOPE-DEFINITION].
This means [EXAMPLE-1], [EXAMPLE-2], [EXAMPLE-3].
The deliverable must be [OUTPUT-TYPE].
```
