#

module Bespoked
  class Controller
    attr_accessor :var_lib_k8s,
                  :var_lib_k8s_host_to_app_dir,
                  :var_lib_k8s_app_to_alias_dir,
                  :var_lib_k8s_sites_dir,
                  :pod_descriptions,
                  :service_descriptions,
                  :ingress_descriptions,
                  :run_loop,
                  :pipes,
                  :nginx_access_log_path,
                  :nginx_conf_path,
                  :nginx_access_file,
                  :nginx_stdout_pipe,
                  :nginx_stderr_pipe,
                  :nginx_access_pipe,
                  :nginx_stdin,
                  :nginx_stdout,
                  :nginx_stderr,
                  :nginx_process_waiter

    def initialize(options = {})
      self.var_lib_k8s = options["var-lib-k8s"] || Dir.mktmpdir
      self.var_lib_k8s_host_to_app_dir = File.join(@var_lib_k8s, "host_to_app") 
      self.var_lib_k8s_app_to_alias_dir = File.join(@var_lib_k8s, "app_to_alias") 
      self.var_lib_k8s_sites_dir = File.join(@var_lib_k8s, "sites")

      # create mapping conf.d dirs
      FileUtils.mkdir_p(@var_lib_k8s_host_to_app_dir)
      FileUtils.mkdir_p(@var_lib_k8s_app_to_alias_dir)
      FileUtils.mkdir_p(@var_lib_k8s_sites_dir)


      self.pod_descriptions = {}
      self.service_descriptions = {}
      self.ingress_descriptions = {}

      self.run_loop = Libuv::Loop.default
      self.pipes = []

    end

    # prepares nginx run loop
    def install_nginx_pipes
      self.nginx_access_log_path = File.join(@var_lib_k8s, "access.log")
      self.nginx_conf_path = File.join(@var_lib_k8s, "nginx.conf")
      local_nginx_conf = File.realpath(File.join(File.dirname(__FILE__), "../..", "nginx/empty.nginx.conf"))
      File.link(local_nginx_conf, @nginx_conf_path)
      self.nginx_access_file = File.open(@nginx_access_log_path, File::CREAT|File::RDWR|File::APPEND)

      combined = ["nginx", "-p", @var_lib_k8s, "-c", "nginx.conf", "-g", "pid #{@var_lib_k8s}/nginx.pid;"]
      p combined
      self.nginx_stdin, self.nginx_stdout, self.nginx_stderr, self.nginx_process_waiter = Open3.popen3(*combined)

      self.nginx_stdout_pipe = @run_loop.pipe
      self.nginx_stderr_pipe = @run_loop.pipe
      self.nginx_access_pipe = @run_loop.pipe

      @pipes << self.nginx_stdout_pipe
      @pipes << self.nginx_stderr_pipe
      @pipes << self.nginx_access_pipe

      self.nginx_stdout_pipe.open(@nginx_stdout.fileno)
      self.nginx_stderr_pipe.open(@nginx_stderr.fileno)
      #self.nginx_access_pipe.open(@nginx_access_file.fileno)

      @nginx_stderr_pipe.progress do |data|
        @run_loop.log :nginx_stderr, data
      end
      @nginx_stderr_pipe.start_read

      @nginx_stdout_pipe.progress do |data|
        @run_loop.log :nginx_stdout, data
      end
      @nginx_stdout_pipe.start_read

      #@nginx_access_pipe.progress do |data|
      #  @run_loop.log :nginx_access, data
      #end
      #@nginx_access_pipe.start_read
    end

    def halt(message)
      if @nginx_process_waiter
        begin
          Process.kill("INT", @nginx_process_waiter.pid)
        rescue Errno::ESRCH
        end
        @nginx_process_waiter.join
      end
      @run_loop.stop
      p message
      #exit 1
    end

    def create_watch_pipe(resource_kind)
      service_host = ENV["KUBERNETES_SERVICE_HOST"] || self.halt("KUBERNETES_SERVICE_HOST missing")
      service_port = ENV["KUBERNETES_SERVICE_PORT_HTTPS"] || self.halt("KUBERNETES_SERVICE_PORT_HTTPS missing")
      bearer_token = File.read('kubernetes/api.token').strip
      get_watch = "GET /apis/extensions/v1beta1/watch/namespaces/default/#{resource_kind} HTTP/1.1\r\nHost: #{service_host}\r\nAuthorization: Bearer #{bearer_token}\r\nAccept: application/json, */*\r\nUser-Agent: bespoked\r\n\r\n"

      client = @run_loop.tcp

      http_parser = Http::Parser.new

      http_parser.on_headers_complete = proc do
        p http_parser.headers
      end

      http_parser.on_body = proc do |chunk|
        # One chunk of the body
        p chunk
      end

      http_parser.on_message_complete = proc do |env|
        # Headers and body is all parsed
      end

      client.connect(service_host, service_port.to_i) do |client|
        client.start_tls({:server => false, :verify_peer => false, :cert_chain => "kubernetes/ca.crt"})

        client.progress do |data|
          #puts data #["client got", data].inspect
          http_parser << data
        end

        client.on_handshake do
          puts get_watch
          client.write(get_watch)
        end

        client.start_read
      end
    end

    def ingress
      @run_loop.signal(:INT) do |_sigint|
        self.halt :run_loop_interupted
      end

      @run_loop.run do |logger|
        logger.progress do |level, errorid, error|
          p [level, errorid, error]
        end
      
        self.create_watch_pipe("ingresses")
        self.install_nginx_pipes

        @run_loop.log :info, :run_loop_started
      end

      p "run_loop_exited"
    end

    def install_vhosts(pod_name, vhosts)
      host_to_app_template = "%s %s;\n"
      app_to_alias_template = "%s %s;\n"
      default_alias = "/dev/null/"

      site_template = <<-EOF_NGINX_SITE_TEMPLATE
        upstream %s {
          server %s fail_timeout=0;
        }
      EOF_NGINX_SITE_TEMPLATE

      vhosts.each do |host, app, upstream|
        host_to_app_line = host_to_app_template % [host, app]
        app_to_alias_line = app_to_alias_template % [app, default_alias]
        site_config = site_template % [app, upstream]

        map_name = [pod_name, app].join("-")

        #puts File.join(@var_lib_k8s_host_to_app_dir, map_name)
        File.open(File.join(@var_lib_k8s_host_to_app_dir, map_name), "w+") do |f|
          f.write(host_to_app_line)
        end

        File.open(File.join(@var_lib_k8s_app_to_alias_dir, map_name), "w+") do |f|
          f.write(app_to_alias_line)
        end

        File.open(File.join(@var_lib_k8s_sites_dir, map_name), "w+") do |f|
          f.write(site_config)
        end
      end
    end

    def register_service(description)
      name = self.extract_name(description)
      @service_descriptions[name] = description
    end

    def locate_service(name)
      @service_descriptions[name]
    end

    def register_pod(description)
      name = self.extract_name(description)
      @pod_descriptions[name] = description
    end

    def locate_pod(name)
      @pod_descriptions[name]
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
                  vhosts << [rule_host, service_name, service_port]
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
