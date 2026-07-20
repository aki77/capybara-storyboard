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

  describe '.clear_output!' do
    include_context 'with cleared screenshot env'

    # Shared by every "armed" example below so the ENV write isn't repeated
    # inline; the "disarmed" example deliberately skips calling this.
    def arm!
      ENV['SCREENSHOTS'] = '1'
    end

    # Recreates the stale marker file exercised by the removal/run-once
    # examples below, so the 3-line mkdir_p+write isn't copy-pasted per example.
    def create_stale_marker(dir)
      marker = File.join(dir, 'old', '001_x.png')
      FileUtils.mkdir_p(File.dirname(marker))
      File.write(marker, 'stale')
      marker
    end

    after do
      described_class.reset_configuration!
      described_class.reset_output_cleared!
    end

    it 'removes the whole output root when armed' do
      arm!
      # Non-block form: clear_output! removes the dir itself, which would make
      # Dir.mktmpdir's own block cleanup raise ENOENT.
      dir = Dir.mktmpdir
      begin
        create_stale_marker(dir)
        described_class.configure { |config| config.output_dir = Pathname(dir) }

        described_class.clear_output!

        expect(File.exist?(dir)).to be(false)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it 'leaves the output root untouched when disarmed' do
      Dir.mktmpdir do |dir|
        marker = create_stale_marker(dir)
        described_class.configure { |config| config.output_dir = Pathname(dir) }

        described_class.clear_output!

        expect(File.exist?(marker)).to be(true)
      end
    end

    it 'clears at most once per process (run-once)' do
      arm!
      Dir.mktmpdir do |dir|
        described_class.configure { |config| config.output_dir = Pathname(dir) }

        described_class.clear_output!

        # Re-create the tree and marker, then call again: the second call must
        # short-circuit on the run-once flag and leave the marker in place.
        marker = create_stale_marker(dir)

        described_class.clear_output!

        expect(File.exist?(marker)).to be(true)
      end
    end

    it 'skips a non-existent output root without raising' do
      arm!
      Dir.mktmpdir do |dir|
        missing = Pathname(dir).join('nonexistent')
        described_class.configure { |config| config.output_dir = missing }

        expect { described_class.clear_output! }.not_to raise_error
      end
    end

    it 'refuses to clear a filesystem root' do
      arm!
      described_class.configure { |config| config.output_dir = Pathname('/') }
      allow(FileUtils).to receive(:rm_rf)

      expect { described_class.clear_output! }.to output(/refusing to clear unsafe output root/).to_stderr
      expect(FileUtils).not_to have_received(:rm_rf)
    end

    it 'refuses to clear the project/cwd root' do
      arm!
      described_class.configure { |config| config.output_dir = described_class.rails_root_or_pwd }
      allow(FileUtils).to receive(:rm_rf)

      expect { described_class.clear_output! }.to output(/refusing to clear unsafe output root/).to_stderr
      expect(FileUtils).not_to have_received(:rm_rf)
    end

    it 'resolves a relative output_dir against the shared base before clearing' do
      arm!
      Dir.mktmpdir do |dir|
        # Build the real directory at the absolute target, then point output_dir
        # at it as a path relative to the shared base (Dir.pwd when Rails is
        # undefined) so we can assert the resolved absolute Pathname.
        base = described_class.rails_root_or_pwd
        absolute = Pathname(dir).join('relative_shots')
        FileUtils.mkdir_p(absolute)
        relative = absolute.relative_path_from(base)
        described_class.configure { |config| config.output_dir = relative }
        allow(FileUtils).to receive(:rm_rf)

        described_class.clear_output!

        expect(FileUtils).to have_received(:rm_rf).with(relative.expand_path(base))
      end
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
