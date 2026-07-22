#!/usr/bin/env bash
# Diff a before/after set of screenshots using reg-cli.
# Fixes reg-cli's argument order (actual -> expected -> diff) and report paths
# to prevent mix-ups on the caller's side.
#
# NOTE: does not open the report. The agent verifies report.json / diff images
#       first, and opening it for the user happens afterward (that step is done
#       explicitly in SKILL.md step 6).
#
# Usage:
#   scripts/reg-diff.sh <after_dir> <before_dir> [out_dir]
#     after_dir  : screenshot directory for after (working tree)  = reg-cli's actual
#     before_dir : screenshot directory for before (HEAD)          = reg-cli's expected
#     out_dir    : output destination (default tmp/vrt). diff/report.html/report.json written here
#
# Exit codes:
#   0   ... no diff (no visual change)
#   1   ... diff detected (expected in this skill's flow, not an error)
#   2   ... execution error such as invalid arguments or missing input directory

set -u

after_dir=${1:-}
before_dir=${2:-}
out_dir=${3:-tmp/vrt}

if [[ -z "$after_dir" || -z "$before_dir" ]]; then
  echo "usage: reg-diff.sh <after_dir> <before_dir> [out_dir]" >&2
  exit 2
fi
for d in "$after_dir" "$before_dir"; do
  if [[ ! -d "$d" ]]; then
    echo "error: directory not found: $d" >&2
    exit 2
  fi
done

diff_dir="$out_dir/diff"
report_html="$out_dir/report.html"
report_json="$out_dir/report.json"
mkdir -p "$diff_dir"

# Pass args in the order actual(after) -> expected(before) -> diff.
npx reg-cli "$after_dir" "$before_dir" "$diff_dir" \
  --report "$report_html" \
  --json "$report_json"
reg_status=$?

# reg-cli exits non-zero (1) when a diff is detected. That's expected, so don't abort here.
# Don't open the report (opened in step 6, after verification).
echo "---"
echo "reg-cli exit=$reg_status  (0=no diff, 1=diff detected)"
echo "report.html: $report_html   # open this after verification to check"
echo "report.json: $report_json"
echo "diff images: $diff_dir"

exit "$reg_status"
