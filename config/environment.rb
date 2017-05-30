#

$:.unshift File.join(File.dirname(__FILE__), "../lib")

# gems
Bundler.require

require 'bespoked'
#RUN_LOOP_CLASS = Bespoked::RunLoop

require 'libuv'
RUN_LOOP_CLASS = Libuv::Reactor
