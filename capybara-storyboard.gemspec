# frozen_string_literal: true

require_relative 'lib/capybara/storyboard/version'

Gem::Specification.new do |spec|
  spec.name = 'capybara-storyboard'
  spec.version = Capybara::Storyboard::VERSION
  spec.authors = ['aki']
  spec.email = ['lala.akira@gmail.com']

  spec.summary = 'Capture and visualize Capybara system test flows as screenshot storyboards.'
  spec.description = 'Capybara::Storyboard records Capybara system test operations and their ' \
                     'screenshots, then visualizes them as a storyboard so you can review test ' \
                     'flows at a glance.'
  spec.homepage = 'https://github.com/aki77/capybara-storyboard'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "#{spec.homepage}/tree/main"
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files =
    IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
      ls.readlines("\x0", chomp: true).reject do |f|
        (f == gemspec) ||
          f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml doc/])
      end
    end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'capybara'

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
