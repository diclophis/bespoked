#

module Bespoked
  class RackProxyController < ProxyController
    attr_accessor :rack_handler

    def initialize(run_loop_in, controller_in)
      super
      #self.rack_handler = LibUVHttpProxyHandler.new(@run_loop, method(:handle_request), {:Port => 8888})
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
