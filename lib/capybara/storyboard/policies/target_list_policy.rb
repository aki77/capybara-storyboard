# frozen_string_literal: true

module Capybara
  module Storyboard
    module Policies
      # Restricts screenshots to an explicit set of test files. The set holds
      # already-normalized paths (see Capybara::Storyboard.normalize_test_path);
      # #call normalizes the context's raw test_file the same way before matching.
      #
      # An empty set means "explicitly no targets" and always returns false. The
      # backward-compatible "capture everything" behavior is handled upstream by
      # default_policy, which simply never constructs this policy when no target
      # list is configured.
      class TargetListPolicy
        def initialize(paths)
          @paths = Set.new(paths)
        end

        def call(context)
          return false if @paths.empty?

          test_file = context&.test_file
          return false if test_file.nil?

          @paths.include?(Capybara::Storyboard.normalize_test_path(test_file))
        end
      end
    end
  end
end
