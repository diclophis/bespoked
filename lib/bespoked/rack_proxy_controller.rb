#

module Bespoked
  class RackProxyController < ProxyController
    attr_accessor :http_proxy_server

    def initialize(run_loop_in, entry_point_in)
      super

      self.http_proxy_server = LibUVHttpProxyServer.new(@run_loop, @entry_point.logger, self, {:Port => 80})
    end

    def add_tls_host(private_key, cert_chain, host_name)
      @http_proxy_server.add_tls_host(private_key, cert_chain, host_name)
    end

    def shutdown
      @http_proxy_server.shutdown
    end

    def start
      @http_proxy_server.start
    end
  end
end
