#

module Bespoked
  class LibUVRackHandler
    def self.run(run_loop, app, options={})
      environment  = ENV['RACK_ENV'] || 'development'

      options[:BindAddress] ||= "0.0.0.0"
      options[:Port] ||= 45678

      run_loop.log(:warn, :rack_options, [options])

      server = run_loop.tcp

      server.bind(options[:BindAddress], options[:Port]) do |client|
        http_parser = Http::Parser.new

        # HTTP headers available
        http_parser.on_headers_complete = proc do
          run_loop.log(:warn, :got_dashboard_headers, [http_parser.http_method, http_parser.request_url])
        end

        # One chunk of the body
        http_parser.on_body = proc do |chunk|
          run_loop.log(:info, :got_dashboard_body, nil)
        end

        # Headers and body is all parsed
        http_parser.on_message_complete = proc do |env|
          run_loop.log(:info, :dashboard_http_on_message_completed, nil)

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

          status, headers, body = app.call(env)

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
