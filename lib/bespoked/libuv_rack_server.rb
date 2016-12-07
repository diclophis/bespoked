#

module Bespoked
  class HijackWrapper
    def initialize(reader, writer)
      #TODO: assert this is correct wrapper script
      @reader = reader
      @writer = writer
    end

    def call(*args)
      self
    end

    def read
      @reader.read
    end
    
    def write(chunk)
      @writer.write(chunk)
    end

    def read_nonblock
      read
    end

    def write_nonblock(chunk)
      write(chunk)
    end

    def flush
      @writer.flush
    end
    
    def close
      @writer.close
    end
    
    def close_read
      close
    end
    
    def close_write
      close
    end
    
    def closed?
      @writer.closed?
    end
  end

  class LibUVRackServer
    attr_accessor :run_loop,
                  :app,
                  :server

    def initialize(run_loop_in, app_in, options={})
      self.run_loop = run_loop_in
      self.app = app_in

      options[:BindAddress] = DEFAULT_LIBUV_SOCKET_BIND

      self.server = @run_loop.tcp(flags: Socket::AF_INET6 | Socket::AF_INET)

      @server.catch do |reason|
        puts reason.inspect
      end

      @server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        handle_client(client)
      end
    end

    def start
      @server.listen(1024)
    end

    def shutdown
      @server.shutdown
      @server.close
    end

    def handle_client(client)
      http_parser = Http::Parser.new
      host = nil
      port = nil
      host_header = nil
      string_io = StringIO.new.set_encoding('ASCII-8BIT')
      query_string = nil
      path_info = nil

      # HTTP headers available
      http_parser.on_headers_complete = proc do
        #@run_loop.log(:debug, :http_rack_headers, http_parser.headers)

        host_header = (http_parser.headers["host"] || http_parser.headers["Host"])

        url = URI.parse("http://" + host_header + http_parser.request_url)
        host = url.host
        port = url.port

        query_string = url.query
        path_info = url.path

        #@run_loop.log(:warn, :rack_http_on_headers_complete, [http_parser.http_method, http_parser.request_url, host, port])
      end

      # One chunk of the body
      http_parser.on_body = proc do |chunk|
        #@run_loop.log(:info, :rack_http_on_body, [http_parser.headers])
        string_io << chunk
      end

      # Headers and body is all parsed
      http_parser.on_message_complete = proc do |env|
        #@run_loop.log(:info, :rack_http_on_message_completed, nil)

        hijack_wrapper = HijackWrapper.new(string_io, client)

        env = {}

        env.update(
          'RACK_VERSION'      => ::Rack::VERSION.to_s,
          #'RACK_INPUT'        => StringIO.new,
          'RACK_ERRORS'       => "",

          #'RACK_MULTITHREAD'  => "false",
          #'RACK_MULTIPROCESS' => "false",
          #'RACK_RUNONCE'      => "false",

          'RACK_URL_SCHEME'   => "http",
          'rack.url_scheme'   => "http",

          'rack.hijack?'      => true,
          'rack.hijack'       => hijack_wrapper,

          #proc { |*env| puts "#{env}wtf!!!!!!!!!!!!!"; hijack_wrapper },
          #'rack.hijack_io'    => hijack_wrapper,

          'HTTP_VERSION'      => "HTTP/#{http_parser.http_version.join(".")}",
          "rack.errors"       => $stdout,
          "rack.version"      => ::Rack::VERSION.to_s.split("."),
          "rack.multithread"  => "false",
          "rack.multiprocess" => "false",
          "rack.run_once"     => "true",
          "rack.input"        => string_io, #StringIO.new.set_encoding('ASCII-8BIT'),
          "RACK_INPUT"        => ""
        )
        
        #'RACK_IS_HIJACK'    => "false",
        #'RACK_HIJACK'       => lambda { raise NotImplementedError, "only partial hijack is supported."},

        env['HTTP_VERSION'] ||= env['SERVER_PROTOCOL']
        env['QUERY_STRING'] ||= query_string || ""
        env['REQUEST_METHOD'] = http_parser.http_method
        env['PATH_INFO'] = path_info #http_parser.request_url
        #env['SCRIPT_NAME'] = "" $TODO #path_info #http_parser.request_url
        env['REQUEST_PATH'] = http_parser.request_url
        env["SERVER_NAME"] = host #(http_parser.headers["host"] || http_parser.headers["Host"])
        env["SERVER_PORT"] = port.to_s

        env["HTTP_COOKIE"] = http_parser.headers["Cookie"] || ""
        env["CONTENT_TYPE"] = http_parser.headers["Content-Type"] || ""
        env["CONTENT_LENGTH"] = http_parser.headers["Content-Length"] || "0"
        env["HTTP_ACCEPT"] = http_parser.headers["Accept"] || "0"

        ["Accept-Language", "Accept-Encoding", "Connection", "Upgrade-Insecure-Requests"].each do |inbh|
          env["HTTP_" + inbh.upcase.gsub("-", "_")] = http_parser.headers[inbh] if  http_parser.headers[inbh]
        end

        begin
          status, headers, body = @app.call(env)
        rescue => e
          #TODO: see if this is needed, elsewise use logger
          puts e.inspect
          raise e
        end

        #length = 0
        #body.each { |b|
        #  length += b.length
        #}
        #headers["Content-Length"] = length.to_s

        send_headers client, status, headers

        unless headers["Content-Type"] == "text/event-stream"
          send_body client, body
        else
          Thread.new {
            #TODO: figure out better plan
            send_body client, body
          }
        end

        #TODO: final touches on keep-alive
        #client.close
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
          out = "#{k}: #{v}\r\n"
          client.write out
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
