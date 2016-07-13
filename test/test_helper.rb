ENV['RUBY_ENV'] ||= 'test'

require File.expand_path('../../config/environment', __FILE__)

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'

class MiniTest::Spec
  # Add more helper methods to be used by all tests here...
end
