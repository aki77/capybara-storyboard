# frozen_string_literal: true

module Capybara
  module Storyboard
    # Value object passed to a policy's #call. Derivation from the RSpec example
    # lives in TestHelper; this object only carries values.
    #
    # test_file is the raw RSpec file_path string; this object never normalizes
    # it. Canonicalization to a base-relative path is done on demand by
    # Capybara::Storyboard.normalize_test_path (used by TargetListPolicy).
    Context = Data.define(:test_class_name, :test_method_name, :test_file)
  end
end
