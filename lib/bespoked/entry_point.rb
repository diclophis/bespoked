#

module Bespoked
  class EntryPoint
    attr_accessor :proxy,
                  :descriptions,
                  :run_loop,
                  :checksum,
                  :watch,
                  :dashboard,
                  :health,
                  :watch_class,
                  :proxy_class,
                  :failure_to_auth_timer,
                  :authenticated,
                  :stopping,
                  :heartbeat

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

    def initialize(run_loop_in, options = {})
      self.descriptions = {}
      self.run_loop = run_loop_in #Libuv::Reactor.default #Libuv::Reactor.new #Libuv::Loop.default
      self.authenticated = false
      self.stopping = false

      #self.watch_class = Bespoked.const_get(options["watch-class"] || "KubernetesWatch")
      #self.proxy_class = Bespoked.const_get(options["proxy-class"] || "RackProxy")
    end

    def start
      @run_loop.log :info, :controller_start, [@proxy, @health, @dashboard]

      @proxy.start if @proxy
      @health.start if @health
      @dashboard.start if @dashboard
    end

    def stop_proxy
      @proxy.stop if @proxy
    end

    def install_proxy
      if ingress_descriptions = @descriptions["ingress"]
        @proxy.install(ingress_descriptions) if @proxy
      end
    end

    def recheck
      old_checksum = @checksum
      @checksum = Digest::MD5.hexdigest(Marshal.dump(@descriptions))
      changed = @checksum != old_checksum
      @run_loop.log :info, :checksum, [old_checksum, @checksum] if changed
      return changed
    end

    def running?
      !@stopping
    end

    def halt(message)
      #self.stop_proxy
      #@run_loop.log(:info, :halt, message)
      #@run_loop.stop
      @stopping = true
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

    def run_ingress_controller(fail_after_milliseconds = FAILED_TO_AUTH_TIMEOUT)
      @failure_to_auth_timer = @run_loop.timer
      @failure_to_auth_timer.progress do
        self.halt :no_ok_auth_failed
      end
      @failure_to_auth_timer.start(fail_after_milliseconds, 0)

      self.install_heartbeat

=begin
      proceed_to_emit_conf = self.install_heartbeat
=end

=begin
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

        self.watch = @watch_class.new(@run_loop)
        self.proxy = @proxy_class.new(@run_loop, self)
        self.dashboard = Dashboard.new(@run_loop)
        self.health = HealthService.new(@run_loop)
      end
=end
    
      yield if block_given?
    end

    def install_heartbeat
      self.heartbeat = @run_loop.timer

      @heartbeat.progress do
        #@run_loop.log(:info, :heartbeat_progress)
        self.install_proxy
      end

=begin
      defer = @run_loop.defer

      #TODO: what is this defer for???
      defer.promise.then do
        self.start
      end

      return defer
=end
    end

    def resolve_authentication!(proceed = nil)
      #@retry_timer.stop
      @failure_to_auth_timer.stop
      @authenticated = true
      proceed.resolve if proceed
    end

    def connect(proceed)
      ing_ok = self.pipe("ingresses")
      ser_ok = self.pipe("services")
      pod_ok = self.pipe("pods")

      @run_loop.finally(ing_ok, ser_ok, pod_ok).then do |deferred_auths|
        auth_ok = deferred_auths.all? { |http_ok, resolved| http_ok }

        if auth_ok
          self.resolve_authentication!(proceed)
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
