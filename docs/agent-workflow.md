# Agent workflow: visually verifying a storyboard

This is a procedure for an AI agent (Claude Code, or any agent that can read PNG files from
the filesystem) to visually verify the screenshots Capybara::Storyboard captures. It's a
rewrite of a former "screenshot-test" gist skill, adapted to diff-based target selection.

## Premise

Narrowing the captured tests to only the system specs touched by a change (for example, via
the diff-based recipe in [docs/github-actions.md](github-actions.md)) turns the screenshot set
into an ordered, small collection of only the screens related to that change. That's what
keeps the set a realistic size for an agent to read one image at a time — capturing every
system spec in the suite would produce hundreds of images, which is impractical to review this
way.

## Reading the output layout

Screenshots are written under:

```
tmp/screenshots/{GroupName}/{example_name}/{NNN_action_detail}.png
```

No extra conversion or preprocessing is needed — read this directory structure as-is:

- `{GroupName}/{example_name}` is one directory per test. Treat each directory as one unit of
  review.
- Within a directory, the filenames describe the actions that produced them, and the
  zero-padded `NNN` prefix preserves the order in which those actions happened during the
  test. Reading files in `NNN` order lets the agent follow, image by image, "what screen is
  this, right after which action" for the whole test.

## Steps

1. **Run the tests.** Either run the system specs locally with `SCREENSHOTS=1` and a target
   list (`SCREENSHOT_TESTS_FILE` or `SCREENSHOT_TESTS`, scoped to the specs relevant to the
   change), or download the screenshot artifact from CI if the storyboard was produced there.

2. **Enumerate the output PNGs per test.** For each `{GroupName}/{example_name}` directory,
   list its PNG files in `NNN` sequence order.

3. **Visually verify one image at a time.** For each image in order, check for layout
   breakage, unintended or leftover UI state, error screens, and anything else that looks
   wrong given the action the filename describes and the point it occurs at in the sequence.

4. **Report per test.** For each `{GroupName}/{example_name}` directory, report which test it
   is, and for any issue found: right after which action (by filename/sequence number) it
   appeared, and what was observed.

5. **Clean up.** Remove the local `tmp/screenshots/**` output once review is done, unless it's
   needed for later reference. When working from a CI artifact instead, there is nothing local
   to clean up — the artifact's own retention policy governs how long it stays available.
