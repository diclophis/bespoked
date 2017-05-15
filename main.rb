#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

run_loop = Libuv::Reactor.new

logger = Bespoked::Logger.new(STDERR)
logger.start(run_loop)

run_loop.run do |exception_handler|
  exception_handler.notifier do |error, message, trace|
    logger.notify({:lineno => :main, :date => Time.now, :exception => error.class, :backtrace => error.backtrace, :message => message, :trace => trace || error.to_s})
  end

  #INIT
  bespoked = Bespoked::EntryPoint.new(
    run_loop,
    logger,
    ["ingresses", "services", "pods", "secrets"],
    {
      "proxy-controller-factory-class" => ENV["BESPOKED_PROXY_CLASS"],
      "watch-factory-class" => ENV["BESPOKED_WATCH_CLASS"]
    }
  )

  run_loop.signal(:INT) do |_sigint|
    bespoked.halt :run_loop_interupted
  end

  run_loop.signal(:HUP) do |_sigint|
    bespoked.halt :run_loop_hangup
  end

  run_loop.signal(3) do |_sigint|
    bespoked.halt :run_loop_quit
  end

  run_loop.signal(15) do |_sigint|
    bespoked.halt :run_loop_terminated
  end

  #run_loop.next_tick do
    bespoked.run_ingress_controller
  #end
end
