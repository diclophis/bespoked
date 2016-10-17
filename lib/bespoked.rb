#

module Bespoked
  autoload :Controller, 'bespoked/controller'
  autoload :Proxy, 'bespoked/proxy'
  autoload :Watch, 'bespoked/watch'
  autoload :NginxProxy, 'bespoked/nginx_proxy'
  autoload :KubernetesWatch, 'bespoked/kubernetes_watch'
end
