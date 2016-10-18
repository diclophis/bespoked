#

module Bespoked
  class LibUVHttpProxyHandler
    def self.run(run_loop, app, options={})
      environment  = ENV['RACK_ENV'] || 'development'

      options[:BindAddress] ||= "0.0.0.0"
      options[:Port] ||= 45678

      run_loop.log(:warn, :rack_options, [options])

      server = run_loop.tcp

      uri = URI::Parser.new

      server.bind(options[:BindAddress], options[:Port]) do |client|
        http_parser = Http::Parser.new

        http_parser.on_headers_complete = proc do
          env = {"HTTP_HOST" => http_parser.headers["Host"]}

          if url = app.call(env)
            host = url.host
            port = url.port

            run_loop.log(:warn, :rack_http_on_headers_complete, [http_parser.http_method, http_parser.request_url, host, port])

            run_loop.lookup(host).then(proc { |addrinfo|
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
              run_loop.log(:warn, :dns_error, [err, err.class])
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

      server.listen(1024)
    end

    def self.send_headers(client, status, headers)
      client.write "HTTP/1.1 #{status} #{WEBrick::HTTPStatus.reason_phrase(status)}\r\n"
      headers.each { |k, vs|
        vs.split("\n").each { |v|
          client.write "#{k}: #{v}\r\n"
        }
      }
      client.write "\r\n"
    end

    def self.send_body(client, body)
      body.each { |part|
        client.write part
      }
    end
  end
end
