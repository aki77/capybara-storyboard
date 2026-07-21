#!/usr/bin/env bash
#
# Parse a reg-cli JSON report (reg.json) into machine-readable outputs and a
# human-readable summary of the pixel-diff result.
#
# reg-cli emits, among other keys:
#   .failedItems   - files that changed (present in both base and head, differ)
#   .newItems      - files present only in head (added; also how a step-index
#                    shift shows up on the head side)
#   .deletedItems  - files present only in base (removed; the other side of a
#                    step-index shift)
#   .passedItems   - files that matched
#
# Each item is a path relative to the compared roots, e.g.
#   system/signup/logs_in/001_visit_login.png
#
# Usage:
#   parse-reg-report.sh <reg.json> <github-output-file>
#
# Writes these keys to <github-output-file> (GITHUB_OUTPUT format):
#   failed_count   - number of changed files
#   new_count      - number of added files
#   deleted_count  - number of removed files
#   total_count    - failed + new + deleted
#
set -euo pipefail

REPORT="${1:?usage: parse-reg-report.sh <reg.json> <github-output-file>}"
OUT="${2:?usage: parse-reg-report.sh <reg.json> <github-output-file>}"

# Normalize a missing OR unparseable report to an empty object so the jq below
# (which already tolerates missing keys via `// []`) yields zero counts without a
# separate branch. A report that exists but isn't valid JSON (e.g. reg-cli killed
# mid-write) would otherwise crash under `set -e` and leave every count output
# unwritten — which the caller then misreads as a non-zero total.
if [[ ! -f "$REPORT" ]] || ! jq -e . "$REPORT" >/dev/null 2>&1; then
  REPORT=$(mktemp)
  echo '{}' >"$REPORT"
fi

failed_count=$(jq '(.failedItems // []) | length' "$REPORT")
new_count=$(jq '(.newItems // []) | length' "$REPORT")
deleted_count=$(jq '(.deletedItems // []) | length' "$REPORT")
total_count=$((failed_count + new_count + deleted_count))

{
  echo "failed_count=${failed_count}"
  echo "new_count=${new_count}"
  echo "deleted_count=${deleted_count}"
  echo "total_count=${total_count}"
} >>"$OUT"
