# frozen_string_literal: true

module StoryboardPageStabilitySpecSupport
  # A fake JS harness page. execute_script records the scripts it received (used
  # to assert setup/cleanup happened and to inspect the embedded JSON), while
  # evaluate_script replays a canned queue of check results, string-keyed like a
  # real driver returns.
  class HarnessPage
    attr_reader :executed_scripts, :evaluate_calls

    def initialize(results)
      @results = results.dup
      @executed_scripts = []
      @evaluate_calls = 0
    end

    def execute_script(script)
      @executed_scripts << script
      nil
    end

    def evaluate_script(_script)
      @evaluate_calls += 1
      @results.shift
    end
  end

  def self.result(running:, elapsed:)
    { 'runningAnimations' => running, 'timeSinceLastMutation' => elapsed }
  end
end

RSpec.describe Capybara::Storyboard::PageStability do
  include StoryboardPageStabilitySpecSupport

  # Never sleep for real; polling loops finish instantly.
  before { allow(described_class).to receive(:sleep) }

  def wait(page, interval: 0.5, max_attempts: 10, excluded_animations: [])
    described_class.wait_for_stable_page(
      page,
      interval:,
      max_attempts:,
      excluded_animations:
    )
  end

  def result(running:, elapsed:)
    StoryboardPageStabilitySpecSupport.result(running:, elapsed:)
  end

  describe 'stable detection' do
    it 'returns as soon as animations are 0 and the DOM has been quiet long enough' do
      # interval 0.5s -> threshold 500ms; 600ms elapsed with 0 animations passes.
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [result(running: 0, elapsed: 600)]
      )

      wait(page, interval: 0.5)

      expect(page.evaluate_calls).to eq(1)
    end

    it 'does not poll again after the first stable result' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [result(running: 0, elapsed: 600), result(running: 0, elapsed: 600)]
      )

      wait(page)

      expect(page.evaluate_calls).to eq(1)
    end
  end

  describe 'polling continuation' do
    it 'keeps polling while animations are still running' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [
          result(running: 2, elapsed: 600),
          result(running: 1, elapsed: 600),
          result(running: 0, elapsed: 600),
        ]
      )

      wait(page)

      expect(page.evaluate_calls).to eq(3)
    end

    it 'keeps polling while the DOM was mutated too recently' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [
          result(running: 0, elapsed: 100),
          result(running: 0, elapsed: 300),
          result(running: 0, elapsed: 600),
        ]
      )

      wait(page, interval: 0.5)

      expect(page.evaluate_calls).to eq(3)
    end

    it 'sleeps between polls by the interval' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [result(running: 1, elapsed: 600), result(running: 0, elapsed: 600)]
      )

      wait(page, interval: 0.5)

      expect(described_class).to have_received(:sleep).with(0.5).once
    end
  end

  describe 'timeout behavior' do
    it 'warns to STDERR without raising when the page never stabilizes' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        Array.new(20) { result(running: 3, elapsed: 600) }
      )

      expect { wait(page, max_attempts: 3) }
        .to output(/did not become stable/).to_stderr
    end

    it 'does not raise on timeout' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        Array.new(20) { result(running: 3, elapsed: 600) }
      )

      expect { wait(page, max_attempts: 3) }.not_to raise_error
    end
  end

  describe 'non-numeric poll results (e.g. a page navigation mid-poll)' do
    # A page navigation between setup and a poll resets the measurement, so a
    # field comes back non-numeric. Two flavors reach Ruby depending on the
    # driver: Selenium serializes the reset NaN to JSON null (nil here), while
    # CDP drivers such as Cuprite/Ferrum decode it back into a literal
    # Float::NAN. Both mean "measurement lost". The Ruby loop recovers by
    # re-arming the observer (re-running setup, which re-injects the excluded
    # animations) so the next poll can measure again. These examples pin that
    # contract: a non-numeric field must never crash the poll loop (the
    # NoMethodError regression) and, for Float::NAN, must not be mistaken for a
    # real number that never settles; a later numeric poll must still be able to
    # settle; and detecting the reset must trigger a fresh setup.
    def setup_scripts(page)
      page.executed_scripts.select { |script| script.include?('MutationObserver') }
    end

    # Builds a "measurement lost" first poll by dropping the given field to a
    # non-numeric value; the other field stays a valid number.
    def lost_result(field, value)
      field == :elapsed ? result(running: 0, elapsed: value) : result(running: value, elapsed: 600)
    end

    # nil stands in for Selenium (JSON null); Float::NAN stands in for CDP
    # drivers (Cuprite/Ferrum) that decode the reset NaN back into a literal.
    [
      ['timeSinceLastMutation is nil', :elapsed, nil],
      ['runningAnimations is nil', :running, nil],
      ['timeSinceLastMutation is NaN', :elapsed, Float::NAN],
      ['runningAnimations is NaN', :running, Float::NAN],
    ].each do |description, lost_field, lost_value|
      it "keeps polling without raising when #{description}, then stabilizes on a later numeric poll" do
        page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
          [lost_result(lost_field, lost_value), result(running: 0, elapsed: 600)]
        )

        expect { wait(page, interval: 0.5) }.not_to raise_error
        expect(page.evaluate_calls).to eq(2)
      end

      it "re-arms the observer via setup when #{description}" do
        page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
          [lost_result(lost_field, lost_value), result(running: 0, elapsed: 600)]
        )

        wait(page, interval: 0.5)

        # Initial setup plus the re-arm triggered by the non-numeric poll.
        expect(setup_scripts(page).length).to be >= 2
      end
    end

    it 'does not raise and warns "did not become stable" when every poll stays non-numeric (regression for NoMethodError)' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        Array.new(20) { result(running: 0, elapsed: nil) }
      )

      expect { wait(page, max_attempts: 3) }.to output(/did not become stable/).to_stderr
    end

    it 'does not treat a Float::NAN poll as stable and never settles on it (CDP-driver regression)' do
      # NaN is Numeric, so a naive is_a?(Numeric) check would accept it; then
      # NaN.zero? is false and NaN >= threshold is false, so it would poll
      # forever without ever re-arming. Every poll here is NaN, so the loop must
      # exhaust max_attempts and warn rather than settle.
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        Array.new(20) { result(running: Float::NAN, elapsed: Float::NAN) }
      )

      expect { wait(page, max_attempts: 3) }.to output(/did not become stable/).to_stderr
    end
  end

  describe 'setup and cleanup' do
    it 'runs setup once and cleanup once on the stable path' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [result(running: 0, elapsed: 600)]
      )

      wait(page)

      # First execute_script is setup, last is cleanup.
      expect(page.executed_scripts.length).to eq(2)
      expect(page.executed_scripts.first).to include('MutationObserver')
      expect(page.executed_scripts.last).to include('disconnect')
    end

    it 'still cleans up (via ensure) on the timeout path' do
      # The loop consumes up to max_attempts results and warn reuses the last
      # one (no re-check); extra results are simply left unused.
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        Array.new(20) { result(running: 3, elapsed: 600) }
      )

      expect { wait(page, max_attempts: 2) }.to output.to_stderr

      expect(page.executed_scripts.last).to include('disconnect')
    end

    it 'embeds the excluded animations JSON in the setup script' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [result(running: 0, elapsed: 600)]
      )

      wait(page, excluded_animations: %w[spin pulse])

      expect(page.executed_scripts.first).to include('["spin","pulse"]')
    end
  end

  describe 'boundary values' do
    it 'warns and returns immediately when max_attempts is 0 (no polling)' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [result(running: 0, elapsed: 600)]
      )

      expect { wait(page, max_attempts: 0) }.to output(/did not become stable/).to_stderr
      # max_attempts 0 means the loop never runs, and warn no longer re-checks,
      # so no evaluate_script call is ever made.
      expect(page.evaluate_calls).to eq(0)
    end

    it 'stabilizes on the very last allowed attempt' do
      page = StoryboardPageStabilitySpecSupport::HarnessPage.new(
        [
          result(running: 1, elapsed: 600),
          result(running: 1, elapsed: 600),
          result(running: 0, elapsed: 600),
        ]
      )

      expect { wait(page, max_attempts: 3) }.not_to output.to_stderr
      expect(page.evaluate_calls).to eq(3)
    end
  end

  describe 'non-JS driver handling' do
    # The gem's specs don't require real Capybara, so provide the sentinel
    # constant the code rescues on for the duration of these examples.
    before { stub_const('Capybara::NotSupportedByDriverError', Class.new(StandardError)) }

    # A page whose script hooks raise the not-supported error, mimicking a
    # non-JS driver like Rack::Test. Built lazily so stub_const is in effect.
    def non_js_page
      klass =
        Class.new do
          def execute_script(_script)
            raise Capybara::NotSupportedByDriverError, 'no JS'
          end

          def evaluate_script(_script)
            raise Capybara::NotSupportedByDriverError, 'no JS'
          end
        end
      klass.new
    end

    it 'is a silent no-op and does not raise' do
      expect { wait(non_js_page) }.not_to raise_error
    end

    it 'does not propagate the driver error to STDERR as a crash' do
      expect { wait(non_js_page) }.not_to output(/did not become stable/).to_stderr
    end

    # non_js_driver_error? is true for this error, so it must be skipped
    # silently: no "skipped after error" warning either, not just no crash
    # message.
    it 'does not warn at all (fully silent skip)' do
      expect { wait(non_js_page) }.not_to output.to_stderr
    end
  end

  describe 'unexpected driver error handling' do
    # A page whose script hooks raise something other than a recognized
    # "this driver can't run JS" error — standing in for e.g. Cuprite/Ferrum
    # raising Ferrum::JavaScriptError, which the gem has no dependency on and
    # therefore cannot rescue by name. Built lazily per example.
    def unexpected_error_page(error_class)
      klass =
        Class.new do
          define_method(:execute_script) { |_script| raise error_class, 'boom' }
          define_method(:evaluate_script) { |_script| raise error_class, 'boom' }
        end
      klass.new
    end

    # A screenshot must never be blocked by a stability-wait crash, even for
    # errors the gem doesn't know how to classify as "expected".
    it 'does not propagate an unrecognized StandardError (screenshot must still proceed)' do
      page = unexpected_error_page(RuntimeError)

      expect { wait(page) }.not_to raise_error
    end

    it 'does not propagate a custom StandardError subclass (e.g. Ferrum::JavaScriptError stand-in)' do
      fake_ferrum_js_error = Class.new(StandardError)
      page = unexpected_error_page(fake_ferrum_js_error)

      expect { wait(page) }.not_to raise_error
    end

    # Unlike the recognized non-JS-driver case, an unexpected error must be
    # surfaced so a real driver problem doesn't fail silently.
    it 'warns to STDERR that the wait was skipped after an unrecognized error' do
      page = unexpected_error_page(RuntimeError)

      expect { wait(page) }.to output(/page stability wait skipped after error/).to_stderr
    end

    it 'includes the error class and message in the warning' do
      page = unexpected_error_page(RuntimeError)

      expect { wait(page) }.to output(/RuntimeError: boom/).to_stderr
    end
  end
end
