# frozen_string_literal: true

require_relative 'storyboard/version'

module Capybara
  module Storyboard
    class Error < StandardError; end
  end
end

require_relative 'storyboard/session'
require_relative 'storyboard/test_helper'
