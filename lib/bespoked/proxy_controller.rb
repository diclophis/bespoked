#

module Bespoked
  class ProxyController
    attr_accessor :run_loop,
                  :entry_point,
                  :vhosts

    def initialize(run_loop_in, entry_point_in)
      self.run_loop = run_loop_in
      self.entry_point = entry_point_in
      self.vhosts = {}
    end

    def shutdown
      raise "must override"
    end

    def install(ingress_descriptions)
      #@run_loop.log(:info, :proxy_controller_install, ingress_descriptions.keys)
      ingress_descriptions.values.each do |ingress_description|
        vhosts_for_ingress = self.extract_vhosts(ingress_description)
        #@run_loop.log(:info, :vhosts_extracted, vhosts_for_ingress)
        vhosts_for_ingress.each do |host, service_name, upstreams|
          #@run_loop.log(:info, :rack_proxy_vhost, [host, service_name, upstreams])
          @vhosts[host] = upstreams[0]
        end
      end

      @entry_point.record :info, :vhosts, @vhosts
    end

    def extract_name(description)
      if metadata = description["metadata"]
        metadata["name"]
      end
    end

    def add_tls_host(private_key, cert_chain, host_name)
      @entry_point.add_tls_host(private_key, cert_chain, host_name)
    end

    def extract_vhosts(description)
      ingress_name = self.extract_name(description)
      spec_rules = description["spec"]["rules"]

      #TODO: refactor this elsewhere, maybe
      if false
        spec_tls = description["spec"]["tls"]
        if spec_tls && spec_tls.length > 0
          spec_tls.each do |hosts_and_secret|
            list_of_hosts = hosts_and_secret["hosts"]
            secret_name = hosts_and_secret["secretName"]
            tls_secret = @entry_point.locate_secret(secret_name)
            data = tls_secret["data"] # has_keys? tls.crt, tls.key

            list_of_hosts.each do |host|
              @entry_point.record :info, :tls, [list_of_hosts, host, data.keys].inspect
              self.add_tls_host(Base64.decode64(data["tls.key"]), Base64.decode64(data["tls.crt"]), host)
            end
          end
        end
      end

      vhosts = []

      spec_rules.each do |rule|
        rule_host = rule["host"]
        if http = rule["http"]
          http["paths"].each do |http_path|
            service_name = http_path["backend"]["serviceName"]
            if @entry_point && service = @entry_point.locate_service(service_name)
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

      #@entry_point.record :info, :vhosts, vhosts

      vhosts
    end
  end
end
