#

module Bespoked
  class Controller
    attr_accessor :proxy,
                  :descriptions,
                  :run_loop,
                  :checksum,
                  :watch,
                  :dashboard,
                  :health,
                  :watch_class,
                  :proxy_class

    RECONNECT_WAIT = 500
    FAILED_TO_AUTH_TIMEOUT = 30000
    RELOAD_TIMEOUT = 1

    KINDS = ["pod", "service", "ingress", "endpoint"]
    KINDS.each do |kind|
      register_method = "register_#{kind}"
      locate_method = "locate_#{kind}"

      define_method register_method do |event, description|
        self.descriptions[kind] ||= {}

        name = self.extract_name(description)

        case event
          when "DELETED"
            self.descriptions[kind].delete(name)

        else
          self.descriptions[kind][name] = description
        end
      end

      define_method locate_method do |name|
        self.descriptions[kind] ||= {}
        self.descriptions[kind][name]
      end
    end

    def initialize(options = {})
      self.descriptions = {}
      self.run_loop = Libuv::Reactor.default #Libuv::Reactor.new #Libuv::Loop.default

      self.watch_class = Bespoked.const_get(options["watch-class"] || "KubernetesWatch")
      self.proxy_class = Bespoked.const_get(options["proxy-class"] || "RackProxy")
    end

    def start
      @run_loop.log :info, :controller_start, [@proxy, @health, @dashboard]

        self.watch = @watch_class.new(@run_loop)
        self.proxy = @proxy_class.new(@run_loop, self)
        self.dashboard = Dashboard.new(@run_loop)
        self.health = HealthService.new(@run_loop)

      @proxy.start if @proxy
      @health.start if @health
      @dashboard.start if @dashboard
    end

    def stop_proxy
      @proxy.stop if @proxy
    end

    def install_proxy(ingress_descriptions)
      @proxy.install(ingress_descriptions) if @proxy
    end

    def recheck
      old_checksum = @checksum
      @checksum = Digest::MD5.hexdigest(Marshal.dump(@descriptions))
      changed = @checksum != old_checksum
      @run_loop.log :info, :checksum, [old_checksum, @checksum] if changed
      return changed
    end

    def halt(message)
      self.stop_proxy
      @run_loop.log(:info, :halt, message)
      @run_loop.stop
    end

    def pipe(resource_kind)
      defer = @run_loop.defer

      reconnect_timer = @run_loop.timer

      proceed_with_reconnect = proc {
        reconnect_timer.stop
        reconnect_timer.start(RECONNECT_WAIT, 0)
      }

      reconnect_timer.progress do
        json_parser = Yajl::Parser.new
        json_parser.on_parse_complete = proc do |event|
          self.handle_event(event)
        end

        if @watch
          reconnect_loop = @watch.create(resource_kind, defer, json_parser)
          reconnect_loop.then do
            proceed_with_reconnect.call
          end
        else
          proceed_with_reconnect.call
        end
      end

      proceed_with_reconnect.call

      return defer.promise
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
      @failed_to_auth_timeout.start(FAILED_TO_AUTH_TIMEOUT, 0)
      @failed_to_auth_timeout.progress do
        self.halt :no_ok_auth_failed
      end

      proceed_to_emit_conf = self.install_heartbeat

      @run_loop.run do |logger|
        @stdout_pipe = @run_loop.pipe
        @stdout_pipe.open($stdout.fileno)

        logger.notifier do |level, type, message, _not_used|
          error_trace = (message && message.respond_to?(:backtrace)) ? [message, message.backtrace] : message
          @stdout_pipe.write(Yajl::Encoder.encode({:date => Time.now, :level => level, :type => type, :message => error_trace}))
          @stdout_pipe.write($/)
        end

        @retry_timer = @run_loop.timer
        @retry_timer.progress do
          self.connect(proceed_to_emit_conf)
        end
        @retry_timer.start(RECONNECT_WAIT, 0)

      end
    end

    def install_heartbeat
      @heartbeat = @run_loop.timer

      @heartbeat.progress do
        #@run_loop.log(:info, :heartbeat_progress)
        if ingress_descriptions = @descriptions["ingress"]
          self.install_proxy(ingress_descriptions)
        end
      end

      defer = @run_loop.defer

      #TODO: what is this defer for???
      defer.promise.then do
        self.start
      end

      return defer
    end

    def connect(proceed)
      ing_ok = self.pipe("ingresses")
      ser_ok = self.pipe("services")
      pod_ok = self.pipe("pods")

      @run_loop.finally(ing_ok, ser_ok, pod_ok).then do |deferred_auths|
        auth_ok = deferred_auths.all? { |http_ok, resolved| http_ok }

        if auth_ok
          @retry_timer.stop
          @failed_to_auth_timeout.stop
          proceed.resolve
        end
      end
    end

    def handle_event(event)
      type = nil
      description = nil

      if type = event["type"]
        description = event["object"]
      else
        type = "ADDED"
        description = event
      end

      if description
        kind = description["kind"]
        name = description["metadata"]["name"]

        unless (kind == "Endpoints" && name == "kubernetes")
          #NOTE: kubernetes api-server endpoints are not logged, dont name your branch kubernetes
          #@run_loop.log :info, :event, [type, kind, name]
        end

        case kind
          when "PodList"
            event["items"].each do |pod|
              self.register_pod(type, pod)
            end

          when "ServiceList"
            event["items"].each do |service|
              self.register_service(type, service)
            end

          when "IngressList"
            event["items"].each do |ingress|
              self.register_ingress(type, ingress)
            end

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

        else
          @run_loop.log(:info, :unsupported_resource_list_type, kind)
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
  end
end
