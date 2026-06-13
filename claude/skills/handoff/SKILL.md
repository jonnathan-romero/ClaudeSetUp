---
name: handoff
description: Compact the current conversation into a handoff document so a fresh agent can resume the work. ALWAYS trigger when the user says "hand this off", "write a handoff", "compact this conversation", "summarize for the next session", "I'm running low on context", "pick this up later", or asks to save session state before /clear or restart. Captures goal, progress, what worked, what didn't, and next steps as a markdown file in the project's `.handoffs/` directory. Do NOT use for commit messages, PR descriptions, or end-of-task summaries that stay in the current conversation.
argument-hint: "What will the next session focus on?"
---

Draft a handoff document, show it to the user inline for review, apply any edits they request, then write the final version to disk.

## Filename and location

Save into a `.handoffs/` directory at the root of the current project. Create it if it doesn't exist, and name the file by timestamp:

```bash
mkdir -p .handoffs
echo ".handoffs/handoff-$(date +%Y%m%d-%H%M%S).md"
```

If `.handoffs/` is not already git-ignored, add it to the project's `.gitignore` so handoffs aren't committed.

## Document structure

```markdown
# Handoff — <one-line topic>

_Generated: <ISO date>_

## Session Context
- Working directory: <cwd>
- Master plan: <`.plan/master-plan.md` path, or omit>
- Working plan: <active child plan `.plan/NN-name-plan.md` + current phase/step, or omit>
- Git branch: <branch or "none">
- Python environment: <venv name or "none">
- Files modified this session: <list>
- Original request for current session (verbatim): <quote>
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

## Next Steps
Concrete, ordered action items for continuing. Confirm these with user.

## Open Questions
Decisions the next session needs from the user.
```

**Master plan / Working plan** only apply when this session is doing [rolling-plan](../rolling-plan/SKILL.md) work — i.e. a `.plan/` directory exists. If there's no `.plan/`, omit both lines entirely. When it does exist, point Master plan at `.plan/00-master-plan.md` (drop if there's no master, just a lone child plan) and Working plan at the active child plan with its current phase/step, so the next session can resume against the durable plan. If this session completes a `Step` of working `Plan` (e.g. `.plan/NN-name-plan.md`). See `/rolling-plan` skill for instructions on updating a working `Plan`.

## Workflow

Do not draft the handoff inline in chat. Instead write the proposed content to a temp file and run the bundled `scripts/review-diff.sh`, which opens an **editable side-by-side diff in VS Code** and blocks until the user closes the tab — the user edits the right (proposed) pane directly, and whatever they leave there is saved to the final `.handoffs/` path. This is the review surface; don't ask for changes in chat.

```bash
proposed=$(mktemp -t handoff-XXXX.md)
cat > "$proposed" <<'EOF'
<full handoff document here>
EOF

dest=".handoffs/handoff-$(date +%Y%m%d-%H%M%S).md"
~/.claude/skills/handoff/scripts/review-diff.sh "$dest" "$proposed"
```

(The script is installed alongside this skill at `~/.claude/skills/handoff/scripts/review-diff.sh`.)

Why the script instead of a plain `Write`: the VS Code extension's native approve/reject diff only renders when Claude Code's `/ide` integration is connected — which fails in some remote/Codex setups. The script sidesteps that by driving the `code` CLI directly, so the diff works regardless. 

The script degrades gracefully:
- **No `code` CLI / not in VS Code** → it skips the diff and just writes the file. Report the path and let the user open and edit the `.md` directly.

1. Write the full draft to a temp file and run `scripts/review-diff.sh <dest> <proposed>`.
2. The user reviews/edits in the VS Code diff (or, in the fallback, edits the saved `.md` directly).
3. Print the absolute path and the exact pickup command for the next session:

```
Read <path>, confirm with user the next steps and continue the work described there.
```

If the user passed arguments via `$ARGUMENTS`, treat them as the focus of the next session and tailor the Next Steps section accordingly.
