#

module Bespoked
  class Controller
    attr_accessor :var_lib_k8s,
                  :var_lib_k8s_host_to_app_dir,
                  :var_lib_k8s_app_to_alias_dir,
                  :var_lib_k8s_sites_dir,
                  :nginx_access_log_path,
                  :nginx_conf_path

    def initialize(options = {})
      self.var_lib_k8s = options["var-lib-k8s"] || Dir.mktmpdir
      self.var_lib_k8s_host_to_app_dir = File.join(@var_lib_k8s, "host_to_app") 
      self.var_lib_k8s_app_to_alias_dir = File.join(@var_lib_k8s, "app_to_alias") 
      self.var_lib_k8s_sites_dir = File.join(@var_lib_k8s, "sites")
      self.nginx_access_log_path = File.join(@var_lib_k8s, "access.log")
      self.nginx_conf_path = File.join(@var_lib_k8s, "nginx.conf")

      # create mapping conf.d dirs
      FileUtils.mkdir_p(@var_lib_k8s_host_to_app_dir)
      FileUtils.mkdir_p(@var_lib_k8s_app_to_alias_dir)
      FileUtils.mkdir_p(@var_lib_k8s_sites_dir)

      # prepare nginx
      local_nginx_conf = File.realpath(File.join(File.dirname(__FILE__), "../..", "nginx/empty.nginx.conf"))
      File.link(local_nginx_conf, @nginx_conf_path)
      nginx_access_file = File.open(@nginx_access_log_path, File::CREAT|File::RDWR|File::APPEND)
    end

    def ingress
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
=begin
        when "Ingress"
          puts [kind, name].inspect

          ingress_name = name

          ingress_description = description

          spec_rules = ingress_description["spec"]["rules"]

          vhost_lines = []
          spec_rules.each do |rule|
            rule_host = rule["host"]
            if http = rule["http"]
              http["paths"].each do |http_path|
                service_name = http_path["backend"]["serviceName"]

                if service = service_descriptions[service_name]
                  pod_name = service["spec"]["selector"]["name"]

                  if pod = pod_descriptions[pod_name]
                    pod_ip = pod["status"]["podIP"]

                    service_port = "#{pod_ip}:#{http_path["backend"]["servicePort"]}"

                    vhost_lines << [rule_host, service_name, service_port]
                  else
                    add_to_pending_documents = true
                  end
                else
                  add_to_pending_documents = true
                end
              end
            else
              add_to_pending_documents = true
            end
          end

          unless add_to_pending_documents
=end
      end
  end
end
