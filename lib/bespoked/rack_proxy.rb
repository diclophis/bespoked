#

module Bespoked
  class RackProxy < Proxy
    attr_accessor :rack_handler

    def initialize(run_loop_in, controller_in)
      super(run_loop_in, controller_in)

      self.rack_handler = LibUVRackHandler.run(@run_loop, method(:handle_request), {:Port => 8181})
    end

    def install(ingress_descriptions)
      @run_loop.log(:info, :rack_proxy_install, ingress_descriptions.keys)

      ingress_descriptions.values.each do |ingress_description|
        vhosts_for_ingress = self.extract_vhosts(ingress_description)
        vhosts_for_ingress.each do |host, service_name, upstreams|
          @run_loop.log(:info, :rack_proxy_vhost, [host, service_name, upstreams])
        end
      end
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
