#!/usr/bin/env bash
# PreToolUse hook (Task|Agent): save the prompt passed to each subagent as a
# markdown file under <project>/.agents/, and gitignore that dir in git repos.
#
# Claude Code pipes the tool-call JSON on stdin. We read it once, pull out the
# subagent prompt + metadata, and write a timestamped .md. Best-effort: always
# exits 0 so it never blocks the agent from launching. Matches both "Task" and
# "Agent" since that is the tool name across Claude Code versions.
set -uo pipefail
trap '' INT
umask 077  # prompts can contain secrets — keep saved files owner-only

input="$(cat)"

prompt="$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty' 2>/dev/null)"
[ -n "$prompt" ] || exit 0

atype="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // "agent"' 2>/dev/null)"
desc="$(printf '%s' "$input" | jq -r '.tool_input.description // empty' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
tuid="$(printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null)"

base="${CLAUDE_PROJECT_DIR:-$PWD}"
agents_dir="$base/.agents"
mkdir -p "$agents_dir" || exit 0

# When inside a git work tree, ensure .agents/ is ignored at the repo root.
if git -C "$base" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    root="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null)"
    gi="$root/.gitignore"
    if [ -n "$root" ] && ! { [ -f "$gi" ] && grep -qxF '.agents/' "$gi"; }; then
        # Add a newline first if the file lacks a trailing one, so we never glue
        # '.agents/' onto an existing last line that had no trailing newline.
        [ -s "$gi" ] && [ -n "$(tail -c1 "$gi" 2>/dev/null)" ] && printf '\n' >> "$gi"
        printf '.agents/\n' >> "$gi"
    fi
fi

# Readable, filesystem-safe filename. The trailing token is the tool_use_id so
# the PostToolUse result hook can find this exact file; fall back to $$/$RANDOM
# when no id is present (keeps parallel launches unique either way).
ts="$(date '+%Y%m%d-%H%M%S')"
slug="$(printf '%s' "$desc" | tr '[:upper:] ' '[:lower:]-' | tr -cd '[:alnum:]-' | cut -c1-50)"
file="$agents_dir/${ts}-${atype}${slug:+-$slug}-${tuid:-$$-$RANDOM}.md"

{
    printf '# Agent prompt\n\n'
    printf -- '- **Time:** %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf -- '- **Agent type:** %s\n' "$atype"
    [ -n "$desc" ] && printf -- '- **Description:** %s\n' "$desc"
    [ -n "$sid" ] && printf -- '- **Session:** %s\n' "$sid"
    [ -n "$tuid" ] && printf -- '- **Tool use id:** %s\n' "$tuid"
    printf '\n## Prompt\n\n'
    printf '%s\n' "$prompt"
} > "$file" 2>/dev/null || true

exit 0
