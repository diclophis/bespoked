#!/usr/bin/env ruby

require './lib/bespoked'

stdin, stdout, stderr, wait_thr = Open3.popen3({}, "ruby", "wkndr-msgpack-dream-machine.rb")

u = MessagePack::Unpacker.new(stdout)
u.each do |obj|
  puts obj.inspect
end

puts wait_thr.value
