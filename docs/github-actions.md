# GitHub Actions recipe: capture screenshots on a diff basis

Capybara::Storyboard only receives a target set — it does not know how to compute one. This
recipe shows the CI side of that split: diff against the PR base branch, extract the changed
system spec files, write them to a file, and pass that file in via `SCREENSHOT_TESTS_FILE`.

For how enabling and target-list selection actually behave inside the gem, see the README's
[Enabling screenshots](../README.md#enabling-screenshots) and
[Selecting which tests to capture](../README.md#selecting-which-tests-to-capture) sections —
this document does not repeat that reference material.

## Workflow

```yaml
name: Screenshot storyboard

on:
  pull_request:

jobs:
  storyboard:
    runs-on: ubuntu-latest
    steps:
      - name: Check out code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Fetch base branch
        run: git fetch origin "${{ github.event.pull_request.base.ref }}"

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Extract changed system spec files
        run: |
          mkdir -p tmp
          git diff --name-only --diff-filter=d \
            "origin/${{ github.event.pull_request.base.ref }}...HEAD" \
            | grep -E '^spec/system/.*_spec\.rb$' \
            > tmp/screenshot_targets.txt || true
          touch tmp/screenshot_targets.txt

      - name: Run system specs
        env:
          SCREENSHOTS: "1"
          SCREENSHOT_TESTS_FILE: tmp/screenshot_targets.txt
        run: bundle exec rspec spec/system

      - name: Upload screenshots
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: storyboard-screenshots
          path: tmp/screenshots/**
          if-no-files-found: ignore
```

Notes on the steps above:

- `fetch-depth: 0` on checkout, plus explicitly fetching the base branch, ensures the
  three-dot diff (`origin/<base>...HEAD`) has both sides of history available. A shallow
  checkout without fetching the base ref will fail or produce an incomplete diff.
- The extraction step pipes through `grep -E` and always ends with `touch
  tmp/screenshot_targets.txt`. `grep` exits non-zero when there are no matches, so `|| true`
  keeps the step from failing, and the trailing `touch` guarantees the file exists — empty if
  nothing matched. This is required: see the notes below on why the file must always be
  created.
- The run step passes `SCREENSHOTS=1` and `SCREENSHOT_TESTS_FILE=tmp/screenshot_targets.txt`
  as env for that step only, scoping the target list to this job.
- The upload step uses `if: always()` so screenshots are attached even if a spec fails
  partway through, and `if-no-files-found: ignore` so an empty target list (and therefore no
  screenshots) doesn't fail the upload step.

## Notes

- **View-only PRs are not picked up.** This recipe selects targets by matching test file
  paths in the diff. A PR that only changes views or other application code — leaving the
  system spec file itself untouched — will not add anything to
  `tmp/screenshot_targets.txt`, because the spec file never appears in the diff. This is a
  known, deliberate limitation of the initial version; see the README's
  [Caveats and limitations](../README.md#caveats-and-limitations).
- **An empty target file producing zero screenshots is correct, not a bug.** When no changed
  file matches `spec/system/.*_spec\.rb`, `tmp/screenshot_targets.txt` is empty, the target
  list narrows down to nothing, and zero screenshots are taken. That's the narrowing working
  as intended — it is not the same as omitting `SCREENSHOT_TESTS_FILE` entirely, which instead
  captures every system spec.
- **A missing file fails the job loudly.** If the extraction step were to fail in a way that
  leaves `SCREENSHOT_TESTS_FILE` pointing at a path that doesn't exist, the run raises
  `Capybara::Storyboard::Error` instead of silently capturing everything or nothing. This
  detection only happens in a job that also passes `SCREENSHOTS=1` — a job without it never
  reads the target list at all. This is exactly why the extraction step above always creates
  the file (empty when there are no matches) rather than skipping the write on no matches.
