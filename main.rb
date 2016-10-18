#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

controller = Bespoked::Controller.new({"var-lib-k8s" => (ARGV[0] || Dir.mktmpdir), "proxy-class" => ENV["BESPOKED_PROXY_CLASS"], "watch-class" => ENV["BESPOKED_WATCH_CLASS"]})

controller.ingress
