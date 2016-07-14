#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

controller = Bespoked::Controller.new({"var-lib-k8s" => (ARGV[0] || Dir.mktmpdir)})

puts controller.inspect

controller.ingress
