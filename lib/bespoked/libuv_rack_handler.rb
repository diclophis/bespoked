#

module Bespoked
  class LibUVRackHandler
    attr_accessor :run_loop,
                  :app

    def initialize(run_loop_in, app_in, options={})
      self.run_loop = run_loop_in
      self.app = app_in

      options[:BindAddress] = DEFAULT_LIBUV_SOCKET_BIND

      @run_loop.log(:info, :rack_options, [options])

      server = @run_loop.tcp

      server.catch do |reason|
        @run_loop.log(:error, :rack_handler_server_error, [reason, reason.class])
      end

      server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        handle_client(client)
      end

      server.listen(16)
    end

    def handle_client(client)
      http_parser = Http::Parser.new

      # HTTP headers available
      http_parser.on_headers_complete = proc do
        url = URI.parse("http://" + http_parser.headers["Host"])
        host = url.host
        port = url.port

        @run_loop.log(:warn, :rack_http_on_headers_complete, [http_parser.http_method, http_parser.request_url, host, port])
      end

      # One chunk of the body
      http_parser.on_body = proc do |chunk|
        @run_loop.log(:info, :rack_http_on_body, [http_parser.headers])
      end

      # Headers and body is all parsed
      http_parser.on_message_complete = proc do |env|
        @run_loop.log(:info, :rack_http_on_message_completed, nil)

        env = {}

        env.update(
          'RACK_VERSION'      => ::Rack::VERSION,
          'RACK_INPUT'        => nil,
          'RACK_ERRORS'       => nil,
          'RACK_MULTITHREAD'  => true,
          'RACK_MULTIPROCESS' => false,
          'RACK_RUNONCE'      => false,
          'RACK_URL_SCHEME'   => "http",
          'RACK_IS_HIJACK'    => false,
          'RACK_HIJACK'       => lambda { raise NotImplementedError, "only partial hijack is supported."},
          'RACK_HIJACK_IO'    => nil
        )

        env['HTTP_VERSION'] ||= env['SERVER_PROTOCOL']
        env['QUERY_STRING'] ||= ""
        env['PATH_INFO'] = http_parser.request_url
        env['REQUEST_PATH'] = http_parser.request_url

        status, headers, body = @app.call(env)

        send_headers client, status, headers
        send_body client, body
        client.close
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
