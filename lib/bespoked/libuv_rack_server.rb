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
      @run_loop.work(proc {

      http_parser = Http::Parser.new
      url = nil
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
        forwarded_scheme = (http_parser.headers["X-Forwarded-Proto"] || "http")

        url = URI.parse("#{forwarded_scheme}://" + host_header + http_parser.request_url)
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

          #'RACK_URL_SCHEME'   => "https",
          'rack.url_scheme'   => url.scheme,

          'rack.hijack?'      => true,
          'rack.hijack'       => hijack_wrapper,

          #proc { |*env| puts "#{env}wtf!!!!!!!!!!!!!"; hijack_wrapper },
          #'rack.hijack_io'    => hijack_wrapper,

          'HTTP_VERSION'      => "HTTP/#{http_parser.http_version.join(".")}",
          "rack.errors"       => $stdout,
          "rack.version"      => ::Rack::VERSION.to_s.split("."),
          "rack.multithread"  => true,
          "rack.multiprocess" => false,
          "rack.run_once"     => "true",
          "rack.input"        => string_io, #StringIO.new.set_encoding('ASCII-8BIT'),
          "rack.logger"       => $logger,
          "RACK_INPUT"        => ""
        )
        
        #'RACK_IS_HIJACK'    => "false",
        #'RACK_HIJACK'       => lambda { raise NotImplementedError, "only partial hijack is supported."},

        env['HTTP_VERSION'] ||= env['SERVER_PROTOCOL']
        env['QUERY_STRING'] ||= query_string || ""
        env['REQUEST_METHOD'] = http_parser.http_method

        env['PATH_INFO'] = path_info #http_parser.request_url
        env['SCRIPT_NAME'] = "" #path_info #== "/" ? "" : path_info #http_parser.request_url
        #env['REQUEST_PATH'] = path_info #http_parser.request_url

        env["SERVER_NAME"] = host #(http_parser.headers["host"] || http_parser.headers["Host"])
        env["SERVER_PORT"] = port.to_s

        env["HTTP_COOKIE"] = http_parser.headers["Cookie"] || ""
        env["CONTENT_TYPE"] = http_parser.headers["Content-Type"] || ""
        env["CONTENT_LENGTH"] = http_parser.headers["Content-Length"] || "0"
        env["HTTP_ACCEPT"] = http_parser.headers["Accept"] || "0"

        ["Accept-Language", "Accept-Encoding", "Connection", "Upgrade-Insecure-Requests"].each do |inbh|
          env["HTTP_" + inbh.upcase.gsub("-", "_")] = http_parser.headers[inbh] if  http_parser.headers[inbh]
        end

        status = nil
        headers = nil
        body = nil
        Thread.new {
          status, headers, body = @app.call(env)
        }.join

        #unless headers["Content-Length"]
        #  length = 0
        #  body.each { |b|
        #    length += b.length
        #  }
        #  headers["Content-Length"] = length.to_s
        #end

        send_headers client, status, headers

        unless headers["Content-Type"] == "text/event-stream"
          send_body client, body
        else
          send_body client, body
        end
      end

      ##################

      client.progress do |chunk|
        http_parser << chunk
      end

      client.start_read
      })
    end

    def send_headers(client, status, headers)
      client.write "HTTP/1.1 #{status} #{WEBrick::HTTPStatus.reason_phrase(status)}\r\n"
      headers.each { |k, vs|
        vs.split("\n").each { |v|
          out = "#{k}: #{v}\r\n"
          client.write out, {:wait => true}
        }
      }
      client.write "\r\n"
    end

    def send_body(client, body)
      body.each { |part|
        client.write part, {:wait => true}
      }
    end
  end
end
