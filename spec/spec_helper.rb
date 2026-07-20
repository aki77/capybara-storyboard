# frozen_string_literal: true

# The gem targets Rails apps where ActiveSupport is always loaded. Its code
# uses `present?` / `compact_blank` / `truncate`; pull in just those core
# extensions so the gem's own specs can exercise those paths.
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/enumerable'
require 'active_support/core_ext/string/filters'

require 'capybara/storyboard'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
