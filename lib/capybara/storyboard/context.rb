# frozen_string_literal: true

module Capybara
  module Storyboard
    # Value object passed to a policy's #call. Derivation from the RSpec example
    # lives in TestHelper; this object only carries values.
    #
    # test_file is the raw file_path string in Phase 3 (EnvPolicy ignores it).
    # Phase 4 normalizes it to a Rails.root-relative path for TargetListPolicy.
    Context = Data.define(:test_class_name, :test_method_name, :test_file)
  end
end
