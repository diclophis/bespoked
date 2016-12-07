#!/usr/bin/env ruby

module Bespoked
  module RackHandler
    def self.run(app, options = {})
      run_loop = Libuv::Reactor.new
      foo_bar = Bespoked::LibUVRackServer.new(run_loop, app, options)

      #TODO: make this a util
      run_loop.run do |exception_handler|
        logger = run_loop.defer
        logger.promise.progress do |log_entry|
          puts [foo_bar, log_entry].inspect
        end

        exception_handler.notifier do |error, message, trace|
          logger.notify({:date => Time.now, :exception => error.class, :backtrace => error.backtrace, :message => message, :trace => trace || error.to_s})
        end
      end
    end

    def self.valid_options
      {
        "Port=PORT" => "Port to listen on (default: 9292)"
      }
    end
  end
end

Rack::Handler.register :bespoked, Bespoked::RackHandler
