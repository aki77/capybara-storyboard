# frozen_string_literal: true

require 'pathname'

require_relative 'storyboard/version'

module Capybara
  # Automatic Capybara screenshots for RSpec system specs, gated by a
  # replaceable policy (see Capybara::Storyboard.policy).
  module Storyboard
    class Error < StandardError; end

    class << self
      # An object responding to #call(context) -> Boolean.
      # Assign nil (or call reset_policy!) to restore the default.
      attr_writer :policy

      def policy
        @policy ||= default_policy
      end

      # Equivalent to `self.policy = nil`; named for readable `after` hooks that
      # prevent a custom policy from leaking into later examples.
      def reset_policy!
        @policy = nil
      end

      # Normalizes a test file path to a base-relative string so that target
      # list entries and Context#test_file compare equal regardless of leading
      # `./`, absolute vs relative form, or surrounding whitespace/newlines.
      # Shared by default_policy (list side) and TargetListPolicy#call
      # (context side) so both sides always agree on the canonical form.
      def normalize_test_path(path)
        base = rails_root_or_pwd
        Pathname(path.to_s.strip)
          .expand_path(base)
          .relative_path_from(base)
          .to_s
      end

      # The single place that resolves the base directory: Rails.root when
      # available (the gem stays Rails-optional), else the current directory.
      # Session#default_output_root joins its own subpath onto this.
      def rails_root_or_pwd
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root
        else
          Pathname(Dir.pwd)
        end
      end

      private

      # The single place that builds the default policy.
      #
      # When SCREENSHOTS is unset the mechanism is disarmed: return EnvPolicy
      # alone WITHOUT touching the target list. This honors the "disabled ->
      # nothing happens" contract even when SCREENSHOT_TESTS_FILE points at a
      # missing file (its existence check must not blow up a disarmed suite).
      #
      # When armed: no target list configured (neither ENV set) -> EnvPolicy
      # alone, preserving the gist's "SCREENSHOTS=1 captures everything". A
      # target list configured (even an empty file) -> EnvPolicy AND
      # TargetListPolicy; an empty set then means "explicitly zero targets".
      def default_policy
        env = Policies::EnvPolicy.new
        # EnvPolicy ignores its context, so call(nil) probes the SCREENSHOTS
        # gate. Disarmed -> skip reading/validating the target list entirely.
        return env unless env.call(nil)

        raw_targets = raw_target_list
        return env if raw_targets.nil?

        # Drop blank entries BEFORE normalizing: an empty string normalizes to
        # "." (the base dir), which is not blank and would leak into the set.
        targets = raw_targets.map { |path| path.to_s.strip }.compact_blank.map { |path| normalize_test_path(path) }
        target = Policies::TargetListPolicy.new(targets)

        # Composition style: a plain lambda. A proc responds to #call, so it
        # satisfies the #call(context) -> Boolean policy contract, and it can
        # still be replaced wholesale via #policy=.
        ->(context) { env.call(context) && target.call(context) }
      end

      # Returns the raw (un-normalized) target list, or nil when no target list
      # is configured at all. SCREENSHOT_TESTS_FILE and SCREENSHOT_TESTS are
      # unioned when both are present.
      def raw_target_list
        file_entries = raw_target_list_from_file
        inline_entries = raw_target_list_inline
        return nil if file_entries.nil? && inline_entries.nil?

        (file_entries || []) + (inline_entries || [])
      end

      # Reads SCREENSHOT_TESTS_FILE. Returns nil when unset/blank, raises when
      # the path is set but missing (a silent all/none capture would be worse
      # than a loud failure), otherwise the newline-split contents.
      def raw_target_list_from_file
        path = ENV.fetch('SCREENSHOT_TESTS_FILE', nil)
        return nil unless path.present?

        raise Error, "SCREENSHOT_TESTS_FILE does not exist: #{path}" unless File.exist?(path)

        File.read(path).split("\n")
      end

      # Reads SCREENSHOT_TESTS. Returns nil when unset/blank, otherwise the
      # comma-split entries.
      def raw_target_list_inline
        value = ENV.fetch('SCREENSHOT_TESTS', nil)
        return nil unless value.present?

        value.split(',')
      end
    end
  end
end

require_relative 'storyboard/context'
require_relative 'storyboard/policies/env_policy'
require_relative 'storyboard/policies/target_list_policy'
require_relative 'storyboard/session'
require_relative 'storyboard/test_helper'
