# frozen_string_literal: true

module Capybara
  module Storyboard
    module Policies
      # Arms the whole mechanism from ENV. Backward-compatible with the gist:
      # true iff SCREENSHOTS is set to a non-blank value. Ignores the context
      # entirely — the argument exists only to honor the call(context) contract.
      class EnvPolicy
        def call(_context)
          ENV['SCREENSHOTS'].present?
        end
      end
    end
  end
end
