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

  client = @run_loop.tcp

  client.connect("127.0.0.1", 4567) do
    @logger.notify(:connected => true)

    client.finally do |err|
      @logger.notify(:finally => err)
      client.close
    end

    client.progress do |chunk|
      @logger.notify(:chunk => chunk)
    end

    client.start_read

    client.write("GET / HTTP/1.1\r\nHost: foo\r\nConnection: Close\r\n\r\n")
  end
end

puts :wtf
