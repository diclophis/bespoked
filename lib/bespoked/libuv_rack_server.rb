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

    def gets
      rad = read
      rad
    end

    def each
      rad = read
      yield rad
    end

    def rewind
      @reader.rewind
    end

    def read(length = nil)
      rad = @reader.read(length)
      rad
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
      outer_http_parser = Http::Parser.new

      defer_until_after_body = @run_loop.defer

      # One chunk of the body
      outer_http_parser.on_body = proc do |chunk|
      end

      # HTTP headers available
      outer_http_parser.on_headers_complete = proc do
        defer_until_after_body.promise.progress do |http_parser, string_io|
          http_parser_http_version = http_parser.http_version || ["1", "1"]
          http_parser_http_method = http_parser.http_method || "GET"
          http_parser_headers = http_parser.headers || {}

          url = nil
          host = nil
          port = nil
          host_header = nil
          query_string = nil
          path_info = nil

          host_header = (http_parser_headers["host"] || http_parser_headers["Host"])
          forwarded_scheme = (http_parser_headers["X-Forwarded-Proto"] || "http")

          url = URI.parse("")
          host = ""
          port = 0
          query_string = ""
          path_info = ""
          scheme = forwarded_scheme

          if host_header
            url = URI.parse("#{forwarded_scheme}://" + host_header + http_parser.request_url)
            scheme = url.scheme
            host = url.host
            port = url.port

            query_string = url.query
            path_info = url.path
          end

          hijack_wrapper = HijackWrapper.new(string_io, client)

          env = {}

          env.update(
            'HTTP_VERSION'      => "HTTP/#{http_parser_http_version.join(".")}",

            'RACK_VERSION'      => ::Rack::VERSION.to_s,
            'RACK_ERRORS'       => "",
            "RACK_INPUT"        => ""

            'rack.url_scheme'   => scheme,
            'rack.hijack?'      => true,
            'rack.hijack'       => hijack_wrapper,
            "rack.errors"       => $stdout,
            "rack.version"      => ::Rack::VERSION.to_s.split("."),
            "rack.multithread"  => true,
            "rack.multiprocess" => false,
            "rack.run_once"     => true,
            "rack.input"        => hijack_wrapper
          )

          env['QUERY_STRING'] ||= query_string || ""
          env['REQUEST_METHOD'] = http_parser_http_method

          env['PATH_INFO'] = path_info
          env['SCRIPT_NAME'] = ""

          env["SERVER_NAME"] = host
          env["SERVER_PORT"] = port.to_s

          env["HTTP_COOKIE"] = http_parser_headers["Cookie"] || ""
          env["CONTENT_TYPE"] = http_parser_headers["Content-Type"] || ""
          env["CONTENT_LENGTH"] = http_parser_headers["Content-Length"] || "0"
          env["HTTP_ACCEPT"] = http_parser_headers["Accept"] || "0"

          ["Accept-Language", "Accept-Encoding", "Connection", "Upgrade-Insecure-Requests"].each do |inbh|
            env["HTTP_" + inbh.upcase.gsub("-", "_")] = http_parser_headers[inbh] if  http_parser_headers[inbh]
          end

          status = nil
          headers = nil
          body = nil

          status, headers, body = @app.call(env)

          if headers["Content-Type"] == "text/event-stream"
            #TODO: figure out threads/co-routines
            Thread.new do
              send_headers client, status, headers
              send_body client, body
            end
          else
            unless headers["Content-Length"]
              length = 0
              body.each { |b|
                length += b.length
              }
              headers["Content-Length"] = length.to_s
            end

            send_headers client, status, headers, true
            send_body client, body, true
          end

          outer_http_parser.reset!
        end

        :stop
      end

      ##################

      client.progress do |chunk|
        offset_of_body_left_in_buffer = outer_http_parser << chunk
        body_left_over = chunk[offset_of_body_left_in_buffer, (chunk.length - offset_of_body_left_in_buffer)]
        string_io = StringIO.new(body_left_over).set_encoding('ASCII-8BIT')
        string_io.rewind
        defer_until_after_body.notify(outer_http_parser, string_io)
      end

      client.start_read
    end

    def send_headers(client, status, headers, wait = false)
      client.write "HTTP/1.1 #{status} #{WEBrick::HTTPStatus.reason_phrase(status)}\r\n", {:wait => wait}
      headers.each { |k, vs|
        vs.split("\n").each { |v|
          out = "#{k}: #{v}\r\n"
          client.write out, {:wait => wait}
        }
      }
      client.write "\r\n", {:wait => wait}
    end

    def send_body(client, body, wait = false)
      body.each { |part|
        if part
          unless part.is_a?(String)
            part = part.to_s
          end
          client.write part, {:wait => wait}
        end
      }
    end
  end
end
