#

module Bespoked
  class KubernetesApiWatchFactory < WatchFactory
    WATCH_TIMEOUT = 1000 * 60 * 5

    def create(resource_kind, authentication_timeout = 1)
      new_watch = Watch.new(@run_loop)

      var_run_secrets_k8s_token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
      var_run_secrets_k8s_crt_path = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'

      service_host = ENV["KUBERNETES_SERVICE_HOST"] || "127.0.0.1"
      service_port = ENV["KUBERNETES_SERVICE_PORT"] || "8443"
      bearer_token = ENV["KUBERNETES_DEV_BEARER_TOKEN"] || begin
        if File.exist?(var_run_secrets_k8s_token_path) && (File.size(var_run_secrets_k8s_token_path) > 0)
          File.read(var_run_secrets_k8s_token_path).strip
        else
          #self.halt :k8s_token_not_ready
          #@run_loop.log(:fatal, :kubernetes_watch_create, ["k8s_token not ready"])
          ""	
        end
      end

      get_watch = "GET #{self.path_for_watch(resource_kind)} HTTP/1.1\r\nHost: #{service_host}\r\nAuthorization: Bearer #{bearer_token}\r\nAccept: */*\r\nUser-Agent: bespoked\r\n\r\n"

      new_client = @run_loop.tcp
      retry_defer = @run_loop.defer

      http_parser = Http::Parser.new

      # HTTP headers available
      http_parser.on_headers_complete = proc do
        http_ok = http_parser.status_code.to_i == 200
        #@run_loop.log(:warn, :got_watch_headers, [http_ok])
        #defer.resolve(http_ok)
        new_watch.waiting_for_authentication.resolve(http_ok)
      end

      # One chunk of the body
      http_parser.on_body = proc do |chunk|
        begin
          new_watch.json_parser << chunk
        rescue Yajl::ParseError => bad_json
          #@run_loop.log(:error, :bad_json, [bad_json, chunk])
        end
      end

      # Headers and body is all parsed
      http_parser.on_message_complete = proc do |env|
        #@run_loop.log(:info, :on_message_completed, [])
      end

      new_client.connect(service_host, service_port.to_i) do |client|
        client.start_tls({:server => false, :cert_chain => var_run_secrets_k8s_crt_path})

        client.progress do |data|
          http_parser << data
        end

        client.on_handshake do
          client.enable_keepalive(10) #NOTE: TCP keep-alive circuit
          client.write(get_watch)
        end

        client.finally do |finish|
          #@run_loop.log(:warn, :watch_disconnected, finish)
          retry_defer.resolve(true)
        end
      end

      new_client.catch do |err|
        #NOTE: if the connection refuses, retry the connection
        #@run_loop.log(:warn, :watch_client_error, [err, err.class])
        if err.is_a?(Libuv::Error::ECONNREFUSED)
          retry_defer.resolve(true)
        end
      end

      new_client.start_read

      watch_timeout = @run_loop.timer
      watch_timeout.start(WATCH_TIMEOUT, 0)
      watch_timeout.progress do
        new_client.close
      end

      return new_watch
    end
  end
end
