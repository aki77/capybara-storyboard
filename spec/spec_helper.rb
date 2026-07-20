# frozen_string_literal: true

# The gem targets Rails apps where ActiveSupport is always loaded. Its code
# uses `present?` / `compact_blank` / `truncate`; pull in just those core
# extensions so the gem's own specs can exercise those paths.
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/enumerable'
require 'active_support/core_ext/string/filters'

require 'capybara/storyboard'

# Answers the page-stability JS hooks so capture never blocks: evaluate_script
# reports an already-stable page (0 animations, long-quiet DOM) and
# execute_script is a no-op. Mixed into fake page doubles across specs so the
# stub isn't duplicated.
module AlreadyStablePage
  def execute_script(*); end

  def evaluate_script(*)
    { 'runningAnimations' => 0, 'timeSinceLastMutation' => 10_000 }
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Saves and clears the three ENV vars that drive the default policy, restoring
# them afterwards, so a spec can exercise a known-empty environment without
# leaking into (or being perturbed by) the real shell.
RSpec.shared_context 'with cleared screenshot env' do
  around do |example|
    keys = %w[SCREENSHOTS SCREENSHOT_TESTS SCREENSHOT_TESTS_FILE]
    originals = ENV.values_at(*keys)
    keys.each { |key| ENV.delete(key) }
    begin
      example.run
    ensure
      keys.each_with_index { |key, i| ENV[key] = originals[i] }
    end
  end
end
