#!/usr/bin/env bash
# Run jscpd ONCE over a repo and emit both the compact `ai` report (stdout) and
# machine-readable JSON (for span-level triage). Run this a single time per audit —
# every fanned-out agent reads its output rather than re-invoking npx.
#
# Usage:   scan.sh [PATH] [OUTDIR]
# Env:     MIN_TOKENS MIN_LINES IGNORE JSCPD_VERSION SCAN_MARKDOWN=1
set -euo pipefail

SCAN_PATH="${1:-.}"
OUTDIR="${2:-.research/.dup-scan}"
MIN_TOKENS="${MIN_TOKENS:-50}"
MIN_LINES="${MIN_LINES:-5}"
JSCPD_VERSION="${JSCPD_VERSION:-5}"

# Markdown is excluded by default: docs legitimately repeat their own boilerplate and
# the noise dominates real findings. Set SCAN_MARKDOWN=1 to audit prose duplication.
DEFAULT_IGNORE='**/node_modules/**,**/dist/**,**/build/**,**/vendor/**,**/.venv/**,**/migrations/**,**/*.min.*,**/*.lock,**/__snapshots__/**'
if [ "${SCAN_MARKDOWN:-0}" != "1" ]; then
  DEFAULT_IGNORE="**/*.md,$DEFAULT_IGNORE"
fi
IGNORE="${IGNORE:-$DEFAULT_IGNORE}"

if ! command -v npx >/dev/null 2>&1; then
  echo "DEGRADED: npx not found — jscpd unavailable. Fall back to targeted Grep sweeps" >&2
  echo "and label the audit DEGRADED (recall unknown)." >&2
  exit 3
fi

mkdir -p "$OUTDIR"

# jscpd respects .gitignore by default; do not pass --no-gitignore.
npx --yes "jscpd@${JSCPD_VERSION}" \
  --reporters ai,json \
  --output "$OUTDIR" \
  --min-tokens "$MIN_TOKENS" \
  --min-lines "$MIN_LINES" \
  --ignore "$IGNORE" \
  "$SCAN_PATH"

echo
echo "--- scan metadata ---"
echo "path=$SCAN_PATH min_tokens=$MIN_TOKENS min_lines=$MIN_LINES"
echo "ignore=$IGNORE"
echo "json_report=$OUTDIR/jscpd-report.json"
