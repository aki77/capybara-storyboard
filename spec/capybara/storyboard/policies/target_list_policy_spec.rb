# frozen_string_literal: true

RSpec.describe Capybara::Storyboard::Policies::TargetListPolicy do
  def context_for(test_file)
    Capybara::Storyboard::Context.new(
      test_class_name: 'Ignored',
      test_method_name: 'ignored',
      test_file:
    )
  end

  def normalize(path)
    Capybara::Storyboard.normalize_test_path(path)
  end

  describe '#call' do
    it 'returns false for any context when the set is empty' do
      policy = described_class.new([])

      expect(policy.call(context_for('spec/system/foo_spec.rb'))).to be(false)
    end

    it 'returns true when the context test_file is in a single-element set' do
      policy = described_class.new([normalize('spec/system/foo_spec.rb')])

      expect(policy.call(context_for('spec/system/foo_spec.rb'))).to be(true)
    end

    it 'returns false when the context test_file is not in the set' do
      policy = described_class.new([normalize('spec/system/foo_spec.rb')])

      expect(policy.call(context_for('spec/system/bar_spec.rb'))).to be(false)
    end

    it 'matches against any element of a multi-element set' do
      policy = described_class.new(
        [normalize('spec/system/foo_spec.rb'), normalize('spec/system/bar_spec.rb')]
      )

      expect(policy.call(context_for('spec/system/bar_spec.rb'))).to be(true)
    end

    it 'treats a `./`-prefixed context test_file as equal to a bare list entry' do
      policy = described_class.new([normalize('spec/system/foo_spec.rb')])

      expect(policy.call(context_for('./spec/system/foo_spec.rb'))).to be(true)
    end

    it 'treats an absolute context test_file as equal to a relative list entry' do
      policy = described_class.new([normalize('spec/system/foo_spec.rb')])
      absolute = File.join(Dir.pwd, 'spec/system/foo_spec.rb')

      expect(policy.call(context_for(absolute))).to be(true)
    end

    it 'ignores surrounding whitespace and trailing newlines on the context test_file' do
      policy = described_class.new([normalize('spec/system/foo_spec.rb')])

      expect(policy.call(context_for("  ./spec/system/foo_spec.rb\n"))).to be(true)
    end

    it 'ignores whitespace and `./` variations on the list side too' do
      policy = described_class.new([normalize("  ./spec/system/foo_spec.rb\n")])

      expect(policy.call(context_for('spec/system/foo_spec.rb'))).to be(true)
    end

    it 'returns false when the context test_file is nil' do
      policy = described_class.new([normalize('spec/system/foo_spec.rb')])

      expect(policy.call(context_for(nil))).to be(false)
    end
  end
end
