#!/usr/bin/env bash
#
# Filter a target spec list down to the specs that exist on the currently
# checked-out ref. A spec added in the PR is absent on the base ref; passing it
# to rspec there would raise a LoadError. Such a spec simply has no base
# screenshot — reg-cli reports it as a new item. Because the head and base refs
# are checked out one after the other in the same workspace, this filter is
# re-run per ref (the same input list yields different results per checkout).
#
# Usage:
#   filter-existing-targets.sh <targets.txt> <existing_targets.txt>
#
set -euo pipefail

TARGETS="${1:?usage: filter-existing-targets.sh <targets.txt> <existing_targets.txt>}"
EXISTING="${2:?usage: filter-existing-targets.sh <targets.txt> <existing_targets.txt>}"

: > "$EXISTING"
while IFS= read -r spec; do
  [[ -z "$spec" ]] && continue
  if [[ -f "$spec" ]]; then
    echo "$spec" >> "$EXISTING"
  fi
done < "$TARGETS"
