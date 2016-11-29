#

module Bespoked
  class RackProxyController < ProxyController
    def initialize(run_loop_in, controller_in)
      super

      #self.rack_handler = LibUVHttpProxyHandler.new(@run_loop, method(:handle_request), {:Port => 8888})
    end
  end
end
