#

module Bespoked
  class LibUVRackServer
    attr_accessor :run_loop,
                  :app,
                  :server

    def initialize(run_loop_in, app_in, options={})
      self.run_loop = run_loop_in
      self.app = app_in

      options[:BindAddress] = DEFAULT_LIBUV_SOCKET_BIND

      #@run_loop.log(:info, :rack_options, [options])

      self.server = @run_loop.tcp

      @server.catch do |reason, wtf|
        puts reason.inspect
        puts reason.backtrace.inspect
        #@run_loop.log(:error, :rack_handler_server_error, [reason, reason.class])
      end

      puts [:bind_up, options[:Port]].inspect
      @server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        puts :got_client_in_upstream
        handle_client(client)
      end

      @server.listen(1024)

      #server.enable_simultaneous_accepts
      #server.enable_nodelay
    end

    def shutdown
      puts :upstream_close
      @server.shutdown
    end

    def handle_client(client)
      http_parser = Http::Parser.new

      # HTTP headers available
      http_parser.on_headers_complete = proc do
        #@run_loop.log(:debug, :http_rack_headers, http_parser.headers)

        url = URI.parse("http://" + (http_parser.headers["host"] || http_parser.headers["Host"]))
        host = url.host
        port = url.port

        #@run_loop.log(:warn, :rack_http_on_headers_complete, [http_parser.http_method, http_parser.request_url, host, port])
      end

      # One chunk of the body
      http_parser.on_body = proc do |chunk|
        #@run_loop.log(:info, :rack_http_on_body, [http_parser.headers])
      end

      # Headers and body is all parsed
      http_parser.on_message_complete = proc do |env|
        #@run_loop.log(:info, :rack_http_on_message_completed, nil)

        env = {}

        env.update(
          'RACK_VERSION'      => ::Rack::VERSION.to_s,
          #'RACK_INPUT'        => StringIO.new,
          'RACK_ERRORS'       => String.new,
          'RACK_MULTITHREAD'  => "false",
          'RACK_MULTIPROCESS' => "false",
          'RACK_RUNONCE'      => "false",
          'RACK_URL_SCHEME'   => "http",
          'rack.url_scheme'   => "http",
          'RACK_IS_HIJACK'    => "false",
          'RACK_HIJACK'       => "", #lambda { raise NotImplementedError, "only partial hijack is supported."},
          'RACK_HIJACK_IO'    => "",
          'HTTP_VERSION'      => "HTTP/#{http_parser.http_version.join(".")}",
          "rack.errors"       => $stderr,
          "rack.version"      => ::Rack::VERSION.to_s.split("."),
          "rack.multithread"  => "false",
          "rack.multiprocess" => "false",
          "rack.run_once"     => "true",
          "rack.input"        => StringIO.new.set_encoding('ASCII-8BIT'),
          "RACK_INPUT"        => ""
        )

        env['HTTP_VERSION'] ||= env['SERVER_PROTOCOL']
        env['QUERY_STRING'] ||= ""
        env['REQUEST_METHOD'] = http_parser.http_method
        env['PATH_INFO'] = http_parser.request_url
        env['REQUEST_PATH'] = http_parser.request_url
        env["SERVER_NAME"] = (http_parser.headers["host"] || http_parser.headers["Host"])
        env["SERVER_PORT"] = "1234"

        status, headers, body = @app.call(env)

        length = 0
        body.each { |b|
          length += b.length
        }
        headers["Content-Length"] = length.to_s

        send_headers client, status, headers
        send_body client, body
        client.close

        #@run_loop.log(:debug, :rack_http_sent_response, [status, headers, body])
      end

      ##################

      client.progress do |chunk|
        http_parser << chunk
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
