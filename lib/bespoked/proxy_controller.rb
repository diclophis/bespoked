#

module Bespoked
  class ProxyController
    attr_accessor :run_loop,
                  :entry_point,
                  :vhosts

    def initialize(run_loop_in, entry_point_in, port, tls)
      self.run_loop = run_loop_in
      self.entry_point = entry_point_in
      self.vhosts = {}
    end

    def shutdown
      raise "must override"
    end

    def install(ingress_descriptions)
      new_vhosts = {}

      ingress_descriptions.values.each do |ingress_description|
        vhosts_for_ingress = self.extract_vhosts(ingress_description)
        vhosts_for_ingress.each do |host, service_name, upstreams|
          new_vhosts[host] = self.vhosts[host]
          
          tried_dns = 0
          got_dns_ok = false

          on_dns_ok = proc { |addrinfo|
            got_dns_ok = true
            ip_address = addrinfo[0][0]
            @entry_point.record(:debug, :on_dns, [host, service_name, ip_address])
            new_vhosts[host] = [upstreams[0], ip_address]
          }

          on_dns_bad = proc { |err|
            #@entry_point.record(:debug, :on_dns_bad, [host, service_name, err])
            #TODO: ????
          }

          try_dns_service_lookup = proc {
            @run_loop.lookup(service_name, :IPv4, 59, :wait => false).then(on_dns_ok, on_dns_bad)
          }

          dns_timer = @run_loop.timer
          dns_timer.progress do
            #@entry_point.record(:debug, :dns_prog, [host, service_name, dns_timer])
            tried_dns += 1
            if tried_dns < 30 && got_dns_ok == false
              try_dns_service_lookup.call
            else
              #TODO: ???? on_dns_bad.call(:timeout)
              dns_timer.stop
            end
          end
          dns_timer.start(1000, 0)

          try_dns_service_lookup.call
        end
      end

      self.vhosts = new_vhosts
    end

    def extract_name(description)
      if metadata = description["metadata"]
        metadata["name"]
      end
    end

    def extract_vhosts(description)
      ingress_name = self.extract_name(description)

      #.dig("object", "status", "containerStatuses").all? { |cs| cs.dig("ready") }

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

      #vhosts << ["10.0.0.95", "10.0.0.95", ["10.0.0.95:9090"]]

      @entry_point.record :info, :vhosts, vhosts

      vhosts
    end
  end
end
