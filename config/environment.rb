#

$:.unshift File.join(File.dirname(__FILE__), "../lib")

# stdlib
require 'yaml'
require 'open3'
require 'digest/md5'

#require 'tempfile'
#require 'fileutils'

# gems
Bundler.require

require 'libuv'
require 'libuv/coroutines'
require 'http/parser'
require 'yajl'
require 'rack'
require 'rack/handler'
require 'socket'
require 'webrick'

require 'bespoked'

DEFAULT_LIBUV_SOCKET_BIND = "0:0:0:0:0:0:0:0"
#DEFAULT_LIBUV_SOCKET_BIND = "127.0.0.1"
#DEFAULT_LIBUV_SOCKET_BIND = "0.0.0.0"
