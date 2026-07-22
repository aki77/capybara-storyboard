# Capybara::Storyboard

Capybara::Storyboard records the Capybara operations performed during your RSpec system
tests — `visit`, `click_on`, and more — together with a screenshot taken at each step, and
organizes them into an ordered "storyboard" per test. This lets you review the flow of a
system test at a glance, without re-running it or reading through the spec line by line.

## Requirements

- Ruby >= 3.4.0
- A Rails application with RSpec system specs. ActiveSupport is expected to already be
  loaded (the gem relies on core extensions such as `present?`); it is not declared as a
  gemspec dependency, since a Rails application loads it already.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add capybara-storyboard
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install capybara-storyboard
```

## Setup

Require the gem from `spec_helper.rb` or `rails_helper.rb`:

```ruby
require "capybara/storyboard"
```

Then include `Capybara::Storyboard::TestHelper` in your system specs via `RSpec.configure`,
and register a `before(:suite)` hook that clears stale screenshots from previous runs (see
[Clearing previous screenshots](#clearing-previous-screenshots)):

```ruby
RSpec.configure do |config|
  config.include Capybara::Storyboard::TestHelper, type: :system
  config.before(:suite) { Capybara::Storyboard.clear_output! }
end
```

`TestHelper` overrides Capybara DSL methods (`visit`, `click_on`, etc.) and chains into them
via `super`, so it must be included **after** `Capybara::DSL` has been included. In a normal
RSpec system spec setup, Capybara is already configured for `type: :system` examples, so
including `TestHelper` for the same `type: :system` examples (as shown above) works without
any extra ordering concerns.

## Usage

Once `TestHelper` is included, the Capybara DSL calls in your system specs are automatically
hooked, and — when enabled (see [Enabling screenshots](#enabling-screenshots)) — a screenshot
is captured before and/or after each call.

The following DSL methods are hooked: `visit`, `click_on`, `click_link`, `click_button`,
`fill_in`, `select`, `check`, `uncheck`, `choose`, `attach_file`, `accept_confirm`,
`accept_alert`.

- The click methods (`click_on`, `click_link`, `click_button`) capture **two** screenshots:
  one before and one after the operation.
- All other methods capture **one** screenshot, taken after the operation.

You can also take a screenshot manually at any point in a spec by calling
`storyboard_screenshot`:

```ruby
storyboard_screenshot("some label")
```

Manual screenshots taken via `storyboard_screenshot` obey the same enabling switch as the
automatic hooks: they are captured **only when the mechanism is enabled** (i.e. when the
policy — driven by `SCREENSHOTS` and the target list — evaluates to true), and are skipped
otherwise. If you need an unconditional screenshot regardless of that switch, use Capybara's
own `save_screenshot` instead.

Example:

```ruby
RSpec.describe "Login", type: :system do
  it "logs in successfully" do
    visit "/login"
    fill_in "Email", with: "user@example.com"
    fill_in "Password", with: "password"
    click_on "Log in"

    storyboard_screenshot("logged in")

    expect(page).to have_content("Welcome")
  end
end
```

## Enabling screenshots

Whether screenshots are captured at all is controlled by two independent layers: an
enabling switch (`SCREENSHOTS`), and, within that, an optional target list that narrows
which test files are captured.

| Case | `SCREENSHOTS` | Target list | Behavior |
|---|---|---|---|
| Disabled | unset | — | No screenshots. Hooks have effectively zero overhead. |
| Capture all (default) | `1` | unset (both ENV vars unset) | Screenshots for all system tests. |
| Selective capture | `1` | set via `SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` | Only the listed test files are captured. If the resulting set is empty, zero screenshots are taken (an empty selection does NOT fall back to capturing everything). |

In short: `SCREENSHOTS` arms the mechanism as a whole, and the target list — when present —
filters down which tests are captured within that armed mechanism. The target list affects
capture only, never test execution: RSpec still runs whatever you tell it to run (see
[Selecting which tests to capture](#selecting-which-tests-to-capture)).

## Selecting which tests to capture

When `SCREENSHOTS` is enabled, you can narrow capture to specific test files using either
(or both) of these environment variables:

| ENV var | Format | Purpose |
|---|---|---|
| `SCREENSHOT_TESTS_FILE` | Path to a file containing newline-separated test file paths | Primary channel. Suited for large lists / CI generation. |
| `SCREENSHOT_TESTS` | Comma-separated test file paths | Secondary. For a small number of manual paths. |

When both are set, the union of the two lists is used.

If `SCREENSHOT_TESTS_FILE` points to a file that does not exist, `Capybara::Storyboard::Error`
is raised. (This existence check only runs when `SCREENSHOTS` is enabled; when the mechanism
is disabled, the target list is never read.)

> [!IMPORTANT]
> The target list narrows **which tests are captured**, not **which tests are run**. RSpec
> still executes every test you pass to it; the listed files are merely the ones that get
> screenshots. To also avoid running the other tests — the usual goal in CI — pass the target
> files to `rspec` as arguments instead of (or in addition to) using the target list. See the
> examples below.

Examples:

```bash
# Inline list of test files (all system specs still RUN; only these two are CAPTURED)
SCREENSHOTS=1 SCREENSHOT_TESTS=spec/system/login_spec.rb,spec/system/signup_spec.rb bundle exec rspec

# List generated into a file (e.g. by CI, listing only changed specs)
SCREENSHOTS=1 SCREENSHOT_TESTS_FILE=tmp/screenshot_targets.txt bundle exec rspec

# Narrow both execution AND capture: pass the files to rspec as arguments.
# With SCREENSHOTS=1, every test that actually runs is captured, so no target list is needed.
SCREENSHOTS=1 bundle exec rspec $(cat tmp/screenshot_targets.txt)
```

## Output layout

Screenshots are written under:

```
tmp/screenshots/{spec_path}/{example_name}/{NNN_action_detail}.png
```

`{spec_path}` mirrors the spec file's own path, with the leading `spec/` segment and the
`_spec.rb` suffix removed. For example, `spec/system/signup_spec.rb` becomes
`system/signup/...`, and a nested spec such as `spec/system/admin/users_spec.rb` becomes
`system/admin/users/...`.

Each test gets its own directory, and a zero-padded sequence number (`NNN`) preserves the
order in which actions occurred. For example:

- Click methods capture two files: `001_before_click_on_Done.png`, `002_after_click_on_Done.png`
- Other methods capture one file: `001_visit_users.png`

Non-ASCII descriptions and labels (e.g. Japanese) are preserved as-is in file and directory
names; only symbols and whitespace are replaced with underscores.

The default output root is `<Rails.root>/tmp/screenshots` (overridable, see
[Configuration](#configuration)).

### Clearing previous screenshots

To avoid a run's screenshots mixing with stale files left behind by a previous
run, register `Capybara::Storyboard.clear_output!` in a `before(:suite)` hook (as
shown in [Setup](#setup)):

```ruby
RSpec.configure do |config|
  config.before(:suite) { Capybara::Storyboard.clear_output! }
end
```

When screenshots are enabled (`SCREENSHOTS` is set), this empties the output root
once at the start of the rspec run.

- When `SCREENSHOTS` is unset, `clear_output!` leaves the output root untouched
  (preserving the "disabled → nothing happens" contract), so the hook is safe to
  register unconditionally.
- `clear_output!` clears at most once per process, so registering the hook is
  idempotent even if it runs more than once.
- **With `parallel_tests`**: `before(:suite)` fires once per RSpec process, so
  each worker empties the shared output root at startup — the root is not cleared
  exactly once across all processes.

## Configuration

Use `Capybara::Storyboard.configure` to override the defaults:

```ruby
Capybara::Storyboard.configure do |config|
  config.output_dir = Rails.root.join("tmp", "my_screenshots")
  config.policy = ->(context) { ... } # or any object responding to #call(context) -> Boolean

  config.page_stability_interval = 0.5
  config.page_stability_max_attempts = 10
  config.page_stability_excluded_animations = []
end
```

- `config.output_dir`: overrides the output root directory. Defaults to
  `<Rails.root>/tmp/screenshots`.
- `config.policy`: overrides the policy that decides whether to capture. Must respond to
  `#call(context) -> Boolean` (a proc works too). Defaults to a policy composed from
  `SCREENSHOTS` and the target list, as described in
  [Enabling screenshots](#enabling-screenshots).

If you don't set `config.policy` explicitly, the default policy described above (driven by
`SCREENSHOTS` and the target list) is used.

### Page-stability wait

Just before each screenshot is captured, the gem waits for the page to become visually
stable — no running CSS/JS animations (via `document.getAnimations()`) and no DOM mutations
for a short quiet window (tracked by a `MutationObserver`) — so screenshots don't catch the
page mid-transition. The wait never blocks the screenshot itself: on a non-JS driver (e.g.
`Rack::Test`), or if anything goes wrong while waiting, it's a safe no-op and the screenshot
is still taken. The wait is tunable via:

- `config.page_stability_interval`: seconds between polls, and the required DOM-quiet window.
  Defaults to `0.5`.
- `config.page_stability_max_attempts`: maximum number of polls before giving up. On timeout
  the gem does not raise; it prints a warning to STDERR and captures the screenshot anyway.
  Defaults to `10`.
- `config.page_stability_excluded_animations`: an array of CSS animation names to ignore when
  deciding whether animations are still running (e.g. perpetual spinners). Defaults to `[]`.

## Caveats and limitations

- Test files are expected to be laid out flat as `spec/system/*_spec.rb`. Nested
  subdirectories may work but are not comprehensively verified in this initial version.
- The target-list selection matches on test file paths. A PR that changes only views
  (leaving the system spec file itself unchanged) cannot be picked up by the basic
  path-diff recipe in [docs/github-actions.md](docs/github-actions.md) — a known, deliberate
  limitation of that recipe. The [docs/visual-regression.md](docs/visual-regression.md)
  workflow lifts it via optional Claude-driven target expansion.

## Guides

- [docs/github-actions.md](docs/github-actions.md) — a recipe for capturing screenshots on a
  diff basis in GitHub Actions.
- [docs/visual-regression.md](docs/visual-regression.md) — a reusable GitHub Actions workflow
  for AI-assisted visual regression testing.
- [skills/capybara-storyboard](skills/capybara-storyboard) — an agent skill for visually
  verifying captured screenshots (Claude Code, or any agent that can read PNG files from the
  filesystem).
- [skills/visual-regression-test](skills/visual-regression-test) — an agent skill that
  compares before/after screenshots with `reg-cli` to catch unintended visual regressions,
  invoked via `/visual-regression-test [ref]` in Claude Code.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/aki77/capybara-storyboard. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/aki77/capybara-storyboard/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Capybara::Storyboard project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/aki77/capybara-storyboard/blob/main/CODE_OF_CONDUCT.md).

## Acknowledgments

The idea for this gem was inspired by [Giving Claude Code Eyes: Round Trip Screenshot Testing](https://medium.com/@rotbart/giving-claude-code-eyes-round-trip-screenshot-testing-ce52f7dcc563).
