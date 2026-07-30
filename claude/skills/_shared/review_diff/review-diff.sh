#!/usr/bin/env bash
# Shared by several skills (handoff, rolling-plan, realign-plan, agent-brief):
# open an editable side-by-side diff of a file in VS Code and block until the
# user closes the tab, then write the (possibly edited) result to the final
# destination.
#
# This is a workaround for Claude Code's `/ide` integration not connecting in
# some remote/Codex setups. It uses the VS Code `code` CLI directly
# (which talks to the running window over VSCODE_IPC_HOOK_CLI), so it works
# even when `/ide` reports "failed to connect". The trade-off vs. the native
# extension diff: there is no Approve button — the user accepts by editing the
# RIGHT pane (if desired), saving, and CLOSING the tab.
#
# Usage:
#   review-diff.sh <dest> <proposed>
#     <dest>      final path to write (e.g. .plan/01-data-layer-plan.md,
#                 .handoffs/handoff-20260730-101500.md, .briefs/01-data-layer.md)
#                 may or may not already exist; its current content is the LEFT
#                 (read-only) pane.
#     <proposed>  path to a file holding the proposed content; becomes the
#                 RIGHT (editable) pane.
#
# Behavior:
#   - if `code` is available, opens `code --wait --diff <dest-or-empty> <proposed>`,
#     blocks until the tab closes, then copies <proposed> -> <dest>.
#   - if `code` is NOT available (no VS Code), skips the diff and copies
#     <proposed> -> <dest> directly (the file is the deliverable).
#   - Acceptance cannot be detected by exit code (`code --wait` always returns 0),
#     so whatever is in the RIGHT pane on close is what gets saved. To cancel,
#     empty the right pane (save it blank) before closing — a blank result is
#     treated as a cancel and <dest> is left untouched.
#
# Exit codes:
#   0  saved (or fell back to a plain write)
#   2  cancelled (right pane was emptied) — <dest> unchanged
#   1  usage / IO error

set -euo pipefail

DEST="${1:?usage: review-diff.sh <dest> <proposed>}"
PROPOSED="${2:?usage: review-diff.sh <dest> <proposed>}"

[ -f "$PROPOSED" ] || { echo "review-diff: proposed file not found: $PROPOSED" >&2; exit 1; }

mkdir -p "$(dirname "$DEST")"

if command -v code >/dev/null 2>&1; then
    # LEFT pane = current dest content (read-only). Use an empty temp file when
    # dest doesn't exist yet so the diff still renders.
    left="$DEST"
    cleanup_left=""
    if [ ! -f "$DEST" ]; then
        left="$(mktemp -t review-diff-empty-XXXX.md)"
        cleanup_left="$left"
    fi

    echo "Opening diff in VS Code. Edit the RIGHT pane if you like, then CLOSE the tab to accept." >&2
    echo "(To cancel: delete all content in the right pane, save, then close.)" >&2

    # --wait blocks until the diff tab is closed. The right pane (PROPOSED) is
    # editable; the user's edits are saved to PROPOSED on disk before close.
    code --wait --diff "$left" "$PROPOSED" || true

    [ -n "$cleanup_left" ] && rm -f "$cleanup_left"

    # Treat an emptied right pane as a cancel.
    if [ ! -s "$PROPOSED" ] || ! grep -q '[^[:space:]]' "$PROPOSED"; then
        echo "review-diff: right pane empty — cancelled, $DEST left unchanged." >&2
        exit 2
    fi
else
    echo "review-diff: 'code' CLI not found — writing $DEST without a diff view." >&2
fi

cp "$PROPOSED" "$DEST"
echo "$DEST"
