#

module Bespoked
  class Proxy
    attr_accessor :run_loop

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
    end

    def install(ingress_descriptions)
      @run_loop.log(:info, :debug_proxy_install, ingress_descriptions.keys)
    end

    def start
      @run_loop.log(:info, :debug_proxy_start, nil)
    end

    def stop
      @run_loop.log(:info, :debug_proxy_stop, nil)
    end
  end
end
