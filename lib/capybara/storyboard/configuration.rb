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
      DEFAULT_PAGE_STABILITY_INTERVAL = 0.5
      DEFAULT_PAGE_STABILITY_MAX_ATTEMPTS = 10
      DEFAULT_PAGE_STABILITY_EXCLUDED_ANIMATIONS = [].freeze

      # An object responding to #call(context) -> Boolean. Assign nil (or call
      # reset_policy!) to restore the default on the next read.
      attr_writer :policy

      # Assign nil to any of these to restore its default on the next read:
      #   page_stability_interval=            seconds between polls (default 0.5)
      #   page_stability_max_attempts=        poll count before warning (default 10)
      #   page_stability_excluded_animations= names to ignore (default [])
      attr_writer :page_stability_interval, :page_stability_max_attempts, :page_stability_excluded_animations

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

      # Seconds to wait between page-stability polls, and the same value the
      # DOM-quiet check must exceed. Returns the default (0.5) until overridden.
      def page_stability_interval
        @page_stability_interval || DEFAULT_PAGE_STABILITY_INTERVAL
      end

      # Maximum number of stability polls before giving up (and warning rather
      # than raising). Returns the default (10) until overridden.
      def page_stability_max_attempts
        @page_stability_max_attempts || DEFAULT_PAGE_STABILITY_MAX_ATTEMPTS
      end

      # Animation names ignored by the running-animation check (e.g. infinite
      # spinners). Returns the default (empty list) until overridden.
      def page_stability_excluded_animations
        @page_stability_excluded_animations || DEFAULT_PAGE_STABILITY_EXCLUDED_ANIMATIONS
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
