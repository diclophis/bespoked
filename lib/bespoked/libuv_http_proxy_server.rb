#

module Bespoked
  class LibUVHttpProxyServer
    attr_accessor :run_loop,
                  :logger,
                  :proxy_controller,
                  :server

    def initialize(run_loop_in, logger_in, proxy_controller_in, options={})
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

    def handle_client(client)
      record :info, :start_handle_client, [client].inspect

      http_parser = Http::Parser.new
      reading_state = :request_to_proxy
      body_left_over = nil

      new_client = run_loop.tcp

      new_client.catch do |err|
        record :info, :rack_proxy_client_error, [err, err.class].inspect
        client.close
      end

      new_client.finally do |err|
        record :info, :upstream_server_closed, [err, err.class].inspect
        client.close
      end

      http_parser.on_headers_complete = proc do
        #record :info, :headers, [http_parser.headers].inspect
        #sleep 60
        #record :info, :gogogo, [].inspect

        reading_state = :request_to_upstream

        env = {"HTTP_HOST" => (http_parser.headers["host"] || http_parser.headers["Host"])}

        if env["HTTP_HOST"]
          in_url = URI.parse("http://" + env["HTTP_HOST"])
          out_url = nil

          if mapped_host_port = @proxy_controller.vhosts[in_url.host]
            out_url = URI.parse("http://" + mapped_host_port)
          end

          #record :info, :in_out_url, [in_url, out_url].inspect

          #TODO
          if url = out_url
            host = url.host
            port = url.port

            on_dns_bad = proc { |err|
              #record :info, :bad_dns, [err, err.class].inspect

              client.shutdown
            }

            on_dns_ok = proc { |addrinfo|
              ip_address = addrinfo[0][0]

              #record :info, :dns_ok, [host, ip_address, port.to_i, client.sockname, client.peername].inspect

              new_client.progress do |chunk|
                #record :info, :got_response_from_upstream, [chunk].inspect
                if client && chunk && chunk.length > 0
                  #record :info, :got_response_from_upstream, [chunk].inspect
                  client.write(chunk, {:wait => :promise}).then { |a|
                  }.catch { |e|
                    record :info, :proxy_write_error, [e].inspect
                  }
                end
              end

              new_client.connect(ip_address, port.to_i) do

                upstream_handshake = "#{http_parser.http_method} #{http_parser.request_url} HTTP/1.1\r\n"
                #record :info, :handshare_up, [upstream_handshake].inspect
                new_client.write(upstream_handshake, wait: true)

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
                  [k.split("_").map { |header| header.downcase.capitalize }.join("-"), v]
                }.to_h

                headers_for_upstream_request = http_parser.headers.merge(proxy_override_headers)

                request_to_upstream = String.new

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

                new_client.write(request_to_upstream, {:wait =>  :promise}).then { |b|
                  new_client.start_read
                }.catch { |e|
                  record :info, :wrote_b_catch, [e].inspect
                  #new_client.shutdown
                  #client.shutdown
                  client.write("HTTP/1.1 500 Error\r\nContent-Length: 0\r\n\r\n", {:wait => :promise}).then { |a|
                    record :info, :wrote_c, [a].inspect
                    client.close
                  }.catch { |e|
                    record :info, :wrote_c_catch, [e].inspect
                    client.close
                  }
                }
              end
            }

            #def lookup(hostname, hint = :IPv4, port = 9, wait: true, &block)
            run_loop.lookup(host, :IPv4, 59, :wait => false).then(on_dns_ok, on_dns_bad)
            :stop
          else
            #record :info, :halted_lack_of_something, [].inspect
            client.shutdown
            :stop
          end
        else
          #record :info, :halted_lack_of_http_host, [].inspect
          client.shutdown
          :stop
        end
      end

      ##################

      client.progress do |chunk|
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

      #record :info, :start_read_handle_client, [client, http_parser].inspect

      client.start_read
    end
  end
end
