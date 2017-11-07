#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

@run_loop = Bespoked::RunLoop.new #Libuv::Reactor.new

@run_loop.run do |exception_handler|
  @logger = Bespoked::Logger.new(STDERR, @run_loop)
  @logger.start

  exception_handler.notifier do |error, message, trace|
    @logger.notify({:lineno => :main, :date => Time.now, :exception => error.class, :backtrace => error.backtrace, :message => message, :trace => trace || error.to_s})
  end

  server = @run_loop.tcp

  server.bind("127.0.0.1", 4567) do |client|
    @logger.notify(:connected => true)

    client.finally do |err|
      @logger.notify(:finally => err)
      client.close
    end

    client.progress do |chunk|
      @logger.notify(:chunk => chunk)
      client.write("FooResponed").then do
        client.close
      end
    end

    client.start_read
  end

  server.listen(1024)
end

puts :wtf
