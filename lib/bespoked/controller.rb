#

module Bespoked
  class Controller
    attr_accessor :run_dir,
                  :var_lib_k8s,
                  :var_lib_k8s_host_to_app_dir,
                  :var_lib_k8s_app_to_alias_dir,
                  :var_lib_k8s_sites_dir,
                  :var_lib_k8s_logs_dir,
                  :descriptions,
                  :run_loop,
                  :pipes,
                  :nginx_conf_path,
                  :nginx_stdout_pipe,
                  :nginx_stderr_pipe,
                  :nginx_stdin,
                  :nginx_stdout,
                  :nginx_stderr,
                  :nginx_process_waiter,
                  :filesystem,
                  :version_dir,
                  :version

    def initialize(options = {})
      self.version = 0
      self.run_dir = options["var-lib-k8s"] || Dir.mktmpdir
      self.var_lib_k8s = File.join(@run_dir, "current")
      self.descriptions = {}

      self.run_loop = Libuv::Loop.default
      self.filesystem = @run_loop.filesystem
      self.pipes = []
    end

    def nginx_mkdir
      defer = @run_loop.defer

      @version += 1

      self.version_dir = File.join(@run_dir, (@version).to_s) # old Dir.mktmpdir #NOTE: this is outside the runloop....!
      self.var_lib_k8s_host_to_app_dir = File.join(@version_dir, "host_to_app") 
      self.var_lib_k8s_app_to_alias_dir = File.join(@version_dir, "app_to_alias") 
      self.var_lib_k8s_sites_dir = File.join(@version_dir, "sites")
      self.var_lib_k8s_logs_dir = File.join(@version_dir, "logs")

      @run_loop.finally(@filesystem.mkdir(@version_dir)).then do
        @filesystem.mkdir(@var_lib_k8s_host_to_app_dir).then do
          @filesystem.mkdir(@var_lib_k8s_app_to_alias_dir).then do
            @filesystem.mkdir(@var_lib_k8s_logs_dir).then do
              @filesystem.mkdir(@var_lib_k8s_sites_dir).then do
                defer.resolve(@version_dir)
              end
            end
          end
        end
      end

      return defer.promise
    end

    def nginx_install_version
      defer = @run_loop.defer

      @last_lstat = @filesystem.lstat(@var_lib_k8s)

      proceed = proc {
        @filesystem.rename(@version_dir, @var_lib_k8s).then do
          defer.resolve(true)
        end
      }

      lstat_failed = proc { |reason|
        @run_loop.log :info, :ignore_current_lstat_failed, reason
        proceed.call
      }

      proceed_with_current_to_last_rename = proc {
        rename_current_failed = proc { |reason|
          @run_loop.log :error, :rename_current_to_last_failed, reason
        }

        @filesystem.rename(@var_lib_k8s, File.join(@run_dir, "last-version-before-" + @version.to_s)).then(nil, rename_current_failed) do
          proceed.call
        end
      }

      @last_lstat.then(nil, lstat_failed) do
        proceed_with_current_to_last_rename.call
      end

      return defer.promise
    end

    # prepares nginx run loop
    def install_nginx_pipes
      self.nginx_conf_path = File.join(@run_dir, "nginx.conf")
      local_nginx_conf = File.realpath(File.join(File.dirname(__FILE__), "../..", "nginx/empty.nginx.conf"))

      File.link(local_nginx_conf, @nginx_conf_path)

      self.nginx_mkdir.then do |new_version|
        self.nginx_install_version.then do
          combined = ["nginx", "-p", @run_dir, "-c", "nginx.conf", "-g", "pid #{@run_dir}/nginx.pid;"]
          self.nginx_stdin, self.nginx_stdout, self.nginx_stderr, self.nginx_process_waiter = Open3.popen3(*combined)

          self.nginx_stdout_pipe = @run_loop.pipe
          self.nginx_stderr_pipe = @run_loop.pipe

          @pipes << self.nginx_stdout_pipe
          @pipes << self.nginx_stderr_pipe

          self.nginx_stdout_pipe.open(@nginx_stdout.fileno)
          self.nginx_stderr_pipe.open(@nginx_stderr.fileno)

          @nginx_stderr_pipe.progress do |data|
            @run_loop.log :info, :nginx_stderr, data
          end
          @nginx_stderr_pipe.start_read

          @nginx_stdout_pipe.progress do |data|
            @run_loop.log :info, :nginx_stdout, data
          end
          @nginx_stdout_pipe.start_read
        end
      end
    end

    def halt(message)
      if @nginx_process_waiter
        begin
          Process.kill("INT", @nginx_process_waiter.pid)
        rescue Errno::ESRCH
        end
        @nginx_process_waiter.join
      end
      @run_loop.log(:info, :halt, message)
      @run_loop.stop
    end

    def create_watch_pipe(resource_kind)
      defer = @run_loop.defer

      reconnect_timer = @run_loop.timer

      proceed_with_reconnect = proc {
        reconnect_timer.stop
        reconnect_timer.start(100, 0)
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

      service_host = ENV["KUBERNETES_SERVICE_HOST"] || "127.0.0.1"
      service_port = ENV["KUBERNETES_SERVICE_PORT_HTTPS"] || "8443"
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
        #TODO: @run_loop.log(:info, :on_message_completed, [])
      end

      new_client.connect(service_host, service_port.to_i) do |client|
        client.start_tls({:server => false}) #, :verify_peer => false, :cert_chain => "kubernetes/ca.crt"})

        client.progress do |data|
          http_parser << data
        end

        client.on_handshake do
          client.write(get_watch)
        end

        client.finally do |fin|
          retry_defer.resolve(true)
        end
      end

      new_client.catch do |err|
        #NOTE: if the connection refuses, retry the connection
        if err.is_a?(Libuv::Error::ECONNREFUSED)
          retry_defer.resolve(true)
        end
      end

      new_client.start_read

      return retry_defer.promise
    end

    def ingress
      p @run_dir

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
      @failed_to_auth_timeout.start(5000, 0)
      @failed_to_auth_timeout.progress do
        self.halt :no_ok_auth_failed
      end

      proceed_to_emit_conf = self.install_heartbeat

      @run_loop.run do |logger|
        logger.progress do |level, type, message, wtf|
          error_trace = (message && message.respond_to?(:backtrace)) ? [message, message.backtrace] : message
          p [:log_progress, level, type, error_trace, wtf]
        end

        @retry_timer = @run_loop.timer
        @retry_timer.progress do
          self.connect(proceed_to_emit_conf)
        end
        @retry_timer.start(0, 500)
      end

      p "run_loop_exited"
    end

    def install_heartbeat
      @heartbeat = @run_loop.timer
      defer = @run_loop.defer
      defer.promise.then do
        @heartbeat.progress do
          @heartbeat.stop
          if ingress_descriptions = @descriptions["ingress"]
            self.nginx_mkdir.then do
              self.install_vhosts(ingress_descriptions)
              self.nginx_install_version.then do
                begin
                  Process.kill("HUP", @nginx_process_waiter.pid)
                rescue Errno::ESRCH => no_child
                  @run_loop.log(:warn, :no_child, @nginx_process_waiter.pid)
                end
              end
            end
          end
        end
      end

      self.install_nginx_pipes

      return defer
    end

    def connect(proceed)
      ing_ok = self.create_watch_pipe("ingresses")
      ser_ok = self.create_watch_pipe("services")
      pod_ok = self.create_watch_pipe("pods")
      @run_loop.finally(ing_ok, ser_ok, pod_ok).then do |deferred_auths|
        auth_ok = deferred_auths.all? { |http_ok, resolved| http_ok }
        @run_loop.log :info, :got_auth, auth_ok

        if auth_ok
          @retry_timer.stop
          @failed_to_auth_timeout.stop
          proceed.resolve
        end
      end
    end

    def install_vhosts(ingress_descriptions)
      host_to_app_template = "%s %s;\n"
      app_to_alias_template = "%s %s;\n"
      default_alias = "/dev/null/"

      site_template = <<-EOF_NGINX_SITE_TEMPLATE
        upstream %s {
          server %s fail_timeout=0;
        }
      EOF_NGINX_SITE_TEMPLATE

      ingress_descriptions.values.each do |ingress_description|
        vhosts_for_ingress = self.extract_vhosts(ingress_description)
        vhosts_for_ingress.each do |pod, host, app, upstream|
          pod_name = self.extract_name(pod)
          host_to_app_line = host_to_app_template % [host, app]
          app_to_alias_line = app_to_alias_template % [app, default_alias]
          site_config = site_template % [app, upstream]
          map_name = [pod_name, app].join("-")

          #TODO: make this use async io
          File.open(File.join(@var_lib_k8s_host_to_app_dir, map_name), "w+") do |f|
            f.write(host_to_app_line)
          end

          File.open(File.join(@var_lib_k8s_app_to_alias_dir, map_name), "w+") do |f|
            f.write(app_to_alias_line)
          end

          File.open(File.join(@var_lib_k8s_sites_dir, map_name), "w+") do |f|
            f.write(site_config)
          end

          @run_loop.log(:info, :installing_ingress, [pod_name, host, app, upstream])
        end
      end
    end

    KINDS = ["pod", "service", "ingress"]
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
              pod_name = service["spec"]["selector"]["name"]
              if pod = self.locate_pod(pod_name)
                if status = pod["status"]
                  pod_ip = status["podIP"]
                  service_port = "#{pod_ip}:#{http_path["backend"]["servicePort"]}"
                  vhosts << [pod, rule_host, service_name, service_port]
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

        else
          raise "unknown api Kind to watch: #{kind}"
        end
      end

      path_for_watch
    end

    def handle_event(event)
      type = event["type"]
      description = event["object"]

      if description
        kind = description["kind"]
        name = description["metadata"]["name"]
        @run_loop.log :info, :event, [type, kind, name]
        case kind
          when "IngressList", "PodList", "ServiceList"

          when "Pod"
            self.register_pod(type, description)

          when "Service"
            self.register_service(type, description)

          when "Ingress"
            self.register_ingress(type, description)

        end
      end

      @heartbeat.stop
      @heartbeat.start(100, 0)
    end
  end
end
