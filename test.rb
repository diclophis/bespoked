#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)

require 'config/environment'

def halt(msg)
  puts msg
  exit 1
end

run_loop = Libuv::Reactor.default

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

stdout_pipe = run_loop.pipe
stdout_pipe.open($stdout.fileno)

run_loop.run do |logger|
  logger.notifier do |level, type, message, _not_used|
    error_trace = (message && message.respond_to?(:backtrace)) ? [message, message.backtrace] : message
    stdout_pipe.write(Yajl::Encoder.encode({:date => Time.now, :level => level, :type => type, :message => error_trace}))
    stdout_pipe.write($/)
  end

  watch = Bespoked::DebugWatch.new(run_loop)
  proxy = Bespoked::RackProxy.new(run_loop, nil)
  dashboard = Bespoked::Dashboard.new(run_loop)
  health = Bespoked::HealthService.new(run_loop)

  x = run_loop.timer
  x.start(1500, 1500)
  x.progress do
    run_loop.log(:info, :tick)
  end

  a = run_loop.timer
  a.start(2000, 0)
  a.progress do
    proxy.start
  end

  b = run_loop.timer
  b.start(4000, 0)
  b.progress do
    dashboard.start
  end


  c = run_loop.timer
  c.start(8000, 0)
  c.progress do
    health.start
  end
end
