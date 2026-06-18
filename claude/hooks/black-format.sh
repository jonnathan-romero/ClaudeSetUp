#!/usr/bin/env bash
# PostToolUse hook (Write|Edit|MultiEdit): format Python files with Black.
#
# Claude Code pipes the tool-call JSON on stdin. Pull out the edited file path,
# skip anything that isn't a Python source/stub file, then format with Black --
# preferring a Black already on PATH and falling back to `uvx black` so it still
# works in any project. Best-effort: never blocks the turn.
set -uo pipefail

file="$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"

case "$file" in
    *.py|*.pyi) ;;
    *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

if command -v black >/dev/null 2>&1; then
    black --quiet "$file" >/dev/null 2>&1 || true
elif command -v uvx >/dev/null 2>&1; then
    uvx black --quiet "$file" >/dev/null 2>&1 || true
fi
