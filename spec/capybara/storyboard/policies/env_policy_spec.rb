# frozen_string_literal: true

RSpec.describe Capybara::Storyboard::Policies::EnvPolicy do
  let(:policy) { described_class.new }
  let(:context) do
    Capybara::Storyboard::Context.new(
      test_class_name: 'Ignored',
      test_method_name: 'ignored',
      test_file: 'ignored'
    )
  end

  around do |example|
    original = ENV.fetch('SCREENSHOTS', nil)
    begin
      example.run
    ensure
      ENV['SCREENSHOTS'] = original
    end
  end

  it 'returns false when SCREENSHOTS is unset' do
    ENV.delete('SCREENSHOTS')

    expect(policy.call(context)).to be(false)
  end

  it 'returns false when SCREENSHOTS is set to an empty string' do
    ENV['SCREENSHOTS'] = ''

    expect(policy.call(context)).to be(false)
  end

  it 'returns true when SCREENSHOTS is set to "0" (present? semantics)' do
    ENV['SCREENSHOTS'] = '0'

    expect(policy.call(context)).to be(true)
  end

  it 'returns true when SCREENSHOTS is set to a non-blank value' do
    ENV['SCREENSHOTS'] = '1'

    expect(policy.call(context)).to be(true)
  end

  it 'ignores the context entirely' do
    ENV['SCREENSHOTS'] = '1'

    expect(policy.call(nil)).to be(true)
  end
end
