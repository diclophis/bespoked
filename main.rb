#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

@run_loop = RUN_LOOP_CLASS.new

#@run_loop.run(:UV_RUN_ONCE) do |exception_handler|
#  #exception_handler.notifier do |error, message, trace|
#  #  puts ({:lineno => :main, :date => Time.now, :exception => error.class, :backtrace => error.backtrace, :message => message, :trace => trace || error.to_s})
#  #end
#end

@run_loop.run do |exception_handler|
  @logger = Bespoked::Logger.new(STDERR, @run_loop)
  @logger.start

  exception_handler.notifier do |error, message, trace|
    @logger.notify({:lineno => :main, :date => Time.now, :exception => error.class, :backtrace => error.backtrace, :message => message, :trace => trace || error.to_s})
  end

  #INIT
  bespoked = Bespoked::EntryPoint.new(
    @run_loop,
    @logger,
    ["ingresses", "services", "pods", "secrets"],
    {
      "proxy-controller-factory-class" => ENV["BESPOKED_PROXY_CLASS"],
      "watch-factory-class" => ENV["BESPOKED_WATCH_CLASS"],
      "port" => 443
    }
  )

=begin
  @run_loop.signal(:INT) do |_sigint|
    bespoked.halt :run_loop_interupted
  end

  @run_loop.signal(:HUP) do |_sigint|
    bespoked.halt :run_loop_hangup
  end

  @run_loop.signal(3) do |_sigint|
    bespoked.halt :run_loop_quit
  end

  @run_loop.signal(15) do |_sigint|
    bespoked.halt :run_loop_terminated
  end
=end

  bespoked.run_ingress_controller
end

puts :exited_due_to_full_halt
