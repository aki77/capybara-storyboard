# frozen_string_literal: true

require 'json'

module Capybara
  module Storyboard
    # Waits for a page to become visually stable before a screenshot is taken:
    # no running CSS/JS animations (via document.getAnimations()) AND no DOM
    # mutations for at least +interval+ seconds (tracked by a MutationObserver).
    #
    # Ported from SonicGarden/wlb-morning-mail's capybara_screenshot_helper.rb.
    #
    # Stateless, so exposed as module functions. On a non-JS driver (Rack::Test)
    # or when the driver rejects the script, the whole thing is a safe no-op: a
    # failed wait must never prevent the screenshot itself from being taken.
    module PageStability
      # Reports the running-animation count and time since the last DOM mutation.
      # Static (no interpolation), so built once and reused on every poll.
      CHECK_SCRIPT = <<~JS
        (function() {
          const timeSinceLastMutation = Date.now() - window._lastMutationTime;
          const excludedAnimations = window._excludedAnimations ?? [];
          const animations = document.getAnimations();
          const runningAnimations = animations.filter(animation => {
            // getAnimations() keeps finished/paused animations attached to the
            // element until they are cancelled or the node is removed, so only
            // count the ones actually playing.
            if (animation.playState !== 'running') {
              return false;
            }
            if (animation instanceof CSSAnimation) {
              return !excludedAnimations.includes(animation.animationName);
            }
            return true;
          }).length;
          return { timeSinceLastMutation: timeSinceLastMutation, runningAnimations: runningAnimations };
        })();
      JS

      # Tears down the observer and its globals. Static, so built once and reused.
      CLEANUP_SCRIPT = <<~JS
        if (window._pageStabilityObserver) {
          window._pageStabilityObserver.disconnect();
          delete window._pageStabilityObserver;
          delete window._lastMutationTime;
          delete window._excludedAnimations;
        }
      JS

      module_function

      # Polls +page+ until stable or +max_attempts+ is reached. When the limit
      # is hit the page is deemed "good enough": a warning is printed to STDERR
      # and control returns normally (no exception), so capture proceeds.
      def wait_for_stable_page(page, interval:, max_attempts:, excluded_animations:)
        setup(page, excluded_animations)

        result = nil
        stable = false
        max_attempts.times do |attempt|
          result = check(page)
          stable = stable?(result, interval)
          break if stable

          # No point sleeping after the final check — nothing re-checks it.
          sleep(interval) unless attempt == max_attempts - 1
        end

        # Unstable (or max_attempts was 0): the page is deemed good enough.
        warn_unstable(result, interval) unless stable
      rescue StandardError => e
        # A failed wait must never prevent the screenshot from being taken, so
        # swallow every error and let capture proceed. Expected "this driver
        # can't run JS" errors (e.g. Rack::Test) are silent; anything else is
        # surfaced via warn so a real driver problem stays visible.
        warn("capybara-storyboard: page stability wait skipped after error: #{e.class}: #{e.message}") unless
          non_js_driver_error?(e)
        nil
      ensure
        cleanup(page)
      end

      def setup(page, excluded_animations)
        page.execute_script(<<~JS)
          window._lastMutationTime = Date.now();
          window._excludedAnimations = #{excluded_animations.to_json};
          window._pageStabilityObserver = new MutationObserver(() => {
            window._lastMutationTime = Date.now();
          });
          window._pageStabilityObserver.observe(document.body, {
            childList: true, subtree: true, attributes: true, characterData: true
          });
        JS
      end

      def check(page)
        page.evaluate_script(CHECK_SCRIPT)
      end

      # Best-effort teardown so no globals leak between screenshots. Runs from an
      # ensure block, so it must never raise even when setup never happened or
      # the driver can't run JS.
      def cleanup(page)
        page.execute_script(CLEANUP_SCRIPT)
      rescue StandardError
        nil
      end

      # evaluate_script returns string-keyed hashes on the real drivers; the
      # DOM-quiet window is measured in ms, so compare against interval * 1000.
      def stable?(result, interval)
        result['runningAnimations'].zero? && result['timeSinceLastMutation'] >= (interval * 1000)
      end

      # Warns using the last observed poll result (nil when max_attempts is 0),
      # so no extra JS round-trip is made and the reported numbers match the
      # values that actually failed the stability check.
      def warn_unstable(result, interval)
        warn(
          'capybara-storyboard: page did not become stable before the screenshot ' \
          "(runningAnimations=#{result && result['runningAnimations']}, " \
          "timeSinceLastMutation=#{result && result['timeSinceLastMutation']}ms, threshold=#{interval * 1000}ms)."
        )
      end

      # True when +error+ means "this driver can't run our JS" — the expected,
      # non-alarming case (e.g. Rack::Test) that should skip silently rather
      # than warn. Capybara is optional at load time (the gem's own specs don't
      # require it) and Selenium may be absent, so resolve each constant only
      # when defined; an undefined constant simply never matches.
      def non_js_driver_error?(error)
        return true if defined?(Capybara::NotSupportedByDriverError) &&
                       error.is_a?(Capybara::NotSupportedByDriverError)
        return true if defined?(Selenium::WebDriver::Error::JavascriptError) &&
                       error.is_a?(Selenium::WebDriver::Error::JavascriptError)

        false
      end
    end
  end
end
