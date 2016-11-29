#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'
require 'rack/handler'

puts Bespoked::LibUVRackServer

#$rack_server = nil

module Rack
  module Handler
    module LibUV
      def self.run(app, options = {})
        #$rack_server = 
        run_loop = Libuv::Reactor.new
        foo_bar = Bespoked::LibUVRackServer.new(run_loop, app, options)

        #TODO: make this a util
        run_loop.run do |exception_handler|

=begin
          stdout_pipe = run_loop.pipe
          stdout_pipe.open($stdout.fileno)
=end

          logger = run_loop.defer
          logger.promise.progress do |log_entry|
            puts [foo_bar, log_entry].inspect
            #stdout_pipe.write(Yajl::Encoder.encode(log_entry))
            #stdout_pipe.write($/)
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

    register :libuv, LibUV
  end
end

run proc { |env|
  [200, {"Content-Type" => "text"}, ["example rack handler"]]
}
