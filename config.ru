#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'
require 'bespoked/rack_handler'

$global_logger = Bespoked::Logger.new(STDERR)

run proc { |env|
  [200, {"Content-Type" => "text"}, ["example rack handler"]]
}
