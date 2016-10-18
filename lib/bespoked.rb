#

module Bespoked
  autoload :LibUVRackHandler, 'bespoked/libuv_rack_handler'
  autoload :LibUVHttpProxyHandler, 'bespoked/libuv_http_proxy_handler'

  autoload :Controller, 'bespoked/controller'
  autoload :Dashboard, 'bespoked/dashboard'
  autoload :HealthService, 'bespoked/health_service'

  autoload :Proxy, 'bespoked/proxy'
  autoload :Watch, 'bespoked/watch'

  #autoload :Proxy, 'bespoked/proxy'
  autoload :DebugWatch, 'bespoked/debug_watch'

  autoload :NginxProxy, 'bespoked/nginx_proxy'
  autoload :KubernetesWatch, 'bespoked/kubernetes_watch'

  autoload :RackProxy, 'bespoked/rack_proxy'
  autoload :CommandWatch, 'bespoked/command_watch'
end
