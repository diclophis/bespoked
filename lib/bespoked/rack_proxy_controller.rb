#

module Bespoked
  class RackProxyController < ProxyController
    attr_accessor :http_proxy_server

    def initialize(run_loop_in, entry_point_in)
      super

      self.http_proxy_server = LibUVHttpProxyServer.new(@run_loop, @entry_point.logger, self, {:Port => 8888})
    end

    def shutdown
      @http_proxy_server.shutdown
    end
  end
end
