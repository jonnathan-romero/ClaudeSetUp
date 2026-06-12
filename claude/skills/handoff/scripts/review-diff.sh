#!/usr/bin/env bash
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
        left="$(mktemp -t handoff-empty-XXXX.md)"
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
