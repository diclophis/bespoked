#

$:.unshift File.join(File.dirname(__FILE__), "../lib")

# stdlib
require 'yaml'
require 'open3'

#require 'tempfile'
#require 'fileutils'

# gems
Bundler.require

require 'libuv'
require 'libuv/coroutines'
require 'http/parser'
require 'yajl'

require 'bespoked'
