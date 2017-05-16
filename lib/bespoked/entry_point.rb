#

module Bespoked
  class EntryPoint
    attr_accessor :descriptions,
                  :run_loop,
                  :logger,
                  :checksum,
                  :watch_factory,
                  :watch_factory_class,
                  :proxy_controller,
                  :proxy_controller_factory_class,
                  :watches,
                  :dashboard,
                  :health_controller,
                  :dashboard_controller,
                  :failure_to_auth_timer,
                  :reconnect_timer,
                  :authenticated,
                  :stopping,
                  :heartbeat,
                  :tls_controller

    RECONNECT_WAIT = 2000
    FAILED_TO_AUTH_TIMEOUT = 60000
    RELOAD_TIMEOUT = 100

    KINDS = ["pod", "service", "ingress", "endpoint", "secret"]
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

    def initialize(run_loop_in, logger_in, list_of_resources_to_watch = [], options = {})
      self.watches = []
      self.descriptions = {}
      self.authenticated = false

      self.run_loop = run_loop_in
      self.logger = logger_in
      @list_of_resources_to_watch = list_of_resources_to_watch

      self.proxy_controller_factory_class = Bespoked.const_get(options["proxy-controller-factory-class"] || "RackProxyController")
      self.proxy_controller =  self.proxy_controller_factory_class.new(@run_loop, self)

      self.watch_factory_class = Bespoked.const_get(options["watch-factory-class"] || "KubernetesApiWatchFactory")
      self.watch_factory = @watch_factory_class.new(@run_loop, @logger)

      # fork these into sub processes?
      self.health_controller = Bespoked::HealthController.new(@run_loop, @logger)
      self.dashboard_controller = Bespoked::DashboardController.new(@run_loop, @logger, @proxy_controller)
      self.tls_controller = Bespoked::TlsController.new(@run_loop, @logger, proxy_controller)
    end

    def halt(message)
      @failure_to_auth_timer.stop if @failure_to_auth_timer

      @proxy_controller.shutdown
      @health_controller.shutdown
      @dashboard_controller.shutdown
      @tls_controller.shutdown
      @logger.shutdown

      @watches.each do |watch|
        watch.shutdown
      end
    end

    def add_tls_host(private_key, cert_chain, host_name)
      @proxy_controller.add_tls_host(private_key, cert_chain, host_name)
    end

    def record(level = nil, name = nil, message = nil)
      log_event = {:date => Time.now, :level => level, :name => name, :message => message}
      @logger.notify(log_event)
    end

    def install_watch(new_watch)
      if new_watch
        new_watch.on_event do |event|
          self.handle_event(event)
        end
        self.watches << new_watch
      end
    end

    def install_ingress_into_proxy_controller
      if ingress_descriptions = @descriptions["ingress"]
        #self.record :info, :install_ingress, ingress_descriptions
        @proxy_controller.install(ingress_descriptions)
      end
    end

    def recheck
      old_checksum = @checksum
      @checksum = Digest::MD5.hexdigest(Marshal.dump(@descriptions))
      changed = @checksum != old_checksum

      #self.record :info, :checksum, [old_checksum, @checksum] if changed

      return changed
    end

    def on_failed_to_auth_cb
      self.record :info, :on_failed_to_auth_cb, []

      self.halt :no_ok_auth_failed
    end

    def on_reconnect_cb
      self.record :info, :on_reconnect_cb, []

      self.connect(nil)
    end

    def run_ingress_controller(fail_after_milliseconds = FAILED_TO_AUTH_TIMEOUT, reconnect_wait = RECONNECT_WAIT)
      @logger.start
      @proxy_controller.start
      @health_controller.start
      @dashboard_controller.start
      @tls_controller.start

      self.failure_to_auth_timer = @run_loop.timer
      @failure_to_auth_timer.progress do
        self.on_failed_to_auth_cb
      end
      @failure_to_auth_timer.start(fail_after_milliseconds, 0)

      @list_of_resources_to_watch.collect do |resource_to_watch|
        self.record :info, :creating_watch, [resource_to_watch]

        new_watch = @watch_factory.create(resource_to_watch)
        self.install_watch(new_watch)
      end

      #self.install_heartbeat

      self.prep_connect

      #self.reconnect_timer = @run_loop.timer
      #@reconnect_timer.progress do

      self.on_reconnect_cb

      #end
      #@reconnect_timer.start(0, reconnect_wait)
      #if reconnect_wait
      #else
      #  @reconnect_timer.start(0, RECONNECT_WAIT)
      #end

      self.record :info, :run_ingress_controller, []

      yield if block_given?
    end

    def install_heartbeat
      self.record :info, :pre_install_hb, []

      self.heartbeat = @run_loop.defer

      @heartbeat.promise.progress do
        self.record :info, :heartbeat_progress, []

        self.install_ingress_into_proxy_controller
      end

      self.record :info, :installed_heartbeat, []

      self.heartbeat
    end

    def resolve_authentication!
      self.record :info, :resolved_auth, []

      @failure_to_auth_timer.stop
      @authenticated = true
    end

    def prep_connect
      #self.record :info, :prep_connect, []

      promises = @watches.collect { |watch| watch.waiting_for_authentication_promise }.compact

      #self.record :info, :connect_002, []

      if promises.length > 0
        self.record :info, :connect, promises

        @run_loop.finally(*promises).then do |watch_authentication_promises|
          self.record :info, :connect_finally, watch_authentication_promises

          all_watches_authed_ok = watch_authentication_promises.all? { |http_ok, resolved| 
            #each [result, wasResolved] value pair corresponding to a at the same index in the `promises` array.
            http_ok
          }

          if all_watches_authed_ok
            self.resolve_authentication!
          end
        end
      end
    end

    def connect(proceed)
      #self.record :info, :connect_001, [proceed]

      @watches.each do |watch|
        #self.record :info, :watch_restart, [proceed]

        watch.restart
      end
    end

    def handle_event(event)
      #self.record :info, :handle_event, [event.inspect]

      return unless event

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
          #self.record :info, :event, [type, kind, name]
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

          when "SecretList"
            event["items"].each do |secret|
              self.register_secret(type, secret)
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

          when "Secret"
            self.register_secret(type, description)

        else
          self.record(:info, :unsupported_resource_list_type, kind)
        end
      end

      if self.recheck
        self.install_ingress_into_proxy_controller
        #@heartbeat.stop
        #@heartbeat.start(RELOAD_TIMEOUT, 0)
        #@heartbeat.notify
      end
    end

    def extract_name(description)
      if metadata = description["metadata"]
        metadata["name"]
      end
    end
  end
end
