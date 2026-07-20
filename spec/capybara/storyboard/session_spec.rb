# frozen_string_literal: true

require 'tmpdir'
require 'pathname'

module StoryboardSessionSpecSupport
  # Minimal stand-in for an RSpec example. Holds a metadata Hash plus the
  # description accessors Session reads. No RSpec/Capybara machinery involved.
  FakeExample =
    Struct.new(:description, :full_description, :metadata) do
      def initialize(description: '', full_description: '', metadata: {})
        super(description, full_description, metadata)
      end
    end

  # Records every path handed to #save_screenshot. Includes AlreadyStablePage so
  # capture never blocks on the page-stability wait.
  class RecordingPage
    include AlreadyStablePage

    attr_reader :saved

    def initialize
      @saved = []
    end

    def save_screenshot(path)
      @saved << path
    end
  end

  # Like RecordingPage but #save_screenshot raises for the first +fail_times+
  # calls before recording, to exercise save_screenshot failure protection.
  # Stability stays a no-op via AlreadyStablePage.
  class FailingThenRecordingPage
    include AlreadyStablePage

    attr_reader :saved

    def initialize(fail_times: 1)
      @saved = []
      @remaining_failures = fail_times
    end

    def save_screenshot(path)
      if @remaining_failures.positive?
        @remaining_failures -= 1
        raise 'screenshot boom'
      end
      @saved << path
    end
  end

  # Builds a class whose `.name` returns +class_name+, standing in for a
  # `described_class`.
  def self.named_class(class_name)
    Class.new do
      define_singleton_method(:name) { class_name }
    end
  end
end

RSpec.describe Capybara::Storyboard::Session do
  include StoryboardSessionSpecSupport

  def fake_example
    StoryboardSessionSpecSupport::FakeExample
  end

  def recording_page
    StoryboardSessionSpecSupport::RecordingPage
  end

  def build_session(example: StoryboardSessionSpecSupport::FakeExample.new, enabled: true, output_root: nil)
    described_class.new(example:, enabled:, output_root:)
  end

  def basenames(page)
    page.saved.map { |p| File.basename(p) }
  end

  # Derive the output directory for an example by capturing one screenshot into
  # a tmpdir and returning its parent path. Avoids touching the real tmp/.
  def output_path(example)
    dir = Dir.mktmpdir
    session = build_session(example:, output_root: Pathname(dir))
    page = StoryboardSessionSpecSupport::RecordingPage.new
    session.manual(page, 'shot')
    Pathname(page.saved.first).dirname
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  describe '#enabled?' do
    it 'reflects the injected flag' do
      expect(build_session(enabled: true).enabled?).to be(true)
      expect(build_session(enabled: false).enabled?).to be(false)
    end
  end

  describe 'sanitization (via generated filenames)' do
    def label_for(detail)
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = StoryboardSessionSpecSupport::RecordingPage.new
        session.auto(page, 'act', detail)
        File.basename(page.saved.first, '.png').sub(/\A\d+_act_?/, '')
      end
    end

    it 'replaces symbols with underscores' do
      expect(label_for('a@b')).to eq('a_b')
    end

    it 'replaces whitespace with underscores' do
      expect(label_for('a b')).to eq('a_b')
    end

    it 'replaces non-ASCII (e.g. Japanese) characters' do
      # `\w` here is ASCII-only, so Japanese characters are non-word and get
      # replaced; ASCII word characters around them survive.
      expect(label_for('a押すb')).to eq('a_b')
    end

    it 'compresses consecutive underscores' do
      expect(label_for('a___b')).to eq('a_b')
    end

    it 'strips leading and trailing underscores' do
      expect(label_for('__a__')).to eq('a')
    end
  end

  describe 'filename generation' do
    it 'zero-pads the sequence to three digits and appends .png' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new
        1.upto(10) { session.manual(page, 'shot') }

        names = basenames(page)
        expect(names.first).to eq('001_shot.png')
        expect(names[9]).to eq('010_shot.png')
      end
    end

    it 'supports three-digit sequence numbers' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new
        999.times { session.manual(page, 'shot') }

        expect(basenames(page).last).to eq('999_shot.png')
      end
    end
  end

  describe 'auto vs manual gating' do
    it 'does not capture on #auto when disabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: false, output_root: Pathname(dir))
        page = recording_page.new
        session.auto(page, 'visit', '/x')

        expect(page.saved).to be_empty
      end
    end

    it 'does not capture on #manual when disabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: false, output_root: Pathname(dir))
        page = recording_page.new
        session.manual(page, 'manual')

        expect(page.saved).to be_empty
      end
    end

    it 'captures on #manual when enabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: true, output_root: Pathname(dir))
        page = recording_page.new
        session.manual(page, 'manual')

        expect(basenames(page)).to eq(['001_manual.png'])
      end
    end
  end

  describe 'page-stability wait before capture' do
    before { allow(Capybara::Storyboard::PageStability).to receive(:wait_for_stable_page) }

    it 'waits before save_screenshot on #auto when enabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: true, output_root: Pathname(dir))
        session.auto(recording_page.new, 'visit', '/x')

        expect(Capybara::Storyboard::PageStability).to have_received(:wait_for_stable_page)
      end
    end

    it 'waits before save_screenshot on #manual when enabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: true, output_root: Pathname(dir))
        session.manual(recording_page.new, 'shot')

        expect(Capybara::Storyboard::PageStability).to have_received(:wait_for_stable_page)
      end
    end

    it 'does not wait on #auto when disabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: false, output_root: Pathname(dir))
        session.auto(recording_page.new, 'visit', '/x')

        expect(Capybara::Storyboard::PageStability).not_to have_received(:wait_for_stable_page)
      end
    end

    it 'does not wait on #manual when disabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: false, output_root: Pathname(dir))
        session.manual(recording_page.new, 'shot')

        expect(Capybara::Storyboard::PageStability).not_to have_received(:wait_for_stable_page)
      end
    end
  end

  describe 'group_name derivation' do
    it 'uses described_class name when it responds to :name' do
      example = fake_example.new(
        description: 'does',
        metadata: { described_class: StoryboardSessionSpecSupport.named_class('Widgets::Editor') }
      )
      expect(output_path(example).to_s).to include('Widgets_Editor')
    end

    it 'falls back to the top-level describe description otherwise' do
      example = fake_example.new(
        description: 'does',
        metadata: {
          described_class: 'not a class',
          example_group: {
            description: 'Nested thing',
            parent_example_group: { description: 'Top Level Feature' },
          },
        }
      )
      expect(output_path(example).to_s).to include('Top_Level_Feature')
    end
  end

  describe 'example_name derivation' do
    it 'sanitizes the description' do
      example = fake_example.new(description: 'does a thing!')
      expect(output_path(example).to_s).to include('does_a_thing')
    end

    it 'hard-cuts at 80 characters' do
      example = fake_example.new(description: 'a' * 200)
      leaf = output_path(example).basename.to_s
      expect(leaf.length).to eq(80)
    end

    it 'falls back to full_description when description sanitizes to empty' do
      example = fake_example.new(description: '!!!', full_description: 'Full context here')
      expect(output_path(example).to_s).to include('Full_context_here')
    end

    it 'falls back to "example" when nothing usable remains' do
      example = fake_example.new(description: '!!!', full_description: '@@@')
      expect(output_path(example).basename.to_s).to eq('example')
    end
  end

  describe 'default output root via configuration' do
    after { Capybara::Storyboard.reset_configuration! }

    it 'roots screenshots under configuration.output_dir when no output_root is injected' do
      Dir.mktmpdir do |dir|
        root = Pathname(dir)
        Capybara::Storyboard.configure { |config| config.output_dir = root }

        example = fake_example.new(
          description: 'renders the form',
          metadata: { described_class: StoryboardSessionSpecSupport.named_class('SignupForm') }
        )
        session = build_session(example:)
        page = recording_page.new
        session.manual(page, 'shot')

        expected_dir = root.join('SignupForm', 'renders_the_form')
        expect(Pathname(page.saved.first).dirname).to eq(expected_dir)
      end
    end
  end

  describe 'output path assembly' do
    it 'joins output_root / group_name / example_name' do
      Dir.mktmpdir do |dir|
        root = Pathname(dir)
        example = fake_example.new(
          description: 'renders the form',
          metadata: { described_class: StoryboardSessionSpecSupport.named_class('SignupForm') }
        )
        session = build_session(example:, output_root: root)
        page = recording_page.new
        session.manual(page, 'shot')

        expected_dir = root.join('SignupForm', 'renders_the_form')
        expect(Pathname(page.saved.first).dirname).to eq(expected_dir)
        expect(expected_dir).to be_directory
      end
    end
  end

  describe 'capture suppression' do
    it 'makes #auto a no-op inside a suppress_captures block' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new

        session.suppress_captures { session.auto(page, 'visit', '/x') }

        expect(page.saved).to be_empty
      end
    end

    it 'makes #manual a no-op inside a suppress_captures block' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new

        session.suppress_captures { session.manual(page, 'shot') }

        expect(page.saved).to be_empty
      end
    end

    it 'resumes capturing after the block exits' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new

        session.suppress_captures { session.auto(page, 'visit', '/x') }
        session.auto(page, 'visit', '/y')

        expect(basenames(page)).to eq(['001_visit_y.png'])
      end
    end

    it 'stays suppressed until the outermost nested block exits' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new

        session.suppress_captures do
          session.suppress_captures { session.auto(page, 'inner') }
          session.auto(page, 'outer')
        end
        session.auto(page, 'after')

        expect(basenames(page)).to eq(['001_after.png'])
      end
    end

    it 'resets suppression even when the block raises' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new

        expect { session.suppress_captures { raise 'boom' } }.to raise_error('boom')

        session.auto(page, 'after')
        expect(basenames(page)).to eq(['001_after.png'])
      end
    end

    it 'still yields and returns the block value on a disabled session' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: false, output_root: Pathname(dir))
        yielded = false

        result =
          session.suppress_captures do
            yielded = true
            :block_value
          end

        expect(yielded).to be(true)
        expect(result).to eq(:block_value)
      end
    end

    it 'returns the block value' do
      session = build_session
      expect(session.suppress_captures { :the_value }).to eq(:the_value)
    end
  end

  describe 'save_screenshot failure protection' do
    def failing_page(fail_times: 1)
      StoryboardSessionSpecSupport::FailingThenRecordingPage.new(fail_times:)
    end

    it 'does not propagate the failure out of #auto' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        expect { session.auto(failing_page, 'visit', '/x') }.not_to raise_error
      end
    end

    it 'does not propagate the failure out of #manual' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        expect { session.manual(failing_page, 'shot') }.not_to raise_error
      end
    end

    it 'warns when a screenshot is skipped after an error' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        expect { session.manual(failing_page, 'shot') }
          .to output(/screenshot skipped after error/).to_stderr
      end
    end

    it 'consumes the sequence number on failure, leaving a gap' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = failing_page(fail_times: 1)

        expect { session.auto(page, 'first') }.to output.to_stderr
        session.auto(page, 'second')

        expect(basenames(page)).to eq(['002_second.png'])
      end
    end
  end
end
