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

gem 'sgcop', github: 'SonicGarden/sgcop', ref: '11fb8397d8331fe1eec5a9fb17e694e70ce89da9' # SonicGarden coding style
