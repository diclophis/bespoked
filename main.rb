#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

run_loop = Libuv::Reactor.new

run_loop.run do |exception_handler|
  #LOGGING
  stdout_pipe = run_loop.pipe
  stdout_pipe.open($stdout.fileno)

  logger = run_loop.defer
  logger.promise.progress do |log_entry|
    stdout_pipe.write(Yajl::Encoder.encode(log_entry))
    stdout_pipe.write($/)
  end

  exception_handler.notifier do |error, message, trace|
    logger.notify({:lineno => :main, :date => Time.now, :exception => error.class, :backtrace => error.backtrace, :message => message, :trace => trace || error.to_s})
  end

  #INIT
  bespoked = Bespoked::EntryPoint.new(
    run_loop,
    logger,
    ["ingresses", "services", "pods"],
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

  run_loop.prepare {
    if bespoked.stopping
      #TODO: this should maybe not be needed if we clean up everything ok?
      run_loop.stop
    end
  }.start

  bespoked.run_ingress_controller
end
