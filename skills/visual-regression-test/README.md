# About the visual-regression-test skill

Compares UI changes (views, components, CSS, system specs) before/after using
capybara-storyboard screenshots and `reg-cli` image diffing, to catch unintended
visual regressions. Invoked via `/visual-regression-test [ref]`.

- "After" screenshots are taken from the main repo's working tree (including
  uncommitted changes).
- "Before" screenshots are taken from a separate worktree
  (`.claude/worktrees/vrt-baseline`) checked out at the baseline ref (explicit
  argument, HEAD, or the base branch — see `scripts/resolve-baseline.sh` for
  details).
- The two image sets are diffed with `reg-cli` and rendered as an HTML report.
  The agent verifies whether each diff is intentional before reporting to the
  user.

See `SKILL.md` for the full procedure, baseline resolution logic, and target
spec selection. This README only covers the setup needed to pass step 3b
(the startup check inside the worktree).

## Setup on worktree creation

In `SKILL.md` step 3b, whether to proceed with capturing the "before" set is
decided solely by whether `bundle exec rails runner 'exit 0'` (or an
equivalent startup command) succeeds inside the worktree.

This **assumes the project is configured to automatically provision the
environment whenever `git worktree add` runs**. Gitignored config files (e.g.
DB connection settings, credentials) must be copied, and dependencies must be
installed, by the time the worktree is created — otherwise the startup check
fails.

How this is achieved doesn't matter. A common approach is a `post-checkout`
hook. Since `post-checkout` fires on both regular checkouts and
`git worktree add`, distinguish them using the `$1` argument (PREV_HEAD) Git
passes in: it's the all-zero SHA only for `git worktree add`. Also note that
if `core.hooksPath` isn't configured, `post-checkout` won't fire at all, even
from a custom hooks directory.

```sh
#!/bin/sh
# .githooks/post-checkout
[ "$1" = "0000000000000000000000000000000000000000" ] || exit 0  # worktree add only

main=$(realpath "$(git rev-parse --git-common-dir)/..")
copy_if_missing() {
  [ -f "$1" ] && return 0
  [ -f "$main/$1" ] || return 0
  mkdir -p "$(dirname "$1")"; cp "$main/$1" "$1"
}
copy_if_missing config/database.yml   # add any other required config files similarly

[ -d vendor/bundle ] || bundle install
[ -d node_modules ] || npm install
# if the DB is shared with the main repo, don't call db:prepare or similar
```

Which files to copy and which install commands to run varies per project.
Identify which gitignored files actually cause the startup command to fail
inside the worktree, and adapt accordingly.
