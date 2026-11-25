---
name: screenshot-compare
description: >-
  After changing UI (views, components, CSS) — or when asked to make such a
  change — capture before/after capybara-storyboard screenshots, diff them to
  confirm nothing unintended changed, and show the user the before and after
  side by side in a self-contained HTML page. Use when the user wants to see
  the visual effect of a change, e.g. "change this CSS" followed by comparing
  old and new screens, checking they look fine, and presenting the result as
  HTML. The agent picks how to obtain "before" (pre-capture, worktree, stash,
  or existing directories) based on the situation.
---

# Screenshot compare (before / after side-by-side HTML)

Capture capybara-storyboard screenshots for the "before" and "after" states of a UI change,
diff them with `reg-cli`, verify the result yourself, and then present everything to the user as
a single self-contained HTML page: for each screen, before / after / diff side by side, with
your verdict on each change.

How this differs from the neighboring skills:

- `visual-regression-test` is explicit-invocation only, always captures "before" in a worktree
  at a baseline ref, and opens reg-cli's own HTML report. This skill may fire automatically,
  chooses the cheapest safe way to get "before", and produces a before/after/diff page with the
  agent's verdicts attached.
- The plain `capybara-storyboard` review looks at a single snapshot of the current code ("does
  this look right now?"). This skill answers "what changed compared to before, and was it
  intended?" and shows the user the answer.

## Prerequisites (confirm before starting)

- capybara-storyboard is already set up (screenshots are captured with `SCREENSHOTS=1` and land
  under `tmp/screenshots/`). Setting it up is out of scope for this skill.
- `npx reg-cli` is available (no install needed), `ruby` is available (the HTML builder uses the
  standard library only), and the platform's `open` command exists (macOS).
- Bundled scripts live in `scripts/` next to this SKILL.md, so they work wherever the skill is
  installed. Commands run from the project root; in the commands below, `$SKILL_DIR` stands for
  the absolute path of this skill's base directory (the directory containing this SKILL.md) —
  substitute it, or set `SKILL_DIR` in the same shell call. Output goes under
  `tmp/screenshot-compare/`:

```
tmp/screenshot-compare/
  before/        screenshots before the change
  after/         screenshots after the change
  diff/          reg-cli diff images
  report.json    reg-cli result (failedItems / newItems / deletedItems / passedItems)
  report.html    reg-cli's own report (not shown to the user)
  notes.json     the agent's verdicts (written in step 7)
  compare.html   the final side-by-side page (built in step 8)
```

## Procedure

### 1. Identify the target specs

Narrow to the system specs that exercise the changed screen(s), the same way as the plain
`capybara-storyboard` review. Never run the entire suite.

- Search for specs that render the changed view/component (by name, controller action, or
  route). If the call sites are countable (roughly 10 or fewer), target those specs directly.
- For a shared layout or widely used partial/component, propose a small representative sample
  (roughly 3-6 specs across distinct contexts) and **confirm with the user** before running.
- If a system spec itself changed, that spec is the target.
- Record the exact `rspec` arguments: "before" and "after" must run the identical command.

### 2. Choose how to obtain "before"

Pick the method from the situation. Do not ask the user unless the situation is ambiguous.

| Situation | Method |
| --- | --- |
| Invoked before any edit (nothing changed yet, e.g. just asked to change some CSS) | **Pre-capture**: screenshot the current state, copy it to `before`, then edit and capture "after". No worktree or stash needed; the safest option. Recommended. |
| `before` and `after` directories already exist or were handed over (a CI `vr-shots` artifact, an earlier run) | **Existing directories**: skip capturing. Use them as they are (copy to `tmp/screenshot-compare/before` and `after` if needed) and go to step 6. |
| After editing, and the baseline is something other than HEAD (an explicit ref, or a clean tree compared against the base branch) | **Worktree only** (a stash cannot reproduce this). |
| After editing, comparing uncommitted changes only | **Worktree** by default. Use **stash** if the worktree does not boot in this project, or the change is small. |

For worktree and stash modes, the baseline is decided by `scripts/resolve-baseline.sh`
(priority: explicit ref argument, then HEAD when there are uncommitted changes, then the base
branch when the tree is clean; anything other than HEAD resolves to the merge-base with HEAD;
exit 2 means it can't be resolved, so abort). Pass the first argument only (an empty string if
none); if more were given, tell the user the rest were ignored. If the given ref can't be
resolved, tell the user and abort — never silently fall back to a different ref.

For pre-capture mode:

```bash
rm -rf tmp/screenshots
SCREENSHOTS=1 bundle exec rspec <target specs>
mkdir -p tmp/screenshot-compare && rm -rf tmp/screenshot-compare/before
cp -R tmp/screenshots tmp/screenshot-compare/before
```

Then make the edit, and continue with step 3.

### 3. Capture "after" (skip when using existing directories)

Run it against the main repo's working tree (with the change applied). Remove `tmp/screenshots`
first so stale images from earlier runs don't leak in.

```bash
rm -rf tmp/screenshots
SCREENSHOTS=1 bundle exec rspec <target specs>
mkdir -p tmp/screenshot-compare && rm -rf tmp/screenshot-compare/after
cp -R tmp/screenshots tmp/screenshot-compare/after
```

If the target spec **fails**, the capture may be incomplete. Report the failure (it is a
finding) and confirm with the user whether to use the partial capture.

In pre-capture mode, this is the capture that runs after the edit. In worktree and stash modes,
do this before step 4 so a failing spec is discovered before any worktree or stash is created.

### 4. Capture "before" (worktree or stash modes only)

#### 4a. Worktree

```bash
WT=.claude/worktrees/screenshot-compare-baseline
# Pass "" if no argument was given. Prints the starting ref/SHA to stdout on one line. Abort on exit 2.
BEFORE_REF=$("$SKILL_DIR"/scripts/resolve-baseline.sh "${BASELINE_ARG:-}")
git worktree add "$WT" "$BEFORE_REF"
( cd "$WT" && bundle exec rails runner 'exit 0' )
```

If the boot check fails, remove the worktree and stop:

```bash
git worktree remove --force "$WT"
```

Tell the user the worktree lacks the config files and dependencies that git ignores
(e.g. `config/database.yml`, installed gems/packages), and that they need automatic setup on
worktree creation — for example a `post-checkout` hook that copies those files and installs
dependencies, running only when `$1` is the all-zero SHA (i.e. a freshly created worktree). If
only uncommitted changes are being compared, offer the stash method instead.

If it boots, capture "before" and discard the worktree:

```bash
( cd "$WT" && SCREENSHOTS=1 bundle exec rspec <target specs> )
rm -rf tmp/screenshot-compare/before
cp -R "$WT/tmp/screenshots" tmp/screenshot-compare/before
git worktree remove --force "$WT"
```

The worktree shares the main repo's DB, so do not run other tests concurrently. An old baseline
may not match the current DB schema and fail to boot or run; that is an expected failure, so
suggest a baseline closer to HEAD.

#### 4b. Stash (take every safeguard below)

The stash stack is shared with other worktrees and sessions, so never use a bare `git stash` or
`git stash pop`. First make sure the output directory is ignored; otherwise `-u` would stash the
"after" capture itself, so do not use stash in that case:

```bash
git check-ignore -q tmp/screenshot-compare/after || echo "not ignored: do not use stash"
```

Stash with a unique tag and record the SHA:

```bash
TAG="screenshot-compare-$(date +%s)"
git stash push -u -m "$TAG"
STASH_SHA=$(git stash list --format='%H %gs' | grep -F "$TAG" | head -1 | cut -d' ' -f1)
```

If `STASH_SHA` is empty, no entry was created (there was nothing to stash), so stop. Otherwise
capture "before" on the now-clean tree:

```bash
rm -rf tmp/screenshots
SCREENSHOTS=1 bundle exec rspec <target specs>
rm -rf tmp/screenshot-compare/before
cp -R tmp/screenshots tmp/screenshot-compare/before
```

**Always** restore afterwards, whether or not the spec passed, and verify:

```bash
git stash apply "$STASH_SHA"
git status --short   # confirm the original changes are back
```

Only after verifying, re-find the entry's current position by tag and drop it:

```bash
git stash list --format='%gd %gs' | grep -F "$TAG"   # -> stash@{n}
git stash drop "stash@{n}"
```

### 5. Beware of built assets when changing CSS

Built assets (`app/assets/builds`, `public/assets`, etc.) are often gitignored, so a stash or
worktree does not roll them back to the old state, or they don't exist there at all. If a CSS
change should produce a diff but the diff is zero, suspect this first: rebuild the assets with
the project's own command (e.g. `bin/rails assets:precompile`, `yarn build:css`) and capture
again.

### 6. Diff with reg-cli

```bash
"$SKILL_DIR"/scripts/reg-diff.sh \
  tmp/screenshot-compare/after tmp/screenshot-compare/before tmp/screenshot-compare
```

- Argument order matters: **after (actual) first, before (expected) second, output directory
  third.**
- Exit codes: `0` no visual change, `1` diff detected (expected, **not an error**), `2`
  execution error (bad arguments / missing directory).
- Images present on only one side are reported as new/deleted. This happens when the change
  altered the spec's own steps, or when an ID in a query string (e.g. `/search?user_id=42`)
  shifted a filename. Record IDs in `visit` path segments are already normalized to `N` by the
  gem, so those are not a cause.

### 7. Verify the diffs and write `notes.json`

Read `tmp/screenshot-compare/report.json` (`failedItems`, `newItems`, `deletedItems`). For every
such image, actually read the diff image (`diff/**`) and the corresponding before/after PNGs
(`before/{Group}/{example}/{NNN_action}.png`), and judge each one:

- **intended**: the visual change matches what the code change was meant to do.
- **regression**: an unrelated screen shifted, or something broke — layout breakage, overflow,
  a shared partial/layout/CSS edit leaking into pages it shouldn't affect.
- **noise**: sub-pixel or anti-aliasing differences with no meaningful change. If noise
  dominates, mention reg-cli's `--threshold` / `--enableAntialias` options for a re-run.

Write the verdicts to `tmp/screenshot-compare/notes.json`. Keys are the same relative paths as
the items in `report.json`; passed images need no entry.

```json
{
  "summary": "Overall conclusion (optional)",
  "items": {
    "Group/example/003_after_click_on_Done.png": {
      "verdict": "intended | regression | noise",
      "comment": "Why"
    }
  }
}
```

### 8. Build the HTML, show it, and report

Build the page only after the verification in step 7, so the user never sees diffs you haven't
judged yet.

```bash
ruby "$SKILL_DIR"/scripts/build-html.rb --dir tmp/screenshot-compare \
  [--notes PATH] [--title TEXT] [--out PATH]
open tmp/screenshot-compare/compare.html
```

`--notes` defaults to `<dir>/notes.json` and `--out` to `<dir>/compare.html`. The page lays out
every image per spec/example in three columns (before / after / diff), badges changed / new /
deleted screens, shows each verdict and comment from `notes.json`, and collapses unchanged
screens (shown as a single image, since before and after are identical). Clicking an image
opens it at full size in an overlay (close it by clicking the backdrop, the × button, or Esc).
Images are embedded as base64 in a single HTML file, so it gets large with many images (the
script warns above 50 MB).

Then give a concise written report:

- How many screens changed / were added / were deleted (from `report.json`).
- For each meaningful change: which screen and your verdict.
- A clear conclusion: either "all changes are consistent with the intended edit," or "the
  following look like regressions: ...".
- How "before" was obtained (pre-capture / worktree with baseline / stash / existing
  directories).
- That the HTML is open in the browser for the user to check.

### 9. Output and cleanup

Leave `tmp/screenshot-compare/` in place — the user is looking at it. Only mention that it can be
removed when no longer needed:

```bash
rm -rf tmp/screenshot-compare tmp/screenshots
```

Check `git worktree list` for a stray `.claude/worktrees/screenshot-compare-baseline` and remove
it with `git worktree remove --force <path>`. If the stash method was used, confirm the entry was
dropped.
