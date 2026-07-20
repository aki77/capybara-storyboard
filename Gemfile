# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in capybara-storyboard.gemspec
gemspec

gem 'irb'
gem 'rake', '~> 13.0' # Task runner

# Used at runtime by the target Rails app; required here so the gem's own
# specs can exercise the `present?` / `compact_blank` / `truncate` code paths.
gem 'activesupport'

gem 'rspec', '~> 3.0' # Test framework

gem 'rubocop', '~> 1.21' # Static code analyzer

gem 'sgcop', github: 'SonicGarden/sgcop', tag: 'v1.35.0' # SonicGarden coding style
