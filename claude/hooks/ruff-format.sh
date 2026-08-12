#!/usr/bin/env bash
# PostToolUse hook (Write|Edit|MultiEdit|NotebookEdit): format Python files and
# notebooks with `ruff format` (Black-compatible; formats .ipynb natively).
#
# Claude Code pipes the tool-call JSON on stdin. Pull out the edited file path
# (NotebookEdit passes notebook_path, not file_path), skip anything ruff can't
# format, then format -- preferring a ruff already on PATH and falling back to
# `uvx ruff` so it still works in any project. Best-effort: never blocks the turn.
set -uo pipefail

file="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_response.filePath // empty' 2>/dev/null)"

case "$file" in
    *.py|*.pyi|*.ipynb) ;;
    *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

if command -v ruff >/dev/null 2>&1; then
    ruff format --quiet "$file" >/dev/null 2>&1 || true
elif command -v uvx >/dev/null 2>&1; then
    uvx ruff format --quiet "$file" >/dev/null 2>&1 || true
fi
