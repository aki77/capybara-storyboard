# frozen_string_literal: true

RSpec.describe Capybara::Storyboard::Context do
  let(:context) do
    described_class.new(
      test_class_name: 'FeatureSpec',
      test_method_name: 'does something',
      test_file: './spec/features/feature_spec.rb'
    )
  end

  it 'holds the three fields' do
    expect(context.test_class_name).to eq('FeatureSpec')
    expect(context.test_method_name).to eq('does something')
    expect(context.test_file).to eq('./spec/features/feature_spec.rb')
  end

  it 'is value-equal to another instance with the same fields (Data semantics)' do
    other = described_class.new(
      test_class_name: 'FeatureSpec',
      test_method_name: 'does something',
      test_file: './spec/features/feature_spec.rb'
    )

    expect(context).to eq(other)
  end

  it 'allows nil for every field' do
    context = described_class.new(test_class_name: nil, test_method_name: nil, test_file: nil)

    expect(context.test_class_name).to be_nil
    expect(context.test_method_name).to be_nil
    expect(context.test_file).to be_nil
  end
end
