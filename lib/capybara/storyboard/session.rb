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

      # Manual screenshot. Always captured, independent of the enabled flag /
      # ENV. The page is passed explicitly rather than held as state.
      def capture(page, label)
        capture_with_label(page, sanitize(label))
      end

      private

      def capture_with_label(page, label)
        ensure_dir!
        @index += 1
        filename = "#{format('%03d', @index)}_#{label}.png"
        page.save_screenshot(@dir.join(filename))
      end

      def ensure_dir!
        @dir ||= output_dir
        FileUtils.mkdir_p(@dir)
      end

      def output_dir
        (@output_root || default_output_root).join(group_name, example_name)
      end

      # The single place that depends on Rails.root. Falls back to the current
      # working directory when Rails is not loaded.
      def default_output_root
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join('tmp', 'screenshots')
        else
          Pathname(Dir.pwd).join('tmp', 'screenshots')
        end
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
