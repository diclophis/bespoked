#!/usr/bin/env ruby

module Bespoked
  module RackHandler
    def self.run(app, options = {})
      run_loop = Libuv::Reactor.new

      #run_loop.signal(:INT) do |_sigint|
      #  #bespoked.halt :run_loop_interupted
      #  Thread.list.collect { |thr|
      #    thr.kill
      #  }
      #  run_loop.stop
      #  puts Thread.list.inspect
      #  puts :int
      #end

      foo_bar = Bespoked::LibUVRackServer.new(run_loop, app, options)

      #TODO: make this a util
      run_loop.run do |exception_handler|
        logger = run_loop.defer
        logger.promise.progress do |log_entry|
          puts [log_entry].inspect
        end

        foo_bar.start

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
