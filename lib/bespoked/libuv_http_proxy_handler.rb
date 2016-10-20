#

module Bespoked
  class LibUVHttpProxyHandler
    attr_accessor :run_loop,
                  :app

    def initialize(run_loop_in, app_in, options={})
      self.run_loop = run_loop_in
      self.app = app_in

      options[:BindAddress] = DEFAULT_LIBUV_SOCKET_BIND

      @run_loop.log(:info, :rack_options, [options])

      server = @run_loop.tcp

      server.catch do |reason|
        @run_loop.log(:error, :rack_http_proxy_handler, [reason, reason.class])
      end

      server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        handle_client(client)
      end

      server.listen(16)
    end

    def handle_client(client)
      http_parser = Http::Parser.new

      http_parser.on_headers_complete = proc do
        env = {"HTTP_HOST" => http_parser.headers["Host"]}

        if url = app.call(env)
          host = url.host
          port = url.port

          run_loop.log(:warn, :rack_http_on_headers_complete, [http_parser.http_method, http_parser.request_url, host, port])

          run_loop.lookup(host, {:wait => false}).then(proc { |addrinfo|
            ip_address = addrinfo[0][0]
            run_loop.log(:info, :ip_lookup, [host, ip_address])

            new_client = run_loop.tcp
            new_client.connect(ip_address, port.to_i) do |up_client|
              up_client.write("GET / HTTP/1.1\r\n")
              http_parser.headers.each { |k, vs|
                vs.split("\n").each { |v|
                  up_client.write "#{k}: #{v}\r\n"
                }
              }
              http_parser = nil
              up_client.write("\r\n")
              up_client.progress do |chunk|
                client.write(chunk)
              end

              client.progress do |chunk|
                up_client.write(chunk)
              end
            end

            new_client.catch do |err|
              run_loop.log(:warn, :rack_proxy_client_error, [err, err.class])
            end

            new_client.start_read
          }, proc { |err|
            #TODO: handle "type":"dns_error","message":["temporary failure","Libuv::Error::EAI_AGAIN"]
            run_loop.log(:warn, :dns_error, [err, err.class])
            client.close
          })
        else
          client.close
        end
      end

      ##################

      client.progress do |chunk|
        if http_parser
          http_parser << chunk
        end
      end

      client.start_read
    end

    def send_headers(client, status, headers)
      client.write "HTTP/1.1 #{status} #{WEBrick::HTTPStatus.reason_phrase(status)}\r\n"
      headers.each { |k, vs|
        vs.split("\n").each { |v|
          client.write "#{k}: #{v}\r\n"
        }
      }
      client.write "\r\n"
    end

    def send_body(client, body)
      body.each { |part|
        client.write part
      }
    end

  end
end
