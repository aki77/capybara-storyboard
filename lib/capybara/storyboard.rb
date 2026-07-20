# frozen_string_literal: true

require 'fileutils'
require 'pathname'

require_relative 'storyboard/version'

module Capybara
  # Automatic Capybara screenshots for RSpec system specs, gated by a
  # replaceable policy (see Capybara::Storyboard.policy).
  module Storyboard
    class Error < StandardError; end

    class << self
      # The single Configuration holding user overrides (output root, policy).
      def configuration
        @configuration ||= Configuration.new
      end

      # Yields the Configuration for block-style setup:
      #   Capybara::Storyboard.configure { |config| config.output_dir = ... }
      def configure
        yield(configuration)
      end

      # Drops every override (output_dir and policy) in one shot, restoring the
      # gem's defaults. Handy in `after` hooks so a customized run never leaks
      # into later examples.
      def reset_configuration!
        @configuration = nil
      end

      # Test-hygiene helper mirroring reset_configuration! / reset_policy!:
      # clears the run-once flag so clear_output! can be exercised again
      # within the same process (a real run never needs this).
      def reset_output_cleared!
        @output_cleared = nil
      end

      # Empties the output root once per process so a run's screenshots never mix
      # with stale files left by a previous run. Meant to be wired into a
      # before(:suite) hook by the host app (see the README); not called
      # automatically, so nothing is registered on RSpec just by requiring the gem.
      def clear_output!
        # Run-once guard: idempotent even if the before(:suite) hook fires more
        # than once (e.g. one hook per RSpec process under parallel_tests).
        return if @output_cleared

        # Arm gate: same bare-SCREENSHOTS probe as default_policy's own gate
        # (EnvPolicy ignores its argument, so call(nil) is context-free). We
        # deliberately do NOT use configuration.policy here: a custom policy
        # assumes a per-example Context and may read the target list (raising
        # when SCREENSHOT_TESTS_FILE is bad). A suite-wide clear must key off
        # the global arm state alone, never per-example data.
        return unless Policies::EnvPolicy.new.call(nil)

        # Honor the run-once contract BEFORE touching the filesystem: if the
        # delete fails, we must not keep retrying (and re-deleting) on later
        # registrations of the same hook.
        @output_cleared = true

        # Resolve the root against the shared base so a relative output_dir
        # (kept relative by Configuration) maps to a single absolute target.
        root = configuration.output_dir.expand_path(rails_root_or_pwd)
        return unless safe_to_clear?(root)
        # First run / nothing captured yet: silently skip. Session#ensure_dir!
        # lazily recreates the tree on the first capture, so a missing root is
        # not an error.
        return unless root.exist?

        FileUtils.rm_rf(root)
      end

      # An object responding to #call(context) -> Boolean.
      # Assign nil (or call reset_policy!) to restore the default.
      # Delegated to the Configuration so there is a single source of truth.
      def policy
        configuration.policy
      end

      def policy=(value)
        configuration.policy = value
      end

      # Equivalent to `self.policy = nil`; named for readable `after` hooks that
      # prevent a custom policy from leaking into later examples.
      def reset_policy!
        configuration.reset_policy!
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

      # The single place that builds the default policy. Internal API, public
      # only so Configuration#policy can call it without `send`; use `policy`.
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
        # env.call(nil) probes the bare SCREENSHOTS switch (same gate
        # clear_output! uses), inlined here so we can reuse this exact `env`
        # instance as the return value below instead of building a second one.
        # Disarmed -> skip reading/validating the target list entirely.
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

      private

      # Minimal foot-gun guard for the suite-wide clear: refuse the obviously
      # dangerous roots (a filesystem root, or the project/cwd root itself)
      # rather than rm_rf-ing them. Mirrors the "safe no-op + warn" convention
      # used elsewhere (see Session#save_screenshot_safely); we deliberately
      # stop at these two cases rather than attempting broad path sanitizing.
      def safe_to_clear?(root)
        if root.parent == root || root == rails_root_or_pwd
          warn("capybara-storyboard: refusing to clear unsafe output root: #{root}")
          return false
        end

        true
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
require_relative 'storyboard/configuration'
require_relative 'storyboard/page_stability'
require_relative 'storyboard/session'
require_relative 'storyboard/test_helper'
