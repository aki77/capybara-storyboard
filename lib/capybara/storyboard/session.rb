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
        @suppression_depth = 0
      end

      def enabled?
        @enabled
      end

      # Automatic screenshot for a DSL action. No-op unless enabled.
      def auto(page, action, detail = nil)
        return unless @enabled
        return if suppressed?

        label = [action, sanitize(detail)].compact_blank.join('_')
        capture_with_label(page, label)
      end

      # Manual screenshot hook. Like #auto, captured only when enabled. For an
      # unconditional screenshot, use Capybara's own save_screenshot. The page
      # is passed explicitly rather than held as state.
      def manual(page, label)
        return unless @enabled
        return if suppressed?

        capture_with_label(page, sanitize(label))
      end

      # Suppresses automatic/manual captures for the duration of the block. Used
      # to skip nested captures while a confirm/alert dialog is open, where a
      # screenshot or JS eval would raise UnexpectedAlertOpenError. A depth counter
      # (not a boolean) supports nesting; the ensure guarantees reset on exceptions.
      def suppress_captures
        @suppression_depth += 1
        yield
      ensure
        @suppression_depth -= 1
      end

      def suppressed?
        @suppression_depth.positive?
      end

      private

      def capture_with_label(page, label)
        ensure_dir!
        @index += 1
        filename = "#{format('%03d', @index)}_#{label}.png"
        wait_for_stable_page(page)
        save_screenshot_safely(page, @dir.join(filename))
      end

      # A screenshot is a side effect; an unexpected failure (e.g. a dialog left
      # open) must never break the test body. Mirrors PageStability's warn
      # convention. There is no expected non-JS-driver case here, so warn always.
      # (Named "safely" rather than +save_screenshot+ to avoid colliding with
      # Capybara's DSL debugger method, which RuboCop's Lint/Debugger flags.)
      def save_screenshot_safely(page, path)
        page.save_screenshot(path)
      rescue StandardError => e
        warn("capybara-storyboard: screenshot skipped after error: #{e.class}: #{e.message}")
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
        (@output_root || default_output_root).join(spec_relative_dir, example_name)
      end

      # The output root when none is injected: the configuration's output_dir
      # (default <base>/tmp/screenshots, overridable via Storyboard.configure).
      def default_output_root
        Capybara::Storyboard.configuration.output_dir
      end

      # Mirrors the spec file's location as the output directory tree, so
      # screenshots for spec/system/foo_spec.rb land under system/foo/. The
      # spec/ prefix and the _spec.rb (or .rb) suffix are dropped; each
      # remaining path segment is sanitized while the / separators are kept.
      def spec_relative_dir
        raw = @example.metadata[:file_path]
        return 'spec' if raw.blank?

        relative = Capybara::Storyboard.normalize_test_path(raw)
        segments = relative.split('/')
        segments.shift if segments.first == 'spec'
        segments[-1] = strip_spec_suffix(segments.last) if segments.any?

        sanitized = segments.map { |segment| sanitize(segment) }.reject(&:blank?)
        sanitized.empty? ? 'spec' : sanitized.join('/')
      end

      # Drops the trailing _spec.rb, falling back to a plain .rb, so a spec
      # basename becomes its bare name (hoge_spec.rb -> hoge, hoge.rb -> hoge).
      def strip_spec_suffix(basename)
        basename.sub(/_spec\.rb\z/, '').sub(/\.rb\z/, '')
      end

      def example_name
        name = sanitize(@example.description).truncate(80, omission: '')
        return name if name.present?

        fallback = sanitize(@example.full_description)
        fallback.present? ? fallback.truncate(80, omission: '') : 'example'
      end

      # \p{Word} (Unicode word characters) rather than \w (ASCII-only) so that
      # non-ASCII descriptions/labels (e.g. Japanese) are preserved in filenames
      # and directory names instead of collapsing to underscores.
      def sanitize(text)
        text.to_s.gsub(/[^\p{Word}-]/, '_').gsub(/_+/, '_').gsub(/\A_|_\z/, '')
      end
    end
  end
end
