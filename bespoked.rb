#!/usr/bin/env ruby

require 'tempfile'
require 'yaml'
require 'open3'
require 'psych'
require 'fileutils'

# curl -s -v -H "Accept: application/json" http://localhost:8080/api/v1/watch/namespaces/default/services
# https://tenderlovemaking.com/2010/04/17/event-based-json-and-yaml-parsing.html

IO_CHUNK_SIZE = 1024 * 32

class DocumentStreamHandler < Psych::TreeBuilder
  def initialize &block
    super
    @block = block
  end

  def end_document implicit_end = !streaming?
    @last.implicit_end = implicit_end
    @block.call pop
  end

  def start_document version, tag_directives, implicit
    n = Psych::Nodes::Document.new version, tag_directives, implicit
    push n
  end
end

class Bespoked
  def ingress(options = {})
    var_lib_k8s = options["var-lib-k8s"]
    var_lib_k8s_host_to_app_dir = File.join(var_lib_k8s, "host_to_app") 
    var_lib_k8s_app_to_alias_dir = File.join(var_lib_k8s, "app_to_alias") 
    var_lib_k8s_sites_dir = File.join(var_lib_k8s, "sites")

    FileUtils.mkdir_p(var_lib_k8s_host_to_app_dir)
    FileUtils.mkdir_p(var_lib_k8s_app_to_alias_dir)
    FileUtils.mkdir_p(var_lib_k8s_sites_dir)

    kubectl = ["kubectl", "--cluster=#{options['cluster'] || 'localhost'}"]
    kubectl_get = kubectl + ["get", "-o", "json", "-w"]

    #NOTE: the folling ingress controller
    #      has the following issues that should be correct
    #      1) does not work with multi-master
    #      2) perhaps does not qualify as an actual ingress controller
    #      3) does not cleanup automatically any existing registered maps
    #      4) is not multi-server capable
    #      5) requires nginx reload, and elevated permissions

    pod_name = nil
    pod_description = nil
    pod_ip = nil

    new_descriptions = nil

    pod_descriptions = {}
    service_descriptions = {}

    pending_documents = []

    waiters = []

    document_handler_switch = Proc.new do |document|
      add_to_pending_documents = false

      description = document.to_ruby
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
        pending_documents << document
        false
      else
        true
      end
    end

    parsers = {}
    stderrs = []

    ["pods", "service", "ingress"].each do |kind_to_watch|
      kubectl_get_command = kubectl_get + [kind_to_watch]
      puts kubectl_get_command.inspect
      _,description_io,stderr,waiter = execute(*kubectl_get_command)

      waiters << waiter
      stderrs << stderr

      handler = DocumentStreamHandler.new(&document_handler_switch)
      parsers[description_io] = Psych::Parser.new(handler)
    end

    puts "watching"

    while true
      parsers.each do |description_io, parser|
        begin
          parser.parse(description_io.read_nonblock(IO_CHUNK_SIZE), "watch.json")
        rescue EOFError, Errno::EAGAIN, Errno::EINTR => e
          nil
        end

        sleep 0.1
      end

      documents_examined = []

      while (pending_documents - documents_examined).length > 0
        document_to_examine = (pending_documents - documents_examined)[0]
        documents_examined << document_to_examine
        puts "examining pending"
        if document_handler_switch.call(document_to_examine)
          puts "popping pending"
          pending_documents = (pending_documents - [document_to_examine])
        end
      end

      break unless waiters.all? { |thread| thread.alive? }
    end

    waiters.each { |waiter| waiter.join }

    stderrs.each { |stderr| puts stderr.read }
  end

  def execute(*args)
    nonblock = true

    extra_args = {}
    if args[args.length - 1].is_a?(Hash)
      extra_args = args[args.length - 1]
    else
      args << extra_args
    end

    first_args = {}
    if args[0].is_a?(Hash)
      first_args = args[0]
    else
      args.unshift first_args
    end

    extra_args[:unsetenv_others] = false
    extra_args[:close_others] = false

    first_args['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    first_args['RUBYOPT'] = "-d" if ENV['DEBUG']

    [
      "LANG",
      "USER",
      "HOME",
      "TERM"
    ].each do |pass_env_key|
      first_args[pass_env_key] = ENV[pass_env_key]
    end

    env_component = args.shift
    opt_component = args.pop

    combined = [env_component, *args, opt_component]

    a,b,c,d = Open3.popen3(*combined)
    a.sync = true
    b.sync = true
    c.sync = true
    d[:pid] = d.pid

    return [a, b, c, d]
  end
end

Bespoked.new.ingress({"var-lib-k8s" => (ARGV[0] || "/var/lib/k8s-ingress")})
