# frozen_string_literal: true

require 'pathname'

module Capybara
  module Storyboard
    # Holds the user-overridable settings: where screenshots are rooted and
    # which policy decides whether to capture. Defaults are resolved lazily in
    # the getters so that merely constructing (or loading the gem) never reads
    # ENV or builds the default policy — that keeps the "disabled -> zero
    # overhead" contract intact.
    class Configuration
      # An object responding to #call(context) -> Boolean. Assign nil (or call
      # reset_policy!) to restore the default on the next read.
      attr_writer :policy

      # The output root under which Session appends <group>/<example>. Returns
      # the default (<base>/tmp/screenshots) until overridden.
      def output_dir
        @output_dir || default_output_dir
      end

      # Accepts nil (restore default) or any value coercible to a Pathname.
      # A non-nil value is stored as a Pathname because Session calls #join on
      # it; a relative path is kept as-is (resolved against the cwd, which is
      # Rails.root under normal use).
      def output_dir=(value)
        @output_dir = value.nil? ? nil : Pathname(value)
      end

      def policy
        @policy ||= Capybara::Storyboard.default_policy
      end

      # Equivalent to `self.policy = nil`; named for readable `after` hooks that
      # prevent a custom policy from leaking into later examples.
      def reset_policy!
        @policy = nil
      end

      private

      # Screenshots live under <base>/tmp/screenshots, where the base directory
      # (Rails.root or the cwd fallback) is resolved in one shared place.
      def default_output_dir
        Capybara::Storyboard.rails_root_or_pwd.join('tmp', 'screenshots')
      end
    end
  end
end
