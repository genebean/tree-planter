# frozen_string_literal: true

source 'https://rubygems.org/'

# App Stack
gem 'json',      '~> 2.2'
gem 'passenger', '~> 6.0'
gem 'sinatra',   '~> 2.0'

# rack is pulled as a dep of passenger but needs to be above 2.0.6
# to resolve CVE-2018-16471
gem 'rack',      '~> 2.0', '>= 2.0.7'

group :development do
end

group :test do
  gem 'minitest',           '~> 5.12'
  gem 'minitest-reporters', '~> 1.3'
  gem 'rack-test',          '~> 1.1'
  gem 'rubocop',            '~> 0.78'
end
