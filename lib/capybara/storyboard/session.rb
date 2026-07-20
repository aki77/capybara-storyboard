# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module Capybara
  module Storyboard
    # Per-example state (sequence counter, output directory, enabled flag,
    # example metadata) plus filename / path / sanitize derivation.
    #
    # Extracting this state out of TestHelper keeps its unit tests independent
    # of Capybara and RSpec hooks: a Session can be built with a plain example
    # double and an injected +output_root+.
    class Session
      def initialize(example:, enabled:, output_root: nil)
        @example = example
        @enabled = enabled
        @output_root = output_root
        @index = 0
        @dir = nil
      end

      def enabled?
        @enabled
      end

      # Automatic screenshot for a DSL action. No-op unless enabled.
      def auto(page, action, detail = nil)
        return unless @enabled

        label = [action, sanitize(detail)].compact_blank.join('_')
        capture_with_label(page, label)
      end

      # Manual screenshot hook. Like #auto, captured only when enabled. For an
      # unconditional screenshot, use Capybara's own save_screenshot. The page
      # is passed explicitly rather than held as state.
      def manual(page, label)
        return unless @enabled

        capture_with_label(page, sanitize(label))
      end

      private

      def capture_with_label(page, label)
        ensure_dir!
        @index += 1
        filename = "#{format('%03d', @index)}_#{label}.png"
        wait_for_stable_page(page)
        page.save_screenshot(@dir.join(filename))
      end

      # Both callers (#auto / #manual) are already enabled-gated, so this always
      # runs before an actual capture and never on a disabled session.
      def wait_for_stable_page(page)
        config = Capybara::Storyboard.configuration
        PageStability.wait_for_stable_page(
          page,
          interval: config.page_stability_interval,
          max_attempts: config.page_stability_max_attempts,
          excluded_animations: config.page_stability_excluded_animations
        )
      end

      def ensure_dir!
        @dir ||= output_dir
        FileUtils.mkdir_p(@dir)
      end

      def output_dir
        (@output_root || default_output_root).join(group_name, example_name)
      end

      # The output root when none is injected: the configuration's output_dir
      # (default <base>/tmp/screenshots, overridable via Storyboard.configure).
      def default_output_root
        Capybara::Storyboard.configuration.output_dir
      end

      def group_name
        described_class = @example.metadata[:described_class]
        raw =
          if described_class.respond_to?(:name)
            described_class.name
          else
            top_level_group_description
          end
        sanitize(raw)
      end

      def example_name
        name = sanitize(@example.description).truncate(80, omission: '')
        return name if name.present?

        fallback = sanitize(@example.full_description)
        fallback.present? ? fallback.truncate(80, omission: '') : 'example'
      end

      def top_level_group_description
        group = @example.metadata[:example_group]
        group = group[:parent_example_group] while group && group[:parent_example_group]
        group && group[:description]
      end

      def sanitize(text)
        text.to_s.gsub(/[^\w-]/, '_').gsub(/_+/, '_').gsub(/\A_|_\z/, '')
      end
    end
  end
end
