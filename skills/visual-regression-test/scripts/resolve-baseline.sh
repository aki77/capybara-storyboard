#!/usr/bin/env bash
# Resolve the starting ref for the "before" worktree according to a priority order.
#
# Priority:
#   1. <ref> argument given         -> use that ref as baseline
#   2. no argument & uncommitted changes present -> HEAD as baseline (current behavior)
#   3. no argument & clean tree     -> base branch as baseline
#
# If baseline is anything other than HEAD, the worktree starting point is
# merge-base <baseline> HEAD (equivalent to a three-dot diff).
# If it's HEAD, no merge-base is needed and "HEAD" is returned as-is.
#
# stdout : one line with the ref/SHA to pass to worktree add
# stderr : human-readable explanation of the resolution
# exit   : 0=resolved, 2=execution error

set -u

arg_ref=${1:-}

log() { echo "$@" >&2; }

# Check whether a ref actually exists (existence check only, no side effects)
ref_exists() { git rev-parse --verify --quiet "$1" >/dev/null; }

# Resolve the base branch (order follows github.com/aki77/claude-code-review as reference)
resolve_base_branch() {
  local cur cfg branch cand upstream sym
  cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  # 1. branch.<cur>.github-pr-base-branch
  #    NOTE: the value may be in "owner#repo#branch" form (VSCode GitHub PR extension).
  #          Extract the last '#' segment as the branch name and prefer origin/.
  #          The raw value can't be passed to rev-parse as-is.
  cfg=$(git config "branch.$cur.github-pr-base-branch" 2>/dev/null)
  if [ -n "$cfg" ]; then
    branch=${cfg##*#}
    for cand in "origin/$branch" "$branch" "$cfg"; do
      if ref_exists "$cand"; then echo "$cand"; return 0; fi
    done
  fi

  # 2. branch.<cur>.vscode-merge-base (e.g. origin/release-candidate; usable as-is)
  cfg=$(git config "branch.$cur.vscode-merge-base" 2>/dev/null)
  if [ -n "$cfg" ] && ref_exists "$cfg"; then
    echo "$cfg"; return 0
  fi

  # 3. @{upstream}
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
  if [ -n "$upstream" ]; then
    echo "$upstream"; return 0
  fi

  # 4. origin/HEAD (e.g. refs/remotes/origin/release-candidate)
  sym=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$sym" ]; then
    echo "${sym#refs/remotes/}"; return 0
  fi

  return 1
}

emit_mergebase() {
  local baseline=$1 mb
  if ! ref_exists "$baseline"; then
    log "error: baseline ref not found: $baseline"
    exit 2
  fi
  mb=$(git merge-base "$baseline" HEAD 2>/dev/null)
  if [ -z "$mb" ]; then
    log "error: no merge-base between $baseline and HEAD"
    exit 2
  fi
  log "baseline: '$baseline' -> merge-base $mb"
  echo "$mb"
}

# --- Priority resolution ---
if [ -n "$arg_ref" ]; then
  log "baseline mode: explicit ref '$arg_ref'"
  emit_mergebase "$arg_ref"
  exit 0
fi

if [ -n "$(git status --short)" ]; then
  log "baseline mode: uncommitted changes present -> HEAD"
  echo "HEAD"
  exit 0
fi

log "baseline mode: clean tree -> base branch"
base=$(resolve_base_branch) || { log "error: could not resolve base branch"; exit 2; }
log "resolved base branch: $base"
emit_mergebase "$base"
exit 0
