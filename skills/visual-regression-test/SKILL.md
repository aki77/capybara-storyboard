---
name: visual-regression-test
disable-model-invocation: true
description: >-
  Compare before/after UI changes (views, components, CSS, system specs)
  using capybara-storyboard screenshots and reg-cli image diffing, to catch
  unintended visual regressions. The comparison baseline is determined
  automatically from an optional ref argument, the presence of uncommitted
  changes, and the base branch. Invoke explicitly with
  /visual-regression-test [ref].
---

# Visual regression test (before / after screenshot diff)

Catch unintended visual changes introduced by uncommitted edits. Capture capybara-storyboard
screenshots **twice** — once against the main repo's working tree ("after"), and once against a
separate worktree checked out at a baseline ref (HEAD, an explicit ref, or the merge-base with
the base branch — "before") — then diff the two image sets with `reg-cli`. The output is an HTML
report that highlights which screens changed, so both the agent and the user can confirm whether
each change was intentional.

This differs from "reviewing a screenshot of the current code as-is." A single-snapshot review
answers "does this screen look right right now?" This skill answers "which screens changed
compared to before my edit, and was that change intentional?" The latter is what actually catches
regressions caused by editing a shared partial or layout or CSS. If there's no baseline to compare
against and the user just wants to look at the current UI, that's the territory of the plain
`capybara-storyboard` screenshot review, not this skill.

Because the "before" capture runs in a separate worktree, it never touches the user's original
working tree. There's no stash-and-restore step, and therefore no structural risk of losing the
user's uncommitted work by failing to restore it.

## Prerequisites (confirm before starting)

This skill assumes capybara-storyboard is already set up (screenshots are captured with
`SCREENSHOTS=1` and land under `tmp/screenshots/`). Setting it up is out of scope for this skill.

- **You must be able to determine what to compare against (the baseline).** Baseline resolution
  is delegated to `scripts/resolve-baseline.sh` (see "Determining the baseline" below and step
  3a). If a ref argument was passed, that ref is always the baseline; with no argument and
  uncommitted changes present, HEAD is the baseline; with no argument and a clean tree, the base
  branch is the baseline. So "the tree is clean" is not itself a reason to abort — no-argument
  plus clean proceeds to a comparison against the base branch (effectively a three-dot diff
  against the merge-base). Only abort when the baseline genuinely can't be resolved
  (`resolve-baseline.sh` exits 2).
- **reg-cli** runs via `npx reg-cli` (no install needed). Open the report with the platform's
  `open` command (macOS).

## Determining the baseline (the "before" worktree's starting ref)

"After" is always the main repo's working tree as-is (including any uncommitted changes — the
after side is never turned into a worktree). Only the ref that the "before" worktree is checked
out at is decided, using this priority:

1. A ref/branch was passed as an argument → use that ref (regardless of uncommitted changes).
2. No argument, and uncommitted changes exist (`git status --short` is non-empty) → HEAD (the
   original behavior).
3. No argument, and the tree is clean → the base branch.

When the baseline is anything other than HEAD (case 1 or 3), the worktree's actual starting point
is `git merge-base <baseline> HEAD` (a three-dot diff). For HEAD, no merge-base step is needed —
use HEAD directly. This logic is centralized in the bundled `scripts/resolve-baseline.sh` (it
prints the starting ref to stdout on one line, and exits 2 if it can't be resolved). Resolving the
base branch itself is also handled by that script (roughly in the order
`github-pr-base-branch` → `vscode-merge-base` → `@{upstream}` → `origin/HEAD`; see
`resolve-baseline.sh` for the exact order and how each source is handled).

### Interpreting the argument

Treat the first argument to `/visual-regression-test [ref]` as the baseline ref (any git ref: a
branch name, tag, SHA, `origin/foo`, etc.). Pass it through as the first argument to
`resolve-baseline.sh` (pass an empty string if no argument was given).

- No argument → baseline is determined automatically (uncommitted changes present = HEAD; clean
  = base branch).
- One argument → that ref is fixed as the baseline.
- Two or more arguments → use only the first as the baseline, and briefly tell the user the rest
  were ignored (this skill only supports a single baseline comparison; the range's starting point
  is computed automatically via merge-base, so there's no need to accept both a start and an end).
- If the given ref can't be resolved, `resolve-baseline.sh` stops with exit 2. Tell the user that
  ref doesn't exist and abort (don't silently fall back to a different ref — respect the explicit
  choice).

## Procedure

### 1. Identify the target specs

Reuse the same target-selection logic as the plain `capybara-storyboard` review, narrowing to the
system specs that exercise the changed screen(s). Never run the entire suite twice — it's very
slow, and produces far too large a diff to read.

- If `app/views`, `app/components`, or CSS changed, find the system specs that render that
  screen (search by view/component name, controller action, or route). If the call sites are
  countable (roughly 10 or fewer), target those specs directly.
- If the change is to a layout or a widely shared partial/component, and the search above would
  return most of the suite, don't enumerate every caller. Instead propose a small representative
  sample (roughly 3-6 specs spanning distinct contexts: a signed-out screen, a standard
  authenticated page, an admin/dense-UI page, a narrow-viewport spec if one exists), and **confirm
  with the user** before running.
- If a system spec itself changed, that spec is the target. Note that if the diff changes the
  spec's own steps, the before/after screenshot sequences won't correspond 1:1 — reg-cli will
  report these as added/removed images, which is expected in this case.
- If only a single example in a file is relevant, it's fine to scope down to that example (`-e` or
  a line number).

Record the exact `rspec` target arguments (files and/or line numbers), since the same command runs
twice and both runs must match.

Note that the target spec may not exist, or may differ, at the baseline ref (resolved as the
"before" starting point in step 3a). In no-argument mode with uncommitted changes (baseline=HEAD),
this only applies to newly added specs. In ref-specified or base-branch-comparison mode, the
target spec itself might be absent from the baseline, or have a different signature
(describe/example names). Handle that per step 3c and the "images present on only one side are
new/deleted" note in step 4. For target selection itself, just use the after side (the main repo's
working tree) as the reference.

This target argument works as-is in both the main repo and the worktree described below (the
worktree is a full checkout of the baseline ref, so its path layout matches the main repo).
However, if the target includes a spec file that doesn't exist at the baseline ref (a newly added
spec, or one not yet present when comparing against a base branch), the worktree run will either
fail to load it or produce an empty "before" set with all images treated as new. This is expected,
not an error. In base-branch-comparison mode (no argument and clean, or an older explicit ref),
even when the target spec exists at the baseline its contents may differ, so the screenshot count
or naming may not match "after". reg-cli will report these as diffs/additions/deletions, which is
also expected.

### 2. Capture the "after" set (main repo's working tree)

Capture the after state (with the diff applied) first. This only touches the main repo, so you
can confirm the target specs actually pass before creating a worktree. If this fails, no worktree
is created and no work is wasted.

```bash
SCREENSHOTS=1 bundle exec rspec <target specs>
mkdir -p tmp/vrt && rm -rf tmp/vrt/after
cp -R tmp/screenshots tmp/vrt/after
```

If the target spec **fails**, the screenshot set may be incomplete. Report the failure (the
failure itself is a finding), and confirm with the user whether it's acceptable to use the partial
capture as the diff baseline.

### 3. Create a worktree at the baseline, verify it boots, and capture "before"

#### 3a. Resolve the baseline and create the worktree there

Determine the worktree's starting ref using the logic in "Determining the baseline". Pass the
argument received by this invocation (the baseline ref, or empty if none) straight through to
`resolve-baseline.sh`.

```bash
WT=.claude/worktrees/vrt-baseline
# Pass "" if no argument was given. Prints the starting ref/SHA to stdout on one line. Abort on exit 2.
BEFORE_REF=$(.claude/skills/visual-regression-test/scripts/resolve-baseline.sh "${BASELINE_ARG:-}")
git worktree add "$WT" "$BEFORE_REF"
```

`.claude/worktrees/` is an existing empty directory reserved for this skill's use.
`resolve-baseline.sh` writes the resolved mode (explicit / HEAD / base branch), and — when it's
not HEAD — the merge-base it applied, to **stderr**. Always mention what was used as the baseline
in the user-facing report (step 6) (e.g. "compared against the merge-base with the base branch
origin/release-candidate"), since it changes how the diff should be read.

When the starting point is something other than HEAD (an explicit ref or the base branch), the
worktree is a full checkout of that SHA/branch. Note that the diff shown as "after minus before"
then includes both the uncommitted changes in the after-side working tree *and* every commit
between that starting point and HEAD — not just the uncommitted diff, as it would be when the
baseline is HEAD.

#### 3b. Detect environment setup (important — this is what makes the skill portable)

Verify whether Rails actually boots inside the worktree by checking boot success itself, rather
than checking for the presence of any specific hook. Judging by "does it boot" rather than by
project-specific mechanics keeps this step portable to other projects.

```bash
( cd "$WT" && bundle exec rails runner 'exit 0' )
```

If it boots successfully, treat the config files and dependencies as present (either the
worktree's automatic setup handled it, or none was needed) and proceed to 3c.

If boot fails, abort. Tell the user "this worktree is missing config files/dependencies — you need
automatic setup on worktree creation (e.g. a post-checkout hook)," and point them at this
directory's `README.md` (the reference implementation for this skill). Then clean up the worktree
before finishing.

```bash
git worktree remove --force "$WT"
```

#### 3c. Capture "before" inside the worktree

Run the identical rspec command inside the worktree, and collect the results into the main repo's
`tmp/vrt/before`.

```bash
( cd "$WT" && SCREENSHOTS=1 bundle exec rspec <target specs> )
rm -rf tmp/vrt/before
cp -R "$WT/tmp/screenshots" tmp/vrt/before
```

Running inside a `( cd "$WT" && ... )` subshell keeps the main repo's current directory clean. If
the target spec fails, handle it the same way as "after" in step 2 (report the failure, and
confirm with the user whether to use the partial capture).

### 4. Discard the worktree and diff with reg-cli in the main repo

Once "before" is captured, the worktree is no longer needed — discard it, then diff in the main
repo.

```bash
git worktree remove --force "$WT"
.claude/skills/visual-regression-test/scripts/reg-diff.sh tmp/vrt/after tmp/vrt/before tmp/vrt
```

`--force` is used because any untracked `tmp/screenshots` left inside the worktree doesn't matter
by this point (it was already collected into `before` in step 3c) — just remove it.

The bundled helper (`reg-diff.sh`) is equivalent to:

```bash
npx reg-cli tmp/vrt/after tmp/vrt/before tmp/vrt/diff \
  --report tmp/vrt/report.html \
  --json tmp/vrt/report.json
```

- Argument order matters: **actual (after) first, expected (before) second, diff directory
  third.** Treating after as actual and before as expected frames the report as "what did my diff
  do relative to HEAD."
- Script exit codes: `0` for no visual change, `1` when a diff is detected (expected and
  **not an error** in this context), `2` for an execution error (bad arguments / missing input
  directory). `1` means "there's a diff, go verify it," not failure.
- Since both sets ran the same spec, filenames match across the two sets and reg-cli pairs them
  automatically by path. Images present on only one side are reported as added/deleted — this
  happens when the diff changed the spec's own steps.

### 5. Verify the detected diffs

Read `tmp/vrt/report.json` to get the list of changed/added/deleted images, and for each changed
screen, read the actual **diff image** (`tmp/vrt/diff/**`) along with the corresponding before/
after PNGs. Use the filename to determine which action/screen it belongs to
(`tmp/vrt/before/{Group}/{example}/{NNN_action}.png`). All paths are under the main repo's
`tmp/vrt`.

For each changed image, judge whether the visual change is **intentional**.

- Does the visual change match what the code diff was trying to do? (e.g. a color/spacing/label
  change the user made → expected.)
- Or did an unrelated screen shift — a shared partial/layout edit leaking into pages it shouldn't
  affect, broken layout, overflow, a rendering difference in a component? → report this as a
  regression.
- Minor sub-pixel/anti-aliasing noise with no meaningful change → note it as likely noise rather
  than a regression. If noise dominates, mention that reg-cli's threshold options
  (`--threshold`, `--enableAntialias`, etc.) can suppress it on a re-run.

### 6. Report, then open the HTML report for the user

Only open reg-cli's HTML report after finishing the verification in step 5. Opening it earlier
would show the user diffs the agent hasn't judged yet, breaking the "agent verifies first, then
presents results to the user" order.

```bash
open tmp/vrt/report.html
```

Then return a concise written report:

- How many screens changed/were added/were deleted (from `report.json`).
- For each meaningful change: which screen (spec + action/filename), and your judgment —
  **intentional** (matches the code change) or **possible regression** (what looks wrong and
  where).
- A clear conclusion: either "all detected changes are consistent with the intended edit," or
  "the following look like unintended regressions: ...".
- Mention that the HTML report is open in the browser so the user can check it themselves.

### 7. Output and cleanup

By step 4, the worktree is guaranteed to already be removed via `git worktree remove --force`
(the same applies if step 3b aborted — it's cleaned up before finishing there too). If for some
reason execution was interrupted and the worktree was left behind, check with
`git worktree list` for a stray `.claude/worktrees/vrt-baseline` and remove it with
`git worktree remove --force <path>`.

The worktree shares the same DB (`config/database.yml`) as the main repo. Don't run other tests
concurrently while this skill is executing (steps 2-4), since DB state can conflict.

When the baseline is a base branch or an older ref, that ref's Rails may be out of sync with the
current shared DB schema (migrations already applied in the main repo), causing the worktree's
boot check (step 3b) or rspec run to fail. This is an expected failure caused by an outdated
baseline, and the boot check is what catches it before it goes further. If this happens
frequently, suggest the user shift the baseline closer to HEAD (e.g. compare against uncommitted
changes only).

This skill's final step is "let the user see the HTML report," so **leave the report and the diff
images it references (`tmp/vrt/`) in place**. Deleting them here would pull the report out from
under the user while they're looking at it. Don't clean up on the agent's side.

Just mention that these can be removed once no longer needed (leave the decision of when to run
this to the user):

```bash
rm -rf tmp/vrt tmp/screenshots
```
