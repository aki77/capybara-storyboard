# frozen_string_literal: true

require 'tmpdir'

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

  describe '.policy default composition' do
    def context_for(test_file)
      Capybara::Storyboard::Context.new(
        test_class_name: 'Ignored',
        test_method_name: 'ignored',
        test_file:
      )
    end

    include_context 'with cleared screenshot env'

    after { described_class.reset_policy! }

    it 'is false when SCREENSHOTS is unset (overview §5 case 1)' do
      expect(described_class.policy.call(context_for('spec/system/foo_spec.rb'))).to be(false)
    end

    it 'is true for any test_file when SCREENSHOTS=1 and no target list (overview §5 case 2)' do
      ENV['SCREENSHOTS'] = '1'

      expect(described_class.policy.call(context_for('spec/system/anything_spec.rb'))).to be(true)
    end

    it 'is true only for a listed test_file when SCREENSHOT_TESTS is set (overview §5 case 3, hit)' do
      ENV['SCREENSHOTS'] = '1'
      ENV['SCREENSHOT_TESTS'] = 'spec/system/foo_spec.rb'

      expect(described_class.policy.call(context_for('spec/system/foo_spec.rb'))).to be(true)
    end

    it 'is false for an unlisted test_file when SCREENSHOT_TESTS is set (overview §5 case 3, miss)' do
      ENV['SCREENSHOTS'] = '1'
      ENV['SCREENSHOT_TESTS'] = 'spec/system/foo_spec.rb'

      expect(described_class.policy.call(context_for('spec/system/bar_spec.rb'))).to be(false)
    end

    it 'drops blank entries from SCREENSHOT_TESTS without leaking a base-dir target' do
      ENV['SCREENSHOTS'] = '1'
      ENV['SCREENSHOT_TESTS'] = 'spec/system/foo_spec.rb,,spec/system/bar_spec.rb'

      policy = described_class.policy
      expect([
        policy.call(context_for('spec/system/foo_spec.rb')),
        policy.call(context_for('spec/system/bar_spec.rb')),
        policy.call(context_for('.')),
      ]).to eq([true, true, false])
    end

    it 'drops blank lines from SCREENSHOT_TESTS_FILE without leaking a base-dir target' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'targets.txt')
        File.write(file, "spec/system/foo_spec.rb\n\nspec/system/bar_spec.rb\n")
        ENV['SCREENSHOTS'] = '1'
        ENV['SCREENSHOT_TESTS_FILE'] = file

        policy = described_class.policy
        expect([
          policy.call(context_for('spec/system/foo_spec.rb')),
          policy.call(context_for('spec/system/bar_spec.rb')),
          policy.call(context_for('.')),
        ]).to eq([true, true, false])
      end
    end

    it 'unions SCREENSHOT_TESTS_FILE and SCREENSHOT_TESTS entries' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'targets.txt')
        File.write(file, "spec/system/foo_spec.rb\n")
        ENV['SCREENSHOTS'] = '1'
        ENV['SCREENSHOT_TESTS_FILE'] = file
        ENV['SCREENSHOT_TESTS'] = 'spec/system/bar_spec.rb'

        policy = described_class.policy
        expect([
          policy.call(context_for('spec/system/foo_spec.rb')),
          policy.call(context_for('spec/system/bar_spec.rb')),
        ]).to eq([true, true])
      end
    end

    it 'captures nothing when an explicitly configured target file is empty' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'empty.txt')
        File.write(file, '')
        ENV['SCREENSHOTS'] = '1'
        ENV['SCREENSHOT_TESTS_FILE'] = file

        expect(described_class.policy.call(context_for('spec/system/foo_spec.rb'))).to be(false)
      end
    end

    it 'distinguishes an empty target file (none) from no target list (all)' do
      ENV['SCREENSHOTS'] = '1'

      expect(described_class.policy.call(context_for('spec/system/foo_spec.rb'))).to be(true)
    end

    it 'raises Error when SCREENSHOT_TESTS_FILE points at a missing file' do
      ENV['SCREENSHOTS'] = '1'
      ENV['SCREENSHOT_TESTS_FILE'] = '/no/such/target/list.txt'

      expect { described_class.policy }.to raise_error(Capybara::Storyboard::Error)
    end

    it 'ignores a missing SCREENSHOT_TESTS_FILE when SCREENSHOTS is unset (disarmed)' do
      # SCREENSHOTS unset -> the mechanism is disarmed, so the target file's
      # existence is never checked and a stale/bad path must not blow up.
      ENV['SCREENSHOT_TESTS_FILE'] = '/no/such/target/list.txt'

      policy = nil
      expect { policy = described_class.policy }.not_to raise_error
      expect(policy.call(context_for('spec/system/foo_spec.rb'))).to be(false)
    end

    it 'falls back to Dir.pwd for normalization when Rails is undefined' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'targets.txt')
        # An absolute path under Dir.pwd resolves to the same relative form as
        # the context's relative test_file only via the Dir.pwd fallback base.
        File.write(file, "#{File.join(Dir.pwd, 'spec/system/foo_spec.rb')}\n")
        ENV['SCREENSHOTS'] = '1'
        ENV['SCREENSHOT_TESTS_FILE'] = file

        expect(described_class.policy.call(context_for('spec/system/foo_spec.rb'))).to be(true)
      end
    end
  end

  describe '.configuration' do
    after { described_class.reset_configuration! }

    it 'returns a Configuration' do
      expect(described_class.configuration).to be_a(Capybara::Storyboard::Configuration)
    end

    it 'memoizes the configuration across calls' do
      first = described_class.configuration
      second = described_class.configuration

      expect(first).to be(second)
    end
  end

  describe '.configure' do
    after { described_class.reset_configuration! }

    it 'yields the configuration' do
      described_class.configure do |config|
        expect(config).to be(described_class.configuration)
      end
    end

    it 'reflects an output_dir set inside the block' do
      expected = Pathname('/custom/shots')
      described_class.configure { |config| config.output_dir = '/custom/shots' }

      expect(described_class.configuration.output_dir).to eq(expected)
    end

    it 'reflects a policy set inside the block' do
      custom = Object.new
      described_class.configure { |config| config.policy = custom }

      expect(described_class.policy).to be(custom)
    end

    it 'is last-write-wins across multiple calls' do
      expected = Pathname('/second')
      described_class.configure { |config| config.output_dir = '/first' }
      described_class.configure { |config| config.output_dir = '/second' }

      expect(described_class.configuration.output_dir).to eq(expected)
    end
  end

  describe '.reset_configuration!' do
    after { described_class.reset_configuration! }

    it 'clears both output_dir and policy overrides' do
      expected_default = described_class.rails_root_or_pwd.join('tmp', 'screenshots')
      described_class.configure do |config|
        config.output_dir = '/custom/shots'
        config.policy = Object.new
      end
      described_class.reset_configuration!

      expect(described_class.configuration.output_dir).to eq(expected_default)
      expect(described_class.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
    end
  end

  describe 'policy delegation to configuration' do
    after { described_class.reset_configuration! }

    it 'reads through to the configuration policy' do
      custom = Object.new
      described_class.configuration.policy = custom

      expect(described_class.policy).to be(custom)
    end

    it 'writes through to the configuration policy' do
      custom = Object.new
      described_class.policy = custom

      expect(described_class.configuration.policy).to be(custom)
    end

    it 'reset_policy! clears only the policy, not output_dir' do
      expected = Pathname('/custom/shots')
      described_class.configure do |config|
        config.output_dir = '/custom/shots'
        config.policy = Object.new
      end
      described_class.reset_policy!

      expect(described_class.policy).to be_a(Capybara::Storyboard::Policies::EnvPolicy)
      expect(described_class.configuration.output_dir).to eq(expected)
    end
  end

  it 'has a version number' do
    expect(Capybara::Storyboard::VERSION).not_to be_nil
  end
end
