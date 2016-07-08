#!/usr/bin/env ruby

# stdlib
require 'tempfile'
require 'yaml'
require 'fileutils'

# rubygems
Bundler.require

# curl -s -v -H "Accept: application/json" http://localhost:8080/api/v1/watch/namespaces/default/services

IO_CHUNK_SIZE = 65554
IDLE_SPIN = 10.0

class Bespoked
  def kubectl_get
    if ENV["CI"] && ENV["CI"] == "true"
      ["ruby", "-e", "f=File.open(File.join('test/fixtures', ARGV[0] + '.json')); while c = f.getc do STDOUT.write(c) && sleep(0.001) end"]
    else
      ["sleep", "9999"]
    end
  end

  def ingress(options = {})
    var_lib_k8s = options["var-lib-k8s"]
    var_lib_k8s_host_to_app_dir = File.join(var_lib_k8s, "host_to_app") 
    var_lib_k8s_app_to_alias_dir = File.join(var_lib_k8s, "app_to_alias") 
    var_lib_k8s_sites_dir = File.join(var_lib_k8s, "sites")

    FileUtils.mkdir_p(var_lib_k8s_host_to_app_dir)
    FileUtils.mkdir_p(var_lib_k8s_app_to_alias_dir)
    FileUtils.mkdir_p(var_lib_k8s_sites_dir)

    puts var_lib_k8s

    run_loop = Libuv::Loop.default

    client = run_loop.tcp

    run_loop.all(client).catch do |reason|
      puts ["run_loop caught error", reason].inspect
    end

    client.connect('127.0.0.1', 34567) do |client|
      client.progress do |data|
        puts ["client got", data].inspect
      end

      client.write('GET /goes-here HTTP/1.1\r\nHost: foo-bar\r\n\r\n')
      client.start_read
    end

    run_loop.run do |logger|
      logger.progress do |level, errorid, error|
        begin
          puts "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n") if error.backtrace}\n"
        rescue Exception => e
          puts "error in logger #{e.inspect}"
        end
      end

      $stderr.write(".")
    end

    puts "exiting..."


    #NOTE: the folling ingress controller
    #      has the following issues that should be correct
    #      1) does not work with multi-master
    #      2) perhaps does not qualify as an actual ingress controller
    #      3) does not cleanup automatically any existing registered maps
    #      4) is not multi-server capable
    #      5) requires nginx reload, and elevated permissions

=begin
    pod_name = nil
    pod_description = nil
    pod_ip = nil

    new_descriptions = nil

    pod_descriptions = {}
    service_descriptions = {}

    pending_documents = []

    waiters = []

    document_handler_switch = Proc.new do |event|
      add_to_pending_documents = false

      puts event.inspect

      type = event["type"]
      description = event["object"]

      if description

      kind = description["kind"]
      name = description["metadata"]["name"]

      case kind
        when "IngressList"
          puts [kind].inspect

        when "PodList"
          puts [kind].inspect

        when "ServiceList"
          puts [kind].inspect

        when "Pod"
          puts [kind].inspect

          pod_ip = nil
          if status = description["status"]
            if pod_ip = status["podIP"]
              puts [kind, name, pod_ip].inspect
              pod_descriptions[name] = description
            end
          end

          #unless pod_ip
          #  puts description.inspect
          #  add_to_pending_documents = true
          #end

        when "Service"
          puts [kind].inspect
          service_descriptions[name] = description

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
            host_to_app_template = "%s %s;\n"
            app_to_alias_template = "%s %s;\n"
            default_alias = "/usr/share/nginx/html/"

            site_template = <<-EOF_NGINX_SITE_TEMPLATE
              upstream %s {
                server %s fail_timeout=0;
              }
            EOF_NGINX_SITE_TEMPLATE

            vhost_lines.each do |host, app, upstream|
              host_to_app_line = host_to_app_template % [host, app]
              app_to_alias_line = app_to_alias_template % [app, default_alias]
              site_config = site_template % [app, upstream]

              map_name = [pod_name, app].join("-")

              File.open(File.join(var_lib_k8s_host_to_app_dir, map_name), "w+") do |f|
                f.write(host_to_app_line)
              end

              File.open(File.join(var_lib_k8s_app_to_alias_dir, map_name), "w+") do |f|
                f.write(app_to_alias_line)
              end

              File.open(File.join(var_lib_k8s_sites_dir, map_name), "w+") do |f|
                f.write(site_config)
              end
            end
          end

      end

      if add_to_pending_documents
        puts "adding pending"
        pending_documents << event
        false
      else
        true
      end

      end
    end

    parsers = {}
    stderrs = []
    parse_maps = {}

    #watches = ["pods", "services", "ingress"]
    watches = ["services", "ingress"]
    #watches = ["services"]

    scan_maps = {}
    scan_threads = []

    watches.each do |kind_to_watch|
      kubectl_get_command = kubectl_get + [kind_to_watch]
      puts kubectl_get_command.inspect
      _,description_io,stderr,waiter = #execute(*kubectl_get_command)

      waiters << waiter
      stderrs << stderr

      parser = Yajl::Parser.new
      parser.on_parse_complete = document_handler_switch
      parsers[description_io] = parser
    end

    puts "watching"

    while true
      #IO.select(parsers.keys, [], [], IDLE_SPIN)

      parsers.each do |description_io, parser|
        begin
          chunk = description_io.read_nonblock(IO_CHUNK_SIZE)
          parser << chunk
        rescue EOFError, Errno::EAGAIN, Errno::EINTR => e
          nil
        end
      end

      documents_examined = []

      while (pending_documents - documents_examined).length > 0
        document_to_examine = (pending_documents - documents_examined)[0]
        documents_examined << document_to_examine
        #puts "examining pending"
        if document_handler_switch.call(document_to_examine)
          #puts "popping pending"
          pending_documents = (pending_documents - [document_to_examine])
        end
      end

      all_alive = waiters.all? { |thread| thread.alive? }
      all_dead = waiters.all? { |thread| !thread.alive? }

      all_alive_scan = scan_threads.all? { |thread| thread.alive? }

      all_open = parsers.all? do |description_io, parser|
        is_closed = description_io.closed?
        if is_closed
          parsers.delete(description_io)
        end
        !is_closed
      end

      all_closed = parsers.all? do |description_io, parser|
        description_io.closed?
      end

      break if (all_alive_scan && !all_open) || (all_dead && all_closed)
    end

    puts "exited main loop..."

    waiters.each { |waiter| waiter.join }
    stderrs.each { |stderr| puts stderr.read }
=end

  end
end

Bespoked.new.ingress({"var-lib-k8s" => (ARGV[0] || Dir.mktmpdir)})

=begin
KUBERNETES_SERVICE_PORT=443
KUBERNETES_PORT=tcp://10.254.0.1:443
HOSTNAME=XXXXXXXXXXXXXX
SHLVL=1
HOME=/root
KUBERNETES_PORT_443_TCP_ADDR=10.254.0.1
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
KUBERNETES_PORT_443_TCP_PORT=443
KUBERNETES_PORT_443_TCP_PROTO=tcp
KUBERNETES_SERVICE_PORT_HTTPS=443
KUBERNETES_PORT_443_TCP=tcp://10.254.0.1:443
PWD=/
KUBERNETES_SERVICE_HOST=10.254.0.1
=end
