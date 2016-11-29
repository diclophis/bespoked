#

module Bespoked
  # bind... are "servers"
  autoload :LibUVRackServer, 'bespoked/libuv_rack_server'
  autoload :LibUVHttpProxyServer, 'bespoked/libuv_http_proxy_server'

  # "entrypoint"
  autoload :EntryPoint, 'bespoked/entry_point'

  # "apps"
  # autoload :Dashboard, 'bespoked/dashboard'

  # k8s resource "watchers"
  autoload :Watch, 'bespoked/watch'
  autoload :WatchFactory, 'bespoked/watch_factory'
  autoload :DebugWatchFactory, 'bespoked/debug_watch_factory'

  # autoload :KubernetesWatch, 'bespoked/kubernetes_watch'
  # autoload :CommandWatch, 'bespoked/command_watch'

  # "proxy/other/controllers"
  autoload :ProxyController, 'bespoked/proxy_controller'
  autoload :RackProxyController, 'bespoked/rack_proxy_controller'
  autoload :HealthController, 'bespoked/health_controller'
  # autoload :NginxProxy, 'bespoked/nginx_proxy'

  # generic rack support
  autoload :RackHandler, 'bespoked/rack_handler'
end
