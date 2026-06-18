#!/usr/bin/env bash
# PostToolUse hook (Task|Agent): append a finished subagent's result to the
# markdown file that save-agent-prompts.sh wrote for the same call.
#
# PostToolUse hands us tool_use_id + tool_input + tool_response in ONE payload,
# so we match the prompt file by tool_use_id (no fragile cross-event/FIFO
# matching). If no prompt file is found we write a fresh combined record so the
# result is never lost. Best-effort: always exits 0, never blocks the turn.
set -uo pipefail
trap '' INT
umask 077  # results can contain secrets — keep saved files owner-only

input="$(cat)"

tuid="$(printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null)"
atype="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // "agent"' 2>/dev/null)"

# tool_response shape varies (string | array of blocks | object) — extract text.
result="$(printf '%s' "$input" | jq -r '
  .tool_response as $r
  | if   ($r|type)=="string" then $r
    elif ($r|type)=="array"  then ([$r[]? | (.text // empty)] | join("\n"))
    elif ($r|type)=="object" then
      ( if   (($r.content|type)=="array")  then ([$r.content[]? | (.text // empty)] | join("\n"))
        elif (($r.content|type)=="string") then $r.content
        else ($r.output // $r.result // ($r|tostring)) end )
    else "" end
' 2>/dev/null)"
[ -n "$result" ] || exit 0

base="${CLAUDE_PROJECT_DIR:-$PWD}"
agents_dir="$base/.agents"
mkdir -p "$agents_dir" || exit 0

# Keep .agents/ ignored even if this hook is the first to create the dir.
if git -C "$base" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    root="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null)"
    gi="$root/.gitignore"
    if [ -n "$root" ] && ! { [ -f "$gi" ] && grep -qxF '.agents/' "$gi"; }; then
        [ -s "$gi" ] && [ -n "$(tail -c1 "$gi" 2>/dev/null)" ] && printf '\n' >> "$gi"
        printf '.agents/\n' >> "$gi"
    fi
fi

# Locate the prompt file for this exact call. The prompt hook ends the name
# with "-<tool_use_id>.md", so match that delimited token (not a substring).
match=""
[ -n "$tuid" ] && match="$(ls -t "$agents_dir"/*-"$tuid".md 2>/dev/null | head -1)"

if [ -n "$match" ] && [ -f "$match" ]; then
    {
        printf '\n## Result\n\n'
        printf -- '- **Completed:** %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '%s\n' "$result"
    } >> "$match" 2>/dev/null || true
else
    # No prompt file (PreToolUse hook missing/disabled) — write a fresh record.
    prompt="$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty' 2>/dev/null)"
    ts="$(date '+%Y%m%d-%H%M%S')"
    file="$agents_dir/${ts}-${atype}-${tuid:-$$-$RANDOM}.md"
    {
        printf '# Agent prompt\n\n'
        printf -- '- **Agent type:** %s\n' "$atype"
        [ -n "$tuid" ] && printf -- '- **Tool use id:** %s\n' "$tuid"
        printf '\n## Prompt\n\n%s\n' "$prompt"
        printf '\n## Result\n\n- **Completed:** %s\n\n%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$result"
    } > "$file" 2>/dev/null || true
fi

exit 0
