#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

run_loop = Libuv::Reactor.default


run_loop.run do |logger|

  #LOGGING
  stdout_pipe = run_loop.pipe
  stdout_pipe.open($stdout.fileno)

  logger.notifier do |level, type, message, _not_used|
    if level && type && message
      error_trace = (message && message.respond_to?(:backtrace)) ? [message, message.backtrace] : message
      stdout_pipe.write(Yajl::Encoder.encode({:date => Time.now, :level => level, :type => type, :message => error_trace}))
    end

    stdout_pipe.write($/)
  end

  #INIT
  bespoked = Bespoked::EntryPoint.new(
    run_loop,
    ["ingresses", "services", "pods"],
    {
    "proxy-class" => ENV["BESPOKED_PROXY_CLASS"],
    "watch-class" => ENV["BESPOKED_WATCH_CLASS"]
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
