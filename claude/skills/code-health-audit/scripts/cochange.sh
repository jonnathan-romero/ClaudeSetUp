#!/usr/bin/env bash
# Co-change evidence for duplicate pairs: how often do two files get edited in the SAME commit?
# This is the strongest signal that duplication is costing real maintenance.
#
# Usage:  printf 'fileA\tfileB\n' | cochange.sh
#         cochange.sh fileA fileB
#
# Output (TSV):  shared_commits  ratio  commits_A  commits_B  verdict  fileA  fileB
# ratio = shared / min(commits_A, commits_B). A high ratio built on tiny counts often means
# one repo-wide sweep commit (formatting, license header) — discount those.
# Verdicts: COUPLED (edited together repeatedly) | WEAK (exactly one shared commit — one
#           sweep or squash away from noise) | INDEPENDENT (never together)
#           THIN-HISTORY (too few commits to tell — treat as UNINFORMATIVE, not as evidence
#           against extracting; a young or squashed repo shows no co-change for anything)
set -euo pipefail

# Below this many commits on a file, co-change cannot distinguish "independent" from "new".
THIN_HISTORY_FLOOR="${THIN_HISTORY_FLOOR:-3}"
# Below this many SHARED commits, a single formatting sweep or squash-merged PR would mark
# every pair in the repo COUPLED. Coupling means repetition.
COUPLED_FLOOR="${COUPLED_FLOOR:-2}"

pair() {
  local a="$1" b="$2"
  local ca cb shared ratio verdict
  ca=$(git log --format=%H -- "$a" | wc -l | tr -d ' ')
  cb=$(git log --format=%H -- "$b" | wc -l | tr -d ' ')
  shared=$(comm -12 \
    <(git log --format=%H -- "$a" | sort) \
    <(git log --format=%H -- "$b" | sort) | wc -l | tr -d ' ')

  ratio=$(awk -v s="$shared" -v x="$ca" -v y="$cb" \
    'BEGIN { m = (x < y ? x : y); printf "%.2f", (m > 0 ? s / m : 0) }')

  if [ "$ca" -lt "$THIN_HISTORY_FLOOR" ] || [ "$cb" -lt "$THIN_HISTORY_FLOOR" ]; then
    verdict="THIN-HISTORY"
  elif [ "$shared" -ge "$COUPLED_FLOOR" ]; then
    verdict="COUPLED"
  elif [ "$shared" -gt 0 ]; then
    verdict="WEAK"
  else
    verdict="INDEPENDENT"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$shared" "$ratio" "$ca" "$cb" "$verdict" "$a" "$b"
}

if [ "$#" -eq 2 ]; then
  pair "$1" "$2"
else
  while IFS=$'\t' read -r a b; do
    [ -n "${a:-}" ] && [ -n "${b:-}" ] && pair "$a" "$b"
  done
fi
