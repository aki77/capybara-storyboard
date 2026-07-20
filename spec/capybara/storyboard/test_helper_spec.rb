# frozen_string_literal: true

require 'tmpdir'
require 'pathname'

module StoryboardTestHelperSpecSupport
  # Records every path handed to #save_screenshot. Includes AlreadyStablePage so
  # capture reports an already-stable page.
  class FakePage
    include AlreadyStablePage

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

    # accept_confirm/accept_alert take a block in real Capybara and run it while
    # the dialog is open; yield so nested actions (and their hooks) execute.
    def accept_confirm(*)
      yield if block_given?
      SENTINELS[:accept_confirm]
    end

    def accept_alert(*)
      yield if block_given?
      SENTINELS[:accept_alert]
    end
  end

  # A minimal test double that counts #call invocations and records the
  # context it was given, without depending on rspec-mocks doubles.
  class CountingPolicy
    attr_reader :count, :last_context

    def initialize(result:)
      @result = result
      @count = 0
      @last_context = nil
    end

    def call(context)
      @count += 1
      @last_context = context
      @result
    end
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
      host.storyboard_screenshot('manual')
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

    it 'suppresses nested click_on hooks inside accept_confirm (single shot)' do
      host.accept_confirm { host.click_on('削除') }

      expect(basenames(host)).to eq(['001_accept_confirm.png'])
    end

    it 'suppresses nested click_on hooks inside accept_alert (single shot)' do
      host.accept_alert { host.click_on('x') }

      expect(basenames(host)).to eq(['001_accept_alert.png'])
    end

    it 'preserves the accept_confirm super return value' do
      expect(host.accept_confirm { host.click_on('x') }).to eq(:confirmed)
    end

    it 'resumes capturing after an accept_confirm block' do
      host.accept_confirm { host.click_on('x') }
      host.visit('/next')

      expect(basenames(host)).to eq(%w[001_accept_confirm.png 002_visit_next.png])
    end

    it 'suppresses a manual screenshot taken inside an accept_confirm block' do
      host.accept_confirm { host.storyboard_screenshot('mid') }

      expect(basenames(host)).to eq(['001_accept_confirm.png'])
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

    it 'takes no manual screenshots either' do
      host.storyboard_screenshot('manual')

      expect(host.page.saved).to be_empty
    end

    it 'records nothing for a nested accept_confirm block' do
      host.accept_confirm { host.click_on('削除') }

      expect(host.page.saved).to be_empty
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

  describe 'policy evaluation via __storyboard_init' do
    after { Capybara::Storyboard.reset_policy! }

    def init_host(policy)
      allow(RSpec).to receive(:current_example).and_return(fake_example)
      Capybara::Storyboard.policy = policy

      instance = build_host_class.allocate
      instance.__send__(:__storyboard_init)
      instance
    end

    it 'evaluates the policy exactly once per test, regardless of later actions' do
      policy = StoryboardTestHelperSpecSupport::CountingPolicy.new(result: true)
      instance = init_host(policy)

      instance.visit('/a')
      instance.click_on('Done')
      instance.fill_in('Email')

      expect(policy.count).to eq(1)
    end

    it 'passes a Context instance to the policy' do
      policy = StoryboardTestHelperSpecSupport::CountingPolicy.new(result: true)
      init_host(policy)

      expect(policy.last_context).to be_a(Capybara::Storyboard::Context)
    end

    it 'keeps a cached-enabled host capturing even after the policy flips to false' do
      instance = init_host(StoryboardTestHelperSpecSupport::CountingPolicy.new(result: true))

      Capybara::Storyboard.policy = StoryboardTestHelperSpecSupport::CountingPolicy.new(result: false)
      instance.visit('/a')

      expect(instance.page.saved).not_to be_empty
    end

    it 'reflects a new policy only after __storyboard_init runs again' do
      instance = init_host(StoryboardTestHelperSpecSupport::CountingPolicy.new(result: true))

      Capybara::Storyboard.policy = StoryboardTestHelperSpecSupport::CountingPolicy.new(result: false)
      allow(RSpec).to receive(:current_example).and_return(fake_example)
      instance.__send__(:__storyboard_init)
      instance.visit('/a')

      expect(instance.page.saved).to be_empty
    end
  end
end
