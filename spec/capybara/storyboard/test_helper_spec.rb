# frozen_string_literal: true

require 'tmpdir'
require 'pathname'

module StoryboardTestHelperSpecSupport
  # Records every path handed to #save_screenshot.
  class FakePage
    attr_reader :saved

    def initialize
      @saved = []
    end

    def save_screenshot(path)
      @saved << path
    end
  end

  # Stands in for Capybara::DSL. Each overridden action returns a distinct
  # sentinel so we can assert TestHelper preserves the super return value.
  module FakeCapybaraDSL
    SENTINELS = {
      visit: :visited,
      click_on: :clicked_on,
      click_link: :clicked_link,
      click_button: :clicked_button,
      fill_in: :filled_in,
      select: :selected,
      check: :checked,
      uncheck: :unchecked,
      choose: :chose,
      attach_file: :attached,
      accept_confirm: :confirmed,
      accept_alert: :alerted,
    }.freeze

    def page
      @page ||= FakePage.new
    end

    def visit(*) = SENTINELS[:visit]
    def click_on(*) = SENTINELS[:click_on]
    def click_link(*) = SENTINELS[:click_link]
    def click_button(*) = SENTINELS[:click_button]
    def fill_in(*) = SENTINELS[:fill_in]
    def select(*) = SENTINELS[:select]
    def check(*) = SENTINELS[:check]
    def uncheck(*) = SENTINELS[:uncheck]
    def choose(*) = SENTINELS[:choose]
    def attach_file(*) = SENTINELS[:attach_file]
    def accept_confirm(*) = SENTINELS[:accept_confirm]
    def accept_alert(*) = SENTINELS[:accept_alert]
  end
end

RSpec.describe Capybara::Storyboard::TestHelper do
  # A tmpdir output root per example so screenshots never touch the real tmp/.
  # Registered for cleanup via an after hook without leaking instance state.
  let(:created_tmpdirs) { [] }

  let(:output_root) do
    dir = Dir.mktmpdir
    created_tmpdirs << dir
    Pathname(dir)
  end

  after do
    created_tmpdirs.each { |dir| FileUtils.rm_rf(dir) }
  end

  # A real RSpec example group provides a class-level `before`; the plain host
  # classes here stub it so TestHelper's `self.included` hook succeeds. The
  # Session is then injected directly so the specs stay ENV-independent.
  # FakeCapybaraDSL is included FIRST so TestHelper's overrides chain via super.
  def build_host_class
    Class.new do
      def self.before(*); end
      include StoryboardTestHelperSpecSupport::FakeCapybaraDSL
      include Capybara::Storyboard::TestHelper
    end
  end

  def build_host(enabled:, output_root:)
    host = build_host_class.new
    session = Capybara::Storyboard::Session.new(
      example: fake_example,
      enabled:,
      output_root:
    )
    host.instance_variable_set(:@__storyboard, session)
    host
  end

  def fake_example
    Struct.new(:description, :full_description, :metadata).new(
      'does something', 'Feature does something', {}
    )
  end

  def basenames(host)
    host.page.saved.map { |p| File.basename(p) }
  end

  context 'when SCREENSHOTS is enabled' do
    let(:host) { build_host(enabled: true, output_root:) }

    it 'captures before and after for click_on (two shots, ordered)' do
      result = host.click_on('Done')

      expect(result).to eq(:clicked_on)
      expect(basenames(host)).to eq(
        ['001_before_click_on_Done.png', '002_after_click_on_Done.png']
      )
    end

    it 'captures before and after for click_link and click_button' do
      host.click_link('More')
      host.click_button('Save')

      expect(basenames(host)).to eq(
        %w[
          001_before_click_link_More.png
          002_after_click_link_More.png
          003_before_click_button_Save.png
          004_after_click_button_Save.png
        ]
      )
    end

    it 'captures a single shot after non-click actions' do
      host.visit('/dashboard')
      host.fill_in('Email')
      host.select('Tokyo')
      host.check('agree')
      host.uncheck('news')
      host.choose('plan')
      host.attach_file('avatar')
      host.accept_confirm
      host.accept_alert

      expect(basenames(host)).to eq(
        %w[
          001_visit_dashboard.png
          002_fill_in_Email.png
          003_select_Tokyo.png
          004_check_agree.png
          005_uncheck_news.png
          006_choose_plan.png
          007_attach_file_avatar.png
          008_accept_confirm.png
          009_accept_alert.png
        ]
      )
    end

    it 'preserves the super return value' do
      expect(host.visit('/x')).to eq(:visited)
    end

    it 'shares a continuous sequence across mixed manual and auto shots' do
      host.visit('/a')
      host.screenshot('manual')
      host.fill_in('Name')

      expect(basenames(host)).to eq(
        %w[001_visit_a.png 002_manual.png 003_fill_in_Name.png]
      )
    end

    it 'keeps the sequence continuous when the same action repeats' do
      host.visit('/a')
      host.visit('/b')

      expect(basenames(host)).to eq(%w[001_visit_a.png 002_visit_b.png])
    end
  end

  context 'when SCREENSHOTS is disabled' do
    let(:host) { build_host(enabled: false, output_root:) }

    it 'takes no automatic screenshots' do
      host.click_on('Done')
      host.visit('/x')
      host.fill_in('Email')

      expect(host.page.saved).to be_empty
    end

    it 'still takes manual screenshots (ENV-independent)' do
      host.screenshot('manual')

      expect(basenames(host)).to eq(['001_manual.png'])
    end
  end

  describe 'initialization via the included before hook' do
    it 'builds a Session on the host from RSpec.current_example' do
      allow(RSpec).to receive(:current_example).and_return(fake_example)

      instance = build_host_class.allocate
      instance.__send__(:__storyboard_init)

      captured = instance.instance_variable_get(:@__storyboard)
      expect(captured).to be_a(Capybara::Storyboard::Session)
    end
  end
end
