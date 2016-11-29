#

module Bespoked
  class RackProxyController < ProxyController
    def initialize(run_loop_in, entry_point_in)
      super

      #self.rack_handler = LibUVHttpProxyHandler.new(@run_loop, @entry_point.logger, {:Port => 8888})
    end
  end
end
