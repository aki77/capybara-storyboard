#!/usr/bin/env bash
#
# Move the screenshots just captured under tmp/screenshots into a destination
# directory outside the git workspace, so a subsequent re-checkout of another
# ref cannot clobber them. Used once per side (head, base).
#
# Usage:
#   stash-screenshots.sh <destination-dir>
#
set -euo pipefail

DEST="${1:?usage: stash-screenshots.sh <destination-dir>}"

mkdir -p "$DEST"
if [[ -d tmp/screenshots ]]; then
  mv tmp/screenshots/* "$DEST/" 2>/dev/null || true
fi
