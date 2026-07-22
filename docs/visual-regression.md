# Composite GitHub Action: AI-assisted visual regression testing

This is a composite action, not a reusable workflow: drop it as a **single step** into a job
you already have that runs system specs (headless Chrome). It captures screenshots on the PR
head and its base ref, pixel-diffs them with [reg-cli](https://github.com/reg-viz/reg-cli),
has Claude classify each changed image as intended, a likely regression, or uncertain, and
reports the result as a PR comment and job summary. It never blocks the PR — a human makes the
final call.

This complements the [`docs/github-actions.md`](github-actions.md) recipe rather than
replacing it. That recipe only captures screenshots and uploads them for manual review; it
doesn't detect what changed, and it can't pick up a PR that only touches views (not the spec
files themselves). This action adds automatic change detection on top, and — via Claude-driven
target expansion — can also capture specs affected by a view-only PR that never touches a spec
file.

## Usage

Add it as a step inside your **existing** job — the one that already runs system specs. The
caller job is responsible for three things the action does not do on its own:

1. Checking out the PR head with `actions/checkout` using `fetch-depth: 0`, with the base
   branch fetched (the action diffs `origin/<base>...HEAD`, which needs that history).
2. Setting up **Ruby** (with `bundle install` already run) so `bundle exec rspec` works.
3. Having **Node.js 20+** on `PATH`, for `npx reg-cli`.

```yaml
name: Visual regression

on:
  pull_request:

jobs:
  system-specs:
    permissions:
      contents: read
      pull-requests: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Fetch base branch
        run: git fetch origin ${{ github.event.pull_request.base.ref }}

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true

      - uses: actions/setup-node@v4
        with:
          node-version: "20"

      # ... your existing system spec step(s) here ...

      - uses: aki77/capybara-storyboard/.github/actions/visual-regression@main
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          base_setup_command: |
            bundle install
            pnpm install
```

Pin the `uses:` ref to one that actually exists — the example above uses `@main`; a release
tag such as `@v0.1.0`, or a `@v1` major tag once one is published, work too (a ref that doesn't
resolve fails with "action was not found"). The job needs
`permissions: { contents: read, pull-requests: write }` for the sticky PR comment step; a
repository whose default workflow token is read-only would otherwise get a 403 there.

### Inputs

| Input | Default | Description |
|---|---|---|
| `reg_threshold` | `"0"` | `reg-cli --thresholdRate` (0..1). Fraction of changed pixels tolerated before an image counts as changed. |
| `enable_claude` | `"true"` | Have Claude classify the changed diff images (intended / regression / uncertain). When `"false"`, the pixel diff and report still run but no classification table is produced. This gates classification only; target expansion runs whenever credentials are set. |
| `spec_paths` | `"system,components"` | Comma-separated spec subdirectories under `spec/` to capture (e.g. `system,components`). |
| `base_setup_command` | `""` | Shell commands to run after checking out the base ref, to align dependencies with the base state (e.g. `bundle install`, `pnpm install`). Multiline is supported. Runs with `bash`. Skipped when empty. |
| `anthropic_api_key` | `""` | Anthropic API key for `claude-code-action`. Only used when a Claude feature runs and no OAuth token is set. |
| `claude_code_oauth_token` | `""` | Claude Code OAuth token for `claude-code-action`. Takes precedence over `anthropic_api_key` when set. |

### Authentication

If `claude_code_oauth_token` is set, it's used and `anthropic_api_key` is ignored. Otherwise
`anthropic_api_key` is used if set. If **neither** is set, Claude-driven features (target
expansion and diff classification) are skipped automatically — only the reg-cli pixel diff and
report run.

### Outputs

| Output | Description |
|---|---|
| `has_targets` | Whether any target specs were selected (`"true"`/`"false"`). |
| `total_count` | reg-cli total changed count (failed + new + deleted). `"0"` both when nothing changed and when no target specs were selected — check `has_targets` to tell those apart. |

## How it works

The action runs as a single job, sequentially:

1. **Extract targets** — diffs the base ref against head to find changed spec files under
   `spec_paths`.
2. **Expand targets (Claude)** — always attempted; automatically skipped when no credentials
   are set. Asks Claude to add specs affected by view-facing changes (views, templates,
   components, CSS) elsewhere in the diff, then merges the result into the target list.
3. **Capture screenshots (head)** — runs the target specs with `SCREENSHOTS=1` on the
   already-checked-out PR head, then moves the screenshots to `RUNNER_TEMP` (outside the git
   workspace) so they survive the base checkout below.
4. **Check out the base ref** — re-checks out the workspace at
   `github.event.pull_request.base.ref`, with `clean: false`.
5. **Run `base_setup_command`** (optional) — realigns dependencies with the base state, e.g.
   `bundle install` / `pnpm install`, when the input is non-empty.
6. **Capture screenshots (base)** — same as step 3, run against the base ref, then also moved
   to `RUNNER_TEMP`.
7. **Run reg-cli** — pixel-diffs the head and base screenshot sets.
8. **Classify diffs (Claude)** — when `enable_claude` is `"true"`, there's a nonzero diff count,
   and credentials are set, asks Claude to classify each changed image as `intended`,
   `regression`, or `uncertain`.
9. **Upload artifacts** and **post a sticky PR comment** with the report.

Head and base are shot **one after the other in the same job**, not in parallel — there's no
cross-job artifact hand-off to manage, at the cost of some wall-clock time.

Target expansion is pinned to `claude-haiku-4-5` (a light selection task); diff classification
is pinned to `claude-sonnet-5` (a heavier judgment task). Neither model is configurable by the
caller.

## Reading the artifacts

The action uploads two artifacts:

- **`vr-flagged`** — only the diff images Claude classified as `regression` or `uncertain`,
  uploaded uncompressed so the Actions UI can preview each PNG natively. Start here: it's
  the small set of images that actually need a human look.
- **`vr-full`** — `report.html`, `reg.json`, and the full `diff` image set, as a normal zip.
  Download and open `report.html` locally for the complete reg-cli report, or to inspect a
  diff image that wasn't flagged.

## Notes

- Set `enable_claude: "false"` to disable Claude classification entirely (reg-cli diffing still
  runs); `anthropic_api_key` / `claude_code_oauth_token` are not required in that case.
- Claude's target-list expansion starts only from view-facing changes (views, templates,
  components, CSS) — never from model/migration changes, which usually don't affect rendered
  output and would cause over-selection. It cannot be disabled independently; without any
  credentials set, it's simply skipped along with diff classification.
- A large batch of "added"/"deleted" images clustered under one example usually means a
  Capybara step was inserted or removed in that example, shifting every later step's `NNN`
  sequence number — not many independent regressions.
- Diff images are linked via artifact URLs rather than embedded in the PR comment, because
  GitHub's Markdown image embedding requires a URL its camo proxy can fetch unauthenticated,
  and artifact URLs require authentication.
- If a target spec exists on one ref but not the other (e.g. a spec added in the PR), it's
  simply skipped when capturing the ref where it doesn't exist — reg-cli reports it as a new
  or deleted item rather than the step failing.
- A failed reg-cli run or a failed Claude call never blocks the PR — it surfaces in the report
  (or as "no report produced") rather than failing the job. A **failing target spec is
  different**: the capture step fails, the job goes red, and no report is produced. Fix the
  failing spec first — the action does not diff or report against a partial, unreliable
  screenshot set. (A spec that exists on only one ref is not a failure; it's skipped on the ref
  where it's absent and reg-cli reports it as a new/deleted item, per the note above.)
