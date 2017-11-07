#!/usr/bin/env ruby

module Bespoked
  module RackHandler
    def self.halt(msg)
      $global_run_loop.stop
    end

    def self.run(app, options = {})
      $global_run_loop ||= Libuv::Reactor.new
      run_loop = $global_run_loop

      run_loop.signal(:INT) do |_sigint|
        halt :run_loop_interupted
      end

      run_loop.signal(:HUP) do |_sigint|
        halt :run_loop_hangup
      end

      run_loop.signal(3) do |_sigint|
        halt :run_loop_quit
      end

      run_loop.signal(15) do |_sigint|
        halt :run_loop_terminated
      end

      foo_bar = Bespoked::LibUVRackServer.new(run_loop, $global_logger, app, options)

      #TODO: make this a util
      run_loop.run do |exception_handler|
        foo_bar.start
        $global_logger.start(run_loop)

        exception_handler.notifier do |error, message, trace|
          $global_logger.notify({:lineno => :rack_handler, :date => Time.now, :exception => error.class, :backtrace => error.backtrace, :message => message, :trace => trace || error.to_s})
        end

        foo = run_loop.timer
        foo.progress do
          #TODO: figure this out...
          #DRb.thread.run if DRb.thread
        end
        foo.start(1, 1)

        run_loop.prepare {
          #TODO: figure this out...
          #DRb.thread.run if DRb.thread
        }.start
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
