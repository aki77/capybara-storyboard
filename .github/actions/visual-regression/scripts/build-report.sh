#!/usr/bin/env bash
#
# Build the Markdown report body posted as a PR comment and written to the job
# summary. Combines the pixel-diff counts, Claude's classification summary, and
# links to the two uploaded artifacts.
#
# Usage:
#   build-report.sh > report.md
#
# Reads configuration from environment variables:
#   REG_OK                                   - "false" if reg-cli produced no report
#                                              (distinguishes a real "no diff" from a
#                                              failed comparison)
#   FAILED_COUNT, NEW_COUNT, DELETED_COUNT   - reg-cli diff counts
#   REGRESSION_COUNT, UNCERTAIN_COUNT, INTENDED_COUNT, FLAGGED_COUNT
#                                            - Claude classification counts
#   CLAUDE_RAN                               - "true" only if Claude produced a usable
#                                              classification (collect-flagged.sh's
#                                              `classified` output); false covers disabled,
#                                              nothing to classify, AND a failed classify run
#   STRUCTURED_FILE                          - path to structured_output JSON (may be empty/missing)
#   FLAGGED_ARTIFACT_URL, FULL_ARTIFACT_URL  - artifact-url outputs (may be empty)
#
set -euo pipefail

failed_count="${FAILED_COUNT:-0}"
new_count="${NEW_COUNT:-0}"
deleted_count="${DELETED_COUNT:-0}"
regression_count="${REGRESSION_COUNT:-0}"
uncertain_count="${UNCERTAIN_COUNT:-0}"
intended_count="${INTENDED_COUNT:-0}"
flagged_count="${FLAGGED_COUNT:-0}"
claude_ran="${CLAUDE_RAN:-false}"
structured_file="${STRUCTURED_FILE:-}"
flagged_url="${FLAGGED_ARTIFACT_URL:-}"
full_url="${FULL_ARTIFACT_URL:-}"
reg_ok="${REG_OK:-true}"

echo "## Visual regression report"
echo

# reg-cli never produced a report: don't claim "no differences" — the comparison
# didn't actually run.
if [[ "$reg_ok" != "true" ]]; then
  echo ":warning: reg-cli did not produce a report, so no comparison was made. Check the workflow logs (\`Run reg-cli\`)."
  exit 0
fi

total=$((failed_count + new_count + deleted_count))
if [[ "$total" -eq 0 ]]; then
  echo "No pixel differences were detected between the base and head screenshots. :white_check_mark:"
  exit 0
fi

echo "Pixel diff (via reg-cli):"
echo
echo "| Changed | Added | Removed |"
echo "|--:|--:|--:|"
echo "| ${failed_count} | ${new_count} | ${deleted_count} |"
echo
echo "_Added/removed images in large numbers under one example usually mean a step-sequence shift (a Capybara step was added or removed), not many independent regressions._"
echo

if [[ "$claude_ran" == "true" ]]; then
  echo "AI classification of the changed images:"
  echo
  echo "| Regression | Uncertain | Intended |"
  echo "|--:|--:|--:|"
  echo "| ${regression_count} | ${uncertain_count} | ${intended_count} |"
  echo

  if [[ -n "$structured_file" && -s "$structured_file" ]] && jq -e '.overall_summary' "$structured_file" >/dev/null 2>&1; then
    overall=$(jq -r '.overall_summary // empty' "$structured_file")
    if [[ -n "$overall" ]]; then
      echo "> ${overall}"
      echo
    fi
  fi

  # Per-image details for anything flagged as regression or uncertain.
  if [[ -n "$structured_file" && -s "$structured_file" ]] \
    && jq -e '[.results[] | select(.classification == "regression" or .classification == "uncertain")] | length > 0' "$structured_file" >/dev/null 2>&1; then
    echo "<details><summary>Flagged images (regression / uncertain)</summary>"
    echo
    echo "| Path | Classification | Summary |"
    echo "|---|---|---|"
    jq -r '
      .results[]
      | select(.classification == "regression" or .classification == "uncertain")
      | "| `\(.path)` | \(.classification) | \((.summary // "") | gsub("\n"; " ") | gsub("\\|"; "\\|")) |"
    ' "$structured_file"
    echo
    echo "</details>"
    echo
  fi
else
  echo "_No AI classification is shown: it is disabled, there were no changed images to classify, or the classification run did not return a usable result._"
  echo
fi

echo "Artifacts:"
echo
if [[ -n "$flagged_url" ]]; then
  echo "- **Flagged images** (${flagged_count}) — preview the suspected regressions one by one in the Actions UI: ${flagged_url}"
else
  echo "- **Flagged images** — none, or classification did not run."
fi
if [[ -n "$full_url" ]]; then
  echo "- **Full report** — download for the complete reg-cli report (\`report.html\`), \`reg.json\`, and all diff images: ${full_url}"
else
  echo "- **Full report** — see the workflow run's artifacts."
fi
echo
echo "_This check never blocks the PR; a human makes the final call._"
