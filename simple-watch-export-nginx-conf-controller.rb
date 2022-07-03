#

require './lib/bespoked'

client = Bespoked.new

client.watch!("pods", "services", "ingresses")

client.ingest! do |pods, services, ingresses|
  upstream_map = ""
  host_to_app_map = ""
  app_to_alias_map = ""

  ingresses && ingresses.each { |ingress, ing_spec|
    rules = ing_spec["rules"]
    rules.each { |rule|
      host = rule["host"]
      http = rule["http"]
      paths = http["paths"]
      paths.each { |path|
        backend = path["backend"]
        service = backend["service"]
        service_name = service["name"]
        service_port = service["port"]

        if services && found_service = services[service_name]
          type = found_service["type"]

          case type
            when "NodePort"
              node_port = found_service["ports"].detect { |port|
                port["port"] == service_port["number"]
              }

              puts service_name

              #upstream_map += "upstream #{service_name} {\n  server 127.0.0.1:#{node_port["nodePort"]} fail_timeout=0;\n}\n"
              upstream_map += "upstream #{service_name} {\n"
              2.times do |i|
                upstream_map += "  server 127.0.0.1:#{node_port["nodePort"]} fail_timeout=0 #{i > 0 ? "backup" : ""};\n"
              end
              upstream_map += "}\n"
              host_to_app_map += "#{host} #{service_name};\n"
              app_to_alias_map += "#{service_name} /usr/share/nginx/html2/;\n"

            when "ClusterIP"
              cluster_ip = found_service["clusterIP"]
              upstream_map += "upstream #{service_name} {\n"
              2.times do |i|
                upstream_map += "  server #{cluster_ip}:#{service_port} fail_timeout=0 #{i > 0 ? "backup" : ""}\n"
              end
              upstream_map += "}\n"
              host_to_app_map += "#{host} #{service_name};\n"
              app_to_alias_map += "#{service_name} /usr/share/nginx/html2/;\n"

          end
        end
      }
    }
  }

  puts upstream_map
  puts host_to_app_map
  puts app_to_alias_map

  #confd_dir = ENV["MOCK_CONFD_DIR"] || "/etc/nginx/conf.d"

  #File.open("#{confd_dir}/hosts_app.conf", "w+") { |f|
  #  f.write(upstream_map)
  #}

  #File.open("#{confd_dir}/hosts_app.map", "w+") { |f|
  #  f.write(host_to_app_map)
  #}

  #File.open("#{confd_dir}/hosts_app_alias.map", "w+") {|f|
  #  f.write(app_to_alias_map)
  #}

  #unless system("sudo", "systemctl", "reload", "nginx.service")
  #  $stderr.write("bad nginx conf\n")
  #  exit(1)
  #end

  #$stdout.write("updated vhost table\n")
  #$stdout.flush
end
