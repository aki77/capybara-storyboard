# frozen_string_literal: true

RSpec.describe Capybara::Storyboard do
  describe '.policy' do
    after { described_class.reset_policy! }

    it 'defaults to an EnvPolicy instance' do
      expect(described_class.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
    end

    it 'memoizes the default policy across calls' do
      first = described_class.policy
      second = described_class.policy

      expect(first).to be(second)
    end

    it 'allows injecting a custom policy via .policy=' do
      custom = Object.new
      described_class.policy = custom

      expect(described_class.policy).to be(custom)
    end

    it 'restores the default policy when reset via .reset_policy!' do
      described_class.policy = Object.new
      described_class.reset_policy!

      expect(described_class.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
    end

    it 'restores the default policy when assigned nil' do
      described_class.policy = Object.new
      described_class.policy = nil

      expect(described_class.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
    end
  end

  it 'has a version number' do
    expect(Capybara::Storyboard::VERSION).not_to be_nil
  end
end
