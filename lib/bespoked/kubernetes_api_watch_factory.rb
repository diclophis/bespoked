#

module Bespoked
  class KubernetesApiWatchFactory < WatchFactory
    WATCH_TIMEOUT = 100

    def rebop(retry_defer)
      #watch_timeout = @run_loop.timer
      #watch_timeout.progress do
        #self.record(:warn, :watch_timeout)
        #retry_defer.notify(true)
        #nil
      #end
      #watch_timeout.start(WATCH_TIMEOUT, 0)
      #self.record(:warn, :rebop, [WATCH_TIMEOUT, watch_timeout])
      #watch_timeout
    end

    def create(resource_kind, authentication_timeout = 1)
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

      new_watch = Watch.new(@run_loop)

      retry_defer = @run_loop.defer

      new_client = nil

      retry_defer.promise.progress do
        if new_client
          new_watch.restart
          new_client.close
        end

        new_client = @run_loop.tcp
        new_watch.client = new_client

        http_parser = Http::Parser.new

        # HTTP headers available
        http_parser.on_headers_complete = proc do
          http_ok = http_parser.status_code.to_i == 200
          derefed = new_watch.waiting_for_authentication
          derefed.resolve(http_ok)
          new_watch.rebop = rebop(retry_defer)
          #self.record(:info, :http_ok, http_ok)
        end

        # One chunk of the body
        http_parser.on_body = proc do |chunk|
          begin
            #record(:debug, :watch_json, chunk)
            new_watch.json_parser << chunk
          rescue Yajl::ParseError => bad_json
            #@run_loop.log(:error, :bad_json, [bad_json, chunk])
          end
        end

        ## Headers and body is all parsed
        #http_parser.on_message_complete = proc do |env|
        #  #self.record(:info, :on_message_completed, [])
        #end

        new_client.connect(service_host, service_port.to_i) do |client|
          self.record(:warn, :watch_client_connected)

          client.start_tls({:server => false, :cert_chain => var_run_secrets_k8s_crt_path})

          client.progress do |data|
            http_parser << data
          end

          client.on_handshake do
            client.enable_keepalive(10) #NOTE: TCP keep-alive circuit
            client.write(get_watch)
          end

          client.finally do |finish|
            self.record(:warn, :watch_client_disconnected, finish)
            #new_watch.rebop = rebop(retry_defer)
          end
        
          client.start_read
        end

        new_client.catch do |err|
          #NOTE: if the connection refuses, retry the connection
          #self.record(:warn, :watch_client_error, [err, err.class])
          if err.is_a?(Libuv::Error::ECONNREFUSED)
            #self.record(:warn, :watch_client_error, [err, err.class])

            new_watch.rebop = rebop(retry_defer)

            self.record(:warn, :watch_client_error, [err, err.class])
          end
        end
      end

      retry_defer.notify(true)

      return new_watch
    end
  end
end
