#

module Bespoked
  class Proxy
    attr_accessor :run_loop,
                  :controller

    def initialize(run_loop_in, controller_in)
      self.run_loop = run_loop_in
      self.controller = controller_in
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

    def extract_name(description)
      if metadata = description["metadata"]
        metadata["name"]
      end
    end

    def extract_vhosts(description)
      ingress_name = self.extract_name(description)
      spec_rules = description["spec"]["rules"]

      vhosts = []

      spec_rules.each do |rule|
        rule_host = rule["host"]
        if http = rule["http"]
          http["paths"].each do |http_path|
            service_name = http_path["backend"]["serviceName"]
            if service = @controller.locate_service(service_name)
              if spec = service["spec"]
                upstreams = []
                if ports = spec["ports"]
                  ports.each do |port|
                    upstreams << "%s:%s" % [service_name, port["port"]]
                  end
                end
                if upstreams.length > 0
                  vhosts << [rule_host, service_name, upstreams]
                end
              end
            end
          end
        end
      end

      vhosts
    end
  end
end
