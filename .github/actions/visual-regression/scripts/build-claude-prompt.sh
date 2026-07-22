#!/usr/bin/env bash
#
# Build the prompt handed to claude-code-action for classifying visual diffs.
#
# claude-code-action has no dedicated image input: the prompt lists the file
# paths and the action is granted the Read tool so Claude can open each PNG.
# For every changed screenshot there are up to three images on disk, under the
# base directory passed as the second argument:
#   <base_dir>/base/<path>  - the screenshot on the base branch (expected)
#   <base_dir>/head/<path>  - the screenshot on the PR head (actual)
#   <base_dir>/diff/<path>  - reg-cli's highlighted pixel diff
# The base directory must be absolute (or resolvable from Claude's cwd): Claude
# runs with cwd = the git workspace, but the screenshots live outside it, so the
# caller passes the screenshot directory explicitly rather than relying on "./".
#
# The classification result is requested as structured output (see the
# --json-schema passed in the workflow): one entry per changed path with a
# path, a classification (intended | regression | uncertain), and a summary.
#
# Usage:
#   build-claude-prompt.sh <reg.json> [image_base_dir] > prompt.txt
#
set -euo pipefail

REPORT="${1:?usage: build-claude-prompt.sh <reg.json> [image_base_dir]}"
# Base directory the base/head/diff subdirs live under. Defaults to "." for
# backward compatibility (the old workflow ran with cwd holding ./base ./head).
BASE_DIR="${2:-.}"

changed=$(jq -r '(.failedItems // [])[]' "$REPORT")
added=$(jq -r '(.newItems // [])[]' "$REPORT")
removed=$(jq -r '(.deletedItems // [])[]' "$REPORT")

# Fixed intro (no shell expansion, so backticks/braces in the prose stay literal).
cat <<'PROMPT_INTRO'
You are reviewing a visual regression report for a Ruby on Rails pull request.
The screenshots were captured by capybara-storyboard during RSpec system/component
specs: one screenshot per Capybara step, stored under a stable relative path
`{spec_path}/{example_name}/{NNN}_action_detail.png`, where `NNN` is a
zero-padded, per-example step sequence number.

Two runs were captured with the same target specs:
PROMPT_INTRO

# The only lines that need the base directory interpolated. Kept separate so the
# prose above/below can stay in quoted here-docs (no backtick/`$` escaping).
printf -- '- `%s/base/<path>` is the screenshot on the base branch (the EXPECTED image).\n' "$BASE_DIR"
printf -- '- `%s/head/<path>` is the screenshot on the PR head (the ACTUAL image).\n' "$BASE_DIR"
printf -- '- `%s/diff/<path>` is reg-cli'\''s pixel-diff highlight for images that changed.\n' "$BASE_DIR"

cat <<'PROMPT_HEADER'

Read the images with the Read tool and classify what changed.

Important context about step-index shifts:
- If the PR adds or removes a Capybara step in an example, every later screenshot
  in that example is renumbered, so its `NNN` prefix shifts. reg-cli sees this as
  a large batch of "added" (new) and "removed" (deleted) files for that example
  rather than as content changes. When you see many new/deleted files clustered
  under the same example directory, treat it as a likely STEP-SEQUENCE SHIFT
  (a flow change), not as many independent visual regressions, and say so.

Classify each CHANGED image (the ones with a diff) as exactly one of:
- "intended": the visual change looks like a deliberate result of this PR
  (e.g. copy/layout/styling that the PR set out to change).
- "regression": the change looks unintended and likely breaks the UI
  (e.g. broken layout, overlapping/cut-off text, missing elements, wrong colors
  where none were meant to change).
- "uncertain": you cannot tell from the images whether it is intended.

Be conservative: only mark "intended" when the change is coherent and plausible
for a deliberate edit. When unsure, use "uncertain".

PROMPT_HEADER

if [[ -n "$changed" ]]; then
  echo "CHANGED images to classify (compare ${BASE_DIR}/head vs ${BASE_DIR}/base, diff at ${BASE_DIR}/diff):"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "- ${BASE_DIR}/diff/${p}  (head: ${BASE_DIR}/head/${p} , base: ${BASE_DIR}/base/${p})"
  done <<<"$changed"
  echo
fi

if [[ -n "$added" ]]; then
  echo "ADDED images (present only on head — often the head side of a step-index shift):"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "- ${BASE_DIR}/head/${p}"
  done <<<"$added"
  echo
fi

if [[ -n "$removed" ]]; then
  echo "REMOVED images (present only on base — often the base side of a step-index shift):"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "- ${BASE_DIR}/base/${p}"
  done <<<"$removed"
  echo
fi

cat <<'PROMPT_FOOTER'
Return your answer as structured output matching the provided JSON schema:
an object with a top-level "results" array, one entry per CHANGED image, each with:
- "path": the relative image path (without the ./diff/ prefix).
- "classification": one of "intended", "regression", "uncertain".
- "summary": a one- or two-sentence explanation of what changed and why you
  classified it that way. If the change is part of a step-sequence shift, note it.
Also include a top-level "overall_summary" string: a short paragraph a reviewer
can read first, mentioning any likely step-sequence shifts.
PROMPT_FOOTER
