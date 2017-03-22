#

module Bespoked
  class LibUVHttpProxyServer
    attr_accessor :run_loop,
                  :logger,
                  :proxy_controller,
                  :server,
                  :shutdown_promises

    def initialize(run_loop_in, logger_in, proxy_controller_in, options={})
      self.shutdown_promises = {}
      self.run_loop = run_loop_in
      self.logger = logger_in
      self.proxy_controller = proxy_controller_in

      options[:BindAddress] ||= DEFAULT_LIBUV_SOCKET_BIND
      options[:Port] ||= DEFAULT_LIBUV_HTTP_PROXY_PORT

      self.server = @run_loop.tcp(flags: Socket::AF_INET6 | Socket::AF_INET)

      @server.catch do |reason|
        record :info, :libuv_http_proxy_server_catch, [reason].inspect
      end

      @server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        handle_client(client)
      end

      record :debug, :http_proxy_server_listen, [options].inspect
    end

    def add_tls_host(private_key, cert_chain, host_name)
      record :info, :add_tls_host, [private_key, cert_chain, host_name].inspect

      temp_key = Tempfile.new('bespoked-tls-key')
      key_path = temp_key.path + ".keep"
      File.write(key_path, Base64.decode64(private_key))
      temp_key.close

      temp_crt = Tempfile.new('bespoked-tls-crt')
      crt_path = temp_crt.path + ".keep"
      File.write(crt_path, Base64.decode64(cert_chain))
      temp_crt.close

      @server.add_host({
        :private_key => key_path,
        :cert_chain => crt_path,
        :host_name => host_name
      })
    end

    def start
      @server.listen(1024 * 32)
    end

    def shutdown
      @server.shutdown
      @server.close
    end

    def record(level = nil, name = nil, message = nil)
      if @logger
        log_event = {:date => Time.now, :level => level, :name => name, :message => message}
        @logger.notify(log_event)
      end
    end

    def install_shutdown_promise(client)
      @shutdown_promises[client] ||= @run_loop.defer
    end

    def handle_client(client)
      record :debug, :start_handle_client, [client].inspect
      install_shutdown_promise(client)

      http_parser = Http::Parser.new
      reading_state = :request_to_proxy
      body_left_over = nil

      new_client = run_loop.tcp

      new_client.catch do |err|
        halt_connection(client, 500, [err, err.backtrace, :proxy_client_error])
      end

      new_client.finally do |err|
        record :debug, :upstream_server_closed, [err, err.class].inspect
        sp = install_shutdown_promise(client)
        record :debug, :sp_one, [client.class, client].inspect
        sp.promise.progress do
          record :info, :upstream_server_closed_and_closed, []
          client.close
        end
      end

      client.progress do |chunk|
        record :debug, :progress, [chunk].inspect
        if reading_state == :request_to_upstream
          if new_client && chunk && chunk.length > 0
            new_client.write(chunk)
          end
        end

        if http_parser && reading_state == :request_to_proxy
          if chunk && chunk.length > 0
            offset_of_body_left_in_buffer = http_parser << chunk
            body_left_over = chunk[offset_of_body_left_in_buffer, (chunk.length - offset_of_body_left_in_buffer)]
          end
        end
      end

      http_parser.on_headers_complete = proc do
        reading_state = :request_to_upstream

        env = {"HTTP_HOST" => (http_parser.headers["host"] || http_parser.headers["Host"])}

        if env["HTTP_HOST"]
          in_url = URI.parse("http://" + env["HTTP_HOST"])
          url = nil

          if mapped_host_port = @proxy_controller.vhosts[in_url.host]
            url = URI.parse("http://" + mapped_host_port)
          end

          #TODO: make this not a super-nested proc somehow
          if url
            host = url.host
            port = url.port

            on_dns_bad = proc { |err|
              halt_connection(client, 404, :bad_dns)
            }

            on_dns_ok = proc { |addrinfo|
              ip_address = addrinfo[0][0]
              do_new_thing(host, port, http_parser, client, new_client, ip_address, body_left_over)
            }

            run_loop.lookup(host, :IPv4, 59, :wait => false).then(on_dns_ok, on_dns_bad)

            :stop
          else
            halt_connection(client, 404, [:halted_lack_of_matching_service, @proxy_controller.vhosts.keys, in_url.host])
          end
        else
          halt_connection(client, 404, :halted_lack_of_http_host)
        end
      end

      ##################

      #TODO: determine how to switch here based on if this is the ssl one or not...
      tls_options = {
        :server => true,
        :verify_peer => false
      }
      client.start_tls(tls_options)
      client.start_read
    end

    def write_chunk_to_socket(client, chunk)
      if client && chunk && chunk.length > 0
        client.write(chunk, {:wait => :promise}).then { |a|
          record :info, :proxy_wrote_write_chunk_to_socket, []
          install_shutdown_promise(client).promise.progress do
            record :info, :proxy_wrote_write_chunk_to_socket_and_close, [client.class, client]
          end
          install_shutdown_promise(client).notify
        }.catch { |e|
          should_close = e.is_a?(Libuv::Error::ECANCELED)
          record :info, :proxy_write_error, [e, should_close].inspect
          client.close if should_close
        }
      end
    end

#foop    def (
#      new_client.write(request_to_upstream, {:wait =>  :promise}).then { |b|
#      }.catch { |e|
#        halt_connection(client, 500, :halted_upstream_closed)
#      }

    #TODO: merge with
    def header_stack(http_parser, client)
      #NOTE: these header overrides are based on security recommendations
      proxy_override_headers = {
        "X-Forwarded-For" => client.peername[1] || "", # NOTE: makes the actual IP available
        "X-Request-Start" => "t=#{Time.now.to_f}", # track queue time in newrelic
        "X-Forwarded-Host" => "", # NOTE: this is important to pevent host poisoning... double check this
        "Client-IP" => "" # strip Client-IP header to prevent rails spoofing error
      }

      proxy_override_headers = ENV.select { |possible_header|
        "HTTP" == possible_header.slice(0, 4)
      }.map { |k, v|
        [k.slice(5, (k.length - 5)).split("_").map { |header| header.downcase.capitalize }.join("-"), v]
      }.to_h

      http_parser.headers.merge(proxy_override_headers)
    end

    def construct_upstream_request(http_parser, client, body_left_over)
      #request_to_upstream = String.new
      request_to_upstream = "#{http_parser.http_method} #{http_parser.request_url} HTTP/1.1\r\n"

      headers_for_upstream_request = header_stack(http_parser, client)
      headers_for_upstream_request.each { |k, vs|
        vs.split("\n").each { |v|
          if k && v
            chunk = "#{k}: #{v}\r\n"
            request_to_upstream.concat(chunk)
          end
        }
      }

      request_to_upstream.concat("\r\n")

      if http_parser.upgrade_data && http_parser.upgrade_data.length > 0
        request_to_upstream.concat(http_parser.upgrade_data)
      end

      http_parser.reset!
      http_parser = nil

      if body_left_over && body_left_over.length > 0
        request_to_upstream.concat(body_left_over)
      end

      record :debug, :headers_for_upstream_request, [headers_for_upstream_request].inspect

      request_to_upstream
    end

    #TODO: pass ENV somehow
    def other_twang(http_parser, new_client, client, body_left_over)
      request_to_upstream = construct_upstream_request(http_parser, client, body_left_over)

      new_client.start_read

      write_chunk_to_socket(new_client, request_to_upstream)
    end

    def do_new_thing(host, port, http_parser, client, new_client, ip_address, body_left_over)
      new_client.progress(&proc { |chunk|
        write_chunk_to_socket(client, chunk) unless client.closed?
      })

      new_client.connect(ip_address, port.to_i, &proc {
        other_twang(http_parser, new_client, client, body_left_over)
      })
    end

    def halt_connection(client, status, reason)
      # record :debug, :halt_connection, [reason].inspect
      response = reason.to_s
      client.write("HTTP/1.1 #{status} Halted\r\nConnection: close\r\nContent-Length: #{response.length}\r\n\r\n#{response}", {:wait => :promise}).then {
        record :debug, :wrote_halted_and_closed
        client.close
      }.catch { |e|
        record :info, :wrote_halted_catch, [e].inspect
        client.close
      }
      :stop
    end
  end
end
