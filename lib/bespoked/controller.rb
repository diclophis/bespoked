#

module Bespoked
  class Controller
    attr_accessor :proxy,
                  :descriptions,
                  :run_loop,
                  :checksum

    WATCH_TIMEOUT = 1000 * 60 * 5
    RECONNECT_WAIT = 1000
    RECONNECT_TRIES = 60
    RELOAD_TIMEOUT = 2000

    KINDS = ["pod", "service", "ingress", "endpoint"]
    KINDS.each do |kind|
      register_method = "register_#{kind}"
      locate_method = "locate_#{kind}"

      define_method register_method do |event, description|
        self.descriptions[kind] ||= {}

        name = self.extract_name(description)

        case event
          when "ADDED", "MODIFIED"
            self.descriptions[kind][name] = description
          when "DELETED"
            self.descriptions[kind].delete(name)

        end
      end

      define_method locate_method do |name|
        self.descriptions[kind] ||= {}
        self.descriptions[kind][name]
      end
    end

    def initialize(options = {})
      self.descriptions = {}
      self.run_loop = Libuv::Loop.default
      self.proxy = IngressProxy.new(@run_loop)
    end

    def start_proxy
      @proxy.start
    end

    def stop_proxy
      @proxy.stop
    end

    def install_proxy(ingress_descriptions)
      @proxy.install(ingress_descriptions)
    end

    def recheck
      old_checksum = @checksum
      @checksum = Digest::MD5.hexdigest(Marshal.dump(@descriptions))
      @run_loop.log :info, :checksum, [old_checksum, @checksum]
      return @checksum != old_checksum
    end

    def halt(message)
      self.stop_proxy
      @run_loop.log(:info, :halt, message)
      @run_loop.stop
    end

    def create_watch_pipe(resource_kind)
      defer = @run_loop.defer

      reconnect_timer = @run_loop.timer

      proceed_with_reconnect = proc {
        reconnect_timer.stop
        reconnect_timer.start(RECONNECT_WAIT, 0)
      }

      reconnect_timer.progress do
        reconnect_loop = self.create_retry_watch(resource_kind, defer)
        reconnect_loop.then do
          proceed_with_reconnect.call
        end
      end

      proceed_with_reconnect.call

      return defer.promise
    end

    def create_retry_watch(resource_kind, defer)
      var_run_secrets_k8s_token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
      var_run_secrets_k8s_crt_path = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'

      service_host = ENV["KUBERNETES_SERVICE_HOST"] || "127.0.0.1"
      service_port = ENV["KUBERNETES_SERVICE_PORT"] || "8443"
      bearer_token = ENV["KUBERNETES_DEV_BEARER_TOKEN"] || begin
         unless File.exist?(var_run_secrets_k8s_token_path) && (File.size(var_run_secrets_k8s_token_path) > 0)
           self.halt :k8s_token_not_ready
         end

         File.read(var_run_secrets_k8s_token_path).strip
      end

      get_watch = "GET #{self.path_for_watch(resource_kind)} HTTP/1.1\r\nHost: #{service_host}\r\nAuthorization: Bearer #{bearer_token}\r\nAccept: */*\r\nUser-Agent: bespoked\r\n\r\n"

      new_client = @run_loop.tcp
      retry_defer = @run_loop.defer

      http_parser = Http::Parser.new

      json_parser = Yajl::Parser.new
      json_parser.on_parse_complete = proc do |event|
        self.handle_event(event)
      end

      # HTTP headers available
      http_parser.on_headers_complete = proc do
        http_ok = http_parser.status_code.to_i == 200
        @run_loop.log(:warn, :got_watch_headers, [http_ok])
        defer.resolve(http_ok)
      end

      # One chunk of the body
      http_parser.on_body = proc do |chunk|
        begin
          json_parser << chunk
        rescue Yajl::ParseError => bad_json
          @run_loop.log(:error, :bad_json, [bad_json, chunk])
        end
      end

      # Headers and body is all parsed
      http_parser.on_message_complete = proc do |env|
        @run_loop.log(:info, :on_message_completed, [])
      end

      new_client.connect(service_host, service_port.to_i) do |client|
        client.start_tls({:server => false, :cert_chain => var_run_secrets_k8s_crt_path})

        client.progress do |data|
          http_parser << data
        end

        client.on_handshake do
          client.enable_keepalive(10) #NOTE: TCP keep-alive circuit
          client.write(get_watch)
        end

        client.finally do |finish|
          @run_loop.log(:warn, :watch_disconnected, finish)
          retry_defer.resolve(true)
        end
      end

      new_client.catch do |err|
        #NOTE: if the connection refuses, retry the connection
        @run_loop.log(:warn, :watch_client_error, [err, err.class])
        if err.is_a?(Libuv::Error::ECONNREFUSED)
          retry_defer.resolve(true)
        end
      end

      new_client.start_read

      watch_timeout = @run_loop.timer
      watch_timeout.start(WATCH_TIMEOUT, 0)
      watch_timeout.progress do
        new_client.close
      end

      return retry_defer.promise
    end

    def ingress
      @run_loop.signal(:INT) do |_sigint|
        self.halt :run_loop_interupted
      end

      @run_loop.signal(:HUP) do |_sigint|
        self.halt :run_loop_hangup
      end

      @run_loop.signal(3) do |_sigint|
        self.halt :run_loop_quit
      end

      @run_loop.signal(15) do |_sigint|
        self.halt :run_loop_terminated
      end

      @failed_to_auth_timeout = @run_loop.timer
      @failed_to_auth_timeout.start(RECONNECT_WAIT * RECONNECT_TRIES, 0)
      @failed_to_auth_timeout.progress do
        self.halt :no_ok_auth_failed
      end

      proceed_to_emit_conf = self.install_heartbeat

      @run_loop.run do |logger|
        @stdout_pipe = @run_loop.pipe
        @stdout_pipe.open($stdout.fileno)

        @run_loop.log(:info, :run_dir, @run_dir)

        logger.progress do |level, type, message, _not_used|
          error_trace = (message && message.respond_to?(:backtrace)) ? [message, message.backtrace] : message
          @stdout_pipe.write(Yajl::Encoder.encode({:date => Time.now, :level => level, :type => type, :message => error_trace}))
          @stdout_pipe.write($/)
        end

        @retry_timer = @run_loop.timer
        @retry_timer.progress do
          self.connect(proceed_to_emit_conf)
        end
        @retry_timer.start(0, (RECONNECT_WAIT * 2))
      end
    end

    def install_heartbeat
      @heartbeat = @run_loop.timer

      @heartbeat.progress do
        if ingress_descriptions = @descriptions["ingress"]
          self.install_proxy(ingress_descriptions)
        end
      end

      defer = @run_loop.defer
      
      #defer.promise.then do
      #
      #end

      self.start_proxy

      return defer
    end

    def connect(proceed)
      ing_ok = self.create_watch_pipe("ingresses")
      ser_ok = self.create_watch_pipe("services")
      pod_ok = self.create_watch_pipe("pods")
      #end_ok = self.create_watch_pipe("endpoints")

      @run_loop.finally(ing_ok, ser_ok, pod_ok).then do |deferred_auths|
        auth_ok = deferred_auths.all? { |http_ok, resolved| http_ok }
        #@run_loop.log :info, :got_auth, auth_ok

        if auth_ok
          @retry_timer.stop
          @failed_to_auth_timeout.stop
          proceed.resolve
        end
      end
    end


    def handle_event(event)
      type = event["type"]
      description = event["object"]

      if description
        kind = description["kind"]
        name = description["metadata"]["name"]

        unless (kind == "Endpoints" && name == "kubernetes")
          #NOTE: kubernetes api-server endpoints are not logged, dont name your branch kubernetes
          @run_loop.log :info, :event, [type, kind, name]
        end

        case kind
          when "IngressList", "PodList", "ServiceList"

          when "Pod"
            self.register_pod(type, description)

          when "Service"
            self.register_service(type, description)

          when "Endpoints"
            unless (kind == "Endpoints" && name == "kubernetes")
              self.register_endpoint(type, description)
            end

          when "Ingress"
            self.register_ingress(type, description)

        end
      end

      if self.recheck
        @heartbeat.stop
        @heartbeat.start(RELOAD_TIMEOUT, 0)
      end
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
            if service = self.locate_service(service_name)
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

    def path_for_watch(kind)
      #TODO: add resource very query support e.g. ?resourceVersion=0
      path_prefix = "/%s/watch/namespaces/default/%s"
      path_for_watch = begin
        case kind
          when "pods"
            path_prefix % ["api/v1", "pods"]

          when "services"
            path_prefix % ["api/v1", "services"]

          when "ingresses"
            path_prefix % ["apis/extensions/v1beta1", "ingresses"]

          when "endpoints"
            path_prefix % ["api/v1", "endpoints"]

        else
          raise "unknown api Kind to watch: #{kind}"
        end
      end

      path_for_watch
    end
  end
end
