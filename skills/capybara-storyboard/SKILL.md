---
name: capybara-storyboard
description: Visually verify UI changes by running system specs with capybara-storyboard and reading the captured screenshot sequence. Use whenever app/views or app/components changes need a visual check, or when a system spec is changed and run.
model: sonnet
---

# Capybara Storyboard visual review

Capybara::Storyboard captures a Capybara operation (`visit`, `click_on`, ...) together with a
screenshot at each step of a system spec, and lays the screenshots out as an ordered sequence
per test. This skill drives an agent through generating and reading that sequence to catch
things a passing test can't: layout breakage, leftover UI state (a modal that didn't close, a
flash message still showing), error screens, or anything else that looks wrong for the action
and point in the test where it occurs.

Reviewing screenshots one image at a time only works if the set stays small — narrow to the
system specs actually touched by the change, not the whole suite. Capturing every system spec
would produce hundreds of images, which defeats the purpose.

## When this applies

- `app/views` or `app/components` were changed and the resulting screen needs a visual check.
- A system spec was changed and is being run.

## Steps

### 1. Determine the target specs

Narrow to the system specs relevant to the change:

- If `app/views` or `app/components` changed, identify which system specs exercise the changed
  screen(s) — search for the view/component name, the controller action, or the route it
  belongs to. Use this bullet whenever the call sites are countable: if you can enumerate all
  the places the changed view/component is used and there are roughly 10 or fewer, target those
  specific call sites directly — even if the changed file is itself called a shared "component".
  If more than one spec is a plausible match and it isn't obvious which apply, ask the user.
- If enumerating every call site is impractical, or the changed file is a layout or
  partial/component rendered by most/all pages rather than a handful of named places (so the
  search above would return most or all system specs, not a short list), don't try to enumerate
  every caller. Instead propose a small representative sample (roughly 3-6 specs) spanning
  distinct usage contexts where the change is most likely to visually clash — e.g. a signed-out
  page, a standard authenticated page, an admin/dense-UI page, a mobile/narrow-viewport spec if
  one exists — and confirm the sample with the user before running, since you can't be sure
  those spec files exist or still match without checking.
- If a system spec itself was changed, that spec is the target.

### 2. Run the specs and capture screenshots

Run the target specs locally with the enabling switch and a target list, so only the relevant
tests produce screenshots:

```bash
SCREENSHOTS=1 SCREENSHOT_TESTS=spec/system/login_spec.rb,spec/system/signup_spec.rb bundle exec rspec
```

For a larger list, write paths (one per line) to a file and use `SCREENSHOT_TESTS_FILE`
instead:

```bash
SCREENSHOTS=1 SCREENSHOT_TESTS_FILE=tmp/screenshot_targets.txt bundle exec rspec
```

Omitting both `SCREENSHOT_TESTS` and `SCREENSHOT_TESTS_FILE` while `SCREENSHOTS=1` is set
captures **every** system spec — avoid this unless the user explicitly wants a full-suite
review, since it produces an impractically large set of images to read one at a time.

### 3. Enumerate the output

Screenshots land at:

```
tmp/screenshots/{GroupName}/{example_name}/{NNN_action_detail}.png
```

Each `{GroupName}/{example_name}` directory is one system spec example — treat it as one unit
of review. Within a directory, list PNGs in ascending `NNN` order: that zero-padded prefix is
the order the actions happened during the test, and the rest of the filename names the action
(e.g. `001_visit_users.png`, `002_before_click_on_Done.png`,
`003_after_click_on_Done.png`). Click methods (`click_on`, `click_link`, `click_button`)
produce a before/after pair; everything else produces one screenshot taken after the action.

### 4. Read each image in sequence

For each `{GroupName}/{example_name}` directory, read its PNGs in `NNN` order, one at a time.
For each image, use the filename (the action) and its position in the sequence (what happened
right before it) to judge whether the screen looks right at that point — check for layout
breakage, unintended or leftover UI state, error pages, and anything else inconsistent with
the action just performed.

### 5. Report per test

For each `{GroupName}/{example_name}` directory report:

- Which test it is.
- For any issue found: which action/sequence number (by filename) it appeared right after,
  and what was observed.

A directory with no issues just needs a short confirmation — don't pad the report.

### 6. Clean up

Remove the local `tmp/screenshots/**` output once the review is done, unless the user wants it
kept for later reference.
