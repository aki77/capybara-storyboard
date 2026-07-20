# frozen_string_literal: true

require 'pathname'

RSpec.describe Capybara::Storyboard::Configuration do
  subject(:config) { described_class.new }

  describe '#output_dir' do
    it 'defaults to <base>/tmp/screenshots' do
      expected = Capybara::Storyboard.rails_root_or_pwd.join('tmp', 'screenshots')

      expect(config.output_dir).to eq(expected)
    end

    it 'coerces a String override into a Pathname' do
      expected = Pathname('/custom/shots')
      config.output_dir = '/custom/shots'

      expect(config.output_dir).to eq(expected)
      expect(config.output_dir).to be_a(Pathname)
    end

    it 'keeps an absolute Pathname override as-is' do
      path = Pathname('/custom/shots')
      config.output_dir = path

      expect(config.output_dir).to eq(path)
    end

    it 'keeps a relative String override relative (does not absolutize)' do
      expected = Pathname('relative/shots')
      config.output_dir = 'relative/shots'

      expect(config.output_dir).to eq(expected)
      expect(config.output_dir).to be_a(Pathname)
    end

    it 'keeps a relative Pathname override relative' do
      expected = Pathname('relative/shots')
      config.output_dir = expected

      expect(config.output_dir).to eq(expected)
    end

    it 'restores the default when assigned nil' do
      expected = Capybara::Storyboard.rails_root_or_pwd.join('tmp', 'screenshots')
      config.output_dir = '/custom/shots'
      config.output_dir = nil

      expect(config.output_dir).to eq(expected)
    end
  end

  describe '#policy' do
    include_context 'with cleared screenshot env'

    it 'defaults to an EnvPolicy instance' do
      expect(config.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
    end

    it 'memoizes the default policy across calls' do
      first = config.policy
      second = config.policy

      expect(first).to be(second)
    end

    it 'returns the same injected object from a minimal call(context) responder' do
      custom = Object.new
      def custom.call(_context) = true
      config.policy = custom

      expect(config.policy).to be(custom)
    end

    it 'restores the default policy when assigned nil' do
      config.policy = Object.new
      config.policy = nil

      expect(config.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
    end

    it 'restores the default policy via #reset_policy!' do
      config.policy = Object.new
      config.reset_policy!

      expect(config.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
    end
  end
end
