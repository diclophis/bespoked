#!/usr/bin/env ruby

# stdlib
require 'tempfile'
require 'yaml'
require 'fileutils'

require 'open3'

require 'libuv'
require 'libuv/coroutines'

# rubygems
Bundler.require

# curl -s -v -H "Accept: application/json" http://localhost:8080/api/v1/watch/namespaces/default/services
# http://localhost:8080/apis/extensions/v1beta1/namespaces/default/ingresses
# apis/extensions/v1beta1/watch/namespaces/default/ingresses?resourceVersion=9933
# curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -XGET -H "User-Agent: kubectl" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/apis/extensions/v1beta1/watch/namespaces/default/ingresses?resourceVersion=9933
#apis/extensions/v1beta1/watch/namespaces/default/ingresses?resourceVersion=9933
# curl -k -v -XGET  -H "Accept: application/json, */*" -H "User-Agent: kubectl/v1.3.0 (linux/amd64) kubernetes/2831379" http://localhost:8080/apis/extensions/v1beta1/watch/namespaces/default/ingresses?resourceVersion=0

IO_CHUNK_SIZE = 65554
IDLE_SPIN = 10.0

=begin
        class UvProcessOptions < FFI::Struct
            layout  :st_dev,      :uint64,
                    :st_mode,     :uint64,
                    :st_nlink,    :uint64,
                    :st_uid,      :uint64,
                    :st_gid,      :uint64,
                    :st_rdev,     :uint64,
                    :st_ino,      :uint64,
                    :st_size,     :uint64,
                    :st_blksize,  :uint64,
                    :st_blocks,   :uint64,
                    :st_flags,    :uint64,
                    :st_gen,      :uint64,
                    :st_atim,     UvTimespec,
                    :st_mtim,     UvTimespec,
                    :st_ctim,     UvTimespec,
                    :st_birthtim, UvTimespec
        end
=end


#module UV
  # uv_process_t is a subclass of uv_handle_t
  #
  # ## Fields:
  # :data ::
  #   (FFI::Pointer(*Void))
  # :loop ::
  #   (Loop)
  # :type ::
  #   (Symbol from `enum_handle_type`)
  # :close_cb ::
  #   (Proc(callback_close_cb))
  # :handle_queue ::
  #   (Array<FFI::Pointer(*Void)>)
  # :next_closing ::
  #   (Handle)
  # :flags ::
  #   (Integer)
  # :exit_cb ::
  #   (Proc(callback_exit_cb))
  # :pid ::
  #   (Integer)
  # :queue ::
  #   (Array<FFI::Pointer(*Void)>)
  # :status ::
  #   (Integer)
#  module ProcessWrappers
#    # @param [Integer] signum
#    # @return [Integer]
#    def kill(signum)
#      UV.process_kill(self, signum)
#    end
#  end

  class UvProcess < FFI::Struct
    #include ProcessWrappers
    layout :data, :pointer,
           :loop, :pointer, #Libuv::Loop.by_ref,
           :type, :pointer,
           :close_cb, :pointer,
           :handle_queue, [:pointer, 2],
           :next_closing, :pointer, #Libuv::Handle.by_ref,
           :flags, :uint,
           :exit_cb, :pointer,
           :pid, :int,
           :queue, [:pointer, 2],
           :status, :int
  end

  class UvProcessOptions < FFI::Struct
    layout :exit_cb, :pointer,
           :file, :string,
           :args, :pointer,
           :env, :pointer,
           :cwd, :string,
           :flags, :uint,
           :stdio_count, :int,
           :stdio, :int, #StdioContainer.by_ref,
           :uid, :uint,
           :gid, :uint

    def file=(val)
      pos = offset_of(:file)
      if val.nil?
        self.pointer.put_pointer(pos, FFI::MemoryPointer::NULL)
      elsif val.is_a?(FFI::MemoryPointer)
        self.pointer.put_pointer(pos, val)
      else
        fail("file= requires an FFI::MemoryPointer or nil")
      end

      val
    end
  end

#end

=begin
module Libuv
  module Ext
    attach_function :process_init, :uv_process_init, [:uv_process_t], :int, :blocking => true
  end
end

module Libuv
  class Process < Handle
        def initialize(command)
            # uv_idle_t
            # attach_function :idle_init, :uv_idle_init, [:uv_loop_t, :uv_idle_t], :int, :blocking => true
            process_ptr = ::Libuv::Ext.allocate_handle_process
            error = check_result(::Libuv::Ext.process_init(process_ptr))

            super(process_ptr, error)
        end
  end
end
=end

class Bespoked
  def kubectl_get
    if ENV["CI"] && ENV["CI"] == "true"
      ["ruby", "-e", "f=File.open(File.join('test/fixtures', ARGV[0] + '.json')); while c = f.getc do STDOUT.write(c) && sleep(0.001) end"]
    else
      ["sleep", "9999"]
    end
  end

  def io_for_watch(kind)
    if ENV["CI"] && ENV["CI"] == "true"
      # do system call to make IO that returns mocked watched json stream
    else
      path_prefix = "apis/extensions/v1beta1/watch/namespaces/default/ingresses?resourceVersion=0"
      path_for_watch = begin
        case kind
          when "pods"
            path_prefix % ["v1", "pods"]

          when "services"
            path_prefix % ["v1", "services"]

          when "ingresses"
            path_prefix % ["v1beta1", "ingresses"]

        else
          raise "unknown api Kind to watch: #{kind}"
        end
      end

      puts path_for_watch.inspect
      # curl --cacert kubernetes/ca.crt -v -XGET -H "Authorization: Bearer $(cat kubernetes/api.token)" -H "Accept: application/json, */*" -H "User-Agent: kubectl/v1.3.0 (linux/amd64) kubernetes/2831379" https://192.168.84.10:8443/apis/extensions/v1beta1/watch/namespaces/default/ingresses?resourceVersion=0

      @loop = Libuv::Loop.default
      @client = @loop.tcp

      trap 'INT' do
        $stderr.write("i")
        @loop.stop
      end

      # connect client to server
      @client.connect('192.168.84.10', 8443) do |client|
        $stderr.write("x")

        client.start_tls
        client.progress do |data|
          puts data.inspect
        end

        client.start_read
        $stderr.write("z")
      end

      # catch errors
      @client.catch do |reason|
        puts reason.inspect
      end

      # close the handle
      @client.finally do
        $stderr.write("0")
      end

#      timer = @loop.timer do
#        puts "t"
#        timer.again
#      end
#      timer.start(500)

      @loop.all(@client).catch do |reason|
        puts ["run_loop caught error", reason].inspect
      end

      @loop.run do |logger|
=begin
        logger.progress do |level, errorid, error|
          begin
            puts "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n") if error.backtrace}\n"
          rescue Exception => e
            puts "error in logger #{e.inspect}"
          end
        end
=end
#        co timer

        $stderr.write(".")
      end

      $stderr.write("q")
    end
  end

  def base_api_url
    # 
  end

  def ingress(options = {})
    var_lib_k8s = options["var-lib-k8s"]
    var_lib_k8s_host_to_app_dir = File.join(var_lib_k8s, "host_to_app") 
    var_lib_k8s_app_to_alias_dir = File.join(var_lib_k8s, "app_to_alias") 
    var_lib_k8s_sites_dir = File.join(var_lib_k8s, "sites")

    FileUtils.mkdir_p(var_lib_k8s_host_to_app_dir)
    FileUtils.mkdir_p(var_lib_k8s_app_to_alias_dir)
    FileUtils.mkdir_p(var_lib_k8s_sites_dir)

    File.link(File.realpath("nginx/empty.nginx.conf"), File.join(var_lib_k8s, "nginx.conf"))

    # using libuvs process stream, or popen, or system, need nginx_pid
    #run_nginx_in_background()
    #while event = shit_from_ingress
    #  write_nginx
    #  Kernel.kill(nginx_pid, "HUP")
    #end

    #puts io_for_watch("ingresses")

    puts var_lib_k8s

    run_loop = Libuv::Loop.default

    p run_loop

    client = run_loop.tcp

    nginx_stdout_pipe = run_loop.pipe
    nginx_stderr_pipe = run_loop.pipe

    combined = ["nginx", "-p", var_lib_k8s, "-c", "nginx.conf"]
    _a,b,c,nginx_process_waiter = Open3.popen3(*combined)
    puts [_a,b,c,nginx_process_waiter].inspect

    nginx_stdout_pipe.open(b.fileno)
    nginx_stderr_pipe.open(c.fileno)

    run_loop.all(client, nginx_stdout_pipe, nginx_stderr_pipe).catch do |reason|
      puts ["run_loop caught error", reason].inspect
    end

    run_loop.signal(:INT) do |_sigint|
      Process.kill("HUP", nginx_process_waiter.pid)
      run_loop.stop
      nginx_process_waiter.join
      puts "halted..."
    end

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
      p "Done!"
    end

    client.connect('192.168.84.10', 8443) do |client|
      client.start_tls({:server => false, :verify_peer => false, :cert_chain => "kubernetes/ca.crt"})

    #client.connect('127.0.0.1', 8080) do |client|
      client.progress do |data|
        #puts data #["client got", data].inspect
        http_parser << data
      end

      client.on_handshake do
        get_watch = "GET /apis/extensions/v1beta1/watch/namespaces/default/ingresses HTTP/1.1\r\nHost: 192.168.84.10\r\nAuthorization: Bearer #{File.read('kubernetes/api.token').strip}\r\nAccept: application/json, */*\r\nUser-Agent: kubectl\r\n\r\n"
        puts get_watch
        client.write(get_watch)
        #client.write("GET /apis/extensions/v1beta1/watch/namespaces/default/ingresses?resourceVersion=0 HTTP/1.1\r\nHost: foo-bar\r\n\r\n")
      end

      client.start_read
    end

    nginx_stderr_pipe.progress do |data|
      puts [:nginx_stderr, data].inspect
      Process.kill("HUP", nginx_process_waiter.pid)
    end
    nginx_stderr_pipe.start_read

    nginx_stdout_pipe.progress do |data|
      puts [:nginx_stdout, data].inspect
    end
    nginx_stdout_pipe.start_read

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
