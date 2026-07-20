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

  # Records every path handed to #save_screenshot.
  class RecordingPage
    attr_reader :saved

    def initialize
      @saved = []
    end

    def save_screenshot(path)
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
    session.capture(page, 'shot')
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
        1.upto(10) { session.capture(page, 'shot') }

        names = basenames(page)
        expect(names.first).to eq('001_shot.png')
        expect(names[9]).to eq('010_shot.png')
      end
    end

    it 'supports three-digit sequence numbers' do
      Dir.mktmpdir do |dir|
        session = build_session(output_root: Pathname(dir))
        page = recording_page.new
        999.times { session.capture(page, 'shot') }

        expect(basenames(page).last).to eq('999_shot.png')
      end
    end
  end

  describe 'auto vs capture gating' do
    it 'does not capture on #auto when disabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: false, output_root: Pathname(dir))
        page = recording_page.new
        session.auto(page, 'visit', '/x')

        expect(page.saved).to be_empty
      end
    end

    it 'always captures on #capture even when disabled' do
      Dir.mktmpdir do |dir|
        session = build_session(enabled: false, output_root: Pathname(dir))
        page = recording_page.new
        session.capture(page, 'manual')

        expect(basenames(page)).to eq(['001_manual.png'])
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
        session.capture(page, 'shot')

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
        session.capture(page, 'shot')

        expected_dir = root.join('SignupForm', 'renders_the_form')
        expect(Pathname(page.saved.first).dirname).to eq(expected_dir)
        expect(expected_dir).to be_directory
      end
    end
  end
end
