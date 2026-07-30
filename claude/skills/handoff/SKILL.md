---
name: handoff
description: Compact the current conversation into a handoff document so a fresh agent can resume the work. ALWAYS trigger when the user says "hand this off", "write a handoff", "compact this conversation", "summarize for the next session", "I'm running low on context", "pick this up later", or asks to save session state before /clear or restart. Captures goal, progress, what worked, what didn't, and next steps as a markdown file in the project's `.handoffs/` directory. Do NOT use for commit messages, PR descriptions, or end-of-task summaries that stay in the current conversation.
argument-hint: "What will the next session focus on?"
---

First offer to clean up throwaway files created this session (skip silently if there are none worth removing), then draft a handoff document, show it to the user inline for review, apply any edits they request, and write the final version to disk.

## Filename and location

Handoffs go in a `.handoffs/` directory at the root of the current project, named `handoff-<timestamp>.md`. Step 1 of the [workflow](#workflow) below sets that up in a single command — run it and nothing else. Existing directory → just write into it. Don't stat it first, don't read or grep `.gitignore`, don't ask: if `.handoffs/` is already there it was git-ignored when it was created.

## Document structure

```markdown
# Handoff — <one-line topic>

_Generated: <ISO date>_

## Session Context
- Working directory: <cwd>
- Master plan: <`.plan/00-master-plan.md` path, or omit>
- Working plan: <active child plan `.plan/NN-name-plan.md` + current phase/step, or omit>
- Active brief / brief result: <`../.briefs/NN-step.md` or `NN-step-result.md`, or omit>
- Git branch: <branch or "none">
- Python environment: <venv name or "none">
- Files modified this session: <list>
- Request for next session (verbatim): <quote>
- Agent assumptions (not user-confirmed): <list>

## Goal
What we're trying to accomplish.

## Current Progress
What's been done so far. Reference file paths with `path:line`.

## What Went Right
Approaches that succeeded and relevant to future session — keep doing these.

## What Didn't Work
Approaches that failed and relevant to future session — do not repeat. Include the reason.

## User Corrections (verbatim)
Mid-session course-corrections, quoted exactly. Highest-priority carry-over — if context must be cut, keep these over completed-work detail.

## Decisions Made + Rationale
Decisions that stuck, each with its *why*. For sessions without a plan. When a `.plan/` exists, promote these to the plan's `Decisions Made` before snapshotting — the plan is the durable home; the handoff is regenerated each reset.

## Next Steps
Concrete, ordered action items for continuing. Confirm these with user.

## Open Questions
Decisions the next session needs from the user.
```

**Master plan / Working plan** only apply when this session is doing [rolling-plan](../rolling-plan/SKILL.md) work — i.e. a `.plan/` directory exists. If there's no `.plan/`, omit both lines entirely. When it does exist, point Master plan at `.plan/00-master-plan.md` (drop if there's no master, just a lone child plan) and Working plan at the active child plan with its current phase/step, so the next session can resume against the durable plan. If this session completed a step of the working plan, update the plan before snapshotting — see the rolling-plan skill above for how to flip the step and fill its `Outcome`, and promote any mid-session decisions into the plan's `Decisions Made`.

**With a plan, defer to it; without one, the handoff is the record.** When a `.plan/` exists it is the durable home for Decisions, *plan-level* dead-ends, and step progress — link to it and carry only the *volatile delta* (uncommitted reasoning, what was mid-edit, verbatim corrections, session-level dead-ends), rather than re-narrating what the plan already holds. When there is **no** `.plan/`, the handoff is the sole durable record: keep the full structure and write those decisions and dead-ends into the handoff itself. The skill works standalone — a plan is an optional companion, never a requirement.

## Keep it tight

Short, complete sentences. **Drop any section that would be empty or trivial** instead of padding it — a quick session is a few sections, not all of them. The recall lists (What Went Right / Didn't Work, Decisions) are one line per item, not paragraphs. Spend words on the verbatim user corrections and the next steps — the highest-value carry-over — and trim everywhere else.

## Clean up transient files first

Before drafting, review the files created **this session** and offer to remove the throwaway ones — temp scripts, scratch test files, one-off debug output, dead experiments no longer referenced by the work being handed off. Find candidates with `git status --porcelain` (untracked `??` entries are session-created files); cross-check against what you actually created this session, and exclude anything referenced in Current Progress or Next Steps. List the candidates with a one-line reason each and wait for the user to confirm before deleting; never delete unprompted. **Skip this step silently** (don't mention it) when no files were created, or when every created file is worth keeping.

## Workflow

Do not draft the handoff inline in chat. Instead write the proposed content to a temp file and run the shared `_shared/review_diff/review-diff.sh`, which opens an **editable side-by-side diff in VS Code** and blocks until the user closes the tab — the user edits the right (proposed) pane directly, and whatever they leave there is saved to the final `.handoffs/` path. This is the review surface; don't ask for changes in chat.

```bash
# 1. set up .handoffs/ and print both paths. Creates NO draft file — do not use
#    `mktemp`: it touches the file, and the Write tool refuses to overwrite a
#    file it hasn't Read. Writing to a not-yet-existing path just works.
if [ ! -d .handoffs ]; then
    mkdir -p .handoffs
    git rev-parse --git-dir >/dev/null 2>&1 && echo '.handoffs/' >> .gitignore
fi
TS=$(date +%Y%m%d-%H%M%S)
echo "dest:  $PWD/.handoffs/handoff-$TS.md"
echo "draft: /tmp/handoff-draft-$TS.md"

# 2. (Write tool) write the full handoff document to the draft path —
#    NOT a bash heredoc: the doc contains backticks, `$`, and ``` fences that a
#    quoted heredoc mangles, and a stray `EOF` line silently truncates it.

# 3. open the review diff, using the two paths printed in step 1
~/.claude/skills/_shared/review_diff/review-diff.sh \
  <dest> <draft>
```

(The script is shared with the planning skills at `~/.claude/skills/_shared/review_diff/review-diff.sh` — it is not installed under this skill's own folder.)

Why the script instead of a plain `Write`: the VS Code extension's native approve/reject diff only renders when Claude Code's `/ide` integration is connected — which fails in some remote/Codex setups. The script sidesteps that by driving the `code` CLI directly, so the diff works regardless. 

The script degrades gracefully:
- **No `code` CLI / not in VS Code** → it skips the diff and just writes the file. Report the path and let the user open and edit the `.md` directly.

1. Offer to clean up transient files (see above); skip silently if there's nothing worth removing.
2. Run step 1's single bash call to get the dest and draft paths, write the full draft to the draft path **with the Write tool** (not a heredoc), then run `~/.claude/skills/_shared/review_diff/review-diff.sh <dest> <draft>`.
3. The user reviews/edits in the VS Code diff (or, in the fallback, edits the saved `.md` directly).
4. Print the pickup commands for the next session — the shell one-liner first, since the usual flow is copy → quit → paste into the terminal. Each goes in its own fenced block with nothing else in it, so one click copies a runnable line. The prompt text is **identical** in both; only the `claude "…"` wrapper differs. Use the **absolute** dest path, and keep the prompt free of single quotes, backticks, and `$` so the double-quoted shell string can't break:

New terminal session (copy this, quit Claude Code, paste):

```
claude "Read <abs-path>, confirm the next steps with me, then continue the work described there."
```

Already inside a fresh session (paste at the prompt):

```
Read <abs-path>, confirm the next steps with me, then continue the work described there.
```

If the user passed arguments via `$ARGUMENTS`, treat them as the focus of the next session and tailor the Next Steps section accordingly.
