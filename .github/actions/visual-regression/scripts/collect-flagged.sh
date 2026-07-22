#!/usr/bin/env bash
#
# Select the diff images Claude flagged as "regression" (and "uncertain") and
# copy them into a dedicated directory so they can be uploaded as the small,
# UI-previewable "flagged" artifact.
#
# Input is the structured_output JSON string from claude-code-action, of shape:
#   { "results": [ { "path": "...", "classification": "...", "summary": "..." }, ... ],
#     "overall_summary": "..." }
#
# Usage:
#   collect-flagged.sh <structured_output.json> <diff-dir> <flagged-dir> <github-output-file>
#
# Writes to <github-output-file>:
#   classified       - "true" only when the structured output actually held a
#                      usable results array (so the report can tell a genuine
#                      classification from a Claude step that ran but produced
#                      nothing usable — the action exits 0 either way)
#   regression_count - number of "regression" results
#   uncertain_count  - number of "uncertain" results
#   intended_count   - number of "intended" results
#   flagged_count    - number of images copied into <flagged-dir>
#
set -euo pipefail

STRUCTURED="${1:?usage: collect-flagged.sh <structured_output.json> <diff-dir> <flagged-dir> <github-output-file>}"
DIFF_DIR="${2:?missing diff dir}"
FLAGGED_DIR="${3:?missing flagged dir}"
OUT="${4:?missing github-output file}"

mkdir -p "$FLAGGED_DIR"

classified=false
regression_count=0
uncertain_count=0
intended_count=0
flagged_count=0

# Guard against empty / invalid structured output (e.g. Claude step skipped, or
# claude-code-action exited 0 but its run failed and produced no results).
if [[ -s "$STRUCTURED" ]] && jq -e '(.results | type) == "array"' "$STRUCTURED" >/dev/null 2>&1; then
  classified=true
  regression_count=$(jq '[.results[] | select(.classification == "regression")] | length' "$STRUCTURED")
  uncertain_count=$(jq '[.results[] | select(.classification == "uncertain")] | length' "$STRUCTURED")
  intended_count=$(jq '[.results[] | select(.classification == "intended")] | length' "$STRUCTURED")

  # Flag regression and uncertain images for the small preview artifact.
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    # `rel` comes from Claude's output; reject anything that isn't a plain
    # relative path under DIFF_DIR (absolute paths or `..` traversal) so a bad
    # value can't copy an arbitrary file into the uploaded artifact.
    if [[ "$rel" = /* || "$rel" == *".."* ]]; then
      echo "Skipping suspicious path from classifier output: $rel" >&2
      continue
    fi
    src="${DIFF_DIR}/${rel}"
    if [[ -f "$src" ]]; then
      dest="${FLAGGED_DIR}/${rel}"
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      flagged_count=$((flagged_count + 1))
    else
      # Log rather than drop silently: the report's counts come from the JSON, so
      # a flagged path that matches no diff image would otherwise show up as a
      # non-zero regression/uncertain count with an empty flagged artifact.
      echo "Flagged path has no matching diff image, skipping: $rel" >&2
    fi
  done < <(jq -r '.results[] | select(.classification == "regression" or .classification == "uncertain") | .path' "$STRUCTURED")
fi

{
  echo "classified=${classified}"
  echo "regression_count=${regression_count}"
  echo "uncertain_count=${uncertain_count}"
  echo "intended_count=${intended_count}"
  echo "flagged_count=${flagged_count}"
} >>"$OUT"
