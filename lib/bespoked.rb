#

module Bespoked
  # bind... are "servers"
  # autoload :LibUVRackHandler, 'bespoked/libuv_rack_handler'
  # autoload :LibUVHttpProxyHandler, 'bespoked/libuv_http_proxy_handler'

  # "entrypoint"
  autoload :EntryPoint, 'bespoked/entry_point'

  # "apps"
  # autoload :Dashboard, 'bespoked/dashboard'
  # autoload :HealthService, 'bespoked/health_service'

  # k8s resource "watchers"
  autoload :Watch, 'bespoked/watch'
  autoload :WatchFactory, 'bespoked/watch_factory'
  autoload :DebugWatchFactory, 'bespoked/debug_watch_factory'

  # autoload :KubernetesWatch, 'bespoked/kubernetes_watch'
  # autoload :CommandWatch, 'bespoked/command_watch'

  # "controllers"
  # autoload :Proxy, 'bespoked/proxy'
  # autoload :NginxProxy, 'bespoked/nginx_proxy'
  # autoload :RackProxy, 'bespoked/rack_proxy'
end
