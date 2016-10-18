#

module Bespoked
  class RackProxy < Proxy
    attr_accessor :rack_handler,
                  :vhosts

    def initialize(run_loop_in, controller_in)
      super(run_loop_in, controller_in)
      self.vhosts = {}
    end

    def install(ingress_descriptions)
      @run_loop.log(:info, :rack_proxy_install, ingress_descriptions.keys)

      ingress_descriptions.values.each do |ingress_description|
        vhosts_for_ingress = self.extract_vhosts(ingress_description)
        @run_loop.log(:info, :vhosts_extracted, vhosts_for_ingress)
        vhosts_for_ingress.each do |host, service_name, upstreams|
          @run_loop.log(:info, :rack_proxy_vhost, [host, service_name, upstreams])
          @vhosts[host] = upstreams[0]
        end
      end
    end

    def start
      @run_loop.log(:info, :rack_proxy_start, nil)
      self.rack_handler = LibUVHttpProxyHandler.run(@run_loop, method(:handle_request), {:Port => 8181})
    end

    def stop
      @run_loop.log(:info, :rack_proxy_stop, nil)
    end

    def handle_request(env)
      in_url = URI.parse("http://" + env["HTTP_HOST"])
      out_url = nil

      if mapped_host_port = @vhosts[in_url.host]
        out_url = URI.parse("http://" + mapped_host_port)
      end

      return out_url
    end
  end
end
