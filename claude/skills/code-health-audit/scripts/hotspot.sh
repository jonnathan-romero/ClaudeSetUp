#!/usr/bin/env bash
# Relative churn per file — the gate for whether a complexity finding is worth reporting.
#
# Nagappan & Ball (ICSE 2005) found ABSOLUTE churn is a poor defect predictor while RELATIVE
# churn (normalized by size) predicts defect density well. So this reports a ratio, not a count.
#
# The creating commit is EXCLUDED — but only when it falls inside the window: a file added in
# one commit has churn == its own line count and would masquerade as a hotspot, while a file
# born BEFORE the window never contributed its birth to the windowed sum, and subtracting it
# there would zero out exactly the mature hot files.
#
# Usage:  hotspot.sh [GLOB] [SINCE]        e.g.  hotspot.sh '*.py' '24 months ago'
# Output (TSV, hottest first):  ratio  churned_lines  edit_commits  loc  verdict  file
# Verdicts: HOTSPOT (ratio >= HOTSPOT_RATIO) | STABLE (below it)
#           THIN-HISTORY (too few in-window edits — uninformative, NOT evidence of stability)
# The ratio is continuous — RANK by it; the verdict is only a coarse gate.
# Known limits: paths with spaces are dropped; renames are not followed (no --follow), so a
# recently renamed file can read THIN-HISTORY regardless of its true age.
set -euo pipefail

GLOB="${1:-*}"
SINCE="${2:-24 months ago}"
# Below this many in-window commits, churn cannot distinguish "stable" from "brand new".
MIN_EDITS="${MIN_EDITS:-2}"
# Windowed churn at or above this fraction of file size marks a HOTSPOT.
HOTSPOT_RATIO="${HOTSPOT_RATIO:-0.25}"

git log --since="$SINCE" --numstat --format='%H' -- "$GLOB" 2>/dev/null |
  awk 'NF==3 {ch[$3]+=$1+$2; n[$3]++} END {for (f in ch) print f"\t"ch[f]"\t"n[f]}' |
  while IFS=$'\t' read -r f churn commits; do
    [ -f "$f" ] || continue
    loc=$(wc -l < "$f" | tr -d ' ')
    [ "$loc" -gt 0 ] || continue

    # Subtract the creating commit's additions so "file was written once" scores ~0 —
    # only if the birth commit is inside the window (otherwise it isn't in the sum).
    created=$(git log --diff-filter=A --format='%H' -- "$f" | tail -1)
    in_window=0
    if [ -n "$created" ]; then
      # grep -c (not -q): reads all input, so git never dies on a closed pipe under pipefail.
      in_window=$(git log --since="$SINCE" --format='%H' -- "$f" | grep -cxF "$created" || true)
    fi
    if [ "$in_window" -gt 0 ]; then
      birth=$(git show --numstat --format='' "$created" -- "$f" | awk 'NF==3 {print $1+$2}' | head -1)
      # birth is empty when the creating commit is a merge (no numstat) — it contributed
      # nothing to the windowed sums, so subtract nothing and keep the commit count.
      if [ -n "${birth:-}" ]; then
        churn=$(( churn - birth ))
        commits=$(( commits - 1 ))
      fi
    fi
    [ "$churn" -lt 0 ] && churn=0

    if [ "$commits" -lt "$MIN_EDITS" ]; then
      verdict="THIN-HISTORY"
    else
      verdict=$(awk -v c="$churn" -v l="$loc" -v t="$HOTSPOT_RATIO" \
        'BEGIN { print (c/l >= t) ? "HOTSPOT" : "STABLE" }')
    fi
    awk -v c="$churn" -v n="$commits" -v l="$loc" -v v="$verdict" -v f="$f" \
      'BEGIN { printf "%.2f\t%d\t%d\t%d\t%s\t%s\n", c/l, c, n, l, v, f }'
  done | sort -rn
