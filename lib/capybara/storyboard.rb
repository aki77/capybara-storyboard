# frozen_string_literal: true

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

      private

      # The single place that builds the default policy. Phase 4 swaps the body
      # for "EnvPolicy AND TargetListPolicy" without touching #policy / #policy=.
      def default_policy
        Policies::EnvPolicy.new
      end
    end
  end
end

require_relative 'storyboard/context'
require_relative 'storyboard/policies/env_policy'
require_relative 'storyboard/session'
require_relative 'storyboard/test_helper'
