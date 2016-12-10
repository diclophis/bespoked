#
require 'yaml'
require 'open3'
require 'digest/md5'
require 'libuv'
require 'libuv/coroutines'
require 'http/parser'
require 'yajl'
require 'rack'
require 'rack/handler'
require 'socket'
require 'webrick'

module Bespoked
  DEFAULT_LIBUV_SOCKET_BIND = "0:0:0:0:0:0:0:0"

  # bind... are "servers"
  autoload :LibUVRackServer, 'bespoked/libuv_rack_server'
  autoload :LibUVHttpProxyServer, 'bespoked/libuv_http_proxy_server'
  # autoload :NginxProxy, 'bespoked/nginx_proxy'

  # "entrypoint"
  autoload :EntryPoint, 'bespoked/entry_point'

  # k8s resource "watchers"
  autoload :Watch, 'bespoked/watch'
  autoload :WatchFactory, 'bespoked/watch_factory'
  autoload :DebugWatchFactory, 'bespoked/debug_watch_factory'
  autoload :KubernetesApiWatchFactory, 'bespoked/kubernetes_api_watch_factory'
  # autoload :CommandWatch, 'bespoked/command_watch'

  # "proxy/other/controllers"
  autoload :ProxyController, 'bespoked/proxy_controller'
  autoload :RackProxyController, 'bespoked/rack_proxy_controller'
  autoload :HealthController, 'bespoked/health_controller'
  autoload :DashboardController, 'bespoked/dashboard_controller'

  # generic rack support
  autoload :RackHandler, 'bespoked/rack_handler'
end
