#

module Bespoked
  class NginxProxy < IngressProxy
    attr_accessor :pipes,
                  :filesystem,
                  :nginx_conf_path,
                  :nginx_stdout_pipe,
                  :nginx_stderr_pipe,
                  :nginx_stdin,
                  :nginx_stdout,
                  :nginx_stderr,
                  :nginx_process_waiter,
                  :run_dir,
                  :var_lib_k8s,
                  :var_lib_k8s_host_to_app_dir,
                  :var_lib_k8s_app_to_alias_dir,
                  :var_lib_k8s_sites_dir,
                  :var_lib_k8s_logs_dir,
                  :version_dir,
                  :version

    def initialize(run_loop_in, controller_in)
      super(run_loop_in, controller_in)

      self.version = 0
      self.pipes = []
      self.filesystem = @run_loop.filesystem
      self.run_dir = options["var-lib-k8s"] || Dir.mktmpdir
      self.var_lib_k8s = File.join(@run_dir, "current")
    end

    def install(ingress_descriptions)
      self.nginx_mkdir.then do
        self.write_vhosts(ingress_descriptions)
        self.nginx_install_version.then do
          begin
            Process.kill("HUP", @nginx_process_waiter.pid)
          rescue Errno::ESRCH => no_child
            @run_loop.log(:warn, :no_child, @nginx_process_waiter.pid)
          end

          if @version > 2
            third_oldest_version = File.join(@run_dir, "last-version-before-" + (@version - 2).to_s)
            system("rm", "-Rf", third_oldest_version)
          end
        end
      end
    end

    # prepares nginx run loop
    def start
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

    def stop
      if @nginx_process_waiter
        begin
          Process.kill("INT", @nginx_process_waiter.pid)
        rescue Errno::ESRCH
        end
        @nginx_process_waiter.join
      end
    end

    def write_vhosts(ingress_descriptions)
      host_to_app_template = "%s %s;\n"
      app_to_alias_template = "%s %s;\n"
      default_alias = "/dev/null/"

      site_template = <<-EOF_NGINX_SITE_TEMPLATE
        upstream %s {
          least_conn;
          %s
        }
      EOF_NGINX_SITE_TEMPLATE

      ## NOTE: commercial nginx should activate DNS upstream resolution
      ## zone upstreams 32m;
      ## server %s max_fails=0 fail_timeout=0 resolve
      ## ... ugh

      upstream_template = "server %s max_fails=0 fail_timeout=0"

      ingress_descriptions.values.each do |ingress_description|
        vhosts_for_ingress = self.extract_vhosts(ingress_description)
        vhosts_for_ingress.each do |host, service_name, upstreams|
          host_to_app_line = host_to_app_template % [host, service_name]
          app_to_alias_line = app_to_alias_template % [service_name, default_alias]
          upstream_lines = upstreams.collect { |upstream|
            upstream_template % [upstream]
          }

          site_upstreams = (upstream_lines * 8).map { |up| up + ";" }.join("\n")

          site_config = site_template % [service_name, site_upstreams]

          map_name = service_name

          if Dir.exists?(@var_lib_k8s_host_to_app_dir) &&
             Dir.exists?(@var_lib_k8s_app_to_alias_dir) &&
             Dir.exists?(@var_lib_k8s_sites_dir) then

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

            @run_loop.log(:info, :installing_ingress, [host, service_name, site_upstreams])
          else
            @run_loop.log(:info, :missing_map_dirs, [host, service_name, site_upstreams])
          end
        end
      end
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

    def nginx_mkdir
      defer = @run_loop.defer

      @version += 1

      self.version_dir = File.join(@run_dir, (@version).to_s)
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
  end
end
