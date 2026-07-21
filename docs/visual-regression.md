# Reusable GitHub Actions workflow: AI-assisted visual regression testing

This is a reusable workflow, not a copy-paste recipe: capture screenshots on the PR base and
head branches in parallel, pixel-diff them with [reg-cli](https://github.com/reg-viz/reg-cli),
have Claude classify each changed image as intended, a likely regression, or uncertain, and
report the result as a PR comment and job summary. It never blocks the PR — a human makes the
final call.

This complements the [`docs/github-actions.md`](github-actions.md) recipe rather than
replacing it. That recipe only captures screenshots and uploads them for manual review; it
doesn't detect what changed, and it can't pick up a PR that only touches views (not the spec
files themselves). This workflow adds automatic change detection on top, and — via optional
Claude-driven target expansion — can also capture specs affected by a view-only PR that never
touches a spec file.

## Usage

Call it from a workflow in your application repository. Pin the `uses:` ref to one that
actually exists — the example below uses `@main`; a release tag such as `@v0.1.0`, or a
`@v1` major tag once one is published, work too (a ref that doesn't resolve fails with
"workflow was not found"):

```yaml
name: Visual regression

on:
  pull_request:

jobs:
  visual-regression:
    # A called workflow's token permissions are the intersection of what it
    # requests and what the caller grants, so grant pull-requests: write here —
    # otherwise the PR-comment step is denied (403) on repositories whose default
    # workflow token is read-only.
    permissions:
      contents: read
      pull-requests: write
    uses: aki77/capybara-storyboard/.github/workflows/visual-regression.yml@main
    with:
      ruby_version: "3.4"
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

### Inputs

| Input | Default | Description |
|---|---|---|
| `base_ref` | `${{ github.event.pull_request.base.ref }}` | Base ref to compare against (the expected side). |
| `ruby_version` | `"3.4"` | Ruby version passed to `ruby/setup-ruby`. |
| `node_version` | `"20"` | Node.js version for reg-cli (requires Node 20+). |
| `reg_threshold` | `"0"` | `reg-cli --thresholdRate` (0..1). Fraction of changed pixels tolerated before an image counts as changed. |
| `enable_claude` | `true` | Have Claude classify the changed diff images (intended / regression / uncertain). |
| `enable_claude_target_expansion` | `true` | Have Claude expand the target spec list from view-facing changes (view/template/component/CSS). |
| `model` | `""` | Model to pass to `claude-code-action` (via `--model`). Empty uses the action default. |
| `spec_paths` | `"system,components"` | Comma-separated spec subdirectories under `spec/` to capture (e.g. `system,components`). |

### Secrets

| Secret | Required | Description |
|---|---|---|
| `anthropic_api_key` | No | Anthropic API key for `claude-code-action`. Only needed when Claude features are enabled. |

## How it works

The workflow runs four jobs:

1. **targets** — diffs `base_ref` against head to find changed spec files under `spec_paths`,
   optionally asks Claude to expand that list from view-facing changes elsewhere in the diff,
   and uploads the final list as an artifact.
2. **shoot-base** / **shoot-head** — each checks out its own ref, runs only the target specs
   with `SCREENSHOTS=1`, and uploads the resulting screenshots. Both depend only on `targets`,
   so **they run in parallel**.
3. **compare** — downloads both screenshot sets, pixel-diffs them with reg-cli, has Claude
   classify the changed images (when enabled), and posts a PR comment and job summary. This
   check never blocks the PR.

## Reading the artifacts

The compare job uploads two artifacts:

- **`vr-flagged`** — only the diff images Claude classified as `regression` or `uncertain`,
  uploaded uncompressed so the Actions UI can preview each PNG natively. Start here: it's
  the small set of images that actually need a human look.
- **`vr-full`** — `report.html`, `reg.json`, and the full `diff` image set, as a normal zip.
  Download and open `report.html` locally for the complete reg-cli report, or to inspect a
  diff image that wasn't flagged. The base and head screenshots themselves are the separate
  **`vr-shots-base`** / **`vr-shots-head`** artifacts.

## Notes

- Set `enable_claude: false` to disable Claude classification entirely (reg-cli diffing still
  runs); `anthropic_api_key` is not required in that case.
- Claude's target-list expansion starts only from view-facing changes (views, templates,
  components, CSS) — never from model/migration changes, which usually don't affect rendered
  output and would cause over-selection.
- A large batch of "added"/"deleted" images clustered under one example usually means a
  Capybara step was inserted or removed in that example, shifting every later step's `NNN`
  sequence number — not many independent regressions.
- Diff images are linked via artifact URLs rather than embedded in the PR comment, because
  GitHub's Markdown image embedding requires a URL its camo proxy can fetch unauthenticated,
  and artifact URLs require authentication.
- If a target spec fails on either branch, the shoot job goes red and the compare job is
  skipped, so no diff report is produced. Fix the failing spec first — the workflow does not
  diff against a partial screenshot set. ("Never blocks the PR" refers to the compare job not
  failing the check once it runs, not to tolerating a broken spec run.)
