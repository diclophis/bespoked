#

module Bespoked
  class RackProxy
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
      self.rack_handler = LibUVRackHandler.run(@run_loop, method(:handle_request), {:Port => 8181})
    end

    def install(ingress_descriptions)
      @run_loop.log(:info, :rack_proxy_install, ingress_descriptions.keys)
    end

    def start
      @run_loop.log(:info, :rack_proxy_start, nil)
    end

    def stop
      @run_loop.log(:info, :rack_proxy_stop, nil)
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["A barebones rack app. #{self.inspect}"]]
    end
  end
end
