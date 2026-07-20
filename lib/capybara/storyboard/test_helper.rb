# frozen_string_literal: true

require 'fileutils'

module Capybara
  module Storyboard
    # RSpec system-spec helper. Include AFTER Capybara::DSL so the overrides
    # below chain into the DSL via +super+. A per-test policy call decides
    # whether automatic screenshots are taken (see Capybara::Storyboard.policy).
    module TestHelper
      def self.included(base)
        base.class_eval { before { __storyboard_init } }
      end

      # Manual screenshot. Independent of the SCREENSHOTS gate.
      def screenshot(label)
        @__storyboard.capture(page, label)
      end

      def visit(path, ...)
        super.tap { @__storyboard.auto(page, 'visit', path) }
      end

      def click_on(locator = nil, ...)
        @__storyboard.auto(page, 'before_click_on', locator)
        super.tap { @__storyboard.auto(page, 'after_click_on', locator) }
      end

      def click_link(locator = nil, ...)
        @__storyboard.auto(page, 'before_click_link', locator)
        super.tap { @__storyboard.auto(page, 'after_click_link', locator) }
      end

      def click_button(locator = nil, ...)
        @__storyboard.auto(page, 'before_click_button', locator)
        super.tap { @__storyboard.auto(page, 'after_click_button', locator) }
      end

      def fill_in(locator, ...)
        super.tap { @__storyboard.auto(page, 'fill_in', locator) }
      end

      def select(value = nil, ...)
        super.tap { @__storyboard.auto(page, 'select', value) }
      end

      def check(locator, ...)
        super.tap { @__storyboard.auto(page, 'check', locator) }
      end

      def uncheck(locator, ...)
        super.tap { @__storyboard.auto(page, 'uncheck', locator) }
      end

      def choose(locator, ...)
        super.tap { @__storyboard.auto(page, 'choose', locator) }
      end

      def attach_file(locator, ...)
        super.tap { @__storyboard.auto(page, 'attach_file', locator) }
      end

      def accept_confirm(...)
        super.tap { @__storyboard.auto(page, 'accept_confirm') }
      end

      def accept_alert(...)
        super.tap { @__storyboard.auto(page, 'accept_alert') }
      end

      private

      def __storyboard_init
        example = RSpec.current_example
        @__storyboard = Capybara::Storyboard::Session.new(
          example:,
          enabled: Capybara::Storyboard.policy.call(__storyboard_context(example))
        )
      end

      # Derivation lives here so Context stays a plain value holder.
      def __storyboard_context(example)
        metadata = example.metadata
        described = metadata[:described_class]
        Capybara::Storyboard::Context.new(
          test_class_name: described.respond_to?(:name) ? described.name : nil,
          test_method_name: example.description,
          test_file: metadata[:file_path]
        )
      end
    end
  end
end
